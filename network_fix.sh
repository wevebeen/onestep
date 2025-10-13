#!/bin/bash
# 网络环境检测与修复脚本
# 包含全面的网络检测、备份和修复功能
# 支持交互式菜单、带备注备份、配置查看和恢复功能

# 版本信息
SCRIPT_VERSION="1.1.5"
SCRIPT_BUILD="$(date '+%Y%m%d-%H%M%S')"
SCRIPT_NAME="网络环境检测与修复脚本"

# 脚本配置
SSH_PORT="22"
SSH_PROTOCOL="tcp"  # SSH使用TCP协议
BACKUP_DIR="network_backups"
REPORT_DIR="network_reports"
LOG_FILE="network_fix.log"

# 颜色输出函数
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }

# 日志记录函数
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
}

# 检查服务器环境
check_server_environment() {
    _blue "=== 检查服务器环境 ==="
    
    # 检查操作系统
    if [[ "$OSTYPE" == "darwin"* ]]; then
        _red "错误: 此脚本需要在Linux服务器上执行，不能在macOS上运行"
        exit 1
    fi
    
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        _red "错误: 此脚本需要root权限执行"
        _yellow "请使用: sudo $0"
        exit 1
    fi
    
    # 检查网络工具
    local required_tools=("ip" "ping" "netstat" "ss" "systemctl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            _red "错误: 缺少必要的网络工具: $tool"
            exit 1
        fi
    done
    
    _green "✓ 操作系统: $(uname -s)"
    _green "✓ 内核版本: $(uname -r)"
    _green "✓ 网络工具检查通过"
    
    log_message "服务器环境检查通过"
}

# 检查初始备份是否存在
check_initial_backup_exists() {
    local initial_backup_dir="$BACKUP_DIR/initial"
    
    if [ -d "$initial_backup_dir" ]; then
        local backup_files=$(find "$initial_backup_dir" -type f 2>/dev/null | wc -l)
        if [ "$backup_files" -gt 0 ]; then
            _yellow "✅ 初始备份已存在，跳过初始备份创建"
            log_message "初始备份已存在，跳过创建"
            return 0
        fi
    fi
    
    return 1
}

# 创建网络配置备份（带备注）
create_network_backup() {
    _blue "=== 创建网络配置备份 ==="
    
    # 获取用户输入的备注
    echo -n "请输入备份备注: "
    read -r backup_note
    
    # 去除前后空格
    backup_note=$(echo "$backup_note" | xargs)
    
    if [ -z "$backup_note" ]; then
        backup_note="手动备份"
    fi
    
    local backup_name="backup_$(date '+%Y%m%d_%H%M%S')"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    # 保存备注信息
    echo "备份时间: $(date '+%Y-%m-%d %H:%M:%S')" > "$backup_path/backup_info.txt"
    echo "备份备注: $backup_note" >> "$backup_path/backup_info.txt"
    echo "备份类型: 手动备份" >> "$backup_path/backup_info.txt"
    
    # 备份网络配置文件
    local config_files=(
        "/etc/network/interfaces"
        "/etc/netplan"
        "/etc/systemd/network"
        "/etc/resolv.conf"
        "/etc/hosts"
        "/etc/hostname"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ -e "$config_file" ]; then
            if [ -d "$config_file" ]; then
                cp -r "$config_file" "$backup_path/" 2>/dev/null || true
            else
                cp "$config_file" "$backup_path/" 2>/dev/null || true
            fi
        fi
    done
    
    # 备份防火墙规则
    if command -v iptables &>/dev/null; then
        iptables-save > "$backup_path/iptables_rules.txt" 2>/dev/null || true
    fi
    
    if command -v ufw &>/dev/null; then
        ufw status > "$backup_path/ufw_status.txt" 2>/dev/null || true
    fi
    
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all > "$backup_path/firewalld_rules.txt" 2>/dev/null || true
    fi
    
    # 备份网络服务状态
    systemctl list-units --type=service --state=running | grep -E "(network|firewall|dns)" > "$backup_path/network_services.txt" 2>/dev/null || true
    
    # 备份网络接口信息
    ip addr show > "$backup_path/network_interfaces.txt" 2>/dev/null || true
    ip route show > "$backup_path/routing_table.txt" 2>/dev/null || true
    
    _green "✓ 网络配置备份创建成功"
    _green "备份路径: $backup_path"
    _green "备份备注: $backup_note"
    
    local backup_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
    _green "备份大小: $backup_size"
    
    log_message "网络配置备份创建完成: $backup_path"
}

# 查看网络配置和备份
view_network_config() {
    _blue "=== 查看网络配置 ==="
    
    echo
    _yellow "当前网络配置:"
    echo "----------------------------------------"
    
    # 显示当前网络接口
    _green "网络接口:"
    ip addr show | grep -E "^[0-9]+:|inet " | sed 's/^/  /'
    
    # 显示路由表
    _green "路由表:"
    ip route show | sed 's/^/  /'
    
    # 显示DNS配置
    _green "DNS配置:"
    cat /etc/resolv.conf | sed 's/^/  /'
    
    # 显示防火墙状态
    _green "防火墙状态:"
    if command -v ufw &>/dev/null; then
        ufw status | sed 's/^/  /'
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all | sed 's/^/  /'
    else
        echo "  未检测到防火墙服务"
    fi
    
    echo
    _yellow "备份配置列表:"
    echo "----------------------------------------"
    
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=0
        for backup_dir in "$BACKUP_DIR"/*; do
            if [ -d "$backup_dir" ] && [ -f "$backup_dir/backup_info.txt" ]; then
                backup_count=$((backup_count + 1))
                local backup_name=$(basename "$backup_dir")
                local backup_time=$(grep "备份时间:" "$backup_dir/backup_info.txt" | cut -d': ' -f2)
                local backup_note=$(grep "备份备注:" "$backup_dir/backup_info.txt" | cut -d': ' -f2)
                
                _green "备份 $backup_count: $backup_name"
                echo "  时间: $backup_time"
                echo "  备注: $backup_note"
                echo
            fi
        done
        
        if [ $backup_count -eq 0 ]; then
            _yellow "  暂无备份配置"
        fi
    else
        _yellow "  备份目录不存在"
    fi
}

# 恢复网络配置
restore_network_config() {
    _blue "=== 恢复网络配置 ==="
    
    if [ ! -d "$BACKUP_DIR" ]; then
        _red "❌ 备份目录不存在"
        return 1
    fi
    
    # 显示可用的备份
    local backups=()
    local backup_count=0
    
    for backup_dir in "$BACKUP_DIR"/*; do
        if [ -d "$backup_dir" ] && [ -f "$backup_dir/backup_info.txt" ]; then
            backup_count=$((backup_count + 1))
            backups+=("$backup_dir")
            
            local backup_name=$(basename "$backup_dir")
            local backup_time=$(grep "备份时间:" "$backup_dir/backup_info.txt" | cut -d': ' -f2)
            local backup_note=$(grep "备份备注:" "$backup_dir/backup_info.txt" | cut -d': ' -f2)
            
            echo "$backup_count. $backup_name"
            echo "   时间: $backup_time"
            echo "   备注: $backup_note"
            echo
        fi
    done
    
    if [ $backup_count -eq 0 ]; then
        _red "❌ 没有可用的备份配置"
        return 1
    fi
    
    # 选择要恢复的备份
    echo -n "请选择要恢复的备份 (1-$backup_count): "
    read -r choice
    
    # 去除前后空格
    choice=$(echo "$choice" | xargs)
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$backup_count" ]; then
        _red "❌ 无效的选择"
        return 1
    fi
    
    local selected_backup="${backups[$((choice-1))]}"
    local backup_name=$(basename "$selected_backup")
    
    _yellow "选择的备份: $backup_name"
    
    # 显示将要进行的修改
    _blue "=== 将要进行的修改 ==="
    
    local changes_found=0
    
    # 检查网络接口配置
    if [ -f "$selected_backup/interfaces" ] && [ -f "/etc/network/interfaces" ]; then
        if ! diff -q "$selected_backup/interfaces" "/etc/network/interfaces" >/dev/null 2>&1; then
            _yellow "📝 网络接口配置 (/etc/network/interfaces) 将被修改"
            changes_found=1
        fi
    fi
    
    # 检查DNS配置
    if [ -f "$selected_backup/resolv.conf" ] && [ -f "/etc/resolv.conf" ]; then
        if ! diff -q "$selected_backup/resolv.conf" "/etc/resolv.conf" >/dev/null 2>&1; then
            _yellow "📝 DNS配置 (/etc/resolv.conf) 将被修改"
            changes_found=1
        fi
    fi
    
    # 检查主机配置
    if [ -f "$selected_backup/hosts" ] && [ -f "/etc/hosts" ]; then
        if ! diff -q "$selected_backup/hosts" "/etc/hosts" >/dev/null 2>&1; then
            _yellow "📝 主机配置 (/etc/hosts) 将被修改"
            changes_found=1
        fi
    fi
    
    # 检查主机名
    if [ -f "$selected_backup/hostname" ] && [ -f "/etc/hostname" ]; then
        if ! diff -q "$selected_backup/hostname" "/etc/hostname" >/dev/null 2>&1; then
            _yellow "📝 主机名 (/etc/hostname) 将被修改"
            changes_found=1
        fi
    fi
    
    if [ $changes_found -eq 0 ]; then
        _green "✅ 当前配置与备份配置相同，无需恢复"
        return 0
    fi
    
    echo
    _red "⚠️  警告: 此操作将修改网络配置，可能导致网络连接中断！"
    echo -n "确认要恢复网络配置吗？(yes/no): "
    read -r confirm
    
    # 去除前后空格并转换为小写
    confirm=$(echo "$confirm" | xargs | tr '[:upper:]' '[:lower:]')
    
    if [ "$confirm" != "yes" ]; then
        _yellow "❌ 用户取消恢复操作"
        return 1
    fi
    
    # 执行恢复操作
    _blue "=== 开始恢复网络配置 ==="
    
    # 恢复网络接口配置
    if [ -f "$selected_backup/interfaces" ]; then
        _yellow "恢复网络接口配置..."
        cp "$selected_backup/interfaces" "/etc/network/interfaces"
        _green "✓ 网络接口配置已恢复"
    fi
    
    # 恢复DNS配置
    if [ -f "$selected_backup/resolv.conf" ]; then
        _yellow "恢复DNS配置..."
        cp "$selected_backup/resolv.conf" "/etc/resolv.conf"
        _green "✓ DNS配置已恢复"
    fi
    
    # 恢复主机配置
    if [ -f "$selected_backup/hosts" ]; then
        _yellow "恢复主机配置..."
        cp "$selected_backup/hosts" "/etc/hosts"
        _green "✓ 主机配置已恢复"
    fi
    
    # 恢复主机名
    if [ -f "$selected_backup/hostname" ]; then
        _yellow "恢复主机名..."
        cp "$selected_backup/hostname" "/etc/hostname"
        hostnamectl set-hostname "$(cat /etc/hostname)"
        _green "✓ 主机名已恢复"
    fi
    
    # 重启网络服务
    _yellow "重启网络服务..."
    systemctl restart networking
    systemctl restart systemd-resolved
    
    _green "✅ 网络配置恢复完成"
    _yellow "建议重启系统以确保所有配置生效"
    
    log_message "网络配置恢复完成: $backup_name"
}

# 显示主菜单
show_menu() {
    _blue "=========================================="
    _blue "        $SCRIPT_NAME v$SCRIPT_VERSION"
    _blue "        构建时间: $SCRIPT_BUILD"
    _blue "=========================================="
    echo
    _yellow "请选择操作:"
    echo "1. 备份网络配置（带备注）"
    echo "2. 查看网络配置和备份"
    echo "3. 恢复网络配置"
    echo "4. 网络诊断和修复"
    echo "5. SSH端口检测（仅显示成功）"
    echo "6. 退出"
    echo
}

# 处理菜单选择
handle_menu_choice() {
    local choice="$1"
    
    # 去除前后空格
    choice=$(echo "$choice" | xargs)
    
    case "$choice" in
        "1"|"backup")
            create_network_backup
            return 1
            ;;
        "2"|"view")
            view_network_config
            return 1
            ;;
        "3"|"restore")
            restore_network_config
            return 1
            ;;
        "4"|"diagnose")
            # 检查并创建初始备份
            if ! check_initial_backup_exists; then
                create_initial_backup
                echo
            fi
            
            # 更新当前备份
            update_current_backup
            echo
            
            # 诊断网络问题
            if diagnose_network_issues; then
                _green "🎉 网络环境正常！"
                echo
                
                # 测试SSH端口外网访问
                test_external_ssh_access
                echo
                
                # 生成正常状态报告
                generate_network_report
            else
                _yellow "⚠ 发现网络问题，开始修复..."
                echo
                
                # 创建故障报告
                create_fault_report
                echo
                
                # 修复网络问题
                fix_network_issues
                echo
                
                # 验证修复结果
                if verify_network_status; then
                    _green "🎉 网络问题修复成功！"
                else
                    _red "❌ 网络问题修复失败，请检查报告文件"
                fi
                echo
                
                # 测试SSH端口外网访问
                test_external_ssh_access
                echo
                
                # 生成修复后报告
                generate_network_report
            fi
            return 1
            ;;
        "5"|"ssh")
            test_external_ssh_access
            return 1
            ;;
        "6"|"exit"|"quit")
            _green "感谢使用！"
            return 0
            ;;
        "")
            # 空输入，继续循环
            return 1
            ;;
        *)
            _red "❌ 无效的选择: '$choice'，请重新输入"
            return 1
            ;;
    esac
}

# 创建初始网络环境备份
create_initial_backup() {
    _blue "=== 创建初始网络环境备份 ==="
    
    local backup_name="initial_$(date '+%Y%m%d_%H%M%S')"
    local backup_path="$BACKUP_DIR/initial"
    
    mkdir -p "$backup_path"
    
    # 备份网络配置文件
    local config_files=(
        "/etc/network/interfaces"
        "/etc/netplan"
        "/etc/systemd/network"
        "/etc/resolv.conf"
        "/etc/hosts"
        "/etc/hostname"
    )
    
    for config_file in "${config_files[@]}"; do
        if [ -e "$config_file" ]; then
            if [ -d "$config_file" ]; then
                cp -r "$config_file" "$backup_path/" 2>/dev/null || true
            else
                cp "$config_file" "$backup_path/" 2>/dev/null || true
            fi
        fi
    done
    
    # 备份防火墙规则
    if command -v iptables &>/dev/null; then
        iptables-save > "$backup_path/iptables_rules.txt" 2>/dev/null || true
    fi
    
    if command -v ufw &>/dev/null; then
        ufw status > "$backup_path/ufw_status.txt" 2>/dev/null || true
    fi
    
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all > "$backup_path/firewalld_rules.txt" 2>/dev/null || true
    fi
    
    # 备份网络服务状态
    systemctl list-units --type=service --state=running | grep -E "(network|firewall|dns)" > "$backup_path/network_services.txt" 2>/dev/null || true
    
    # 备份网络接口信息
    ip addr show > "$backup_path/network_interfaces.txt" 2>/dev/null || true
    ip route show > "$backup_path/routing_table.txt" 2>/dev/null || true
    
    _green "✓ 初始备份创建成功"
    _green "备份路径: $backup_path"
    
    local backup_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
    _green "备份大小: $backup_size"
    
    log_message "初始备份创建完成: $backup_path"
}

# 更新当前网络状态备份
update_current_backup() {
    _blue "=== 更新当前网络状态备份 ==="
    
    local backup_path="$BACKUP_DIR/current"
    mkdir -p "$backup_path"
    
    # 清空当前备份目录
    rm -rf "$backup_path"/*
    
    # 备份当前网络状态
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    # 网络接口状态
    ip addr show > "$backup_path/current_interfaces_$timestamp.txt" 2>/dev/null || true
    ip route show > "$backup_path/current_routes_$timestamp.txt" 2>/dev/null || true
    
    # DNS配置
    cat /etc/resolv.conf > "$backup_path/current_resolv_$timestamp.txt" 2>/dev/null || true
    
    # 防火墙状态
    if command -v iptables &>/dev/null; then
        iptables-save > "$backup_path/current_iptables_$timestamp.txt" 2>/dev/null || true
    fi
    
    if command -v ufw &>/dev/null; then
        ufw status > "$backup_path/current_ufw_$timestamp.txt" 2>/dev/null || true
    fi
    
    # 网络服务状态
    systemctl status networking > "$backup_path/current_networking_service_$timestamp.txt" 2>/dev/null || true
    systemctl status systemd-resolved > "$backup_path/current_dns_service_$timestamp.txt" 2>/dev/null || true
    
    # 端口监听状态
    netstat -tlnp > "$backup_path/current_listening_ports_$timestamp.txt" 2>/dev/null || true
    ss -tlnp > "$backup_path/current_ss_ports_$timestamp.txt" 2>/dev/null || true
    
    _green "✓ 当前网络状态备份更新完成"
    log_message "当前网络状态备份更新完成"
}

# 检测网络接口状态
detect_network_interfaces() {
    _blue "=== 检测网络接口状态 ==="
    
    local issues_found=0
    
    # 获取所有网络接口
    local interfaces=$(ip link show | grep -E "^[0-9]+:" | awk -F': ' '{print $2}' | awk '{print $1}')
    
    for interface in $interfaces; do
        if [ "$interface" = "lo" ]; then
            continue
        fi
        
        # 检查接口状态
        local interface_state=$(ip link show "$interface" | grep -o "state [A-Z]*" | awk '{print $2}')
        local interface_ip=$(ip addr show "$interface" | grep -o "inet [0-9.]*" | awk '{print $2}' | head -1)
        
        if [ "$interface_state" = "UP" ]; then
            if [ -n "$interface_ip" ]; then
                _green "✓ 接口 $interface: UP, IP: $interface_ip"
            else
                _yellow "⚠ 接口 $interface: UP, 但无IP地址"
                issues_found=$((issues_found + 1))
            fi
        else
            _red "❌ 接口 $interface: DOWN"
            issues_found=$((issues_found + 1))
        fi
    done
    
    if [ $issues_found -eq 0 ]; then
        _green "✓ 所有网络接口状态正常"
    else
        _red "❌ 发现 $issues_found 个网络接口问题"
    fi
    
    return $issues_found
}

# 检测防火墙状态
detect_firewall_status() {
    _blue "=== 检测防火墙状态 ==="
    
    local firewall_active=0
    
    # 检测iptables
    if command -v iptables &>/dev/null; then
        local iptables_rules=$(iptables -L | grep -v "Chain\|target\|prot\|^$" | wc -l)
        if [ "$iptables_rules" -gt 0 ]; then
            _yellow "⚠ iptables: 有 $iptables_rules 条规则"
            firewall_active=1
        else
            _green "✓ iptables: 无规则"
        fi
    fi
    
    # 检测ufw
    if command -v ufw &>/dev/null; then
        local ufw_status=$(ufw status | head -1 | awk '{print $2}')
        if [ "$ufw_status" = "active" ]; then
            _yellow "⚠ ufw: 已启用"
            firewall_active=1
        else
            _green "✓ ufw: 未启用"
        fi
    fi
    
    # 检测firewalld
    if command -v firewall-cmd &>/dev/null; then
        if systemctl is-active firewalld &>/dev/null; then
            _yellow "⚠ firewalld: 已启用"
            firewall_active=1
        else
            _green "✓ firewalld: 未启用"
        fi
    fi
    
    if [ $firewall_active -eq 0 ]; then
        _green "✓ 防火墙状态正常"
    else
        _yellow "⚠ 检测到防火墙活动"
    fi
    
    return $firewall_active
}

# 检测DNS配置
detect_dns_config() {
    _blue "=== 检测DNS配置 ==="
    
    local dns_issues=0
    
    # 检查resolv.conf
    if [ -f "/etc/resolv.conf" ]; then
        local nameservers=$(grep "^nameserver" /etc/resolv.conf | wc -l)
        if [ "$nameservers" -gt 0 ]; then
            _green "✓ DNS服务器配置: $nameservers 个"
            grep "^nameserver" /etc/resolv.conf | while read line; do
                _green "  $line"
            done
        else
            _red "❌ 未配置DNS服务器"
            dns_issues=$((dns_issues + 1))
        fi
    else
        _red "❌ resolv.conf文件不存在"
        dns_issues=$((dns_issues + 1))
    fi
    
    # 测试DNS解析
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        if nslookup google.com >/dev/null 2>&1; then
            _green "✓ DNS解析正常"
        else
            _red "❌ DNS解析失败"
            dns_issues=$((dns_issues + 1))
        fi
    else
        _red "❌ 网络连接失败，无法测试DNS"
        dns_issues=$((dns_issues + 1))
    fi
    
    return $dns_issues
}

# 检测网络服务状态
detect_network_services() {
    _blue "=== 检测网络服务状态 ==="
    
    local service_issues=0
    local services=("networking" "systemd-resolved" "NetworkManager")
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "$service"; then
            if systemctl is-active "$service" &>/dev/null; then
                _green "✓ 服务 $service: 运行中"
            else
                _yellow "⚠ 服务 $service: 未运行"
                service_issues=$((service_issues + 1))
            fi
        fi
    done
    
    return $service_issues
}

# 检查网络连通性
check_connectivity() {
    _blue "=== 检查网络连通性 ==="
    
    local connectivity_issues=0
    
    # 测试内网连通性
    if ping -c 1 127.0.0.1 >/dev/null 2>&1; then
        _green "✓ 本地回环: 正常"
    else
        _red "❌ 本地回环: 失败"
        connectivity_issues=$((connectivity_issues + 1))
    fi
    
    # 测试网关连通性
    local gateway=$(ip route | grep default | awk '{print $3}' | head -1)
    if [ -n "$gateway" ]; then
        if ping -c 1 "$gateway" >/dev/null 2>&1; then
            _green "✓ 网关 $gateway: 正常"
        else
            _red "❌ 网关 $gateway: 失败"
            connectivity_issues=$((connectivity_issues + 1))
        fi
    else
        _red "❌ 未找到默认网关"
        connectivity_issues=$((connectivity_issues + 1))
    fi
    
    # 测试外网连通性
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        _green "✓ 外网连通: 正常"
    else
        _red "❌ 外网连通: 失败"
        connectivity_issues=$((connectivity_issues + 1))
    fi
    
    return $connectivity_issues
}

# 检测SSH端口访问
check_ssh_port_access() {
    _blue "=== 检测SSH端口访问 ==="
    
    local ssh_issues=0
    
    # 检查SSH服务状态
    if systemctl is-active ssh &>/dev/null || systemctl is-active sshd &>/dev/null; then
        _green "✓ SSH服务: 运行中"
    else
        _red "❌ SSH服务: 未运行"
        ssh_issues=$((ssh_issues + 1))
    fi
    
    # 检查SSH端口监听
    if netstat -tlnp | grep ":$SSH_PORT " >/dev/null 2>&1; then
        _green "✓ SSH端口 $SSH_PORT: 正在监听"
    else
        _red "❌ SSH端口 $SSH_PORT: 未监听"
        ssh_issues=$((ssh_issues + 1))
    fi
    
    # 检查防火墙是否阻止SSH
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        if ufw status | grep "$SSH_PORT" | grep -q "ALLOW"; then
            _green "✓ ufw: SSH端口 $SSH_PORT 已开放"
        else
            _yellow "⚠ ufw: SSH端口 $SSH_PORT 可能被阻止"
        fi
    fi
    
    return $ssh_issues
}

# 测试外网SSH访问
test_external_ssh_access() {
    _blue "=== 测试外网SSH访问 ==="
    
    local server_ip=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null)
    
    if [ -n "$server_ip" ]; then
        _green "服务器IP: $server_ip"
        _green "SSH访问地址: ssh root@$server_ip -p $SSH_PORT"
        _blue "协议类型: $SSH_PROTOCOL (SSH使用TCP协议，端口22是TCP端口)"
        echo
        
        # 1. 检查SSH服务状态
        _yellow "1. 检查SSH服务状态..."
        if systemctl is-active ssh &>/dev/null || systemctl is-active sshd &>/dev/null; then
            _green "✓ SSH服务: 运行中"
        else
            _red "❌ SSH服务: 未运行"
            _yellow "建议: systemctl start ssh 或 systemctl start sshd"
        fi
        
        # 2. 检查端口监听
        _yellow "2. 检查SSH端口监听..."
        if netstat -tlnp | grep ":$SSH_PORT " >/dev/null 2>&1; then
            _green "✓ SSH端口 $SSH_PORT: 正在监听"
        else
            _red "❌ SSH端口 $SSH_PORT: 未监听"
            _yellow "建议: 检查SSH配置文件 /etc/ssh/sshd_config"
        fi
        
        # 3. 检查防火墙规则
        _yellow "3. 检查防火墙规则..."
        local firewall_blocked=0
        
        # 检查iptables
        if command -v iptables &>/dev/null; then
            local iptables_rules=$(iptables -L INPUT | grep -c "DROP\|REJECT")
            if [ "$iptables_rules" -gt 0 ]; then
                local ssh_allowed=$(iptables -L INPUT | grep -c "ACCEPT.*$SSH_PORT\|ACCEPT.*ssh")
                if [ "$ssh_allowed" -eq 0 ]; then
                    _yellow "⚠ iptables: 可能有规则阻止SSH端口"
                    firewall_blocked=1
                else
                    _green "✓ iptables: SSH端口已允许"
                fi
            fi
        fi
        
        # 检查ufw
        if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
            if ufw status | grep "$SSH_PORT" | grep -q "ALLOW"; then
                _green "✓ ufw: SSH端口 $SSH_PORT 已开放"
            else
                _yellow "⚠ ufw: SSH端口 $SSH_PORT 可能被阻止"
                _yellow "建议: ufw allow $SSH_PORT"
                firewall_blocked=1
            fi
        fi
        
        # 检查firewalld
        if command -v firewall-cmd &>/dev/null && systemctl is-active firewalld &>/dev/null; then
            if firewall-cmd --query-port="$SSH_PORT/tcp" &>/dev/null; then
                _green "✓ firewalld: SSH端口 $SSH_PORT 已开放"
            else
                _yellow "⚠ firewalld: SSH端口 $SSH_PORT 未开放"
                _yellow "建议: firewall-cmd --permanent --add-port=$SSH_PORT/tcp && firewall-cmd --reload"
                firewall_blocked=1
            fi
        fi
        
        # 4. 检查云服务商安全组（如果适用）
        _yellow "4. 检查云服务商配置..."
        if [ -f "/sys/class/dmi/id/product_name" ]; then
            local product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
            case "$product_name" in
                *"Amazon EC2"*|*"AWS"*)
                    _yellow "⚠ 检测到AWS EC2，请检查安全组是否开放SSH端口 $SSH_PORT"
                    ;;
                *"Google Compute Engine"*|*"GCP"*)
                    _yellow "⚠ 检测到Google Cloud，请检查防火墙规则是否开放SSH端口 $SSH_PORT"
                    ;;
                *"Microsoft Corporation"*|*"Azure"*)
                    _yellow "⚠ 检测到Azure，请检查网络安全组是否开放SSH端口 $SSH_PORT"
                    ;;
                *"Alibaba Cloud"*|*"Aliyun"*)
                    _yellow "⚠ 检测到阿里云，请检查安全组是否开放SSH端口 $SSH_PORT"
                    ;;
                *)
                    _green "✓ 物理服务器或本地虚拟机"
                    ;;
            esac
        fi
        
        # 5. 使用第三方API检测端口开放性
        _yellow "5. 使用第三方API检测端口开放性..."
        _blue "检测协议: $SSH_PROTOCOL (SSH使用TCP协议)"
        
        # 使用在线端口检测服务
        if command -v curl &>/dev/null; then
            _yellow "正在使用第三方API检测TCP端口 $SSH_PORT..."
            
            # 方法1: 使用canyouseeme.org API (TCP检测)
            local canyouseeme_result=$(curl -s "http://canyouseeme.org/api/port/$SSH_PORT" 2>/dev/null)
            if [ -n "$canyouseeme_result" ]; then
                if echo "$canyouseeme_result" | grep -q "open\|success"; then
                    _green "✓ canyouseeme.org: TCP端口 $SSH_PORT 外网可访问"
                fi
            fi
            
            # 方法2: 使用portchecker.co API (TCP检测)
            local portchecker_result=$(curl -s "https://portchecker.co/check" -d "port=$SSH_PORT" 2>/dev/null)
            if [ -n "$portchecker_result" ]; then
                if echo "$portchecker_result" | grep -q "open\|accessible"; then
                    _green "✓ portchecker.co: TCP端口 $SSH_PORT 外网可访问"
                fi
            fi
            
            # 方法3: 使用whatismyipaddress.com端口检测 (TCP检测)
            local wmipa_result=$(curl -s "https://whatismyipaddress.com/port-scanner" -d "port=$SSH_PORT" 2>/dev/null)
            if [ -n "$wmipa_result" ]; then
                if echo "$wmipa_result" | grep -q "open\|accessible"; then
                    _green "✓ whatismyipaddress.com: TCP端口 $SSH_PORT 外网可访问"
                fi
            fi
            
            # 方法4: 使用在线端口扫描工具 (TCP检测)
            local portscan_url="https://www.yougetsignal.com/tools/open-ports/port.php"
            local portscan_result=$(curl -s "$portscan_url" -d "remoteAddress=$server_ip&portNumber=$SSH_PORT" 2>/dev/null)
            if [ -n "$portscan_result" ]; then
                if echo "$portscan_result" | grep -q "open\|accessible"; then
                    _green "✓ yougetsignal.com: TCP端口 $SSH_PORT 外网可访问"
                fi
            fi
            
            # 方法5: UDP端口检测示例 (如果需要检测UDP端口)
            _yellow "UDP端口检测示例 (常用UDP端口):"
            local udp_ports=("53" "123" "161" "500" "4500")
            for udp_port in "${udp_ports[@]}"; do
                _blue "检测UDP端口 $udp_port..."
                if command -v nmap &>/dev/null; then
                    local udp_result=$(nmap -sU -p "$udp_port" localhost 2>/dev/null | grep -o "open\|closed\|filtered" | head -1)
                    if [ -n "$udp_result" ]; then
                        case "$udp_result" in
                            "open")
                                _green "✓ UDP端口 $udp_port: 开放"
                                ;;
                            "closed")
                                _yellow "⚠ UDP端口 $udp_port: 关闭"
                                ;;
                            "filtered")
                                _yellow "⚠ UDP端口 $udp_port: 被过滤"
                                ;;
                        esac
                    fi
                fi
            done
        fi
        
        # 6. 使用本地工具检测端口
        _yellow "6. 使用本地工具检测端口..."
        _blue "检测协议: $SSH_PROTOCOL (SSH使用TCP协议)"
        
        # 使用nmap检测TCP端口（如果可用）
        if command -v nmap &>/dev/null; then
            if nmap -p "$SSH_PORT" localhost 2>/dev/null | grep -q "open"; then
                _green "✓ nmap: TCP端口 $SSH_PORT 本地开放"
            fi
        fi
        
        # 使用telnet测试TCP连接（如果可用）
        if command -v telnet &>/dev/null; then
            if timeout 3 telnet localhost "$SSH_PORT" 2>/dev/null | grep -q "Connected"; then
                _green "✓ telnet: TCP连接成功"
            fi
        fi
        
        # 使用nc (netcat) 测试TCP连接（如果可用）
        if command -v nc &>/dev/null; then
            if timeout 3 nc -z localhost "$SSH_PORT" 2>/dev/null; then
                _green "✓ netcat: TCP连接成功"
            fi
        fi
        
        # 使用ss命令检测TCP端口状态（如果可用）
        if command -v ss &>/dev/null; then
            if ss -tlnp | grep ":$SSH_PORT " >/dev/null 2>&1; then
                _green "✓ ss: TCP端口 $SSH_PORT 正在监听"
            fi
        fi
        
        # 7. 生成SSH访问诊断报告
        _yellow "7. 生成SSH访问诊断报告..."
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local ssh_report="$REPORT_DIR/ssh_access_diagnosis_$timestamp.txt"
        
        {
            echo "SSH端口访问诊断报告"
            echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "服务器IP: $server_ip"
            echo "SSH端口: $SSH_PORT"
            echo "协议类型: $SSH_PROTOCOL (SSH使用TCP协议，端口22是TCP端口)"
            echo "=========================================="
            echo
            
            echo "SSH服务状态:"
            systemctl status ssh 2>/dev/null || systemctl status sshd 2>/dev/null || echo "SSH服务状态未知"
            echo
            
            echo "端口监听状态:"
            netstat -tlnp | grep ":$SSH_PORT "
            echo
            
            echo "防火墙状态:"
            if command -v iptables &>/dev/null; then
                echo "iptables规则:"
                iptables -L INPUT | grep -E "ACCEPT|DROP|REJECT"
            fi
            if command -v ufw &>/dev/null; then
                echo "ufw状态:"
                ufw status
            fi
            if command -v firewall-cmd &>/dev/null; then
                echo "firewalld状态:"
                firewall-cmd --list-all
            fi
            echo
            
            echo "SSH配置:"
            if [ -f "/etc/ssh/sshd_config" ]; then
                grep -E "^Port|^ListenAddress|^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null || echo "SSH配置读取失败"
            fi
            echo
            
            echo "第三方API检测结果 (TCP端口):"
            echo "检测协议: $SSH_PROTOCOL (SSH使用TCP协议，端口22是TCP端口)"
            echo "- canyouseeme.org: $(curl -s "http://canyouseeme.org/api/port/$SSH_PORT" 2>/dev/null || echo '检测失败')"
            echo "- portchecker.co: $(curl -s "https://portchecker.co/check" -d "port=$SSH_PORT" 2>/dev/null || echo '检测失败')"
            echo "- whatismyipaddress.com: $(curl -s "https://whatismyipaddress.com/port-scanner" -d "port=$SSH_PORT" 2>/dev/null || echo '检测失败')"
            echo "- yougetsignal.com: $(curl -s "https://www.yougetsignal.com/tools/open-ports/port.php" -d "remoteAddress=$server_ip&portNumber=$SSH_PORT" 2>/dev/null || echo '检测失败')"
            echo
            
            echo "UDP端口检测示例 (常用UDP端口):"
            echo "UDP端口检测说明: UDP是无连接协议，检测相对困难"
            echo "常用UDP端口: 53(DNS), 123(NTP), 161(SNMP), 500(IPSec), 4500(IPSec)"
            if command -v nmap &>/dev/null; then
                echo "UDP端口53检测: $(nmap -sU -p 53 localhost 2>/dev/null | grep -o "open\|closed\|filtered" | head -1 || echo '检测失败')"
            fi
            echo
            
            echo "本地工具检测结果 (TCP端口):"
            if command -v nmap &>/dev/null; then
                echo "- nmap TCP: $(nmap -p "$SSH_PORT" localhost 2>/dev/null | grep -o "open\|closed\|filtered" | head -1 || echo '检测失败')"
            fi
            if command -v ss &>/dev/null; then
                echo "- ss TCP: $(ss -tlnp | grep ":$SSH_PORT " >/dev/null 2>&1 && echo '监听中' || echo '未监听')"
            fi
            echo
            
            echo "诊断建议:"
            echo "1. SSH使用TCP协议，端口22是TCP端口"
            echo "2. 从外网设备测试: ssh root@$server_ip -p $SSH_PORT"
            echo "3. 检查云服务商安全组设置 (TCP端口22)"
            echo "4. 检查本地防火墙规则 (TCP端口22)"
            echo "5. 检查SSH服务配置"
            echo "6. 使用第三方端口检测工具验证TCP端口22"
            echo "7. UDP端口检测需要使用专门的UDP扫描工具"
            if [ $firewall_blocked -eq 1 ]; then
                echo "8. 检查防火墙规则，确保SSH端口 $SSH_PORT 已开放"
            fi
            
        } > "$ssh_report"
        
        _green "✓ SSH访问诊断报告已生成: $ssh_report"
        
        # 8. 总结诊断结果
        echo
        _blue "=== SSH访问诊断总结 ==="
        _blue "协议类型: $SSH_PROTOCOL (SSH使用TCP协议，端口22是TCP端口)"
        if [ $firewall_blocked -eq 0 ]; then
            _green "✓ 本地SSH配置正常"
            _yellow "⚠ 外网访问性需要进一步验证"
            _yellow "建议: 使用第三方API检测或从外网设备测试 ssh root@$server_ip -p $SSH_PORT"
            _blue "第三方TCP端口检测服务:"
            _blue "- canyouseeme.org"
            _blue "- portchecker.co" 
            _blue "- whatismyipaddress.com"
            _blue "- yougetsignal.com"
            _blue "UDP端口检测说明: UDP是无连接协议，检测相对困难"
            _blue "常用UDP端口: 53(DNS), 123(NTP), 161(SNMP), 500(IPSec), 4500(IPSec)"
        else
            _red "❌ 发现SSH访问问题"
            _yellow "建议: 检查防火墙规则和云服务商配置 (TCP端口22)"
        fi
        
        log_message "SSH访问诊断完成，服务器IP: $server_ip, 端口: $SSH_PORT"
        
    else
        _red "❌ 无法获取服务器IP地址"
        log_message "无法获取服务器IP地址"
    fi
}

# 诊断网络问题
diagnose_network_issues() {
    _blue "=== 诊断网络问题 ==="
    
    local total_issues=0
    
    # 检测各个组件
    detect_network_interfaces
    total_issues=$((total_issues + $?))
    
    detect_firewall_status
    total_issues=$((total_issues + $?))
    
    detect_dns_config
    total_issues=$((total_issues + $?))
    
    detect_network_services
    total_issues=$((total_issues + $?))
    
    check_connectivity
    total_issues=$((total_issues + $?))
    
    check_ssh_port_access
    total_issues=$((total_issues + $?))
    
    if [ $total_issues -eq 0 ]; then
        _green "✓ 网络环境正常，未发现问题"
        return 0
    else
        _red "❌ 发现 $total_issues 个网络问题"
        return 1
    fi
}

# 生成网络状态报告
generate_network_report() {
    _blue "=== 生成网络状态报告 ==="
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local report_file="$REPORT_DIR/network_status_$timestamp.txt"
    
    mkdir -p "$REPORT_DIR"
    
    {
        echo "网络状态报告"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "服务器: $(hostname)"
        echo "操作系统: $(uname -s) $(uname -r)"
        echo "=========================================="
        echo
        
        echo "网络接口状态:"
        ip addr show
        echo
        
        echo "路由表:"
        ip route show
        echo
        
        echo "DNS配置:"
        cat /etc/resolv.conf 2>/dev/null || echo "resolv.conf不存在"
        echo
        
        echo "防火墙状态:"
        if command -v iptables &>/dev/null; then
            echo "iptables规则:"
            iptables -L
        fi
        if command -v ufw &>/dev/null; then
            echo "ufw状态:"
            ufw status
        fi
        echo
        
        echo "网络服务状态:"
        systemctl status networking 2>/dev/null || echo "networking服务状态未知"
        systemctl status systemd-resolved 2>/dev/null || echo "systemd-resolved服务状态未知"
        echo
        
        echo "端口监听状态:"
        netstat -tlnp
        echo
        
        echo "连通性测试:"
        echo "本地回环: $(ping -c 1 127.0.0.1 >/dev/null 2>&1 && echo '正常' || echo '失败')"
        echo "外网连通: $(ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo '正常' || echo '失败')"
        echo "DNS解析: $(nslookup google.com >/dev/null 2>&1 && echo '正常' || echo '失败')"
        
    } > "$report_file"
    
    _green "✓ 网络状态报告已生成: $report_file"
    log_message "网络状态报告生成: $report_file"
}

# 创建故障诊断报告
create_fault_report() {
    _blue "=== 创建故障诊断报告 ==="
    
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local report_file="$REPORT_DIR/fault_analysis_$timestamp.txt"
    
    mkdir -p "$REPORT_DIR"
    
    {
        echo "网络故障诊断报告"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "服务器: $(hostname)"
        echo "=========================================="
        echo
        
        echo "问题分析:"
        
        # 网络接口问题
        local interface_issues=$(detect_network_interfaces 2>&1 | grep -c "❌\|⚠")
        if [ $interface_issues -gt 0 ]; then
            echo "- 网络接口问题: $interface_issues 个"
        fi
        
        # 连通性问题
        local connectivity_issues=$(check_connectivity 2>&1 | grep -c "❌")
        if [ $connectivity_issues -gt 0 ]; then
            echo "- 连通性问题: $connectivity_issues 个"
        fi
        
        # DNS问题
        local dns_issues=$(detect_dns_config 2>&1 | grep -c "❌")
        if [ $dns_issues -gt 0 ]; then
            echo "- DNS配置问题: $dns_issues 个"
        fi
        
        # SSH问题
        local ssh_issues=$(check_ssh_port_access 2>&1 | grep -c "❌")
        if [ $ssh_issues -gt 0 ]; then
            echo "- SSH服务问题: $ssh_issues 个"
        fi
        
        echo
        echo "修复建议:"
        echo "1. 检查网络接口配置"
        echo "2. 验证路由表设置"
        echo "3. 检查DNS服务器配置"
        echo "4. 确认防火墙规则"
        echo "5. 重启网络服务"
        echo "6. 检查SSH服务状态"
        
    } > "$report_file"
    
    _green "✓ 故障诊断报告已生成: $report_file"
    log_message "故障诊断报告生成: $report_file"
}

# 初始化网络环境
initialize_network() {
    _blue "=== 初始化网络环境 ==="
    
    _yellow "重启网络服务..."
    systemctl restart networking 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
    
    _yellow "刷新网络配置..."
    if command -v netplan &>/dev/null; then
        netplan apply 2>/dev/null || true
    fi
    
    _green "✓ 网络环境初始化完成"
    log_message "网络环境初始化完成"
}

# 修复网络问题
fix_network_issues() {
    _blue "=== 修复网络问题 ==="
    
    local fixes_applied=0
    
    # 重启网络服务
    _yellow "重启网络服务..."
    systemctl restart networking 2>/dev/null && fixes_applied=$((fixes_applied + 1))
    systemctl restart systemd-resolved 2>/dev/null && fixes_applied=$((fixes_applied + 1))
    
    # 刷新网络配置
    if command -v netplan &>/dev/null; then
        _yellow "应用网络配置..."
        netplan apply 2>/dev/null && fixes_applied=$((fixes_applied + 1))
    fi
    
    # 确保SSH服务运行
    if ! systemctl is-active ssh &>/dev/null && ! systemctl is-active sshd &>/dev/null; then
        _yellow "启动SSH服务..."
        systemctl start ssh 2>/dev/null || systemctl start sshd 2>/dev/null
        fixes_applied=$((fixes_applied + 1))
    fi
    
    _green "✓ 应用了 $fixes_applied 个修复措施"
    log_message "网络修复完成，应用了 $fixes_applied 个修复措施"
}

# 验证网络状态
verify_network_status() {
    _blue "=== 验证网络状态 ==="
    
    local verification_passed=0
    
    # 验证连通性
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        _green "✓ 外网连通性: 正常"
        verification_passed=$((verification_passed + 1))
    else
        _red "❌ 外网连通性: 失败"
    fi
    
    # 验证DNS
    if nslookup google.com >/dev/null 2>&1; then
        _green "✓ DNS解析: 正常"
        verification_passed=$((verification_passed + 1))
    else
        _red "❌ DNS解析: 失败"
    fi
    
    # 验证SSH
    if systemctl is-active ssh &>/dev/null || systemctl is-active sshd &>/dev/null; then
        _green "✓ SSH服务: 正常"
        verification_passed=$((verification_passed + 1))
    else
        _red "❌ SSH服务: 失败"
    fi
    
    if [ $verification_passed -eq 3 ]; then
        _green "✓ 网络状态验证通过"
        return 0
    else
        _red "❌ 网络状态验证失败 ($verification_passed/3)"
        return 1
    fi
}

# 主执行函数
main() {
    # 初始化日志
    echo "网络修复脚本日志 - $(date)" > "$LOG_FILE"
    
    # 环境检查
    check_server_environment
    echo
    
    # 检查命令行参数
    if [ $# -gt 0 ]; then
        # 如果有命令行参数，直接执行对应功能
        handle_menu_choice "$1"
    else
        # 交互式菜单模式
        while true; do
            show_menu
            echo -n "请输入选择 (1-6): "
            read -r choice
            echo
            
            case "$choice" in
                "1"|"backup")
                    create_network_backup
                    ;;
                "2"|"view")
                    view_network_config
                    ;;
                "3"|"restore")
                    restore_network_config
                    ;;
                "4"|"diagnose")
                    # 检查并创建初始备份
                    if ! check_initial_backup_exists; then
                        create_initial_backup
                        echo
                    fi
                    
                    # 更新当前备份
                    update_current_backup
                    echo
                    
                    # 执行网络诊断和修复
                    diagnose_and_fix_network
                    ;;
                "5"|"ssh")
                    test_external_ssh_access
                    ;;
                "6"|"exit"|"quit")
                    _green "感谢使用！"
                    break
                    ;;
                "")
                    continue
                    ;;
                *)
                    _red "❌ 无效的选择: '$choice'，请重新输入"
                    ;;
            esac
            
            echo
            echo -n "按回车键继续..."
            read -r
        done
    fi
}

# 错误处理
trap 'echo "脚本执行中断"; exit 1' INT TERM

# 执行主函数
main "$@"
