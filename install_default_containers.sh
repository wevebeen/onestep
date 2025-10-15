#!/bin/bash
# ==========================================================
# 🧩 PVE LXC 默认安装脚本 (固定IP版本)
# ==========================================================

set -e

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${BLUE}[→]${NC} $1"; }

# ==================== 系统配置 ====================
HOST_IP="38.150.1.209"
GW="38.150.1.254"
NETWORK="38.150.1.0"
CIDR="24"
HOST_CPU="4"
HOST_MEM="3931"
HOST_DISK="24"

# 固定IP配置
IP102="38.150.1.102"
IP153="38.150.1.153"

# ==================== 宿主机环境检查 ====================
host_check() {
    log_step "检查系统环境..."
    
    if [ "$(id -u)" -ne 0 ]; then
        log_error "必须以 root 用户运行"
        exit 1
    fi
    
    if ! command -v pct &> /dev/null; then
        log_error "未找到 pct 命令，请确保在 Proxmox VE 环境中运行"
        exit 1
    fi
    
    if ! ip link show eth0 &> /dev/null; then
        log_error "未找到 eth0 网卡"
        exit 1
    fi
    
    log_info "✓ 系统环境检查通过"
}

# ==================== 宿主机清理容器 ====================
host_cleanup() {
    local ID=$1
    
    log_warn "清理失败的容器 $ID..."
    
    # 停止容器
    pct stop $ID --skiplock 2>/dev/null || true
    
    # 等待停止
    sleep 3
    
    # 删除容器
    pct destroy $ID --purge --force 2>/dev/null || true
    
    log_info "容器 $ID 已清理"
}

# ==================== 宿主机下载模板 ====================
host_download() {
    log_step "检查 Debian 12 模板..."
    
    local template_file="debian-12-standard_12.7-1_amd64.tar.zst"
    local template_path="/var/lib/vz/template/cache/$template_file"
    
    if [ ! -f "$template_path" ]; then
        log_info "下载 Debian 12 模板..."
        pveam update
        pveam download local "$template_file"
    else
        log_info "✓ 找到模板: $template_file"
    fi
}

# ==================== 宿主机准备系统 ====================
host_prepare() {
    log_step "准备系统环境..."
    
    # 创建必要目录
    mkdir -p /var/lib/vz/images
    mkdir -p /var/lib/vz/private
    mkdir -p /var/lib/lxc
    
    # 设置内核参数
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv4.conf.all.proxy_arp=1
    sysctl -w net.ipv4.conf.all.rp_filter=0
    
    # 设置防火墙规则
    iptables -I FORWARD -j ACCEPT
    
    log_info "✓ 系统环境已准备"
}

# ==================== 宿主机创建容器 ====================
host_create() {
    local ID=$1
    local IP=$2
    local HOSTNAME="lxc-$ID"
    
    log_step "创建容器 $ID (IP: $IP, 主机名: $HOSTNAME)..."
    
    # 创建容器
    pct create $ID local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
        --hostname "$HOSTNAME" \
        --memory $HOST_MEM \
        --cores $HOST_CPU \
        --rootfs local:8 \
        --net0 name=eth0,bridge=vmbr0,type=veth,ip=$IP/$CIDR,gw=$GW \
        --onboot 1 \
        --features nesting=1
    
    # 启动容器
    pct start $ID
    
    # 等待容器完全启动
    log_step "等待容器 $ID 完全启动..."
    local retry_count=0
    while [ $retry_count -lt 30 ]; do
        if pct status $ID | grep -q "running"; then
            log_info "容器 $ID 已启动"
            break
        fi
        sleep 2
        retry_count=$((retry_count + 1))
    done
    
    if [ $retry_count -eq 30 ]; then
        log_error "容器 $ID 启动超时"
        return 1
    fi
    
    # 额外等待确保网络就绪
    sleep 3
    
    # 配置容器网络
    lxc_network $ID $IP
    
    # 安装基础软件
    lxc_install $ID
    
    log_info "✓ 容器 $ID 创建完成"
}

