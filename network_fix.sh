#!/bin/bash

# 网络环境检测与修复脚本
# 简化版本 - 只包含核心功能

# 版本信息
SCRIPT_VERSION="1.4.0"
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

# 1. 查看当前网络配置
view_network_config() {
    _blue "=== 当前网络配置 ==="
    
    echo
    _yellow "网络接口:"
    ip addr show | grep -E "^[0-9]+:|inet " | head -20
    
    echo
    _yellow "路由表:"
    ip route show | head -10
    
    echo
    _yellow "DNS配置:"
    cat /etc/resolv.conf 2>/dev/null || echo "无法读取DNS配置"
    
    echo
    _yellow "防火墙状态:"
    if command -v ufw >/dev/null 2>&1; then
        ufw status
    elif command -v iptables >/dev/null 2>&1; then
        iptables -L -n | head -10
    else
        echo "未检测到防火墙"
    fi
    
    echo
    _yellow "网络服务状态:"
    systemctl status networking 2>/dev/null || systemctl status NetworkManager 2>/dev/null || echo "网络服务状态未知"
    
    log "查看网络配置完成"
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
    if ss -tlnp | grep ":$SSH_PORT " >/dev/null; then
        _green "✓ SSH服务正在监听端口 $SSH_PORT"
    else
        _red "❌ SSH服务未在端口 $SSH_PORT 监听"
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

# 显示帮助信息
show_help() {
    _blue "=========================================="
    _blue "        网络环境检测与修复脚本 v$SCRIPT_VERSION"
    _blue "=========================================="
    echo
    _yellow "使用方法:"
    echo "  $0 view     - 查看当前网络配置"
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
        show_help
        exit 0
    fi
    
    case "$1" in
        "view")
            view_network_config
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
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi