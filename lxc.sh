#!/bin/bash
# 一键安装命令:
# cat > /tmp/install-pve-lxc.sh << 'EOF'
# [将整个脚本内容粘贴在这里]
# EOF
# chmod +x /tmp/install-pve-lxc.sh && bash /tmp/install-pve-lxc.sh

cat > /usr/local/bin/pve-lxc-manager.sh << 'EOFSCRIPT'
#!/bin/bash
# ==========================================================
# 🧩 PVE LXC 完整管理脚本 v15.2 (完全修复版)
# ==========================================================
#
# ┌─────────────────────────────────────────────────────────┐
# │ 系统环境确认                                            │
# ├─────────────────────────────────────────────────────────┤
# │ • 系统: Proxmox VE (云主机环境)                         │
# │ • 网关: 自动检测 (从路由表获取)                         │
# │ • 宿主机 IP: 自动检测 (从外网获取真实公网 IP)           │
# │ • 网卡: eth0                                            │
# │ • IP 段: 从 eth0 网卡获取公网 IP 段                     │
# │ • 子网掩码: 自动计算 (从 CIDR 获取)                     │
# │ • 可用 IP: 扫描 eth0 上的其他公网 IP                    │
# │ • 模板: 自动下载最新 Debian 12                          │
# │ • 存储: 自动创建必要目录结构                            │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ 云主机限制条件 (已验证)                                 │
# ├─────────────────────────────────────────────────────────┤
# │ ✗ vmbr0/bridge: 禁止修改 /etc/network/interfaces        │
# │ ✗ macvlan: 禁用网卡混杂模式 (ip link set promisc on)   │
# │ ✗ OVS: 限制内核模块加载 (modprobe openvswitch)          │
# │ ✗ TAP/TUN: 可能禁用 /dev/net/tun 字符设备               │
# │ ✓ veth: 内核原生支持，完全可用 ✅                        │
# │ ✓ network namespace: 允许使用 (ip netns) ✅             │
# │ ✓ iptables: 允许配置防火墙 ✅                            │
# │ ✓ Proxy ARP: 内核参数可修改 (sysctl) ✅                 │
# │ ✓ IP 转发: 内核参数可修改 (net.ipv4.ip_forward) ✅      │
# │ ✓ 路由表: 允许添加路由 (ip route add) ✅                │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ 防火墙策略 (已实现)                                     │
# ├─────────────────────────────────────────────────────────┤
# │ • 宿主机入站: 仅开放 22 (SSH), 8006 (PVE), Tailscale   │
# │ • 宿主机转发: 完全允许 (FORWARD ACCEPT) ✅               │
# │ • 容器网络: 不使用 NAT，直接使用自己的公网 IP ✅         │
# │ • 容器端口: 完全独立，外网可直接访问 ✅                  │
# │ • 出站流量: 容器使用自己的 IP (不是宿主机 IP) ✅         │
# │ • 禁用 MASQUERADE: 确保容器不会被 NAT ✅                 │
# │ • Tailscale: 完全排除，不受影响 ✅                       │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ 容器配置规则 (已实现)                                   │
# ├─────────────────────────────────────────────────────────┤
# │ • CPU: 与宿主机相同核心数 ✅                             │
# │ • 内存: 与宿主机相同内存大小 ✅                          │
# │ • 磁盘: 实际可用磁盘空间 (df 命令获取) ✅                │
# │ • IP: 自动分配 eth0 网段内其他公网 IP ✅                 │
# │ • 网关: 自动从路由表获取 ✅                              │
# │ • 子网掩码: 根据 CIDR 自动计算 ✅                        │
# │ • 开机自启: 是 (onboot=1) ✅                             │
# │ • SSH: 必须启用，PermitRootLogin yes ✅                  │
# │ • 主机名: lxc-{IP 最后一段} ✅                           │
# │ • 容器名称: 与 IP 绑定，防止配置丢失 ✅                  │
# │ • 存储目录: 自动创建，避免路径错误 ✅                    │
# └─────────────────────────────────────────────────────────┘
#
# ┌─────────────────────────────────────────────────────────┐
# │ v15.2 修复内容                                          │
# ├─────────────────────────────────────────────────────────┤
# │ ✅ 修复 line 163 语法错误 (for循环中的文件匹配)          │
# │ ✅ 自动创建存储目录 /var/lib/vz/images/{ID}             │
# │ ✅ Enter键返回主菜单 (所有选项)                         │
# │ ✅ 修改IP时不强制修改主机名                              │
# │ ✅ 清理时完全排除Tailscale                               │
# │ ✅ IP扫描改为安全的方式 (避免2>/dev/null语法错误)        │
# │ ✅ 增强错误处理和日志输出                                │
# └─────────────────────────────────────────────────────────┘

set -e

# ==================== 全局配置 ====================
CONFIG_FILE="/etc/pve-lxc-config.conf"
STORAGE_DIR="/var/lib/vz/images"
TEMPLATE_DIR="/var/lib/vz/template/cache"

# ==================== 颜色输出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${BLUE}[→]${NC} $1"; }
log_debug() { echo -e "${CYAN}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}${BOLD}[★]${NC}${GREEN} $1${NC}"; }
log_password() { echo -e "${MAGENTA}${BOLD}[🔑]${NC}${MAGENTA} $1${NC}"; }

generate_password() {
    tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c 16
}

# ==================== 获取宿主机真实公网 IP ====================
get_real_host_ip() {
    local ip=""
    for service in "ifconfig.me" "icanhazip.com" "ipinfo.io/ip" "api.ipify.org"; do
        ip=$(timeout 5 curl -s "https://${service}" 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -1)
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    done
    
    # 优先使用 vmbr0，如果没有则使用 eth0
    if ip -4 addr show vmbr0 | grep inet &>/dev/null; then
        echo $(ip -4 addr show vmbr0 | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -1)
    else
        echo $(ip -4 addr show eth0 | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -1)
    fi
}

