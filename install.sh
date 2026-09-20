#!/usr/bin/env bash
set -euo pipefail

# ============ 颜色 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============ 工具函数 ============
info()  { echo -e "${GREEN}[信息]${NC} $*"; }
warn()  { echo -e "${YELLOW}[警告]${NC} $*"; }
error() { echo -e "${RED}[错误]${NC} $*"; }

pause() {
    echo
    read -rp "按回车返回菜单..." _
}

# 检测包管理器
detect_pkg() {
    if command -v apt >/dev/null 2>&1; then
        PKG="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG="yum"
    elif command -v apk >/dev/null 2>&1; then
        PKG="apk"
    else
        PKG="unknown"
    fi
}

# 统一安装命令
pkg_install() {
    detect_pkg
    case "$PKG" in
        apt)
            apt update -y && apt install -y "$@"
            ;;
        dnf)
            dnf install -y "$@"
            ;;
        yum)
            yum install -y "$@"
            ;;
        apk)
            apk add --no-cache "$@"
            ;;
        *)
            error "不支持的包管理器，请手动安装: $*"
            return 1
            ;;
    esac
}

# ============ 功能 1：系统信息 ============
show_system() {
    clear
    echo -e "${CYAN}========== 系统信息 ==========${NC}"
    echo
    echo "主机名   : $(hostname)"
    echo "系统     : $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 未知)"
    echo "内核     : $(uname -r)"
    echo "架构     : $(uname -m)"
    echo "运行时间 : $(uptime -p 2>/dev/null || uptime)"
    echo
    echo -e "${CYAN}---------- CPU ----------${NC}"
    if command -v lscpu >/dev/null 2>&1; then
        lscpu | grep -E "Model name|CPU\(s\)" | head -5
    else
        grep -m1 "model name" /proc/cpuinfo 2>/dev/null || echo "无法读取"
        echo "核心数: $(nproc)"
    fi
    echo
    echo -e "${CYAN}---------- 内存 ----------${NC}"
    free -h
    echo
    echo -e "${CYAN}---------- 磁盘 ----------${NC}"
    df -hT | grep -v tmpfs
    pause
}

# ============ 功能 2：网络信息 ============
show_network() {
    clear
    echo -e "${CYAN}========== 网络信息 ==========${NC}"
    echo
    echo -e "${CYAN}---------- 公网 IP ----------${NC}"
    IPV4=$(curl -4 -s --max-time 5 ifconfig.me || echo "获取失败")
    IPV6=$(curl -6 -s --max-time 5 ifconfig.me || echo "无 IPv6")
    echo "IPv4: $IPV4"
    echo "IPv6: $IPV6"
    echo
    echo -e "${CYAN}---------- 网卡 ----------${NC}"
    ip -br addr 2>/dev/null || ifconfig
    echo
    echo -e "${CYAN}---------- 路由 ----------${NC}"
    ip route 2>/dev/null | head -5
    pause
}

# ============ 功能 3：常用工具安装 ============
install_tools() {
    clear
    echo -e "${CYAN}========== 安装常用工具 ==========${NC}"
    echo
    TOOLS=(curl wget vim nano htop screen tmux unzip zip git socat net-tools dnsutils qrencode)
    info "即将安装: ${TOOLS[*]}"
    echo
    read -rp "确认安装？[y/N]: " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        warn "已取消"
        pause
        return
    fi
    for t in "${TOOLS[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            info "$t 已安装，跳过"
        else
            info "正在安装 $t ..."
            pkg_install "$t" >/dev/null 2>&1 && info "$t 安装成功" || warn "$t 安装失败"
        fi
    done
    pause
}

# ============ 功能 4：测速 ============
speed_test() {
    clear
    echo -e "${CYAN}========== 网络测速 ==========${NC}"
    echo
    if ! command -v curl >/dev/null 2>&1; then
        warn "缺少 curl，正在安装..."
        pkg_install curl
    fi
    info "正在测试到 Cloudflare 的下载速度..."
    echo
    curl -o /dev/null -s -w "下载速度: %{speed_download} B/s\n连接时间: %{time_connect}s\n总时间  : %{time_total}s\n" \
        --max-time 15 https://speed.cloudflare.com/__down?bytes=100000000 || warn "测速失败"
    echo
    info "正在测试延迟（ping 1.1.1.1）..."
    ping -c 4 1.1.1.1 || warn "ping 不可用"
    pause
}

# ============ 功能 5：换源（仅 Ubuntu/Debian） ============
change_mirror() {
    clear
    echo -e "${CYAN}========== 更换软件源 ==========${NC}"
    echo
    if ! command -v apt >/dev/null 2>&1; then
        warn "此功能仅支持 Ubuntu / Debian"
        pause
        return
    fi
    echo "1) 阿里云"
    echo "2) 清华 TUNA"
    echo "3) 中科大 USTC"
    echo "4) 恢复官方源"
    echo "0) 返回"
    echo
    read -rp "请选择: " m
    case "$m" in
        1) MIRROR="mirrors.aliyun.com" ;;
        2) MIRROR="mirrors.tuna.tsinghua.edu.cn" ;;
        3) MIRROR="mirrors.ustc.edu.cn" ;;
        4) MIRROR="archive.ubuntu.com" ;;
        0) return ;;
        *) warn "无效选择"; pause; return ;;
    esac

    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    info "正在备份原 sources.list ..."
    cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s) 2>/dev/null || true

    info "正在写入新源: $MIRROR"
    cat > /etc/apt/sources.list <<EOF
deb http://$MIRROR/ubuntu/ $CODENAME main restricted universe multiverse
deb http://$MIRROR/ubuntu/ $CODENAME-updates main restricted universe multiverse
deb http://$MIRROR/ubuntu/ $CODENAME-backports main restricted universe multiverse
deb http://$MIRROR/ubuntu/ $CODENAME-security main restricted universe multiverse
EOF

    info "更新软件列表..."
    apt update -y || warn "apt update 出错，请检查源"
    info "换源完成"
    pause
}

# ============ 功能 6：查看端口监听 ============
show_ports() {
    clear
    echo -e "${CYAN}========== 端口监听 ==========${NC}"
    echo
    if command -v ss >/dev/null 2>&1; then
        ss -tulnp
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tulnp
    else
        warn "缺少 ss 和 netstat，请先安装 net-tools / iproute2"
    fi
    pause
}

# ============ 主菜单 ============
show_menu() {
    clear
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}        VPS 一键工具菜单${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "  1) 查看系统信息"
    echo "  2) 查看网络信息"
    echo "  3) 安装常用工具"
    echo "  4) 网络测速"
    echo "  5) 更换软件源（Ubuntu/Debian）"
    echo "  6) 查看端口监听"
    echo "  0) 退出"
    echo -e "${BLUE}=========================================${NC}"
}

main() {
    while true; do
        show_menu
        read -rp "请选择 [0-6]: " choice
        case "$choice" in
            1) show_system ;;
            2) show_network ;;
            3) install_tools ;;
            4) speed_test ;;
            5) change_mirror ;;
            6) show_ports ;;
            0) echo "再见"; exit 0 ;;
            *) warn "无效选择"; sleep 1 ;;
        esac
    done
}

main
