#!/bin/bash

# 网络环境检测与修复脚本
# 包含全面的网络检测、备份和修复功能
# 支持交互式菜单、带备注备份、配置查看和恢复功能

# 版本信息
SCRIPT_VERSION="1.5.0"
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
        exit 1
    fi
    
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
    echo "2. 备份当前网络环境"
    echo "3. 检测22端口"
    echo "4. 恢复网络配置"
    echo "5. 退出"
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
    _yellow "14. 网络相关进程:"
    ps aux | grep -E "(network|dhcp|dns|sshd)" | grep -v grep
    
    echo
    _green "✓ 全面网络环境检测完成"
    log "全面网络环境检测完成"
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
    
    # 备份防火墙配置
    if command -v ufw >/dev/null 2>&1; then
        ufw status > "$backup_path/ufw_status.txt"
    fi
    
    if command -v iptables >/dev/null 2>&1; then
        iptables-save > "$backup_path/iptables_rules.txt"
    fi
    
    # 备份DNS配置
    cp /etc/resolv.conf "$backup_path/" 2>/dev/null || true
    
    # 备份主机名配置
    cp /etc/hostname "$backup_path/" 2>/dev/null || true
    cp /etc/hosts "$backup_path/" 2>/dev/null || true
    
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
                backup_note=$(grep "备份备注:" "$backup/backup_info.txt" | cut -d: -f2- | xargs)
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
    
    # 执行恢复
    _green "正在恢复网络配置..."
    
    # 恢复网络接口配置
    if [ -d "$selected_backup/netplan" ]; then
        cp -r "$selected_backup/netplan" /etc/
    fi
    
    if [ -f "$selected_backup/interfaces" ]; then
        cp "$selected_backup/interfaces" /etc/network/
    fi
    
    # 恢复防火墙配置
    if [ -f "$selected_backup/iptables_rules.txt" ]; then
        iptables-restore < "$selected_backup/iptables_rules.txt"
    fi
    
    # 恢复DNS配置
    if [ -f "$selected_backup/resolv.conf" ]; then
        cp "$selected_backup/resolv.conf" /etc/
    fi
    
    # 恢复主机名配置
    if [ -f "$selected_backup/hostname" ]; then
        cp "$selected_backup/hostname" /etc/
    fi
    
    if [ -f "$selected_backup/hosts" ]; then
        cp "$selected_backup/hosts" /etc/
    fi
    
    _green "✓ 网络配置恢复完成"
    _yellow "⚠️ 建议重启网络服务或重启系统以确保配置生效"
    
    log "恢复备份: $selected_backup"
}

# 处理菜单选择
handle_menu_choice() {
    case "$1" in
        "1")
            view_comprehensive_network
            ;;
        "2")
            backup_network_config
            ;;
        "3")
            check_ssh_port
            ;;
        "4")
            restore_network_config
            ;;
        "5")
            _green "感谢使用！"
            return 0
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
    return 1
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
    echo "  $0 backup   - 备份当前网络环境"
    echo "  $0 check    - 检测22端口"
    echo "  $0 restore  - 恢复网络配置"
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
            echo -n "请输入选择 (1-5): "
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
            "backup")
                backup_network_config
                ;;
            "check")
                check_ssh_port
                ;;
            "restore")
                restore_network_config
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