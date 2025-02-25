#!/bin/bash

# 增强型错误处理
set -euo pipefail

# 日志文件配置（实时显示进度）
LOG_FILE="docker-auto-$(date +%Y%m%d%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 进度显示函数
show_progress() {
    echo "[$(date +'%H:%M:%S')] $1"
}

# 国内镜像配置
UBUNTU_MIRROR="http://mirrors.aliyun.com/ubuntu"
DOCKER_MIRROR="https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
GPG_KEY_URL="https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg"
SUPPORTED_DISTROS=("focal" "jammy" "buster" "bullseye" "bookworm")

# ======================= 环境检测函数 ======================= #
check_docker_installed() {
    if command -v docker &>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_distro() {
    local distro_code=$(lsb_release -cs)
    [[ " ${SUPPORTED_DISTROS[*]} " =~ " ${distro_code} " ]] || {
        show_progress "错误：不支持的系统版本 ${distro_code}"
        show_progress "支持列表：${SUPPORTED_DISTROS[*]}"
        exit 1
    }
}

check_root() {
    [[ $EUID -eq 0 ]] || {
        show_progress "错误：请使用 sudo 或 root 用户执行"
        exit 1
    }
}

# ======================= 安装相关函数 ======================= #
configure_ubuntu_mirror() {
    show_progress "配置阿里云系统镜像源..."
    local distro_code=$(lsb_release -cs)
    
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    cat << EOF | sudo tee /etc/apt/sources.list >/dev/null
deb ${UBUNTU_MIRROR} ${distro_code} main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${distro_code}-updates main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${distro_code}-backports main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${distro_code}-security main restricted universe multiverse
EOF
    sudo apt-get update | tee -a "$LOG_FILE"
}

install_dependencies() {
    show_progress "安装系统依赖..."
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        software-properties-common \
        lsb-release | tee -a "$LOG_FILE"
}

configure_docker_repo() {
    show_progress "配置 Docker 镜像源..."
    curl -fsSL "$GPG_KEY_URL" | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $DOCKER_MIRROR $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update | tee -a "$LOG_FILE"
}

install_docker() {
    show_progress "安装 Docker 核心组件..."
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin | tee -a "$LOG_FILE"
}

# ======================= 卸载相关函数 ======================= #
uninstall_docker() {
    show_progress "开始卸载 Docker..."
    sudo apt-get remove -y --purge \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
        docker-compose \
        docker-ce-rootless-extras 2>/dev/null

    show_progress "清理残留数据..."
    sudo rm -rf /var/lib/{docker,containerd,docker-engine}
    sudo rm -rf /etc/docker
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg

    sudo apt-get autoremove -y --purge
    sudo apt-get autoclean
}

# ======================= 主控制流程 ======================= #
interactive_prompt() {
    if check_docker_installed; then
        echo "-------------------------------------------------"
        echo "检测到系统已安装 Docker"
        echo "请选择操作："
        echo "1) 卸载并重新安装 Docker"
        echo "2) 直接退出"
        echo "-------------------------------------------------"
        read -p "请输入选项 (1/2): " choice

        case $choice in
            1)
                uninstall_docker
                show_progress "即将开始全新安装..."
                ;;
            2)
                show_progress "操作已取消"
                exit 0
                ;;
            *)
                show_progress "无效输入，操作取消"
                exit 1
                ;;
        esac
    fi
}

main() {
    check_root
    check_distro
    interactive_prompt  # 先执行交互式选择
    
    # 安装流程
    configure_ubuntu_mirror
    install_dependencies
    configure_docker_repo
    install_docker
    
    # 最终提示
    if check_docker_installed; then
        show_progress "✅ Docker 安装成功！版本信息："
        docker --version | tee -a "$LOG_FILE"
        show_progress "提示：需要重新登录以应用用户组权限"
    else
        show_progress "❌ 安装失败，请检查日志：${LOG_FILE}"
        exit 1
    fi
}

# 启动脚本
show_progress "=== 开始执行 Docker 自动化管理脚本 ==="
main
show_progress "操作日志已保存至：${LOG_FILE}"