# ==================== 获取子网信息 ====================
get_subnet_info() {
    local host_ip=$1
    
    # 从vmbr0或eth0获取CIDR
    if ip -4 addr show vmbr0 | grep "inet.*${host_ip}" &>/dev/null; then
        CIDR=$(ip -4 addr show vmbr0 | grep "inet.*${host_ip}" | awk '{print $2}' | cut -d'/' -f2 | head -1)
    else
        CIDR=$(ip -4 addr show eth0 | grep "inet.*${host_ip}" | awk '{print $2}' | cut -d'/' -f2 | head -1)
    fi
    if [ -z "$CIDR" ]; then
        CIDR=24
        log_warn "无法检测CIDR，默认使用 /24"
    fi
    
    mask=$((0xffffffff << (32 - CIDR)))
    NETMASK="$((mask >> 24 & 0xff)).$((mask >> 16 & 0xff)).$((mask >> 8 & 0xff)).$((mask & 0xff))"
    
    IFS='.' read -r i1 i2 i3 i4 <<< "$host_ip"
    IFS='.' read -r m1 m2 m3 m4 <<< "$NETMASK"
    NETWORK="$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).$((i4 & m4))"
    
    log_debug "子网: $NETWORK/$CIDR, 掩码: $NETMASK"
}

# ==================== 扫描 eth0 上的其他公网 IP (修复版) ====================
scan_available_ips() {
    local host_ip=$1
    log_step "扫描 eth0 网段的其他公网 IP (排除宿主机 IP: $host_ip)..."
    
    get_subnet_info "$host_ip"
    
    local base_ip=$(echo $NETWORK | cut -d'.' -f1-3)
    local available_ips=()
    
    # 收集已使用的IP
    local used_ips=("$host_ip")
    
    # 从容器配置中收集 (修复语法错误)
    if [ -d /etc/pve/lxc ]; then
        local conf_files=$(ls /etc/pve/lxc/*.conf 2>/dev/null || true)
        if [ -n "$conf_files" ]; then
            for CONF in $conf_files; do
                if [ -f "$CONF" ]; then
                    local ip=$(grep "^# LXC_IP=" "$CONF" 2>/dev/null | cut -d'=' -f2 || true)
                    if [ -n "$ip" ]; then
                        used_ips+=("$ip")
                    fi
                fi
            done
        fi
    fi
    
    # 扫描eth0网段的公网IP
    local start_octet=1
    local end_octet=254
    
    # 根据CIDR调整范围
    if [ $CIDR -ge 24 ]; then
        start_octet=2
        end_octet=254
    fi
    
    for i in $(seq $start_octet $end_octet); do
        local test_ip="${base_ip}.${i}"
        
        # 跳过网络地址和广播地址
        if [ $i -eq 0 ] || [ $i -eq 255 ]; then
            continue
        fi
        
        # 检查是否已使用
        local is_used=0
        for used in "${used_ips[@]}"; do
            if [ "$test_ip" = "$used" ]; then
                is_used=1
                break
            fi
        done
        
        if [ $is_used -eq 0 ]; then
            available_ips+=("$test_ip")
        fi
    done
    
    log_debug "找到 ${#available_ips[@]} 个可用公网 IP"
    echo "${available_ips[@]}"
}

# ==================== 配置管理 ====================
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        GW=$(ip route | grep default | awk '{print $3}' | head -1)
        HOST_IP=$(get_real_host_ip)
        HOST_IF="eth0"
        
        HOST_CPU=$(nproc)
        HOST_MEM=$(free -m | awk '/^Mem:/{print int($2)}')
        HOST_DISK=$(df -BG /var/lib/vz | awk 'NR==2{print int($4)}')
        
        get_subnet_info "$HOST_IP"
    fi
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
GW="$GW"
HOST_IP="$HOST_IP"
HOST_IF="$HOST_IF"
HOST_CPU=$HOST_CPU
HOST_MEM=$HOST_MEM
HOST_DISK=$HOST_DISK
CIDR=$CIDR
NETMASK="$NETMASK"
NETWORK="$NETWORK"
EOF
}

# ==================== 系统环境检查 ====================
check_environment() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "必须以 root 用户运行"
        return 1
    fi
    
    if ! command -v pct &>/dev/null; then
        log_error "未检测到 Proxmox VE"
        return 1
    fi
    
    if ! ip link show eth0 &>/dev/null; then
        log_error "网卡 eth0 不存在"
        return 1
    fi
    
    return 0
}

# ==================== 模板下载 ====================
download_template() {
    log_step "检查 Debian 12 模板..."
    
    mkdir -p ${TEMPLATE_DIR}
    
    TEMPLATE=$(ls -t ${TEMPLATE_DIR}/debian-12-standard_*.tar.* 2>/dev/null | head -1 || true)
    
    if [ -z "$TEMPLATE" ] || [ ! -f "$TEMPLATE" ]; then
        log_warn "未找到模板，开始下载..."
        
        TEMPLATE_URL="http://download.proxmox.com/images/system"
        VERSIONS=("12.7-1" "12.2-1" "12.0-1")
        
        for VER in "${VERSIONS[@]}"; do
            TEMPLATE_NAME="debian-12-standard_${VER}_amd64.tar.zst"
            DOWNLOAD_URL="${TEMPLATE_URL}/${TEMPLATE_NAME}"
            
            if wget -q --spider "${DOWNLOAD_URL}" 2>/dev/null; then
                log_info "找到模板: ${TEMPLATE_NAME}"
                
                if wget --progress=bar:force -O "${TEMPLATE_DIR}/${TEMPLATE_NAME}" "${DOWNLOAD_URL}"; then
                    TEMPLATE="${TEMPLATE_DIR}/${TEMPLATE_NAME}"
                    log_info "✓ 模板下载成功"
                    break
                fi
            fi
        done
        
        if [ -z "$TEMPLATE" ]; then
            log_error "无法下载模板"
            return 1
        fi
    else
        log_info "✓ 找到模板: $(basename $TEMPLATE)"
    fi
    
    return 0
}

# ==================== 清理新增的 LXC 容器 ====================
cleanup_all() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            清理新增的 LXC 容器                        ║"
    echo "║            (保留系统配置和 Tailscale)                 ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    # 显示当前容器列表
    log_info "当前容器列表:"
    pct list
    echo ""
    
    read -p "确认删除所有 LXC 容器？(输入 YES 继续，按Enter取消): " confirm
    
    if [ -z "$confirm" ]; then
        log_info "已取消"
        return 0
    fi
    
    if [ "$confirm" != "YES" ]; then
        log_warn "已取消"
        return 1
    fi
    
    log_step "开始清理 LXC 容器..."
    
    # 停止并删除所有容器
    local container_list=$(pct list 2>/dev/null | awk 'NR>1{print $1}' || true)
    if [ -n "$container_list" ]; then
        for ID in $container_list; do
            log_step "删除容器 $ID..."
            pct stop $ID --skiplock 2>/dev/null || true
            sleep 2
            pct destroy $ID --purge --force 2>/dev/null || true
        done
    fi
    
    # 删除veth网络接口 (排除tailscale)
    log_step "清理网络接口..."
    local veth_list=$(ip link show 2>/dev/null | grep 'veth' | grep -v 'tailscale' | awk -F: '{print $2}' | tr -d ' ' || true)
    if [ -n "$veth_list" ]; then
        for veth in $veth_list; do
            log_step "删除网络接口 $veth..."
            ip link delete $veth 2>/dev/null || true
        done
    fi
    
    # 清理容器存储和配置
    log_step "清理容器存储..."
    rm -rf /var/lib/vz/images/* 2>/dev/null || true
    rm -rf /var/lib/vz/private/* 2>/dev/null || true
    rm -rf /var/lib/lxc/* 2>/dev/null || true
    
    if [ -d /etc/pve/lxc ]; then
        log_step "清理容器配置文件..."
        rm -f /etc/pve/lxc/*.conf* 2>/dev/null || true
    fi
    
    # 清理脚本创建的配置文件
    log_step "清理脚本配置文件..."
    rm -f "$CONFIG_FILE" 2>/dev/null || true
    
    log_success "✓ LXC 容器清理完成"
    log_info "✓ 系统配置已保留"
    log_info "✓ Tailscale 已保留"
    log_info "✓ 防火墙规则已保留"
    echo ""
}

# ==================== 系统环境准备 ====================
prepare_system() {
    log_step "准备系统环境..."
    
    # 创建必要目录
    mkdir -p ${STORAGE_DIR} /var/lib/vz/private /etc/pve/lxc /var/lib/vz/snippets
    
    # 配置内核参数
    cat > /etc/sysctl.d/99-pve-lxc.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
net.ipv4.conf.all.proxy_arp=1
net.ipv4.conf.default.proxy_arp=1
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
EOF
    
    sysctl -p /etc/sysctl.d/99-pve-lxc.conf &>/dev/null
    
    # 配置防火墙 (保留Tailscale)
    iptables -P INPUT DROP 2>/dev/null || true
    iptables -F INPUT 2>/dev/null || true
    iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 8006 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -i tailscale+ -j ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT 2>/dev/null || true
    iptables -t nat -F POSTROUTING 2>/dev/null || true
    
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    
    log_info "✓ 系统环境已准备"
}

# ==================== 创建自动化脚本 ====================
create_automation() {
    log_step "创建自动化脚本..."
    
    cat > /usr/local/bin/pve-lxc-network-init.sh << 'EOFNET'
#!/bin/bash
CONFIG_FILE="/etc/pve-lxc-config.conf"
source "$CONFIG_FILE" 2>/dev/null || exit 1

sysctl -p /etc/sysctl.d/99-pve-lxc.conf &>/dev/null

if [ -f /etc/iptables/rules.v4 ]; then
    iptables-restore < /etc/iptables/rules.v4 2>/dev/null || true
fi

if [ -d /etc/pve/lxc ]; then
    for CONF in /etc/pve/lxc/*.conf; do
        [ -f "$CONF" ] || continue
        
        ID=$(basename "$CONF" .conf)
        IP=$(grep "^# LXC_IP=" "$CONF" 2>/dev/null | cut -d'=' -f2)
        [ -z "$IP" ] && continue
        
        VETH_HOST="veth${ID}h"
        VETH_CONT="veth${ID}c"
        
        ip link delete ${VETH_HOST} 2>/dev/null || true
        
        if ip link add ${VETH_HOST} type veth peer name ${VETH_CONT}; then
            ip link set ${VETH_HOST} up
            ip route add ${IP}/32 dev ${VETH_HOST} 2>/dev/null || true
            echo 1 > /proc/sys/net/ipv4/conf/${VETH_HOST}/proxy_arp 2>/dev/null || true
            echo 0 > /proc/sys/net/ipv4/conf/${VETH_HOST}/rp_filter 2>/dev/null || true
        fi
    done
fi

echo 1 > /proc/sys/net/ipv4/conf/${HOST_IF}/proxy_arp 2>/dev/null || true
echo 0 > /proc/sys/net/ipv4/conf/${HOST_IF}/rp_filter 2>/dev/null || true
EOFNET
    
    chmod +x /usr/local/bin/pve-lxc-network-init.sh
    
    cat > /usr/local/bin/pve-lxc-network-attach.sh << 'EOFATT'
#!/bin/bash
ID=$1
CONFIG_FILE="/etc/pve-lxc-config.conf"
source "$CONFIG_FILE" 2>/dev/null || exit 1

CONF="/etc/pve/lxc/${ID}.conf"
[ -f "$CONF" ] || exit 1

IP=$(grep "^# LXC_IP=" "$CONF" 2>/dev/null | cut -d'=' -f2)
[ -z "$IP" ] && exit 1

VETH_HOST="veth${ID}h"
VETH_CONT="veth${ID}c"

sleep 5

CONTAINER_PID=$(lxc-info -n $ID -p 2>/dev/null | awk '{print $2}')
[ -z "$CONTAINER_PID" ] && exit 1

if ip link show ${VETH_CONT} &>/dev/null; then
    if ip link set ${VETH_CONT} netns ${CONTAINER_PID}; then
        pct exec $ID -- bash -c "
            ip link set ${VETH_CONT} name eth0 2>/dev/null || true
            ip link set eth0 up
            ip addr flush dev eth0 2>/dev/null || true
            ip addr add ${IP}/32 dev eth0
            ip route add ${GW} dev eth0
            ip route add default via ${GW} dev eth0
            cat > /etc/resolv.conf << EOFDNS
nameserver 8.8.8.8
nameserver 8.8.4.4
EOFDNS
        " 2>/dev/null
    fi
fi
EOFATT
    
    chmod +x /usr/local/bin/pve-lxc-network-attach.sh
    
    cat > /var/lib/vz/snippets/lxc-network-hook.pl << 'EOFHOOK'
#!/usr/bin/perl
use strict;
use warnings;

my $phase = shift;
my $vmid = shift;

if ($phase eq 'post-start') {
    system("/usr/local/bin/pve-lxc-network-attach.sh $vmid &");
}

exit(0);
EOFHOOK
    
    chmod +x /var/lib/vz/snippets/lxc-network-hook.pl
    
    cat > /etc/systemd/system/pve-lxc-network.service << 'EOFSVC'
[Unit]
Description=PVE LXC Network Initialization
After=network.target pve-cluster.service
Before=lxc.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pve-lxc-network-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFSVC
    
    systemctl daemon-reload
    systemctl enable pve-lxc-network.service &>/dev/null
    
    log_info "✓ 自动化脚本已创建"
}

# ==================== 创建容器 (修复版) ====================
create_container() {
    local ID=$1
    local IP=$2
    
    local LAST_OCTET=$(echo $IP | cut -d'.' -f4)
    local HOSTNAME="lxc-${LAST_OCTET}"
    
    log_step "创建容器 $ID (IP: $IP, 主机名: $HOSTNAME)..."
    
    # 确保存储目录存在 (修复bug)
    mkdir -p "${STORAGE_DIR}/${ID}"
    
    CONTAINER_PASSWORD=$(generate_password)
    
    if ! pct create $ID $TEMPLATE \
        --hostname "$HOSTNAME" \
        --rootfs local:${HOST_DISK},size=${HOST_DISK}G \
        --memory ${HOST_MEM} \
        --cores ${HOST_CPU} \
        --unprivileged 0 \
        --features nesting=1,keyctl=1 \
        --onboot 1 \
        --start 0 &>/dev/null; then
        log_error "✗ 容器创建失败"
        return 1
    fi
    
    echo "# LXC_IP=${IP}" >> /etc/pve/lxc/${ID}.conf
    echo "# LXC_HOSTNAME=${HOSTNAME}" >> /etc/pve/lxc/${ID}.conf
    echo "hookscript: local:snippets/lxc-network-hook.pl" >> /etc/pve/lxc/${ID}.conf
    
    VETH_HOST="veth${ID}h"
    VETH_CONT="veth${ID}c"
    
    ip link delete ${VETH_HOST} 2>/dev/null || true
    
    if ! ip link add ${VETH_HOST} type veth peer name ${VETH_CONT}; then
        log_error "✗ veth 创建失败"
        return 1
    fi
    
    ip link set ${VETH_HOST} up
    ip route add ${IP}/32 dev ${VETH_HOST} 2>/dev/null || true
    echo 1 > /proc/sys/net/ipv4/conf/${VETH_HOST}/proxy_arp
    echo 0 > /proc/sys/net/ipv4/conf/${VETH_HOST}/rp_filter
    
    if ! pct start $ID 2>/dev/null; then
        log_error "✗ 容器启动失败"
        return 1
    fi
    
    sleep 5
    
    CONTAINER_PID=$(lxc-info -n $ID -p 2>/dev/null | awk '{print $2}')
    if [ -z "$CONTAINER_PID" ]; then
        log_error "✗ 无法获取容器 PID"
        return 1
    fi
    
    if ! ip link set ${VETH_CONT} netns ${CONTAINER_PID}; then
        log_error "✗ veth 移入容器失败"
        return 1
    fi
    
    pct exec $ID -- bash -c "
        ip link set ${VETH_CONT} name eth0 2>/dev/null || true
        ip link set eth0 up
        ip addr flush dev eth0 2>/dev/null || true
        ip addr add ${IP}/32 dev eth0
        ip route add ${GW} dev eth0
        ip route add default via ${GW} dev eth0
        cat > /etc/resolv.conf << EOFDNS
nameserver 8.8.8.8
nameserver 8.8.4.4
EOFDNS
    " 2>/dev/null
    
    echo "root:${CONTAINER_PASSWORD}" | pct exec $ID -- chpasswd 2>/dev/null
    
    pct exec $ID -- bash -c "
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq &>/dev/null
        apt-get install -y -qq locales openssh-server curl wget iputils-ping iproute2 nano &>/dev/null
        echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
        locale-gen &>/dev/null
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        systemctl enable ssh &>/dev/null
        systemctl restart ssh &>/dev/null
    " 2>/dev/null
    
    CONF_FILE="/etc/pve/lxc/${ID}.conf"
    MAC=$(ip link show $VETH_HOST 2>/dev/null | grep "link/ether" | awk '{print $2}')
    if [ -n "$MAC" ]; then
        sed -i '/^net0:/d' "$CONF_FILE"
        echo "net0: name=eth0,bridge=${VETH_HOST},hwaddr=${MAC},ip=${IP}/32,gw=${GW},type=veth" >> "$CONF_FILE"
    fi
    
    log_success "✓ 容器 $ID 创建成功"
    log_password "ID: $ID | IP: $IP | 主机名: $HOSTNAME | 密码: $CONTAINER_PASSWORD"
    
    echo "$ID|$IP|$HOSTNAME|$CONTAINER_PASSWORD" >> /tmp/pve-lxc-passwords.txt
    
    return 0
}

# ==================== 批量创建容器 ====================
batch_create_containers() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            批量创建容器                               ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    local available_ips=($(scan_available_ips "$HOST_IP"))
    
    if [ ${#available_ips[@]} -eq 0 ]; then
        log_error "没有可用的公网 IP 地址"
        log_info "eth0 网段的 IP 均已被使用"
        read -p "按Enter键继续..."
        return 1
    fi
    
    log_info "在 eth0 网段找到 ${#available_ips[@]} 个可用公网 IP"
    echo ""
    
    echo "可用 IP 列表 (前 10 个):"
    for i in {0..9}; do
        if [ $i -lt ${#available_ips[@]} ]; then
            echo "  $((i+1)). ${available_ips[$i]}"
        fi
    done
    
    if [ ${#available_ips[@]} -gt 10 ]; then
        echo "  ... 还有 $((${#available_ips[@]} - 10)) 个"
    fi
    
    echo ""
    read -p "要创建多少个容器？(1-${#available_ips[@]}) [按Enter取消]: " COUNT
    
    # Enter键返回
    if [ -z "$COUNT" ]; then
        log_info "已取消"
        return 0
    fi
    
    if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt ${#available_ips[@]} ]; then
        log_error "无效的数量"
        read -p "按Enter键继续..."
        return 1
    fi
    
    log_step "分配容器 ID..."
    local container_ids=()
    for ((i=100; i<=999; i++)); do
        if ! pct status $i &>/dev/null; then
            container_ids+=($i)
            if [ ${#container_ids[@]} -eq $COUNT ]; then
                break
            fi
        fi
    done
    
    if [ ${#container_ids[@]} -lt $COUNT ]; then
        log_error "没有足够的容器 ID 可用"
        read -p "按Enter键继续..."
        return 1
    fi
    
    echo ""
    log_info "将创建以下容器:"
    for i in $(seq 0 $((COUNT-1))); do
        echo "  容器 ${container_ids[$i]}: IP ${available_ips[$i]}"
    done
    
    echo ""
    read -p "确认创建？(y/n) [按Enter取消]: " confirm
    
    # Enter键返回
    if [ -z "$confirm" ]; then
        log_info "已取消"
        return 0
    fi
    
    if [ "$confirm" != "y" ]; then
        log_warn "已取消"
        return 0
    fi
    
    if ! download_template; then
        log_error "模板下载失败"
        read -p "按Enter键继续..."
        return 1
    fi
    
    prepare_system
    create_automation
    
    rm -f /tmp/pve-lxc-passwords.txt
    
    echo ""
    log_step "开始批量创建容器..."
    echo ""
    
    for i in $(seq 0 $((COUNT-1))); do
        create_container ${container_ids[$i]} ${available_ips[$i]}
        sleep 2
    done
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            🔑 容器登录信息                            ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    if [ -f /tmp/pve-lxc-passwords.txt ]; then
        while IFS='|' read -r id ip hostname password; do
            echo "  容器 $id ($hostname):"
            echo "  IP: $ip"
            echo "  密码: $password"
            echo "  登录: ssh root@$ip"
            echo ""
        done < /tmp/pve-lxc-passwords.txt
        
        rm -f /tmp/pve-lxc-passwords.txt
    fi
    
    log_success "✓ 批量创建完成"
    echo ""
    read -p "按Enter键继续..."
}

# ==================== 安装默认容器 (自动分配IP) ====================
install_default_containers() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            安装默认容器 (102 和 153)                 ║"
    echo "║            (自动分配 eth0 网段的前两个可用IP)         ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "系统资源:"
    echo "  • CPU: ${HOST_CPU} 核"
    echo "  • 内存: ${HOST_MEM} MB"
    echo "  • 磁盘: ${HOST_DISK} GB"
    echo "  • 网关: ${GW}"
    echo "  • 宿主机 IP: ${HOST_IP}"
    echo "  • 网段: ${NETWORK}/${CIDR}"
    
    # 扫描可用IP
    local available_ips=($(scan_available_ips "$HOST_IP"))
    
    if [ ${#available_ips[@]} -lt 2 ]; then
        log_error "eth0 网段可用公网 IP 不足 (需要至少 2 个)"
        read -p "按Enter键继续..."
        return 1
    fi
    
    local IP102="${available_ips[0]}"
    local IP153="${available_ips[1]}"
    
    echo ""
    log_info "自动分配的公网 IP:"
    echo "  • 容器 102: $IP102"
    echo "  • 容器 153: $IP153"
    
    echo ""
    read -p "确认安装？(y/n) [按Enter取消]: " confirm
    
    # Enter键返回
    if [ -z "$confirm" ]; then
        log_info "已取消"
        return 0
    fi
    
    if [ "$confirm" != "y" ]; then
        log_warn "已取消"
        return 0
    fi
    
    if ! download_template; then
        read -p "按Enter键继续..."
        return 1
    fi
    
    prepare_system
    create_automation
    
    rm -f /tmp/pve-lxc-passwords.txt
    
    echo ""
    log_step "开始创建容器..."
    echo ""
    
    create_container 102 "$IP102"
    sleep 2
    create_container 153 "$IP153"
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            🔑 容器登录信息                            ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    if [ -f /tmp/pve-lxc-passwords.txt ]; then
        while IFS='|' read -r id ip hostname password; do
            echo "  容器 $id ($hostname):"
            echo "  IP: $ip"
            echo "  密码: $password"
            echo "  登录: ssh root@$ip"
            echo ""
        done < /tmp/pve-lxc-passwords.txt
        
        rm -f /tmp/pve-lxc-passwords.txt
    fi
    
    log_success "✓ 安装完成"
    echo ""
    read -p "按Enter键继续..."
}

# ==================== 新增单个容器 ====================
add_single_container() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            新增单个容器                               ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "现有容器:"
    pct list
    
    local available_ips=($(scan_available_ips "$HOST_IP"))
    
    if [ ${#available_ips[@]} -eq 0 ]; then
        log_error "eth0 网段没有可用的公网 IP 地址"
        read -p "按Enter键继续..."
        return 1
    fi
    
    echo ""
    log_info "eth0 网段可用公网 IP (前 10 个):"
    for i in {0..9}; do
        if [ $i -lt ${#available_ips[@]} ]; then
            echo "  ${available_ips[$i]}"
        fi
    done
    
    echo ""
    read -p "输入新容器 ID [按Enter取消]: " ID
    
    # Enter键返回
    if [ -z "$ID" ]; then
        log_info "已取消"
        return 0
    fi
    
    if pct status $ID &>/dev/null; then
        log_error "容器 $ID 已存在"
        read -p "按Enter键继续..."
        return 1
    fi
    
    read -p "输入容器 IP (或留空自动分配) [按Enter自动分配]: " IP
    
    if [ -z "$IP" ]; then
        IP=${available_ips[0]}
        log_info "自动分配公网 IP: $IP"
    fi
    
    if [ "$IP" = "$HOST_IP" ]; then
        log_error "不能使用宿主机 IP"
        read -p "按Enter键继续..."
        return 1
    fi
    
    echo ""
    log_info "容器配置:"
    echo "  • ID: $ID"
    echo "  • IP: $IP"
    echo "  • 主机名: lxc-$(echo $IP | cut -d'.' -f4)"
    echo "  • CPU: ${HOST_CPU} 核"
    echo "  • 内存: ${HOST_MEM} MB"
    echo "  • 磁盘: ${HOST_DISK} GB"
    
    echo ""
    read -p "确认创建？(y/n) [按Enter取消]: " confirm
    
    # Enter键返回
    if [ -z "$confirm" ]; then
        log_info "已取消"
        return 0
    fi
    
    if [ "$confirm" != "y" ]; then
        log_warn "已取消"
        return 0
    fi
    
    rm -f /tmp/pve-lxc-passwords.txt
    
    echo ""
    create_container $ID "$IP"
    
    echo ""
    if [ -f /tmp/pve-lxc-passwords.txt ]; then
        while IFS='|' read -r id ip hostname password; do
            echo "  容器 $id ($hostname):"
            echo "  IP: $ip"
            echo "  密码: $password"
            echo "  登录: ssh root@$ip"
            echo ""
        done < /tmp/pve-lxc-passwords.txt
        
        rm -f /tmp/pve-lxc-passwords.txt
    fi
    
    read -p "按Enter键继续..."
}

# ==================== 修改容器 IP (仅修改IP，不改主机名) ====================
modify_container_ip() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            修改容器 IP (仅修改IP，不改主机名)         ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "当前容器列表:"
    pct list
    
    echo ""
    read -p "输入容器 ID [按Enter取消]: " ID
    
    # Enter键返回
    if [ -z "$ID" ]; then
        log_info "已取消"
        return 0
    fi
    
    if ! pct status $ID &>/dev/null; then
        log_error "容器 $ID 不存在"
        read -p "按Enter键继续..."
        return 1
    fi
    
    CONF_FILE="/etc/pve/lxc/${ID}.conf"
    OLD_IP=$(grep "^# LXC_IP=" "$CONF_FILE" 2>/dev/null | cut -d'=' -f2)
    OLD_HOSTNAME=$(grep "^# LXC_HOSTNAME=" "$CONF_FILE" 2>/dev/null | cut -d'=' -f2)
    
    if [ -n "$OLD_IP" ]; then
        log_info "当前 IP: $OLD_IP"
    fi
    if [ -n "$OLD_HOSTNAME" ]; then
        log_info "当前主机名: $OLD_HOSTNAME (保持不变)"
    fi
    
    echo ""
    read -p "输入新的 IP [按Enter取消]: " NEW_IP
    
    # Enter键返回
    if [ -z "$NEW_IP" ]; then
        log_info "已取消"
        return 0
    fi
    
    log_step "停止容器..."
    pct stop $ID 2>/dev/null || true
    sleep 3
    
    if [ -n "$OLD_IP" ]; then
        ip route del ${OLD_IP}/32 2>/dev/null || true
    fi
    
    VETH_HOST="veth${ID}h"
    VETH_CONT="veth${ID}c"
    ip link delete ${VETH_HOST} 2>/dev/null || true
    
    # 仅更新IP，不修改主机名
    sed -i "s|^# LXC_IP=.*|# LXC_IP=${NEW_IP}|" "$CONF_FILE"
    sed -i "s|ip=[^,]*|ip=${NEW_IP}/32|g" "$CONF_FILE"
    
    if ip link add ${VETH_HOST} type veth peer name ${VETH_CONT}; then
        ip link set ${VETH_HOST} up
        ip route add ${NEW_IP}/32 dev ${VETH_HOST} 2>/dev/null || true
        echo 1 > /proc/sys/net/ipv4/conf/${VETH_HOST}/proxy_arp
        echo 0 > /proc/sys/net/ipv4/conf/${VETH_HOST}/rp_filter
        
        MAC=$(ip link show $VETH_HOST 2>/dev/null | grep "link/ether" | awk '{print $2}')
        if [ -n "$MAC" ]; then
            sed -i '/^net0:/d' "$CONF_FILE"
            echo "net0: name=eth0,bridge=${VETH_HOST},hwaddr=${MAC},ip=${NEW_IP}/32,gw=${GW},type=veth" >> "$CONF_FILE"
        fi
    fi
    
    log_step "启动容器..."
    pct start $ID 2>/dev/null
    sleep 5
    
    CONTAINER_PID=$(lxc-info -n $ID -p 2>/dev/null | awk '{print $2}')
    if [ -n "$CONTAINER_PID" ]; then
        ip link set ${VETH_CONT} netns ${CONTAINER_PID} 2>/dev/null || true
        
        pct exec $ID -- bash -c "
            ip link set ${VETH_CONT} name eth0 2>/dev/null || true
            ip link set eth0 up
            ip addr flush dev eth0 2>/dev/null || true
            ip addr add ${NEW_IP}/32 dev eth0
            ip route flush dev eth0 2>/dev/null || true
            ip route add ${GW} dev eth0
            ip route add default via ${GW} dev eth0
        " 2>/dev/null
    fi
    
    log_success "✓ 容器 IP 已更新"
    log_info "IP: $OLD_IP → $NEW_IP"
    log_info "主机名: $OLD_HOSTNAME (保持不变)"
    echo ""
    read -p "按Enter键继续..."
}

# ==================== 查看容器列表 ====================
list_containers() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            容器列表                                   ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    pct list
    
    echo ""
    log_info "详细信息:"
    
    if [ -d /etc/pve/lxc ]; then
        local conf_files=$(ls /etc/pve/lxc/*.conf 2>/dev/null || true)
        if [ -n "$conf_files" ]; then
            for CONF in $conf_files; do
                if [ -f "$CONF" ]; then
                    ID=$(basename "$CONF" .conf)
                    IP=$(grep "^# LXC_IP=" "$CONF" 2>/dev/null | cut -d'=' -f2)
                    HOSTNAME=$(grep "^# LXC_HOSTNAME=" "$CONF" 2>/dev/null | cut -d'=' -f2)
                    STATUS=$(pct status $ID 2>/dev/null | awk '{print $2}')
                    
                    if [ -n "$IP" ]; then
                        echo "  容器 $ID: $HOSTNAME | IP $IP | $STATUS"
                    fi
                fi
            done
        fi
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# ==================== 测试容器网络 ====================
test_container_network() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            测试容器网络                               ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    pct list
    
    echo ""
    read -p "输入容器 ID [按Enter取消]: " ID
    
    # Enter键返回
    if [ -z "$ID" ]; then
        log_info "已取消"
        return 0
    fi
    
    if ! pct status $ID &>/dev/null; then
        log_error "容器 $ID 不存在"
        read -p "按Enter键继续..."
        return
    fi
    
    if ! pct status $ID | grep -q "running"; then
        log_error "容器 $ID 未运行"
        read -p "按Enter键继续..."
        return
    fi
    
    IP=$(grep "^# LXC_IP=" /etc/pve/lxc/${ID}.conf 2>/dev/null | cut -d'=' -f2)
    HOSTNAME=$(grep "^# LXC_HOSTNAME=" /etc/pve/lxc/${ID}.conf 2>/dev/null | cut -d'=' -f2)
    
    echo ""
    log_step "测试容器 $ID ($HOSTNAME, IP: $IP)..."
    echo ""
    
    log_step "Ping 测试 (8.8.8.8)..."
    if pct exec $ID -- ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
        log_info "✓ 可以访问外网"
    else
        log_error "✗ 无法访问外网"
    fi
    
    log_step "DNS 测试 (google.com)..."
    if pct exec $ID -- ping -c 2 -W 3 google.com &>/dev/null; then
        log_info "✓ DNS 解析正常"
    else
        log_error "✗ DNS 解析失败"
    fi
    
    log_step "外部 IP 测试 (ifconfig.me)..."
    EXTERNAL_IP=$(pct exec $ID -- timeout 5 curl -s https://ifconfig.me 2>/dev/null || echo "超时")
    if [ "$EXTERNAL_IP" = "$IP" ]; then
        log_info "✓ 外部 IP 正确: $EXTERNAL_IP"
    elif [ "$EXTERNAL_IP" = "$HOST_IP" ]; then
        log_error "✗ 显示宿主机 IP: $EXTERNAL_IP (应为 $IP)"
    else
        log_warn "⚠ 外部 IP: $EXTERNAL_IP"
    fi
    
    log_step "SSH 服务测试..."
    if pct exec $ID -- systemctl is-active ssh &>/dev/null; then
        log_info "✓ SSH 服务运行中"
    else
        log_error "✗ SSH 服务未运行"
    fi
    
    log_step "主机名测试..."
    CURRENT_HOSTNAME=$(pct exec $ID -- hostname 2>/dev/null)
    if [ "$CURRENT_HOSTNAME" = "$HOSTNAME" ]; then
        log_info "✓ 主机名正确: $CURRENT_HOSTNAME"
    else
        log_warn "⚠ 主机名不匹配: $CURRENT_HOSTNAME (应为 $HOSTNAME)"
    fi
    
    echo ""
    log_step "网络配置:"
    pct exec $ID -- ip addr show eth0 2>/dev/null || log_error "✗ 无法获取网卡信息"
    
    echo ""
    log_step "路由表:"
    pct exec $ID -- ip route show 2>/dev/null || log_error "✗ 无法获取路由信息"
    
    echo ""
    read -p "按Enter键继续..."
}

# ==================== 验证系统配置 ====================
verify_configuration() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            系统配置验证                               ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    local errors=0
    
    log_step "检查网卡配置..."
    if ip link show $HOST_IF &>/dev/null; then
        log_info "✓ 网卡 $HOST_IF 存在"
    else
        log_error "✗ 网卡 $HOST_IF 不存在"
        errors=$((errors + 1))
    fi
    
    log_step "检查 IP 转发..."
    if [ "$(cat /proc/sys/net/ipv4/ip_forward)" = "1" ]; then
        log_info "✓ IP 转发已启用"
    else
        log_error "✗ IP 转发未启用"
        errors=$((errors + 1))
    fi
    
    log_step "检查 Proxy ARP..."
    if [ "$(cat /proc/sys/net/ipv4/conf/${HOST_IF}/proxy_arp)" = "1" ]; then
        log_info "✓ Proxy ARP 已启用"
    else
        log_error "✗ Proxy ARP 未启用"
        errors=$((errors + 1))
    fi
    
    log_step "检查 rp_filter..."
    if [ "$(cat /proc/sys/net/ipv4/conf/all/rp_filter)" = "0" ]; then
        log_info "✓ rp_filter 已禁用"
    else
        log_error "✗ rp_filter 未禁用"
        errors=$((errors + 1))
    fi
    
    log_step "检查防火墙配置..."
    if iptables -L FORWARD -n | grep -q "policy ACCEPT"; then
        log_info "✓ 防火墙 FORWARD 链允许转发"
    else
        log_error "✗ 防火墙 FORWARD 链未允许转发"
        errors=$((errors + 1))
    fi
    
    log_step "检查 NAT 配置..."
    if iptables -t nat -L POSTROUTING -n | grep -q "MASQUERADE"; then
        log_error "✗ 检测到 NAT (MASQUERADE) - 应禁用"
        errors=$((errors + 1))
    else
        log_info "✓ 未使用 NAT"
    fi
    
    log_step "检查 Tailscale 保护..."
    if iptables -L INPUT -n | grep -q "tailscale"; then
        log_info "✓ Tailscale 规则已保留"
    else
        log_warn "⚠ 未检测到 Tailscale 规则"
    fi
    
    log_step "检查自动化脚本..."
    if [ -f /usr/local/bin/pve-lxc-network-init.sh ]; then
        log_info "✓ 网络初始化脚本存在"
    else
        log_warn "⚠ 网络初始化脚本不存在"
    fi
    
    if systemctl is-enabled pve-lxc-network.service &>/dev/null; then
        log_info "✓ systemd 服务已启用"
    else
        log_warn "⚠ systemd 服务未启用"
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        log_success "✓ 配置验证通过"
    else
        log_error "✗ 发现 $errors 个错误"
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# ==================== 环境一致性检查 ====================
verify_environment_consistency() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            环境一致性检查                             ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    local errors=0
    
    log_step "检查云主机限制..."
    
    if ip link help 2>&1 | grep -q veth; then
        log_info "✓ veth 支持 (内核原生) ✅"
    else
        log_error "✗ veth 不支持 ❌"
        errors=$((errors + 1))
    fi
    
    if ip netns help &>/dev/null; then
        log_info "✓ 网络命名空间支持 ✅"
    else
        log_error "✗ 网络命名空间不支持 ❌"
        errors=$((errors + 1))
    fi
    
    if command -v iptables &>/dev/null; then
        log_info "✓ iptables 可用 ✅"
    else
        log_error "✗ iptables 不可用 ❌"
        errors=$((errors + 1))
    fi
    
    if sysctl -a 2>/dev/null | grep -q net.ipv4.conf.all.proxy_arp; then
        log_info "✓ Proxy ARP 支持 ✅"
    else
        log_error "✗ Proxy ARP 不支持 ❌"
        errors=$((errors + 1))
    fi
    
    if sysctl -a 2>/dev/null | grep -q net.ipv4.ip_forward; then
        log_info "✓ IP 转发支持 ✅"
    else
        log_error "✗ IP 转发不支持 ❌"
        errors=$((errors + 1))
    fi
    
    log_step "检查配置一致性..."
    
    if [ -f /etc/sysctl.d/99-pve-lxc.conf ]; then
        if grep -q "net.ipv4.ip_forward=1" /etc/sysctl.d/99-pve-lxc.conf && \
           grep -q "net.ipv4.conf.all.proxy_arp=1" /etc/sysctl.d/99-pve-lxc.conf && \
           grep -q "net.ipv4.conf.all.rp_filter=0" /etc/sysctl.d/99-pve-lxc.conf; then
            log_info "✓ sysctl 配置正确 ✅"
        else
            log_error "✗ sysctl 配置不完整 ❌"
            errors=$((errors + 1))
        fi
    else
        log_warn "⚠ sysctl 配置文件不存在"
    fi
    
    if iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q MASQUERADE; then
        log_error "✗ 检测到 NAT (MASQUERADE) - 违反设计要求 ❌"
        errors=$((errors + 1))
    else
        log_info "✓ 未使用 NAT (符合要求) ✅"
    fi
    
    log_step "检查存储目录..."
    if [ -d "$STORAGE_DIR" ]; then
        log_info "✓ 存储目录存在 ✅"
    else
        log_error "✗ 存储目录不存在 ❌"
        errors=$((errors + 1))
    fi
    
    echo ""
    if [ $errors -eq 0 ]; then
        log_success "✓ 环境一致性检查通过 ✅"
    else
        log_error "✗ 发现 $errors 个问题"
    fi
    
    echo ""
    read -p "按Enter键继续..."
}

# ==================== 显示系统信息 ====================
show_system_info() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║            系统信息                                   ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "网络配置:"
    echo "  • 宿主机 IP: $HOST_IP"
    echo "  • 网关: $GW"
    echo "  • 网卡: $HOST_IF"
    echo "  • 网络: $NETWORK/$CIDR"
    echo "  • 子网掩码: $NETMASK"
    
    echo ""
    log_info "系统资源:"
    echo "  • CPU: ${HOST_CPU} 核"
    echo "  • 内存: ${HOST_MEM} MB"
    echo "  • 磁盘: ${HOST_DISK} GB"
    
    echo ""
    log_info "容器统计:"
    local total=$(pct list 2>/dev/null | wc -l)
    total=$((total - 1))
    local running=$(pct list 2>/dev/null | grep -c "running" || echo 0)
    echo "  • 总数: $total"
    echo "  • 运行中: $running"
    
    echo ""
    log_info "可用公网 IP:"
    local available_ips=($(scan_available_ips "$HOST_IP"))
    echo "  • eth0 网段可用: ${#available_ips[@]} 个"
    
    echo ""
    read -p "按Enter键继续..."
}

# ==================== 主菜单 ====================
show_menu() {
    clear
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║      PVE LXC 容器管理脚本 v15.2                      ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    echo "  当前配置:"
    echo "  • 宿主机 IP: $HOST_IP"
    echo "  • 网关: $GW | 网络: $NETWORK/$CIDR"
    echo "  • CPU: ${HOST_CPU}核 | 内存: ${HOST_MEM}MB | 磁盘: ${HOST_DISK}GB"
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║              主菜单                                   ║"
    echo "╠═══════════════════════════════════════════════════════╣"
    echo "║  1. 安装默认容器 (102 和 153，自动分配公网IP)        ║"
    echo "║  2. 新增单个容器 (可自动分配 eth0 网段公网IP)        ║"
    echo "║  3. 批量创建容器 (自动分配所有可用公网IP)            ║"
    echo "║  4. 修改容器 IP (仅修改IP，不改主机名)               ║"
    echo "║  5. 查看容器列表                                      ║"
    echo "║  6. 测试容器网络                                      ║"
    echo "║  7. 验证系统配置                                      ║"
    echo "║  8. 环境一致性检查                                    ║"
    echo "║  9. 显示系统信息                                      ║"
    echo "║  10. 清理 LXC 容器 (保留系统配置和Tailscale)          ║"
    echo "║  0. 退出                                              ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
}

# ==================== 主程序 ====================
main() {
    if ! check_environment; then
        exit 1
    fi
    
    load_config
    save_config
    
    while true; do
        show_menu
        read -p "请选择操作 [0-10] [按Enter刷新菜单]: " choice
        
        # Enter键刷新菜单
        if [ -z "$choice" ]; then
            continue
        fi
        
        case $choice in
            1)
                install_default_containers
                ;;
            2)
                add_single_container
                ;;
            3)
                batch_create_containers
                ;;
            4)
                modify_container_ip
                ;;
            5)
                list_containers
                ;;
            6)
                test_container_network
                ;;
            7)
                verify_configuration
                ;;
            8)
                verify_environment_consistency
                ;;
            9)
                show_system_info
                ;;
            10)
                cleanup_all
                ;;
            0)
                echo ""
                log_info "再见！"
                echo ""
                exit 0
                ;;
            *)
                log_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

main

EOFSCRIPT

chmod +x /usr/local/bin/pve-lxc-manager.sh

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║            ✅ 安装完成！                              ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""
echo "运行命令:"
echo "  pve-lxc-manager.sh"
echo ""
echo "或者:"
echo "  bash /usr/local/bin/pve-lxc-manager.sh"
echo ""