# ==================== LXC容器网络配置 ====================
lxc_network() {
    local ID=$1
    local IP=$2
    
    log_step "配置容器 $ID 网络..."
    
    # 等待容器网络就绪
    local retry_count=0
    while [ $retry_count -lt 10 ]; do
        if pct exec $ID -- ip addr show eth0 >/dev/null 2>&1; then
            log_info "容器 $ID 网络接口就绪"
            break
        fi
        sleep 2
        retry_count=$((retry_count + 1))
    done
    
    if [ $retry_count -eq 10 ]; then
        log_error "容器 $ID 网络接口未就绪"
        return 1
    fi
    
    # 设置DNS
    pct exec $ID -- bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf" || log_warn "DNS配置失败"
    pct exec $ID -- bash -c "echo 'nameserver 8.8.4.4' >> /etc/resolv.conf" || log_warn "DNS配置失败"
    
    # 设置主机名
    pct exec $ID -- bash -c "echo 'lxc-$ID' > /etc/hostname" || log_warn "主机名配置失败"
    pct exec $ID -- bash -c "echo '127.0.0.1 localhost' > /etc/hosts" || log_warn "hosts配置失败"
    pct exec $ID -- bash -c "echo '$IP lxc-$ID' >> /etc/hosts" || log_warn "hosts配置失败"
    
    log_info "✓ 容器 $ID 网络配置完成"
}

# ==================== LXC容器软件安装 ====================
lxc_install() {
    local ID=$1
    
    log_step "安装容器 $ID 基础软件..."
    
    # 等待容器完全就绪
    local retry_count=0
    while [ $retry_count -lt 10 ]; do
        if pct exec $ID -- apt --version >/dev/null 2>&1; then
            log_info "容器 $ID 包管理器就绪"
            break
        fi
        sleep 2
        retry_count=$((retry_count + 1))
    done
    
    if [ $retry_count -eq 10 ]; then
        log_error "容器 $ID 包管理器未就绪"
        return 1
    fi
    
    # 更新包列表
    log_step "更新包列表..."
    pct exec $ID -- apt update || log_warn "包列表更新失败"
    
    # 安装基础软件
    log_step "安装基础软件..."
    pct exec $ID -- apt install -y openssh-server curl wget nano htop || log_warn "基础软件安装失败"
    
    # 配置SSH
    log_step "配置SSH..."
    pct exec $ID -- bash -c "echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config" || log_warn "SSH配置失败"
    pct exec $ID -- systemctl enable ssh || log_warn "SSH服务启用失败"
    pct exec $ID -- systemctl restart ssh || log_warn "SSH服务重启失败"
    
    log_info "✓ 容器 $ID 基础软件安装完成"
}

# ==================== 主程序 ====================
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            安装默认容器 (102 和 153)                 ║"
    echo "║            (固定使用 38.150.1.102 和 38.150.1.153)   ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "系统资源:"
    echo "  • CPU: ${HOST_CPU} 核"
    echo "  • 内存: ${HOST_MEM} MB"
    echo "  • 磁盘: ${HOST_DISK} GB"
    echo "  • 网关: ${GW}"
    echo "  • 宿主机 IP: ${HOST_IP}"
    echo "  • 网段: ${NETWORK}/${CIDR}"
    
    echo ""
    log_info "固定分配的公网 IP:"
    echo "  • 容器 102: $IP102"
    echo "  • 容器 153: $IP153"
    
    echo ""
    log_info "确认安装？(y/n) [按Enter取消]: "
    read -p "" confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "已取消"
        exit 0
    fi
    
    # 检查环境
    host_check
    
    # 下载模板
    host_download
    
    # 准备系统
    host_prepare
    
    # 创建容器
    log_step "开始创建容器..."
    
    # 创建容器102
    if host_create 102 $IP102; then
        log_info "✓ 容器102创建成功"
    else
        log_error "✗ 容器102创建失败"
        host_cleanup 102
        exit 1
    fi
    
    # 创建容器153
    if host_create 153 $IP153; then
        log_info "✓ 容器153创建成功"
    else
        log_error "✗ 容器153创建失败"
        host_cleanup 153
        exit 1
    fi
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            🔑 容器登录信息                            ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    echo "容器 102:"
    echo "  • IP: $IP102"
    echo "  • SSH: ssh root@$IP102"
    echo ""
    echo "容器 153:"
    echo "  • IP: $IP153"
    echo "  • SSH: ssh root@$IP153"
    echo ""
    
    log_info "✓ 安装完成"
    echo ""
}

# 运行主程序
main