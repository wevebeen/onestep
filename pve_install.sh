#!/bin/bash
# PVE一键安装脚本
# 包含详细的调试信息和错误处理
# 脚本来源：https://virt.spiritlhl.net/guide/pve/pve_install.html

# 版本信息
SCRIPT_VERSION="1.0.3"
SCRIPT_BUILD="20251013-095519"
SCRIPT_NAME="PVE一键安装脚本"

# 脚本配置
PVE_URL="https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/install_pve.sh"
BACKEND_URL="https://raw.githubusercontent.com/oneclickvirt/pve/main/scripts/build_backend.sh"

# 颜色输出函数
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }

# 调试函数
# 调试日志函数（已禁用）
debug_log() {
    # 调试输出已禁用，只在失败时显示错误
    return 0
}

# 检查备份是否存在
check_backup_exists() {
    local backup_dir="backups"
    local today=$(date '+%Y%m%d')
    
    # 检查今天的备份是否存在
    if [ -d "$backup_dir" ]; then
        local today_backups=$(find "$backup_dir" -name "backup_${today}_*" -type d 2>/dev/null | wc -l)
            if [ "$today_backups" -gt 0 ]; then
                # 找到最早创建的备份
                local earliest_backup=$(find "$backup_dir" -name "backup_${today}_*" -type d 2>/dev/null | sort | head -1)
                local backup_name=$(basename "$earliest_backup")
                
                # 只显示简单提示
                _yellow "✅ 备份已存在，跳过备份"
                
                return 0
            fi
    fi
    
    return 1
}

# 备份函数
backup_before_change() {
    # 先检查备份是否存在
    if check_backup_exists; then
        return 0
    fi
    
    local backup_name="backup_$(date '+%Y%m%d_%H%M%S')"
    
    # 备份重要文件
    mkdir -p backups/$backup_name
    cp -f install.log backups/$backup_name/ 2>/dev/null || true
    cp -f debug.log backups/$backup_name/ 2>/dev/null || true
    
    # 显示备份创建信息
    _green "=== 备份创建成功 ==="
    echo "备份名称: $backup_name"
    echo "备份路径: backups/$backup_name"
    echo "创建时间: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # 显示备份内容
    if [ -d "backups/$backup_name" ]; then
        local backup_size=$(du -sh "backups/$backup_name" 2>/dev/null | cut -f1)
        echo "备份大小: $backup_size"
        echo
        _blue "备份内容:"
        ls -la "backups/$backup_name" | while read line; do
            echo "  $line"
        done
    fi
    echo
}

# 检查执行环境
check_environment() {
    _blue "=== 检查执行环境 ==="
    
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
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        _red "错误: 网络连接失败，请检查网络配置"
        exit 1
    fi
    
    # 检查系统资源
    local mem_gb=$(free -g | awk 'NR==2{print $2}')
    local disk_gb=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    
    if [ "$mem_gb" -lt 2 ]; then
        _yellow "警告: 内存不足2GB，建议至少2GB内存"
    fi
    
    if [ "$disk_gb" -lt 20 ]; then
        _yellow "警告: 磁盘空间不足20GB，建议至少20GB存储空间"
    fi
    
    _green "✓ 操作系统: $(uname -s)"
    _green "✓ 内存: ${mem_gb}GB"
    _green "✓ 磁盘: ${disk_gb}GB"
}

# 检测当前安装状态
detect_installation_status() {
    # 检查PVE是否已安装
    if command -v pct &>/dev/null && command -v qm &>/dev/null; then
        echo "installed"
        return
    fi
    
    # 检查重启标记
    if [ -f "/usr/local/bin/reboot_pve.txt" ]; then
        echo "reboot_marked"
        return
    fi
    
    # 检查后端配置标记
    if [ -f "/usr/local/bin/build_backend_pve.txt" ]; then
        echo "backend_done"
        return
    fi
    
    # 全新安装
    echo "fresh"
}

# 下载脚本文件
download_script() {
    local script_url="$1"
    local script_name="$2"
    
    _green "下载 $script_name..."
    
    if curl -L "$script_url" -o "$script_name" --connect-timeout 30; then
        chmod +x "$script_name"
        return 0
    else
        return 1
    fi
}

