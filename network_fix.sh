#!/bin/bash
# 网络环境检测与修复脚本
# 包含全面的网络检测、备份和修复功能
# 支持初始备份、当前备份、故障诊断和网络修复

# 版本信息
SCRIPT_VERSION="1.0.0"
SCRIPT_BUILD="$(date '+%Y%m%d-%H%M%S')"
SCRIPT_NAME="网络环境检测与修复脚本"

# 脚本配置
SSH_PORT="22"
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
        
        # 检查端口是否可以从外网访问
        if timeout 5 bash -c "</dev/tcp/$server_ip/$SSH_PORT" 2>/dev/null; then
            _green "✓ SSH端口 $SSH_PORT 外网可访问"
        else
            _yellow "⚠ SSH端口 $SSH_PORT 外网访问测试失败"
            _yellow "可能原因: 防火墙阻止、网络问题或SSH服务未运行"
        fi
    else
        _red "❌ 无法获取服务器IP地址"
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
    
    _blue "=========================================="
    _blue "        $SCRIPT_NAME v$SCRIPT_VERSION"
    _blue "        构建时间: $SCRIPT_BUILD"
    _blue "=========================================="
    echo
    
    # 环境检查
    check_server_environment
    echo
    
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
    
    echo
    _blue "=== 执行完成 ==="
    _green "日志文件: $LOG_FILE"
    _green "备份目录: $BACKUP_DIR/"
    _green "报告目录: $REPORT_DIR/"
    echo
}

# 错误处理
trap 'echo "脚本执行中断"; exit 1' INT TERM

# 执行主函数
main "$@"
