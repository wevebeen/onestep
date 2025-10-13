#!/bin/bash

# 网络环境检测与修复脚本
# 包含全面的网络检测、备份和修复功能
# 支持交互式菜单、带备注备份、配置查看和恢复功能

# 版本信息
SCRIPT_VERSION="1.7.8"
SCRIPT_BUILD="$(date '+%Y%m%d-%H%M%S')"
SCRIPT_NAME="网络环境检测与修复脚本"

# 脚本配置
SSH_PORT="22"
BACKUP_DIR="$HOME/network_backup"
LOG_FILE="$HOME/network_fix.log"

# 颜色输出函数
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[34m\033[01m$@\033[0m"; }

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查环境
check_environment() {
    # 检查操作系统（测试时跳过）
    if [[ "$OSTYPE" != "linux-gnu"* ]] && [[ "$OSTYPE" != "darwin"* ]]; then
        _red "❌ 此脚本需要在Linux服务器上执行"
        exit 1
    fi
    
    # 检查root权限（测试时跳过）
    if [[ $EUID -ne 0 ]] && [[ "$OSTYPE" == "linux-gnu"* ]]; then
        _red "❌ 此脚本需要root权限执行"
        _yellow "💡 请使用: sudo bash $0"
        exit 1
    fi
    
    # 权限问题说明
    _blue "ℹ️ 权限说明:"
    _blue "   - 某些系统文件可能受到保护，恢复时会出现权限错误"
    _blue "   - 这是正常现象，脚本会尝试恢复并提示手动操作"
    _blue "   - 如果遇到权限问题，请手动复制备份文件到对应位置"
    echo
    
    # 检查关键文件权限
    check_file_permissions() {
        local files=("/etc/hostname" "/etc/hosts" "/etc/network/interfaces" "/etc/resolv.conf")
        local protected_files=()
        
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                # 检查文件是否可写
                if [ ! -w "$file" ]; then
                    protected_files+=("$file")
                fi
                
                # 检查文件属性
                if command -v lsattr >/dev/null 2>&1; then
                    local attrs=$(lsattr "$file" 2>/dev/null | cut -d' ' -f1)
                    if [[ "$attrs" == *"i"* ]]; then
                        protected_files+=("$file (不可变)")
                    fi
                fi
            fi
        done
        
        if [ ${#protected_files[@]} -gt 0 ]; then
            _yellow "⚠️ 检测到受保护的文件:"
            for file in "${protected_files[@]}"; do
                _yellow "   - $file"
            done
            _yellow "💡 建议在恢复前先解除保护: chattr -i <文件>"
            echo
        fi
    }
    
    check_file_permissions
    
    # 创建必要目录
    mkdir -p "$BACKUP_DIR"
    
    log "环境检查完成"
}

# 显示菜单
show_menu() {
    clear
    _blue "=========================================="
    _blue "        网络环境检测与修复脚本 v$SCRIPT_VERSION"
    _blue "=========================================="
    echo
    _yellow "请选择操作:"
    echo "1. 全面查看网络环境"
    echo "2. 查看备份列表"
    echo "3. 备份当前网络环境"
    echo "4. 恢复网络配置"
    echo "5. 检测22端口"
    echo "0. 退出"
    echo
}

# 1. 全面查看网络环境
view_comprehensive_network() {
    _blue "=== 全面网络环境检测 ==="
    
    echo
    _yellow "1. 系统基本信息:"
    echo "操作系统: $(uname -a)"
    echo "内核版本: $(uname -r)"
    echo "架构: $(uname -m)"
    echo "主机名: $(hostname)"
    echo "当前用户: $(whoami)"
    echo "当前时间: $(date)"
    
    echo
    _yellow "2. 网络接口详细信息:"
    if command -v ip >/dev/null 2>&1; then
        ip addr show
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig -a
    else
        echo "无法获取网络接口信息"
    fi
    
    echo
    _yellow "3. 路由表信息:"
    if command -v ip >/dev/null 2>&1; then
        ip route show
    elif command -v route >/dev/null 2>&1; then
        route -n
    else
        echo "无法获取路由表信息"
    fi
    
    echo
    _yellow "4. DNS配置:"
    if [ -f "/etc/resolv.conf" ]; then
        cat /etc/resolv.conf
    else
        echo "无法读取DNS配置文件"
    fi
    
    echo
    _yellow "5. 网络服务状态:"
    if command -v systemctl >/dev/null 2>&1; then
        echo "NetworkManager状态:"
        systemctl status NetworkManager --no-pager -l 2>/dev/null || echo "NetworkManager未运行"
        echo
        echo "networking服务状态:"
        systemctl status networking --no-pager -l 2>/dev/null || echo "networking服务未运行"
    else
        echo "无法检查网络服务状态"
    fi
    
    echo
    _yellow "6. 防火墙状态:"
    if command -v ufw >/dev/null 2>&1; then
        echo "UFW防火墙状态:"
        ufw status verbose
    elif command -v iptables >/dev/null 2>&1; then
        echo "iptables防火墙规则:"
        iptables -L -n -v
    elif command -v firewall-cmd >/dev/null 2>&1; then
        echo "firewalld防火墙状态:"
        firewall-cmd --state 2>/dev/null || echo "firewalld未运行"
        firewall-cmd --list-all 2>/dev/null || echo "无法获取firewalld配置"
    else
        echo "未检测到防火墙"
    fi
    
    echo
    _yellow "7. 监听端口:"
    if command -v ss >/dev/null 2>&1; then
        echo "TCP监听端口:"
        ss -tlnp
        echo
        echo "UDP监听端口:"
        ss -ulnp
    elif command -v netstat >/dev/null 2>&1; then
        echo "TCP监听端口:"
        netstat -tlnp
        echo
        echo "UDP监听端口:"
        netstat -ulnp
    else
        echo "无法获取端口监听信息"
    fi
    
    echo
    _yellow "8. 网络连接状态:"
    if command -v ss >/dev/null 2>&1; then
        echo "TCP连接:"
        ss -tnp
        echo
        echo "UDP连接:"
        ss -unp
    elif command -v netstat >/dev/null 2>&1; then
        echo "TCP连接:"
        netstat -tnp
        echo
        echo "UDP连接:"
        netstat -unp
    else
        echo "无法获取网络连接信息"
    fi
    
    echo
    _yellow "9. 网络统计信息:"
    if [ -f "/proc/net/dev" ]; then
        echo "网络接口统计:"
        cat /proc/net/dev
    fi
    
    if [ -f "/proc/net/snmp" ]; then
        echo
        echo "网络协议统计:"
        cat /proc/net/snmp
    fi
    
    echo
    _yellow "10. ARP表:"
    if command -v ip >/dev/null 2>&1; then
        ip neigh show
    elif command -v arp >/dev/null 2>&1; then
        arp -a
    else
        echo "无法获取ARP表"
    fi
    
    echo
    _yellow "11. 网络连通性测试:"
    echo "测试本地回环:"
    ping -c 3 127.0.0.1 2>/dev/null || echo "本地回环测试失败"
    
    echo
    echo "测试网关连通性:"
    gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    if [ -n "$gateway" ]; then
        ping -c 3 "$gateway" 2>/dev/null || echo "网关连通性测试失败"
    else
        echo "无法获取网关信息"
    fi
    
    echo
    echo "测试DNS解析:"
    nslookup google.com 2>/dev/null || echo "DNS解析测试失败"
    
    echo
    echo "测试外网连通性:"
    ping -c 3 8.8.8.8 2>/dev/null || echo "外网连通性测试失败"
    
    echo
    _yellow "12. 网络配置文件:"
    echo "主机名配置:"
    if [ -f "/etc/hostname" ]; then
        cat /etc/hostname
    fi
    
    echo
    echo "主机映射:"
    if [ -f "/etc/hosts" ]; then
        cat /etc/hosts
    fi
    
    echo
    echo "网络接口配置:"
    if [ -d "/etc/netplan" ]; then
        echo "Netplan配置:"
        ls -la /etc/netplan/
        for file in /etc/netplan/*.yaml; do
            if [ -f "$file" ]; then
                echo "文件: $file"
                cat "$file"
                echo
            fi
        done
    elif [ -f "/etc/network/interfaces" ]; then
        echo "传统网络配置:"
        cat /etc/network/interfaces
    fi
    
    echo
    _yellow "13. 系统资源使用:"
    echo "内存使用:"
    free -h
    
    echo
    echo "磁盘使用:"
    df -h
    
    echo
    echo "CPU负载:"
    uptime
    
    echo
    _yellow "14. 网络转发和NAT配置:"
    echo "IP转发状态:"
    if [ -f "/proc/sys/net/ipv4/ip_forward" ]; then
        echo "IPv4转发: $(cat /proc/sys/net/ipv4/ip_forward)"
    fi
    if [ -f "/proc/sys/net/ipv6/conf/all/forwarding" ]; then
        echo "IPv6转发: $(cat /proc/sys/net/ipv6/conf/all/forwarding)"
    fi
    
    echo
    echo "NAT规则 (iptables):"
    if command -v iptables >/dev/null 2>&1; then
        echo "NAT表规则:"
        iptables -t nat -L -n -v 2>/dev/null || echo "无法获取NAT规则"
        echo
        echo "MASQUERADE规则:"
        iptables -t nat -L POSTROUTING -n -v 2>/dev/null || echo "无法获取MASQUERADE规则"
    else
        echo "iptables未安装"
    fi
    
    echo
    _yellow "15. 网络桥接和VLAN:"
    if command -v brctl >/dev/null 2>&1; then
        echo "网桥信息:"
        brctl show 2>/dev/null || echo "无法获取网桥信息"
    elif command -v bridge >/dev/null 2>&1; then
        echo "网桥信息:"
        bridge link show 2>/dev/null || echo "无法获取网桥信息"
    else
        echo "网桥工具未安装"
    fi
    
    echo
    echo "VLAN配置:"
    if command -v ip >/dev/null 2>&1; then
        ip link show type vlan 2>/dev/null || echo "无VLAN配置"
    else
        echo "无法检查VLAN配置"
    fi
    
    echo
    _yellow "16. 网络隧道和VPN:"
    echo "隧道接口:"
    if command -v ip >/dev/null 2>&1; then
        ip link show type tun 2>/dev/null || echo "无TUN接口"
        ip link show type tap 2>/dev/null || echo "无TAP接口"
        ip link show type gre 2>/dev/null || echo "无GRE隧道"
        ip link show type sit 2>/dev/null || echo "无SIT隧道"
    else
        echo "无法检查隧道接口"
    fi
    
    echo
    echo "VPN服务状态:"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status openvpn --no-pager -l 2>/dev/null || echo "OpenVPN未运行"
        systemctl status strongswan --no-pager -l 2>/dev/null || echo "StrongSwan未运行"
        systemctl status wireguard --no-pager -l 2>/dev/null || echo "WireGuard未运行"
    else
        echo "无法检查VPN服务"
    fi
    
    echo
    _yellow "17. 网络QoS和流量控制:"
    echo "TC (Traffic Control) 规则:"
    if command -v tc >/dev/null 2>&1; then
        tc qdisc show 2>/dev/null || echo "无QoS规则"
        tc class show 2>/dev/null || echo "无流量分类"
        tc filter show 2>/dev/null || echo "无流量过滤"
    else
        echo "TC工具未安装"
    fi
    
    echo
    _yellow "18. 网络安全配置:"
    echo "SSH配置:"
    if [ -f "/etc/ssh/sshd_config" ]; then
        echo "SSH端口: $(grep -E '^Port' /etc/ssh/sshd_config 2>/dev/null || echo '默认22')"
        echo "SSH协议: $(grep -E '^Protocol' /etc/ssh/sshd_config 2>/dev/null || echo '默认2')"
        echo "SSH登录: $(grep -E '^PermitRootLogin' /etc/ssh/sshd_config 2>/dev/null || echo '默认no')"
    else
        echo "SSH配置文件不存在"
    fi
    
    echo
    echo "SSL证书:"
    if [ -d "/etc/ssl/certs" ]; then
        echo "SSL证书目录: /etc/ssl/certs"
        ls -la /etc/ssl/certs/ | head -5
    fi
    
    echo
    _yellow "19. 网络代理配置:"
    echo "环境变量代理:"
    echo "HTTP_PROXY: ${HTTP_PROXY:-未设置}"
    echo "HTTPS_PROXY: ${HTTPS_PROXY:-未设置}"
    echo "NO_PROXY: ${NO_PROXY:-未设置}"
    
    echo
    echo "系统代理配置:"
    if [ -f "/etc/environment" ]; then
        grep -i proxy /etc/environment 2>/dev/null || echo "无代理配置"
    fi
    
    echo
    _yellow "20. 网络时间同步:"
    echo "NTP服务状态:"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status ntp --no-pager -l 2>/dev/null || echo "NTP未运行"
        systemctl status chrony --no-pager -l 2>/dev/null || echo "Chrony未运行"
        systemctl status systemd-timesyncd --no-pager -l 2>/dev/null || echo "systemd-timesyncd未运行"
    else
        echo "无法检查时间同步服务"
    fi
    
    echo
    echo "NTP配置:"
    if [ -f "/etc/ntp.conf" ]; then
        grep -E '^server|^pool' /etc/ntp.conf 2>/dev/null || echo "无NTP服务器配置"
    elif [ -f "/etc/chrony.conf" ]; then
        grep -E '^server|^pool' /etc/chrony.conf 2>/dev/null || echo "无Chrony服务器配置"
    else
        echo "无NTP配置文件"
    fi
    
    echo
    _yellow "21. 网络存储配置:"
    echo "NFS服务状态:"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status nfs-server --no-pager -l 2>/dev/null || echo "NFS服务未运行"
        systemctl status nfs-kernel-server --no-pager -l 2>/dev/null || echo "NFS内核服务未运行"
    else
        echo "无法检查NFS服务"
    fi
    
    echo
    echo "SMB/CIFS服务状态:"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status smbd --no-pager -l 2>/dev/null || echo "SMB服务未运行"
        systemctl status nmbd --no-pager -l 2>/dev/null || echo "NetBIOS服务未运行"
    else
        echo "无法检查SMB服务"
    fi
    
    echo
    _yellow "22. 网络监控配置:"
    echo "SNMP服务状态:"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status snmpd --no-pager -l 2>/dev/null || echo "SNMP服务未运行"
    else
        echo "无法检查SNMP服务"
    fi
    
    echo
    echo "网络监控工具:"
    if command -v netstat >/dev/null 2>&1; then
        echo "netstat: 已安装"
    fi
    if command -v ss >/dev/null 2>&1; then
        echo "ss: 已安装"
    fi
    if command -v tcpdump >/dev/null 2>&1; then
        echo "tcpdump: 已安装"
    fi
    if command -v wireshark >/dev/null 2>&1; then
        echo "wireshark: 已安装"
    fi
    
    echo
    _yellow "23. 网络相关进程:"
    ps aux | grep -E "(network|dhcp|dns|sshd|ntp|chrony|openvpn|strongswan|wireguard|nfs|smb|snmp)" | grep -v grep
    
    echo
    _green "✓ 全面网络环境检测完成 (共23项检测)"
    log "全面网络环境检测完成 (共23项检测)"
}

# 2. 备份当前网络环境
backup_network_config() {
    _blue "=== 备份网络配置 ==="
    
    # 获取备份备注
    echo -n "请输入备份备注: "
    read backup_note
    backup_note=$(echo "$backup_note" | xargs)
    if [ -z "$backup_note" ]; then
        backup_note="手动备份"
    fi
    
    # 创建备份目录
    backup_timestamp=$(date '+%Y%m%d-%H%M%S')
    backup_path="$BACKUP_DIR/backup_$backup_timestamp"
    mkdir -p "$backup_path"
    
    # 备份网络配置
    _green "正在备份网络配置..."
    
    # 备份网络接口配置
    if [ -d "/etc/netplan" ]; then
        cp -r /etc/netplan "$backup_path/"
    fi
    
    if [ -f "/etc/network/interfaces" ]; then
        cp /etc/network/interfaces "$backup_path/"
    fi
    
    # 备份当前网络接口状态（包括secondary IP）
    if command -v ip >/dev/null 2>&1; then
        ip addr show > "$backup_path/current_interfaces.txt"
        ip route show > "$backup_path/current_routes.txt"
    elif command -v ifconfig >/dev/null 2>&1; then
        ifconfig -a > "$backup_path/current_interfaces.txt"
        route -n > "$backup_path/current_routes.txt"
    fi
    
    # 备份防火墙配置
    if command -v ufw >/dev/null 2>&1; then
        ufw status > "$backup_path/ufw_status.txt"
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        iptables-save > "$backup_path/iptables_rules.txt"
        iptables -t nat -L -n -v > "$backup_path/iptables_nat.txt" 2>/dev/null || true
        iptables -t mangle -L -n -v > "$backup_path/iptables_mangle.txt" 2>/dev/null || true
    fi
    
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --list-all > "$backup_path/firewalld_config.txt" 2>/dev/null || true
    fi
    
    # 备份DNS配置
    cp /etc/resolv.conf "$backup_path/" 2>/dev/null || true
    
    # 备份主机名配置
    cp /etc/hostname "$backup_path/" 2>/dev/null || true
    cp /etc/hosts "$backup_path/" 2>/dev/null || true
    
    # 备份网络转发配置
    if [ -f "/proc/sys/net/ipv4/ip_forward" ]; then
        cat /proc/sys/net/ipv4/ip_forward > "$backup_path/ipv4_forward.txt" 2>/dev/null || true
    fi
    if [ -f "/proc/sys/net/ipv6/conf/all/forwarding" ]; then
        cat /proc/sys/net/ipv6/conf/all/forwarding > "$backup_path/ipv6_forward.txt" 2>/dev/null || true
    fi
    
    # 备份网络桥接配置
    if command -v brctl >/dev/null 2>&1; then
        brctl show > "$backup_path/bridge_info.txt" 2>/dev/null || true
    fi
    
    # 备份SSH配置
    if [ -f "/etc/ssh/sshd_config" ]; then
        cp /etc/ssh/sshd_config "$backup_path/"
    fi
    
    # 备份NTP配置
    if [ -f "/etc/ntp.conf" ]; then
        cp /etc/ntp.conf "$backup_path/"
    fi
    if [ -f "/etc/chrony.conf" ]; then
        cp /etc/chrony.conf "$backup_path/"
    fi
    
    # 备份网络代理配置
    if [ -f "/etc/environment" ]; then
        cp /etc/environment "$backup_path/"
    fi
    
    # 备份网络存储配置
    if [ -f "/etc/exports" ]; then
        cp /etc/exports "$backup_path/"
    fi
    if [ -f "/etc/samba/smb.conf" ]; then
        cp /etc/samba/smb.conf "$backup_path/"
    fi
    
    # 备份SNMP配置
    if [ -f "/etc/snmp/snmpd.conf" ]; then
        cp /etc/snmp/snmpd.conf "$backup_path/"
    fi
    
    # 备份网络管理器配置
    if [ -d "/etc/NetworkManager" ]; then
        cp -r /etc/NetworkManager "$backup_path/"
    fi
    
    # 备份DHCP配置
    if [ -f "/etc/dhcp/dhcpd.conf" ]; then
        cp /etc/dhcp/dhcpd.conf "$backup_path/"
    fi
    if [ -f "/etc/dhcpcd.conf" ]; then
        cp /etc/dhcpcd.conf "$backup_path/"
    fi
    
    # 保存备份信息
    cat > "$backup_path/backup_info.txt" << EOF
备份时间: $(date '+%Y-%m-%d %H:%M:%S')
备份备注: $backup_note
脚本版本: $SCRIPT_VERSION
系统信息: $(uname -a)
EOF
    
    _green "✓ 备份创建成功"
    _green "备份路径: $backup_path"
    _green "备份备注: $backup_note"
    
    log "创建备份: $backup_path, 备注: $backup_note"
    
    echo
    echo -n "按回车键继续..."
    read
    return 1
}

# 3. 检测22端口
check_ssh_port() {
    _blue "=== SSH端口检测 ==="
    
    # 获取服务器IP
    server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || hostname -I | awk '{print $1}')
    
    if [ -z "$server_ip" ]; then
        _red "❌ 无法获取服务器公网IP"
        return 1
    fi
    
    _green "服务器公网IP: $server_ip"
    _green "检测端口: $SSH_PORT"
    
    # 本地检测
    _yellow "本地检测结果:"
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnp | grep ":$SSH_PORT " >/dev/null; then
            _green "✓ SSH服务正在监听端口 $SSH_PORT"
        else
            _red "❌ SSH服务未在端口 $SSH_PORT 监听"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp | grep ":$SSH_PORT " >/dev/null; then
            _green "✓ SSH服务正在监听端口 $SSH_PORT"
        else
            _red "❌ SSH服务未在端口 $SSH_PORT 监听"
        fi
    fi
    
    # 第三方API检测（仅显示成功）
    _yellow "第三方API检测结果:"
    
    # canyouseeme.org
    if curl -s "https://canyouseeme.org/api/port/$SSH_PORT/$server_ip" | grep -q '"status":"open"'; then
        _green "✓ canyouseeme.org: 端口 $SSH_PORT 开放"
    fi
    
    # portchecker.co
    if curl -s "https://portchecker.co/check" -d "port=$SSH_PORT&ip=$server_ip" | grep -q "open"; then
        _green "✓ portchecker.co: 端口 $SSH_PORT 开放"
    fi
    
    # whatismyipaddress.com
    if curl -s "https://whatismyipaddress.com/port-scanner" -d "port=$SSH_PORT&ip=$server_ip" | grep -q "open"; then
        _green "✓ whatismyipaddress.com: 端口 $SSH_PORT 开放"
    fi
    
    # yougetsignal.com
    if curl -s "https://www.yougetsignal.com/tools/open-ports/" -d "remoteAddress=$server_ip&portNumber=$SSH_PORT" | grep -q "open"; then
        _green "✓ yougetsignal.com: 端口 $SSH_PORT 开放"
    fi
    
    _green "检测完成"
    log "SSH端口检测完成"
    
    echo
    echo -n "按回车键继续..."
    read
    return 1
}

# 5. 查看备份列表
view_backup_list() {
    _blue "=== 查看备份列表 ==="
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR")" ]; then
        _yellow "ℹ️ 没有找到任何网络配置备份。"
        log "没有找到任何网络配置备份"
        return 1
    fi
    
    _yellow "可用的备份:"
    local backups=()
    local i=1
    for dir in "$BACKUP_DIR"/backup_*/; do
        if [ -d "$dir" ]; then
            local backup_name=$(basename "$dir")
            local backup_info_file="$dir/backup_info.txt"
            local backup_note="无备注"
            local backup_time="未知时间"
            local backup_files=""
            
            if [ -f "$backup_info_file" ]; then
                backup_time=$(sed -n 's/备份时间: *//p' "$backup_info_file" | head -1)
                backup_note=$(sed -n 's/备份备注: *//p' "$backup_info_file" | head -1)
            fi
            
            # 统计备份文件数量
            local file_count=$(find "$dir" -type f -not -name "backup_info.txt" | wc -l)
            
            _yellow "$i. $backup_name"
            echo "   时间: $backup_time"
            echo "   备注: $backup_note"
            echo "   文件数: $file_count"
            
            # 显示备份的文件列表
            echo "   备份文件:"
            find "$dir" -type f -not -name "backup_info.txt" -printf "     %f\n" 2>/dev/null || \
            find "$dir" -type f -not -name "backup_info.txt" -exec basename {} \; 2>/dev/null | sed 's/^/     /'
            
            backups+=("$dir")
            i=$((i+1))
            echo
        fi
    done
    
    if [ ${#backups[@]} -eq 0 ]; then
        _yellow "ℹ️ 没有找到任何有效的网络配置备份。"
        log "没有找到任何有效的网络配置备份"
        return 1
    fi
    
    echo -n "请输入要查看的备份编号 (1-${#backups[@]}) 或按回车返回: "
    read choice
    choice=$(echo "$choice" | xargs)
    
    if [ -z "$choice" ]; then
        return 1
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#backups[@]} )); then
        _red "❌ 无效的备份编号。"
        log "ERROR: 无效的备份编号: $choice"
        return 1
    fi
    
    local selected_backup_path="${backups[$((choice-1))]}"
    _yellow "查看备份: $(basename "$selected_backup_path")"
    
    # 显示备份详细信息
    if [ -f "$selected_backup_path/backup_info.txt" ]; then
        echo
        _yellow "备份信息:"
        cat "$selected_backup_path/backup_info.txt"
    fi
    
    echo
    _yellow "备份文件内容:"
    for file in "$selected_backup_path"/*; do
        if [ -f "$file" ] && [ "$(basename "$file")" != "backup_info.txt" ]; then
            echo
            _blue "文件: $(basename "$file")"
            echo "----------------------------------------"
            if [[ "$file" == *.txt ]] || [[ "$file" == *.conf ]] || [[ "$file" == *.yaml ]]; then
                cat "$file" 2>/dev/null || echo "无法读取文件内容"
            else
                echo "二进制文件，无法显示内容"
            fi
        fi
    done
    
    _green "✓ 备份查看完成"
    log "查看备份: $(basename "$selected_backup_path")"
    
    echo
    echo -n "按回车键继续..."
    read
    return 1
}


# 4. 恢复网络配置
restore_network_config() {
    _blue "=== 恢复网络配置 ==="
    
    # 显示可用备份
    if [ ! -d "$BACKUP_DIR" ] || [ ! "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        _red "❌ 没有找到任何备份"
        return 1
    fi
    
    _yellow "可用备份:"
    backups=()
    i=1
    for backup in "$BACKUP_DIR"/backup_*; do
        if [ -d "$backup" ]; then
            backup_name=$(basename "$backup")
            backup_time=$(echo "$backup_name" | sed 's/backup_//')
            if [ -f "$backup/backup_info.txt" ]; then
                backup_note=$(sed -n 's/备份备注: *//p' "$backup/backup_info.txt" | head -1)
                echo "  $i. $backup_name - $backup_note"
            else
                echo "  $i. $backup_name"
            fi
            backups+=("$backup")
            ((i++))
        fi
    done
    
    echo
    echo -n "请选择要恢复的备份 (1-$((i-1))): "
    read choice
    choice=$(echo "$choice" | xargs)
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge "$i" ]; then
        _red "❌ 无效的选择"
        return 1
    fi
    
    selected_backup="${backups[$((choice-1))]}"
    
    # 显示将要恢复的配置
    _yellow "将要恢复的配置:"
    if [ -f "$selected_backup/backup_info.txt" ]; then
        cat "$selected_backup/backup_info.txt"
    fi
    
    echo
    echo -n "确认恢复此配置? (y/N): "
    read confirm
    confirm=$(echo "$confirm" | xargs | tr '[:upper:]' '[:lower:]')
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "yes" ]; then
        _yellow "取消恢复"
        return 1
    fi
    
    # 按分类对比当前配置和备份配置
    _blue "🔍 按分类对比当前配置和备份配置..."
    local changed_files=()
    echo
    
    # 1. 基础系统配置对比
    _yellow "1️⃣ 基础系统配置对比:"
    local basic_files=("hostname" "hosts" "environment")
    for file in "${basic_files[@]}"; do
        local backup_file="$selected_backup/$file"
        local current_file=""
        
        case "$file" in
            "hostname") current_file="/etc/hostname" ;;
            "hosts") current_file="/etc/hosts" ;;
            "environment") current_file="/etc/environment" ;;
        esac
        
        if [ -f "$backup_file" ] && [ -f "$current_file" ]; then
            if ! diff -q "$backup_file" "$current_file" >/dev/null 2>&1; then
                changed_files+=("$file")
                _yellow "  📝 $file 有修改"
            else
                _green "  ✓ $file 无修改"
            fi
        elif [ -f "$backup_file" ] && [ ! -f "$current_file" ]; then
            changed_files+=("$file (备份存在，当前不存在)")
            _blue "  ℹ️ 恢复时会创建文件: $current_file"
        elif [ ! -f "$backup_file" ] && [ -f "$current_file" ]; then
            changed_files+=("$file (备份不存在，当前存在)")
            _red "  ⚠️ 恢复时会删除当前文件: $current_file"
        else
            _blue "  ⏭️ $file 跳过 (备份和当前都不存在)"
        fi
    done
    echo
    
    # 2. 网络接口配置对比
    _yellow "2️⃣ 网络接口配置对比:"
    local network_files=("interfaces")
    local network_dirs=("netplan" "NetworkManager")
    
    for file in "${network_files[@]}"; do
        local backup_file="$selected_backup/$file"
        local current_file=""
        
        case "$file" in
            "interfaces") current_file="/etc/network/interfaces" ;;
        esac
        
        if [ -f "$backup_file" ] && [ -f "$current_file" ]; then
            if ! diff -q "$backup_file" "$current_file" >/dev/null 2>&1; then
                changed_files+=("$file")
                _yellow "  📝 $file 有修改"
            else
                _green "  ✓ $file 无修改"
            fi
        elif [ -f "$backup_file" ] && [ ! -f "$current_file" ]; then
            changed_files+=("$file (备份存在，当前不存在)")
            _blue "  ℹ️ 恢复时会创建文件: $current_file"
        elif [ ! -f "$backup_file" ] && [ -f "$current_file" ]; then
            changed_files+=("$file (备份不存在，当前存在)")
            _red "  ⚠️ 恢复时会删除当前文件: $current_file"
        else
            _blue "  ⏭️ $file 跳过 (备份和当前都不存在)"
        fi
    done
    
    # 检查网络接口状态
    if [ -f "$selected_backup/current_interfaces.txt" ]; then
        _green "  ✓ 网络接口状态备份存在"
    else
        _blue "  ⏭️ 网络接口状态备份不存在"
    fi
    
    # 检查目录
    for dir in "${network_dirs[@]}"; do
        local backup_dir="$selected_backup/$dir"
        local current_dir=""
        
        case "$dir" in
            "netplan") current_dir="/etc/netplan" ;;
            "NetworkManager") current_dir="/etc/NetworkManager" ;;
        esac
        
        if [ -d "$backup_dir" ] && [ -d "$current_dir" ]; then
            if ! diff -r "$backup_dir" "$current_dir" >/dev/null 2>&1; then
                changed_files+=("$dir (目录有修改)")
                _yellow "  📝 $dir 目录有修改"
            else
                _green "  ✓ $dir 目录无修改"
            fi
        elif [ -d "$backup_dir" ] && [ ! -d "$current_dir" ]; then
            changed_files+=("$dir (备份存在，当前不存在)")
            _blue "  ℹ️ 恢复时会创建目录: $current_dir"
        elif [ ! -d "$backup_dir" ] && [ -d "$current_dir" ]; then
            changed_files+=("$dir (备份不存在，当前存在)")
            _red "  ⚠️ 恢复时会删除当前目录: $current_dir"
        else
            _blue "  ⏭️ $dir 跳过 (备份和当前都不存在)"
        fi
    done
    echo
    
    # 3. DNS配置对比
    _yellow "3️⃣ DNS配置对比:"
    if [ -f "$selected_backup/resolv.conf" ] && [ -f "/etc/resolv.conf" ]; then
        if ! diff -q "$selected_backup/resolv.conf" "/etc/resolv.conf" >/dev/null 2>&1; then
            changed_files+=("resolv.conf")
            _yellow "  📝 resolv.conf 有修改"
        else
            _green "  ✓ resolv.conf 无修改"
        fi
    elif [ -f "$selected_backup/resolv.conf" ] && [ ! -f "/etc/resolv.conf" ]; then
        changed_files+=("resolv.conf (备份存在，当前不存在)")
        _blue "  ℹ️ 恢复时会创建文件: /etc/resolv.conf"
    elif [ ! -f "$selected_backup/resolv.conf" ] && [ -f "/etc/resolv.conf" ]; then
        changed_files+=("resolv.conf (备份不存在，当前存在)")
        _red "  ⚠️ 恢复时会删除当前文件: /etc/resolv.conf"
    else
        _blue "  ⏭️ resolv.conf 跳过 (备份和当前都不存在)"
    fi
    echo
    
    # 4. 防火墙配置对比
    _yellow "4️⃣ 防火墙配置对比:"
    local firewall_files=("ufw_status.txt" "iptables_rules.txt" "iptables_nat.txt" "iptables_mangle.txt" "firewalld_config.txt")
    for file in "${firewall_files[@]}"; do
        local backup_file="$selected_backup/$file"
        if [ -f "$backup_file" ]; then
            _green "  ✓ $file 备份存在"
        else
            _blue "  ⏭️ $file 跳过 (备份不存在)"
        fi
    done
    echo
    
    # 5. 网络转发配置对比
    _yellow "5️⃣ 网络转发配置对比:"
    local forward_files=("ipv4_forward.txt" "ipv6_forward.txt")
    for file in "${forward_files[@]}"; do
        local backup_file="$selected_backup/$file"
        if [ -f "$backup_file" ]; then
            _green "  ✓ $file 备份存在"
        else
            _blue "  ⏭️ $file 跳过 (备份不存在)"
        fi
    done
    echo
    
    # 6. SSH配置对比
    _yellow "6️⃣ SSH配置对比:"
    if [ -f "$selected_backup/sshd_config" ] && [ -f "/etc/ssh/sshd_config" ]; then
        if ! diff -q "$selected_backup/sshd_config" "/etc/ssh/sshd_config" >/dev/null 2>&1; then
            changed_files+=("sshd_config")
            _yellow "  📝 sshd_config 有修改"
        else
            _green "  ✓ sshd_config 无修改"
        fi
    elif [ -f "$selected_backup/sshd_config" ] && [ ! -f "/etc/ssh/sshd_config" ]; then
        changed_files+=("sshd_config (备份存在，当前不存在)")
        _blue "  ℹ️ 恢复时会创建文件: /etc/ssh/sshd_config"
    elif [ ! -f "$selected_backup/sshd_config" ] && [ -f "/etc/ssh/sshd_config" ]; then
        changed_files+=("sshd_config (备份不存在，当前存在)")
        _red "  ⚠️ 恢复时会删除当前文件: /etc/ssh/sshd_config"
    else
        _blue "  ⏭️ sshd_config 跳过 (备份和当前都不存在)"
    fi
    echo
    
    # 7. 时间同步配置对比
    _yellow "7️⃣ 时间同步配置对比:"
    local time_files=("ntp.conf" "chrony.conf")
    for file in "${time_files[@]}"; do
        local backup_file="$selected_backup/$file"
        local current_file=""
        
        case "$file" in
            "ntp.conf") current_file="/etc/ntp.conf" ;;
            "chrony.conf") current_file="/etc/chrony.conf" ;;
        esac
        
        if [ -f "$backup_file" ] && [ -f "$current_file" ]; then
            if ! diff -q "$backup_file" "$current_file" >/dev/null 2>&1; then
                changed_files+=("$file")
                _yellow "  📝 $file 有修改"
            else
                _green "  ✓ $file 无修改"
            fi
        elif [ -f "$backup_file" ] && [ ! -f "$current_file" ]; then
            changed_files+=("$file (备份存在，当前不存在)")
            _blue "  ℹ️ 恢复时会创建文件: $current_file"
        elif [ ! -f "$backup_file" ] && [ -f "$current_file" ]; then
            changed_files+=("$file (备份不存在，当前存在)")
            _red "  ⚠️ 恢复时会删除当前文件: $current_file"
        else
            _blue "  ⏭️ $file 跳过 (备份和当前都不存在)"
        fi
    done
    echo
    
    # 8. 网络存储配置对比
    _yellow "8️⃣ 网络存储配置对比:"
    local storage_files=("exports" "smb.conf")
    for file in "${storage_files[@]}"; do
        local backup_file="$selected_backup/$file"
        local current_file=""
        
        case "$file" in
            "exports") current_file="/etc/exports" ;;
            "smb.conf") current_file="/etc/samba/smb.conf" ;;
        esac
        
        if [ -f "$backup_file" ] && [ -f "$current_file" ]; then
            if ! diff -q "$backup_file" "$current_file" >/dev/null 2>&1; then
                changed_files+=("$file")
                _yellow "  📝 $file 有修改"
            else
                _green "  ✓ $file 无修改"
            fi
        elif [ -f "$backup_file" ] && [ ! -f "$current_file" ]; then
            changed_files+=("$file (备份存在，当前不存在)")
            _blue "  ℹ️ 恢复时会创建文件: $current_file"
        elif [ ! -f "$backup_file" ] && [ -f "$current_file" ]; then
            changed_files+=("$file (备份不存在，当前存在)")
            _red "  ⚠️ 恢复时会删除当前文件: $current_file"
        else
            _blue "  ⏭️ $file 跳过 (备份和当前都不存在)"
        fi
    done
    echo
    
    # 9. 网络监控配置对比
    _yellow "9️⃣ 网络监控配置对比:"
    if [ -f "$selected_backup/snmpd.conf" ] && [ -f "/etc/snmp/snmpd.conf" ]; then
        if ! diff -q "$selected_backup/snmpd.conf" "/etc/snmp/snmpd.conf" >/dev/null 2>&1; then
            changed_files+=("snmpd.conf")
            _yellow "  📝 snmpd.conf 有修改"
        else
            _green "  ✓ snmpd.conf 无修改"
        fi
    elif [ -f "$selected_backup/snmpd.conf" ] && [ ! -f "/etc/snmp/snmpd.conf" ]; then
        changed_files+=("snmpd.conf (备份存在，当前不存在)")
        _blue "  ℹ️ 恢复时会创建文件: /etc/snmp/snmpd.conf"
    elif [ ! -f "$selected_backup/snmpd.conf" ] && [ -f "/etc/snmp/snmpd.conf" ]; then
        changed_files+=("snmpd.conf (备份不存在，当前存在)")
        _red "  ⚠️ 恢复时会删除当前文件: /etc/snmp/snmpd.conf"
    else
        _blue "  ⏭️ snmpd.conf 跳过 (备份和当前都不存在)"
    fi
    echo
    
    # 10. DHCP配置对比
    _yellow "🔟 DHCP配置对比:"
    local dhcp_files=("dhcpd.conf" "dhcpcd.conf")
    for file in "${dhcp_files[@]}"; do
        local backup_file="$selected_backup/$file"
        local current_file=""
        
        case "$file" in
            "dhcpd.conf") current_file="/etc/dhcp/dhcpd.conf" ;;
            "dhcpcd.conf") current_file="/etc/dhcpcd.conf" ;;
        esac
        
        if [ -f "$backup_file" ] && [ -f "$current_file" ]; then
            if ! diff -q "$backup_file" "$current_file" >/dev/null 2>&1; then
                changed_files+=("$file")
                _yellow "  📝 $file 有修改"
            else
                _green "  ✓ $file 无修改"
            fi
        elif [ -f "$backup_file" ] && [ ! -f "$current_file" ]; then
            changed_files+=("$file (备份存在，当前不存在)")
            _blue "  ℹ️ 恢复时会创建文件: $current_file"
        elif [ ! -f "$backup_file" ] && [ -f "$current_file" ]; then
            changed_files+=("$file (备份不存在，当前存在)")
            _red "  ⚠️ 恢复时会删除当前文件: $current_file"
        else
            _blue "  ⏭️ $file 跳过 (备份和当前都不存在)"
        fi
    done
    echo
    
    if [ ${#changed_files[@]} -gt 0 ]; then
        echo
        _yellow "⚠️ 检测到以下文件/目录有修改:"
        for file in "${changed_files[@]}"; do
            _yellow "   - $file"
        done
        echo
    else
        _green "✓ 所有文件和目录都无修改"
        echo
    fi
    
    # 执行恢复
    _green "正在恢复网络配置..."
    
    # 记录恢复的文件和失败原因
    local restored_files=()
    local failed_files=()
    local failed_reasons=()
    
    # 尝试解除文件保护
    _blue "🔓 尝试解除文件保护..."
    local protected_files=("/etc/hostname" "/etc/hosts" "/etc/network/interfaces" "/etc/resolv.conf")
    for file in "${protected_files[@]}"; do
        if [ -f "$file" ] && command -v chattr >/dev/null 2>&1; then
            chattr -i "$file" 2>/dev/null && _green "✓ 已解除 $file 的保护" || true
        fi
    done
    echo
    
    # 删除备份不存在但当前存在的文件
    _blue "🗑️ 删除备份不存在但当前存在的文件..."
    local backup_files=("hostname" "hosts" "interfaces" "resolv.conf" "sshd_config" "ntp.conf" "chrony.conf" "environment" "exports" "smb.conf" "snmpd.conf" "dhcpd.conf" "dhcpcd.conf" "ufw_status.txt" "iptables_rules.txt" "iptables_nat.txt" "iptables_mangle.txt" "firewalld_config.txt" "current_interfaces.txt" "current_routes.txt")
    
    for file in "${backup_files[@]}"; do
        local backup_file="$selected_backup/$file"
        local current_file=""
        
        case "$file" in
            "hostname")
                current_file="/etc/hostname"
                ;;
            "hosts")
                current_file="/etc/hosts"
                ;;
            "interfaces")
                current_file="/etc/network/interfaces"
                ;;
            "resolv.conf")
                current_file="/etc/resolv.conf"
                ;;
            "sshd_config")
                current_file="/etc/ssh/sshd_config"
                ;;
            "ntp.conf")
                current_file="/etc/ntp.conf"
                ;;
            "chrony.conf")
                current_file="/etc/chrony.conf"
                ;;
            "environment")
                current_file="/etc/environment"
                ;;
            "exports")
                current_file="/etc/exports"
                ;;
            "smb.conf")
                current_file="/etc/samba/smb.conf"
                ;;
            "snmpd.conf")
                current_file="/etc/snmp/snmpd.conf"
                ;;
            "dhcpd.conf")
                current_file="/etc/dhcp/dhcpd.conf"
                ;;
            "dhcpcd.conf")
                current_file="/etc/dhcpcd.conf"
                ;;
        esac
        
        # 如果备份不存在但当前存在，删除当前文件
        if [ ! -f "$backup_file" ] && [ -f "$current_file" ]; then
            rm "$current_file" 2>/dev/null && {
                _green "✓ 已删除: $current_file"
            } || {
                _red "❌ 删除失败: $current_file"
            }
        fi
    done
    echo
    
    # 恢复网络配置
    _blue "📋 恢复网络配置..."
    echo
    
    # 基础系统配置
    if [ -f "$selected_backup/hostname" ]; then
        if cp "$selected_backup/hostname" /etc/ 2>/dev/null; then
            _green "✓ /etc/hostname"
            restored_files+=("/etc/hostname")
        else
            _red "❌ /etc/hostname (恢复失败)"
            failed_files+=("/etc/hostname")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    if [ -f "$selected_backup/hosts" ]; then
        if cp "$selected_backup/hosts" /etc/ 2>/dev/null; then
            _green "✓ /etc/hosts"
            restored_files+=("/etc/hosts")
        else
            _red "❌ /etc/hosts (恢复失败)"
            failed_files+=("/etc/hosts")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    if [ -f "$selected_backup/environment" ]; then
        if cp "$selected_backup/environment" /etc/ 2>/dev/null; then
            _green "✓ /etc/environment"
            restored_files+=("/etc/environment")
        else
            _red "❌ /etc/environment (恢复失败)"
            failed_files+=("/etc/environment")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    # 网络接口配置
    if [ -d "$selected_backup/netplan" ]; then
        if cp -r "$selected_backup/netplan" /etc/ 2>/dev/null; then
            _green "✓ /etc/netplan/ (目录)"
            restored_files+=("/etc/netplan")
        else
            _red "❌ /etc/netplan/ (恢复失败)"
            failed_files+=("/etc/netplan")
            failed_reasons+=("权限不足或目录被保护")
        fi
    fi
    
    if [ -f "$selected_backup/interfaces" ]; then
        if cp "$selected_backup/interfaces" /etc/network/ 2>/dev/null; then
            _green "✓ /etc/network/interfaces"
            restored_files+=("/etc/network/interfaces")
        else
            _red "❌ /etc/network/interfaces (恢复失败)"
            failed_files+=("/etc/network/interfaces")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    if [ -d "$selected_backup/NetworkManager" ]; then
        if cp -r "$selected_backup/NetworkManager" /etc/ 2>/dev/null; then
            _green "✓ /etc/NetworkManager/ (目录)"
            restored_files+=("/etc/NetworkManager")
        else
            _red "❌ /etc/NetworkManager/ (恢复失败)"
            failed_files+=("/etc/NetworkManager")
            failed_reasons+=("权限不足或目录被保护")
        fi
    fi
    
    # 网络接口状态恢复
    if [ -f "$selected_backup/current_interfaces.txt" ]; then
        _blue "📋 检测到网络接口状态备份，正在恢复secondary IP地址..."
        
        local interface_name=""
        local primary_ip=""
        local secondary_ips=()
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^[0-9]+:[[:space:]]+([^:]+): ]]; then
                interface_name="${BASH_REMATCH[1]}"
                primary_ip=""
                secondary_ips=()
            fi
            
            if [[ "$line" =~ inet[[:space:]]+([0-9.]+/[0-9]+)[[:space:]]+scope[[:space:]]+global ]]; then
                primary_ip="${BASH_REMATCH[1]}"
            fi
            
            if [[ "$line" =~ inet[[:space:]]+([0-9.]+/[0-9]+)[[:space:]]+scope[[:space:]]+global[[:space:]]+secondary ]]; then
                secondary_ips+=("${BASH_REMATCH[1]}")
            fi
        done < "$selected_backup/current_interfaces.txt"
        
        if [ ${#secondary_ips[@]} -gt 0 ]; then
            _blue "🔍 发现 ${#secondary_ips[@]} 个secondary IP地址需要恢复:"
            for secondary_ip in "${secondary_ips[@]}"; do
                local ip_addr=$(echo "$secondary_ip" | cut -d'/' -f1)
                local cidr=$(echo "$secondary_ip" | cut -d'/' -f2)
                
                if command -v ip >/dev/null 2>&1; then
                    if ip addr add "$ip_addr/$cidr" dev "$interface_name" 2>/dev/null; then
                        _green "✓ 已恢复secondary IP: $ip_addr/$cidr on $interface_name"
                        restored_files+=("secondary_ip:$ip_addr/$cidr")
                    else
                        _red "❌ 恢复secondary IP失败: $ip_addr/$cidr on $interface_name"
                        restored_files+=("secondary_ip:$ip_addr/$cidr (恢复失败)")
                    fi
                else
                    _yellow "⚠️ 无法恢复secondary IP: $ip_addr/$cidr (ip命令不可用)"
                    restored_files+=("secondary_ip:$ip_addr/$cidr (跳过)")
                fi
            done
        else
            _blue "ℹ️ 没有发现secondary IP地址"
        fi
    fi
    
    # DNS配置
    if [ -f "$selected_backup/resolv.conf" ]; then
        if cp "$selected_backup/resolv.conf" /etc/ 2>/dev/null; then
            _green "✓ /etc/resolv.conf"
            restored_files+=("/etc/resolv.conf")
        else
            _red "❌ /etc/resolv.conf (恢复失败)"
            failed_files+=("/etc/resolv.conf")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    # 防火墙配置
    if [ -f "$selected_backup/iptables_rules.txt" ]; then
        if iptables-restore < "$selected_backup/iptables_rules.txt" 2>/dev/null; then
            _green "✓ iptables规则"
            restored_files+=("iptables_rules")
        else
            _red "❌ iptables规则 (恢复失败)"
            failed_files+=("iptables_rules")
            failed_reasons+=("iptables命令不可用或权限不足")
        fi
    fi
    
    if [ -f "$selected_backup/iptables_nat.txt" ]; then
        if iptables-restore < "$selected_backup/iptables_nat.txt" 2>/dev/null; then
            _green "✓ iptables NAT规则"
            restored_files+=("iptables_nat")
        else
            _red "❌ iptables NAT规则 (恢复失败)"
            failed_files+=("iptables_nat")
            failed_reasons+=("iptables命令不可用或权限不足")
        fi
    fi
    
    if [ -f "$selected_backup/iptables_mangle.txt" ]; then
        if iptables-restore < "$selected_backup/iptables_mangle.txt" 2>/dev/null; then
            _green "✓ iptables MANGLE规则"
            restored_files+=("iptables_mangle")
        else
            _red "❌ iptables MANGLE规则 (恢复失败)"
            failed_files+=("iptables_mangle")
            failed_reasons+=("iptables命令不可用或权限不足")
        fi
    fi
    
    if [ -f "$selected_backup/ufw_status.txt" ]; then
        _yellow "⚠️ UFW状态文件已恢复，请手动检查并启用UFW"
        restored_files+=("ufw_status")
    fi
    
    if [ -f "$selected_backup/firewalld_config.txt" ]; then
        _yellow "⚠️ firewalld配置已恢复，请手动检查并重新加载"
        restored_files+=("firewalld_config")
    fi
    
    # 网络转发配置
    if [ -f "$selected_backup/ipv4_forward.txt" ]; then
        if echo "$(cat "$selected_backup/ipv4_forward.txt")" > /proc/sys/net/ipv4/ip_forward 2>/dev/null; then
            _green "✓ IPv4转发"
            restored_files+=("ipv4_forward")
        else
            _red "❌ IPv4转发 (恢复失败)"
            failed_files+=("ipv4_forward")
            failed_reasons+=("无法写入/proc/sys/net/ipv4/ip_forward")
        fi
    fi
    
    if [ -f "$selected_backup/ipv6_forward.txt" ]; then
        if echo "$(cat "$selected_backup/ipv6_forward.txt")" > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null; then
            _green "✓ IPv6转发"
            restored_files+=("ipv6_forward")
        else
            _red "❌ IPv6转发 (恢复失败)"
            failed_files+=("ipv6_forward")
            failed_reasons+=("无法写入/proc/sys/net/ipv6/conf/all/forwarding")
        fi
    fi
    
    # SSH配置
    if [ -f "$selected_backup/sshd_config" ]; then
        if cp "$selected_backup/sshd_config" /etc/ssh/ 2>/dev/null; then
            _green "✓ /etc/ssh/sshd_config"
            restored_files+=("/etc/ssh/sshd_config")
        else
            _red "❌ /etc/ssh/sshd_config (恢复失败)"
            failed_files+=("/etc/ssh/sshd_config")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    # 时间同步配置
    if [ -f "$selected_backup/ntp.conf" ]; then
        if cp "$selected_backup/ntp.conf" /etc/ 2>/dev/null; then
            _green "✓ /etc/ntp.conf"
            restored_files+=("/etc/ntp.conf")
        else
            _red "❌ /etc/ntp.conf (恢复失败)"
            failed_files+=("/etc/ntp.conf")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    if [ -f "$selected_backup/chrony.conf" ]; then
        if cp "$selected_backup/chrony.conf" /etc/ 2>/dev/null; then
            _green "✓ /etc/chrony.conf"
            restored_files+=("/etc/chrony.conf")
        else
            _red "❌ /etc/chrony.conf (恢复失败)"
            failed_files+=("/etc/chrony.conf")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    # 网络存储配置
    if [ -f "$selected_backup/exports" ]; then
        if cp "$selected_backup/exports" /etc/ 2>/dev/null; then
            _green "✓ /etc/exports"
            restored_files+=("/etc/exports")
        else
            _red "❌ /etc/exports (恢复失败)"
            failed_files+=("/etc/exports")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    if [ -f "$selected_backup/smb.conf" ]; then
        if cp "$selected_backup/smb.conf" /etc/samba/ 2>/dev/null; then
            _green "✓ /etc/samba/smb.conf"
            restored_files+=("/etc/samba/smb.conf")
        else
            _red "❌ /etc/samba/smb.conf (恢复失败)"
            failed_files+=("/etc/samba/smb.conf")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    # 网络监控配置
    if [ -f "$selected_backup/snmpd.conf" ]; then
        if cp "$selected_backup/snmpd.conf" /etc/snmp/ 2>/dev/null; then
            _green "✓ /etc/snmp/snmpd.conf"
            restored_files+=("/etc/snmp/snmpd.conf")
        else
            _red "❌ /etc/snmp/snmpd.conf (恢复失败)"
            failed_files+=("/etc/snmp/snmpd.conf")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    # DHCP配置
    if [ -f "$selected_backup/dhcpd.conf" ]; then
        if cp "$selected_backup/dhcpd.conf" /etc/dhcp/ 2>/dev/null; then
            _green "✓ /etc/dhcp/dhcpd.conf"
            restored_files+=("/etc/dhcp/dhcpd.conf")
        else
            _red "❌ /etc/dhcp/dhcpd.conf (恢复失败)"
            failed_files+=("/etc/dhcp/dhcpd.conf")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    
    if [ -f "$selected_backup/dhcpcd.conf" ]; then
        if cp "$selected_backup/dhcpcd.conf" /etc/ 2>/dev/null; then
            _green "✓ /etc/dhcpcd.conf"
            restored_files+=("/etc/dhcpcd.conf")
        else
            _red "❌ /etc/dhcpcd.conf (恢复失败)"
            failed_files+=("/etc/dhcpcd.conf")
            failed_reasons+=("权限不足或文件被保护")
        fi
    fi
    echo
    
    # 显示恢复总结
    _blue "📊 恢复总结:"
    
    # 显示成功的项目
    if [ ${#restored_files[@]} -gt 0 ]; then
        _green "✓ 成功 (${#restored_files[@]} 项):"
        for file in "${restored_files[@]}"; do
            echo "  • $file"
        done
    fi
    
    # 显示失败的项目
    if [ ${#failed_files[@]} -gt 0 ]; then
        echo
        _red "❌ 失败 (${#failed_files[@]} 项):"
        for i in "${!failed_files[@]}"; do
            echo "  • ${failed_files[$i]} - ${failed_reasons[$i]}"
        done
    fi
    
    # 如果没有恢复任何项目
    if [ ${#restored_files[@]} -eq 0 ] && [ ${#failed_files[@]} -eq 0 ]; then
        _yellow "⚠️ 没有恢复任何配置项"
    fi
    
    echo
    
    _green "✓ 网络配置恢复完成"
    _yellow "⚠️ 建议重启网络服务或重启系统以确保配置生效"
    
    # 显示手动恢复提示
    echo
    _blue "📋 如果某些文件恢复失败，可以手动执行以下命令:"
    _blue "   sudo cp $selected_backup/hostname /etc/hostname"
    _blue "   sudo cp $selected_backup/hosts /etc/hosts"
    _blue "   sudo cp $selected_backup/interfaces /etc/network/interfaces"
    _blue "   sudo cp $selected_backup/resolv.conf /etc/resolv.conf"
    _blue "   sudo systemctl restart networking"
    echo
    
    log "恢复备份: $selected_backup"
    
    # 自动启用文件保护
    _blue "🔒 自动启用文件保护..."
    local protected_files=("/etc/hostname" "/etc/hosts" "/etc/network/interfaces" "/etc/resolv.conf")
    local protected_count=0
    
    for file in "${protected_files[@]}"; do
        if [ -f "$file" ] && command -v chattr >/dev/null 2>&1; then
            if chattr +i "$file" 2>/dev/null; then
                _green "✓ 已保护: $file"
                ((protected_count++))
            else
                _red "❌ 保护失败: $file"
            fi
        fi
    done
    
    if [ $protected_count -gt 0 ]; then
        _green "✓ 已保护 $protected_count 个文件"
        _yellow "💡 如需修改这些文件，请先运行权限修复功能解除保护"
    fi
    
    # 强制重启相关服务
    _blue "🔄 强制重启相关网络服务..."
    local services=("networking" "NetworkManager" "ssh" "sshd" "chrony" "ntp" "smbd" "nmbd" "snmpd" "dhcpd" "dhcpcd")
    local restarted_count=0
    local skipped_count=0
    
    for service in "${services[@]}"; do
        # 检查服务是否存在
        if systemctl list-unit-files | grep -q "^${service}\.service"; then
            # 强制重启服务，不管当前状态
            echo "正在重启服务: $service"
            if systemctl restart "$service" 2>/dev/null; then
                _green "✓ 已重启: $service"
                ((restarted_count++))
            else
                _red "❌ 重启失败: $service"
            fi
        else
            _blue "⏭️ 跳过: $service (服务不存在)"
            ((skipped_count++))
        fi
    done
    
    echo
    _green "✓ 服务重启完成"
    _green "✓ 已重启 $restarted_count 个服务"
    if [ $skipped_count -gt 0 ]; then
        _blue "⏭️ 跳过 $skipped_count 个不存在的服务"
    fi
    
    echo
    
    echo
    echo -n "按回车键继续..."
    read
    return 1
}


# 处理菜单选择
handle_menu_choice() {
    case "$1" in
        "1")
            view_comprehensive_network
            return 1
            ;;
        "2")
            view_backup_list
            return 1
            ;;
        "3")
            backup_network_config
            return 1
            ;;
        "4")
            restore_network_config
            return 1
            ;;
        "5")
            check_ssh_port
            return 1
            ;;
        "0")
            _green "感谢使用！"
            exit 0
            ;;
        "")
            return 1
            ;;
        *)
            _red "❌ 无效的选择: '$1'"
            return 1
            ;;
    esac
    
    echo
    echo -n "按回车键继续..."
    read
}