# 第一次执行安装
first_execution() {
    _blue "=== 第一次执行安装 ==="
    
    # 下载安装脚本
    if ! download_script "$PVE_URL" "install_pve.sh"; then
        _red "❌ 下载安装脚本失败"
        return 1
    fi
    
    # 执行安装脚本
    _green "执行PVE安装脚本..."
    
    # 直接执行脚本
    bash install_pve.sh
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] || [ $exit_code -eq 1 ]; then
        _green "第一次执行完成（官网脚本要求重启）"
        return 0
    else
        _red "❌ 第一次执行失败，退出码: $exit_code"
        return 1
    fi
}

# 验证第一次执行结果
verify_first_execution() {
    _blue "=== 验证第一次执行结果 ==="
    
    # 检查第一个脚本是否创建了重启标记
    if [ -f "/usr/local/bin/reboot_pve.txt" ]; then
        _green "✓ 检测到第一个脚本创建的重启标记"
    else
        _red "❌ 第一个脚本未创建重启标记"
        return 1
    fi
    
    # 检查网络配置
    if ip link show vmbr0 &>/dev/null; then
        _green "✓ vmbr0网桥已创建"
    else
        _red "❌ vmbr0网桥未创建"
        return 1
    fi
    
    # 检查APT源配置
    if [ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]; then
        _green "✓ PVE APT源已配置"
    else
        _red "❌ PVE APT源未配置"
        return 1
    fi
    
    _green "第一次执行验证通过"
    return 0
}

# 重启相关服务以应用更改
restart_services() {
    _blue "=== 重启服务以应用更改 ==="
    
    # 重启网络服务
    _yellow "重启网络服务..."
    systemctl restart networking
    if [ $? -eq 0 ]; then
        _green "✓ 网络服务重启成功"
    else
        _red "❌ 网络服务重启失败"
    fi
    
    # 重启DNS服务
    _yellow "重启DNS服务..."
    systemctl restart systemd-resolved
    if [ $? -eq 0 ]; then
        _green "✓ DNS服务重启成功"
    else
        _red "❌ DNS服务重启失败"
    fi
    
    # 重启时间同步服务
    _yellow "重启时间同步服务..."
    systemctl restart chronyd
    if [ $? -eq 0 ]; then
        _green "✓ 时间同步服务重启成功"
    else
        _red "❌ 时间同步服务重启失败"
    fi
    
    # 重启haveged服务
    _yellow "重启haveged服务..."
    systemctl restart haveged
    if [ $? -eq 0 ]; then
        _green "✓ haveged服务重启成功"
    else
        _red "❌ haveged服务重启失败"
    fi
    
    # 重启DNS检查服务
    _yellow "重启DNS检查服务..."
    systemctl restart check-dns.service
    if [ $? -eq 0 ]; then
        _green "✓ DNS检查服务重启成功"
    else
        _red "❌ DNS检查服务重启失败"
    fi
    
    _green "服务重启完成"
}

# 模拟重启状态
simulate_reboot() {
    _blue "=== 模拟重启状态 ==="
    
    echo "1" > "/usr/local/bin/reboot_pve.txt"
    
    _green "重启标记已创建: /usr/local/bin/reboot_pve.txt"
    _yellow "模拟系统重启后的状态"
    
    sleep 1
}

# 第二次执行安装
second_execution() {
    _blue "=== 第二次执行安装 ==="
    
    # 确保安装脚本存在
    if [ ! -f "install_pve.sh" ]; then
        _red "❌ 安装脚本不存在，重新下载"
        if ! download_script "$PVE_URL" "install_pve.sh"; then
            _red "❌ 重新下载安装脚本失败"
            return 1
        fi
    fi
    
    # 执行安装脚本
    _green "执行PVE安装脚本（第二次）..."
    
    bash install_pve.sh
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        _green "第二次执行完成"
        return 0
    else
        _red "❌ 第二次执行失败，退出码: $exit_code"
        return 1
    fi
}

# 执行后端配置
execute_backend_setup() {
    _blue "=== 执行后端配置 ==="
    
    # 下载后端脚本
    if ! download_script "$BACKEND_URL" "build_backend.sh"; then
        _red "❌ 下载后端脚本失败"
        return 1
    fi
    
    # 执行后端脚本
    _green "执行后端配置脚本..."
    
    bash build_backend.sh
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        _green "后端配置完成"
        return 0
    else
        _red "❌ 后端配置失败，退出码: $exit_code"
        return 1
    fi
}

