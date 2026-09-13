#!/system/bin/sh
TS_DIR="/data/adb/tricky_store"
TARGET_KEYBOX="$TS_DIR/keybox.xml"
TMP_DIR="/data/data/keybox_update"
TMP_RAW="$TMP_DIR/raw.tmp"
TMP_KEYBOX="$TMP_DIR/keybox_tmp.xml"
YURIKEY_URL="https://raw.githubusercontent.com/Yurii0307/yurikey/main/key"
TRICKYADDONUPDATETARGETLIST_URL="https://raw.githubusercontent.com/KOWX712/Tricky-Addon-Update-Target-List/keybox/.extra"
INTEGRITYBOX_URL="https://raw.gitmirror.com/MeowDump/MeowDump/refs/heads/main/NullVoid/OptimusPrime"
INTEGRITYBOX_MIRROR="https://raw.githubusercontent.com/MeowDump/MeowDump/refs/heads/main/NullVoid/OptimusPrime"

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
BLUE="\033[1;34m"
PURPLE="\033[1;35m"
BOLD="\033[1m"
RESET="\033[0m"
BLINK="\033[5m"
NC="\033[0m"
LINE="${BLUE}--------------------------------------------------${RESET}"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
show_decode_progress() {
    local current=$1
    local total=$2
    local bar_len=20
    local filled=$((current * bar_len / total))
    local empty=$((bar_len - filled))
    local bar=$(printf "%0.s#" $(seq 1 $filled))$(printf "%0.s-" $(seq 1 $empty))
    echo -ne "${BLUE}[DECODE]${NC} [$bar] $current/$total 层 \r"
    if [ $current -eq $total ]; then echo -e "\n"; fi
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "需要 Root 权限!"
        exit 1
    fi
}

check_tools() {
    missing=""
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing="$missing curl/wget"
    fi
    if ! command -v toybox >/dev/null 2>&1; then
        log_warn "未找到 toybox 显式指令，将尝试直接调用系统命令"
    fi
    if [ -n "$missing" ]; then
        log_error "缺少必要工具: $missing"
        exit 1
    fi
}

run_xxd() {
    if command -v xxd >/dev/null 2>&1; then
        xxd "$@"
    elif command -v toybox >/dev/null 2>&1 && toybox xxd --help >/dev/null 2>&1; then
        toybox xxd "$@"
    else
        log_error "系统中未找到 xxd 工具"
        return 1
    fi
}

run_base64_d() {
    if command -v toybox >/dev/null 2>&1; then
        toybox base64 -d "$@"
    else
        base64 -d "$@"
    fi
}

download_file() {
    url="$1"
    dest="$2"
    rm -f "$dest"
    
    if command -v curl >/dev/null 2>&1; then
        curl --connect-timeout 10 --retry 1 -fL --progress-bar "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -T 10 -t 1 --no-check-certificate --progress=bar:force -O "$dest" "$url"
    else
        return 1
    fi
    
    [ -s "$dest" ]
}

init_env() {
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    mkdir -p "$TS_DIR"
}

fetch_yurikey() {
    log_info "正在下载 Yurikey 源..."
    if ! download_file "$YURIKEY_URL" "$TMP_RAW"; then
        log_error "下载失败，请检查网络或开启 VPN"
        return 1
    fi

    log_info "正在解码..."
    if ! run_base64_d "$TMP_RAW" > "$TMP_KEYBOX" 2>/dev/null; then
        log_error "解码失败"
        return 1
    fi
    return 0
}

fetch_TRICKYADDONUPDATETARGETLIST() {
    log_info "正在下载 Tricky Addon-Update Target List 源..."
    if ! download_file "$TRICKYADDONUPDATETARGETLIST_URL" "$TMP_RAW"; then
        log_error "下载失败，请检查网络"
        return 1
    fi

    log_info "正在解码..."
    if ! cat "$TMP_RAW" | run_xxd -r -p | run_base64_d > "$TMP_KEYBOX" 2>/dev/null; then
        log_error "解码失败"
        return 1
    fi
    return 0
}

fetch_integritybox() {
    log_info "正在下载 IntegrityBox 源..."
    if ! download_file "$INTEGRITYBOX_URL" "$TMP_RAW"; then
        log_warn "主源连接失败，尝试镜像源..."
        if ! download_file "$INTEGRITYBOX_MIRROR" "$TMP_RAW"; then
            log_error "所有源下载失败"
            return 1
        fi
    fi

    log_info "正在解码..."
    cp "$TMP_RAW" "$TMP_DIR/process.tmp"
    for i in $(seq 1 10); do
        if [ ! -s "$TMP_DIR/process.tmp" ]; then
            log_error "解码中断：第 $i 层数据为空"
            return 1
        fi
        show_decode_progress $i 10
        if ! run_base64_d "$TMP_DIR/process.tmp" > "$TMP_DIR/process.next" 2>/dev/null; then
            log_error "第 $i 层 Base64 解码失败"
            return 1
        fi
        mv -f "$TMP_DIR/process.next" "$TMP_DIR/process.tmp"
    done

    log_info "正在最终格式转换..."
    if ! cat "$TMP_DIR/process.tmp" | run_xxd -r -p | \
         tr 'A-Za-z' 'N-ZA-Mn-za-m' > "$TMP_KEYBOX"; then
         log_error "最终格式转换失败"
         return 1
    fi

    return 0
}

validate_keybox() {
    file="$1"
    if [ ! -s "$file" ]; then
        log_error "生成的 Keybox 文件无效（为空）"
        return 1
    fi

    if ! grep -q "<?xml" "$file" || \
       ! grep -q "<AndroidAttestation>" "$file" || \
       ! grep -q "BEGIN CERTIFICATE" "$file"; then
        log_error "Keybox 内容校验失败"
        return 1
    fi

    size=$(toybox stat -c%s "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    log_info "校验通过，文件大小: $size 字节"
    return 0
}

install_keybox() {
    if mv -f "$TMP_KEYBOX" "$TARGET_KEYBOX"; then
        chmod 644 "$TARGET_KEYBOX"
        log_info "✅ Keybox 更新成功！"
        return 0
    else
        log_error "写入文件失败"
        return 1
    fi
}

show_current() {
    if [ -f "$TARGET_KEYBOX" ]; then
        echo -e "${CYAN}当前文件:${NC} $TARGET_KEYBOX"
        ls -lh "$TARGET_KEYBOX"
        echo -e "${CYAN}头部预览:${NC}"
        head -n 5 "$TARGET_KEYBOX"
        echo "..."
    else
        echo -e "${YELLOW}未找到 Keybox 文件${NC}"
    fi
}

main() {
    check_root
    check_tools
    init_env

show_menu() {
    clear
    echo -e "\n${GREEN}${BLINK}欢迎使用 Keybox 工具箱${RESET}${NC}"
    echo -e ""
    echo -e "${LINE}"
    echo -e "${RED}${BLINK}              Keybox 一键更新${RESET}${NC}"
    echo -e "${LINE}"
    echo -e "       ${BOLD}请选择功能（直接输编号，0退出）${RESET}"
    echo -e "         ${RED}1.  ${BLINK}Y${NC}${RED}${BLINK}u${NC}${RED}${BLINK}r${NC}${RED}${BLINK}i${NC}${RED}${BLINK}k${NC}${RED}${BLINK}e${NC}${RED}${BLINK}y${NC}${RED}${BLINK}源${NC}"
    echo -e "         ${GREEN}2.  ${BLINK}T${NC}${GREEN}${BLINK}r${NC}${GREEN}${BLINK}i${NC}${GREEN}${BLINK}c${NC}${GREEN}${BLINK}k${NC}${GREEN}${BLINK}y${NC}${GREEN}${BLINK}-${NC}${GREEN}${BLINK}A${NC}${GREEN}${BLINK}d${NC}${GREEN}${BLINK}d${NC}${GREEN}${BLINK}o${NC}${GREEN}${BLINK}n${NC}${GREEN}${BLINK}源${NC}"
    echo -e "         ${YELLOW}3.  ${BLINK}I${NC}${YELLOW}${BLINK}n${NC}${YELLOW}${BLINK}t${NC}${YELLOW}${BLINK}e${NC}${YELLOW}${BLINK}g${NC}${YELLOW}${BLINK}r${NC}${YELLOW}${BLINK}i${NC}${YELLOW}${BLINK}t${NC}${YELLOW}${BLINK}y${NC}${YELLOW}${BLINK}B${NC}${YELLOW}${BLINK}o${NC}${YELLOW}${BLINK}x${NC}${YELLOW}${BLINK}源${NC}"
    echo -e "         ${CYAN}4.  ${BLINK}查${NC}${CYAN}${BLINK}看${NC}${CYAN}${BLINK}当${NC}${CYAN}${BLINK}前${NC}${CYAN}${BLINK}状${NC}${CYAN}${BLINK}态${NC}"
    echo -e "${LINE}"
    echo -e "输入后直接执行，无需按回车："
    echo -e "${LINE}"
    echo -e "${PURPLE}${BOLD}TG: @a78c75  QQ: 1103116215${RESET}"
    echo -e "${PURPLE}${BOLD}请使用魔法网络加速器使用本工具${RESET}"
    echo -e "${LINE}"
}

    while true; do
        show_menu
        read -n 1 choice
        case $choice in
            1)
                echo -e "\n"
                fetch_yurikey && validate_keybox "$TMP_KEYBOX" && install_keybox
                sleep 3
                ;;
            2)
                echo -e "\n"
                fetch_TRICKYADDONUPDATETARGETLIST && validate_keybox "$TMP_KEYBOX" && install_keybox
                sleep 3
                ;;
            3)
                echo -e "\n"
                fetch_integritybox && validate_keybox "$TMP_KEYBOX" && install_keybox
                sleep 3
                ;;
            4)
                echo -e "\n"
                show_current
                sleep 3
                ;;
            0)
                echo -e "\n${GREEN}👋 感谢使用，再见！${RESET}"
                rm -rf "$TMP_DIR"
                exit 0
                ;;
            *)
                echo -e "\n${RED}❌ 无效选项${RESET}"
                sleep 1
                ;;
        esac
    done
}

main