# 显示帮助信息
show_help() {
    _blue "=========================================="
    _blue "        网络环境检测与修复脚本 v$SCRIPT_VERSION"
    _blue "=========================================="
    echo
    _yellow "使用方法:"
    echo "  $0          - 启动交互式菜单"
    echo "  $0 view     - 全面查看网络环境"
    echo "  $0 list     - 查看备份列表"
    echo "  $0 backup   - 备份当前网络环境"
    echo "  $0 restore  - 恢复网络配置"
    echo "  $0 check    - 检测22端口"
    echo "  $0 help     - 显示帮助信息"
    echo
}

# 主函数
main() {
    # 检查环境
    check_environment
    
    # 检查参数
    if [ $# -eq 0 ]; then
        # 交互式菜单模式
        while true; do
            show_menu
            echo -n "请输入选择 (0-5): "
            read choice
            choice=$(echo "$choice" | xargs)
            
            if handle_menu_choice "$choice"; then
                break
            fi
        done
    else
        # 命令行模式
        case "$1" in
               "view")
                   view_comprehensive_network
                   ;;
               "list")
                   view_backup_list
                   ;;
               "backup")
                   backup_network_config
                   ;;
               "restore")
                   restore_network_config
                   ;;
               "check")
                   check_ssh_port
                   ;;
               "help")
                   show_help
                   ;;
               *)
                   _red "❌ 无效的参数: $1"
                   show_help
                   exit 1
                   ;;
        esac
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi