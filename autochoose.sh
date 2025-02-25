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

# 国内镜像配置列表（名称 Ubuntu地址 Docker地址 GPG地址）
MIRRORS=(
    "阿里云 http://mirrors.aliyun.com/ubuntu https://mirrors.aliyun.com/docker-ce/linux/ubuntu https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg"
    "腾讯云 http://mirrors.tencent.com/ubuntu https://mirrors.tencent.com/docker-ce/linux/ubuntu https://mirrors.tencent.com/docker-ce/linux/ubuntu/gpg"
    "清华大学 https://mirrors.tuna.tsinghua.edu.cn/ubuntu https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg"
)

# ======================= 环境检测函数 ======================= #
check_docker_installed() {
    command -v docker &>/dev/null
}

check_distro() {
    local distro_code=$(lsb_release -cs)
    [[ " focal jammy buster bullseye bookworm " =~ " ${distro_code} " ]] || {
        show_progress "错误：不支持的系统版本 ${distro_code}"
        exit 1
    }
}

check_root() {
    [[ $EUID -eq 0 ]] || {
        show_progress "错误：请使用 sudo 或 root 用户执行"
        exit 1
    }
}

# ======================= 镜像源选择 ======================= #
select_fastest_mirror() {
    show_progress "开始网络质量检测..."
    local best_time=99999
    local selected_mirror=""

    for mirror in "${MIRRORS[@]}"; do
        IFS=' ' read -r name ubuntu_url docker_url gpg_url <<< "$mirror"
        
        show_progress "测试 [$name] 镜像源..."
        
        # 检测GPG密钥可用性
        local http_code=$(curl -I -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$gpg_url")
        if [[ $http_code != "200" ]]; then
            show_progress "  [警告] GPG密钥不可访问，跳过此镜像源"
            continue
        fi

        # 测试Ubuntu镜像延迟
        local ubuntu_time=$(curl -o /dev/null -s -w "%{time_total}" \
            --connect-timeout 2 --max-time 4 \
            "${ubuntu_url}/dists/$(lsb_release -cs)/Release.gpg" 2>/dev/null || echo 999)
        
        # 测试Docker镜像延迟
        local docker_time=$(curl -o /dev/null -s -w "%{time_total}" \
            --connect-timeout 2 --max-time 4 \
            "${docker_url}/dists/$(lsb_release -cs)/InRelease" 2>/dev/null || echo 999)

        # 计算综合延迟
        local total_time=$(awk "BEGIN {print $ubuntu_time + $docker_time}")
        show_progress "  网络质量报告：Ubuntu ${ubuntu_time}s + Docker ${docker_time}s = ${total_time}s"

        if (( $(awk "BEGIN {print ($total_time < $best_time)}") )); then
            best_time=$total_time
            selected_mirror="$mirror"
        fi
    done

    # 回退机制
    [[ -n "$selected_mirror" ]] || {
        show_progress "所有镜像源检测失败，使用默认阿里云源"
        selected_mirror=${MIRRORS[0]}
    }

    IFS=' ' read -r MIRROR_NAME UBUNTU_MIRROR DOCKER_MIRROR GPG_KEY_URL <<< "$selected_mirror"
    show_progress "已选择最优镜像源：$MIRROR_NAME (综合延迟 ${best_time}s)"
}

# ======================= 系统配置 ======================= #
configure_system() {
    show_progress "配置系统镜像源..."
    local distro_code=$(lsb_release -cs)
    
    # 备份原文件
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    
    # 生成新配置
    sudo tee /etc/apt/sources.list >/dev/null <<EOF
deb ${UBUNTU_MIRROR} ${distro_code} main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${distro_code}-updates main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${distro_code}-backports main restricted universe multiverse
deb ${UBUNTU_MIRROR} ${distro_code}-security main restricted universe multiverse
EOF

    # 更新软件列表
    sudo apt-get update | tee -a "$LOG_FILE"
}

configure_docker_repo() {
    show_progress "配置Docker仓库..."
    curl -fsSL "$GPG_KEY_URL" | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] $DOCKER_MIRROR $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update | tee -a "$LOG_FILE"
}

# ======================= 安装/卸载 ======================= #
install_docker() {
    show_progress "安装Docker组件..."
    sudo apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin | tee -a "$LOG_FILE"
}

uninstall_docker() {
    show_progress "开始彻底卸载..."
    sudo apt-get remove -y --purge \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
        docker-compose \
        docker-ce-rootless-extras 2>/dev/null

    show_progress "清理残留文件..."
    sudo rm -rf /var/lib/{docker,containerd,docker-engine}
    sudo rm -rf /etc/docker
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /usr/share/keyrings/docker-archive-keyring.gpg

    sudo apt-get autoremove -y --purge
    sudo apt-get autoclean
}

# ======================= 主流程控制 ======================= #
interactive_check() {
    if check_docker_installed; then
        echo "-------------------------------------------------"
        echo "检测到系统中已安装 Docker"
        echo -e "\033[33m请选择操作：\033[0m"
        echo "1) 卸载并重新安装"
        echo "2) 退出脚本"
        echo "-------------------------------------------------"
        read -p "请输入选项 (1/2): " choice
        
        case $choice in
            1)
                uninstall_docker
                show_progress "准备全新安装..."
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
    interactive_check
    select_fastest_mirror
    configure_system
    configure_docker_repo
    install_docker

    # 验证安装
    if check_docker_installed; then
        show_progress "✅ 安装成功！Docker版本信息："
        docker --version |