# 验证安装结果
verify_installation() {
    
    # 收集验证结果
    local verification_results=""
    
    # 检查PVE命令
    if command -v pct &>/dev/null && command -v qm &>/dev/null; then
        verification_results="${verification_results}✓ PVE命令可用 "
    else
        verification_results="${verification_results}✗ PVE命令不可用 "
        _red "❌ PVE命令验证失败"
        return 1
    fi
    
    # 检查网桥
    if ip link show vmbr0 &>/dev/null; then
        verification_results="${verification_results}✓ vmbr0网桥已创建 "
    else
        verification_results="${verification_results}⚠ vmbr0网桥未找到 "
    fi
    
    # 检查PVE服务
    if systemctl is-active pveproxy &>/dev/null; then
        verification_results="${verification_results}✓ PVE服务运行正常 "
    else
        verification_results="${verification_results}⚠ PVE服务状态异常 "
    fi
    
    # 获取服务器IP
    local server_ip=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null)
    if [ -n "$server_ip" ]; then
        verification_results="${verification_results}✓ 服务器IP: $server_ip"
    else
        verification_results="${verification_results}⚠ 无法获取服务器IP"
    fi
    
    # 显示验证结果（一行）
    echo "$verification_results"
    
    # 显示Web界面信息
    if [ -n "$server_ip" ]; then
        echo "🌐 PVE Web界面: https://$server_ip:8006"
    fi
}

# 清理临时文件
cleanup_files() {
    rm -f install_pve.sh build_backend.sh
    
    if [ -f "/usr/local/bin/reboot_pve.txt" ]; then
        rm -f /usr/local/bin/reboot_pve.txt
    fi
}

# 显示安装信息
show_installation_info() {
    _blue "=== 安装完成信息 ==="
    
    local server_ip=$(ip route get 8.8.8.8 | awk '{print $7; exit}' 2>/dev/null)
    
    echo
    _green "🎉 PVE安装完成！"
    echo
    _blue "访问信息:"
    _green "  Web界面: https://$server_ip:8006"
    _green "  用户名: root"
    _green "  密码: 服务器root密码"
    echo
    _blue "管理命令:"
    _green "  容器管理: pct"
    _green "  虚拟机管理: qm"
    _green "  查看状态: pveversion"
    echo
    _blue "调试信息:"
    _yellow "  调试日志: debug.log"
    _yellow "  安装日志: install.log"
    _yellow "  备份目录: backups/"
    echo
}

# 主执行函数
main() {
    # 初始化日志
    echo "PVE一键安装日志 - $(date)" > debug.log
    echo "PVE一键安装日志 - $(date)" > install.log
    
    _blue "=========================================="
    _blue "        $SCRIPT_NAME v$SCRIPT_VERSION"
    _blue "        构建时间: $SCRIPT_BUILD"
    _blue "=========================================="
    echo
    
    # 创建备份
    backup_before_change
    
    # 环境检查
    check_environment
    echo
    
    # 检测安装状态
    local status=$(detect_installation_status)
    _yellow "当前状态: $status"
    
    case $status in
        "installed")
            _green "PVE已安装，无需重复安装"
            verify_installation
            ;;
        "backend_done")
            _green "PVE安装和后端配置已完成"
            verify_installation
            ;;
        "reboot_marked")
            _yellow "检测到重启标记，继续第二次安装"
            if second_execution; then
                echo
                if execute_backend_setup; then
                    echo
                    verify_installation
                fi
            fi
            ;;
        "fresh")
            _green "开始全新安装流程"
            if first_execution; then
                echo
                if verify_first_execution; then
                    echo
                    restart_services
                    echo
                    simulate_reboot
                    echo
                    _yellow "第一次执行完成！"
                    _yellow "官网脚本要求重启系统，但我们模拟了重启状态"
                    _yellow "现在继续第二次执行..."
                    sleep 2
                    if second_execution; then
                        echo
                        if execute_backend_setup; then
                            echo
                            verify_installation
                        fi
                    fi
                else
                    _red "❌ 第一次执行后环境验证失败，安装终止"
                    exit 1
                fi
            else
                _red "❌ 第一次执行失败，安装终止"
                exit 1
            fi
            ;;
        *)
            _red "❌ 未知状态: $status"
            exit 1
            ;;
    esac
    
    echo
    cleanup_files
    echo
    show_installation_info
    
}

# 错误处理
trap 'echo "脚本执行中断"; exit 1' INT TERM

# 执行主函数
main "$@"
