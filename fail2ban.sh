#!/bin/bash
# fail2ban智能安装和管理脚本
# 作者: PVE Installer
# 创建时间: 2025-01-14
# 版本: 2.1.0

# 颜色定义
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
_cyan() { echo -e "\033[96m\033[01m$@\033[0m"; }
_magenta() { echo -e "\033[35m\033[01m$@\033[0m"; }

# 获取当前日期时间
get_datetime() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

# 显示标题
show_title() {
    clear
    echo ""
    _cyan "╔══════════════════════════════════════════════════════════════╗"
    _cyan "║                    fail2ban 智能管理工具                    ║"
    _cyan "║                    版本: 2.1.0                             ║"
    _cyan "║                    作者: PVE Installer                      ║"
    _cyan "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    _magenta "当前时间: $(get_datetime)"
    _magenta "系统信息: $(uname -s) $(uname -r) | $(hostname)"
    echo ""
}

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then
    show_title
    _red "❌ 错误: 请以root用户运行此脚本"
    exit 1
fi

# 获取当前用户IP
get_current_ip() {
    CURRENT_IP=$(who am i | awk '{print $NF}' | sed 's/[()]//g')
    if [ -z "$CURRENT_IP" ]; then
        CURRENT_IP=$(w | grep -E "pts/[0-9]" | awk '{print $3}' | head -1)
    fi
    if [ -z "$CURRENT_IP" ]; then
        CURRENT_IP=$(ss -tn | grep ESTAB | awk '{print $4}' | cut -d: -f1 | sort -u | grep -v 127.0.0.1 | head -1)
    fi
    echo "$CURRENT_IP"
}

# 检查fail2ban是否已安装
check_fail2ban_installed() {
    if command -v fail2ban-client >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# 检查fail2ban服务状态
check_fail2ban_status() {
    if systemctl is-active --quiet fail2ban; then
        return 0
    else
        return 1
    fi
}

# 安装fail2ban
install_fail2ban() {
    show_title
    _blue "🚀 开始安装fail2ban防火墙..."
    
    CURRENT_IP=$(get_current_ip)
    _blue "📍 检测到当前用户IP: $CURRENT_IP"
    echo ""
    
    # 1. 更新软件包列表
    _green "📦 1. 更新软件包列表..."
    apt update
    
    # 2. 安装fail2ban
    _green "📦 2. 安装fail2ban..."
    apt install -y fail2ban whois python3-systemd
    
    # 3. 创建配置文件
    _green "⚙️  3. 创建配置文件..."
    
    # 创建主配置文件
    cat > /etc/fail2ban/jail.local << JAIL_EOF
[DEFAULT]
# 默认配置
bantime = 14400
findtime = 600
maxretry = 3
backend = systemd
usedns = warn
logencoding = auto
enabled = false
filter = %(__name__)s
destemail = root@localhost
sender = root@localhost
mta = sendmail
protocol = tcp
chain = <known/chain>
port = 0:65535
fail2ban_agent = Fail2Ban/%(fail2ban_version)s

# 忽略的IP地址（白名单）- 包含当前用户IP
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 $CURRENT_IP

# 动作配置
action = %(action_)s
name = %(name)s

# SSH防护
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 3
bantime = 14400
findtime = 600
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 $CURRENT_IP
JAIL_EOF

    # 创建SSH专用配置
    cat > /etc/fail2ban/jail.d/sshd.local << SSHD_EOF
[sshd]
enabled = true
port = ssh
filter = sshd
backend = systemd
maxretry = 3
bantime = 14400
findtime = 600
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 $CURRENT_IP
SSHD_EOF

    # 4. 启动服务
    _green "🔄 4. 启动fail2ban服务..."
    systemctl start fail2ban
    systemctl enable fail2ban
    
    # 5. 检查服务状态
    _green "✅ 5. 检查服务状态..."
    if systemctl is-active --quiet fail2ban; then
        _green "✅ fail2ban服务启动成功"
    else
        _red "❌ fail2ban服务启动失败"
        return 1
    fi
    
    echo ""
    _green "🎉 fail2ban安装完成！"
    show_status
}

# 添加当前IP到白名单
add_current_ip_to_whitelist() {
    show_title
    CURRENT_IP=$(get_current_ip)
    if [ -z "$CURRENT_IP" ]; then
        _red "❌ 无法检测到当前用户IP"
        return 1
    fi
    
    _blue "📍 当前用户IP: $CURRENT_IP"
    echo ""
    
    # 检查IP是否已在白名单中
    if fail2ban-client get sshd ignoreip | grep -q "$CURRENT_IP"; then
        _yellow "⚠️  IP $CURRENT_IP 已在白名单中"
        return 0
    fi
    
    # 添加到白名单
    _green "➕ 添加IP $CURRENT_IP 到白名单..."
    
    # 更新配置文件
    sed -i "s/ignoreip = 127.0.0.1\/8 ::1 10.0.0.0\/8 172.16.0.0\/12 192.168.0.0\/16/ignoreip = 127.0.0.1\/8 ::1 10.0.0.0\/8 172.16.0.0\/12 192.168.0.0\/16 $CURRENT_IP/g" /etc/fail2ban/jail.local
    sed -i "s/ignoreip = 127.0.0.1\/8 ::1 10.0.0.0\/8 172.16.0.0\/12 192.168.0.0\/16/ignoreip = 127.0.0.1\/8 ::1 10.0.0.0\/8 172.16.0.0\/12 192.168.0.0\/16 $CURRENT_IP/g" /etc/fail2ban/jail.d/sshd.local
    
    # 重启服务
    systemctl restart fail2ban
    
    if systemctl is-active --quiet fail2ban; then
        _green "✅ IP $CURRENT_IP 已成功添加到白名单"
    else
        _red "❌ 添加白名单失败，服务重启失败"
        return 1
    fi
}

# 显示状态信息
show_status() {
    show_title
    _blue "📊 === fail2ban状态 ==="
    fail2ban-client status
    
    echo ""
    _blue "🛡️  === SSH防护状态 ==="
    fail2ban-client status sshd
    
    echo ""
    _blue "🚫 === 当前封禁的IP ==="
    BANNED_IPS=$(iptables -L f2b-sshd -n | grep REJECT | awk '{print $4}')
    if [ -z "$BANNED_IPS" ]; then
        _green "✅ 当前没有封禁的IP"
    else
        echo "$BANNED_IPS" | while read ip; do
            _red "🚫 $ip"
        done
    fi
    
    echo ""
    _blue "⚙️  === 配置信息 ==="
    BANTIME=$(fail2ban-client get sshd bantime)
    FINDTIME=$(fail2ban-client get sshd findtime)
    MAXRETRY=$(fail2ban-client get sshd maxretry)
    
    _cyan "⏰ 封禁时间: $BANTIME 秒 ($(($BANTIME/3600)) 小时)"
    _cyan "🔍 检测窗口: $FINDTIME 秒 ($(($FINDTIME/60)) 分钟)"
    _cyan "🔢 最大重试: $MAXRETRY 次"
    
    echo ""
    _cyan "📋 白名单IP:"
    fail2ban-client get sshd ignoreip | sed 's/^/   /'
    
    echo ""
    _green "📁 日志文件: /var/log/fail2ban.log"
    _green "📁 配置文件: /etc/fail2ban/jail.local"
    _green "📁 SSH配置: /etc/fail2ban/jail.d/sshd.local"
}

# 显示菜单
show_menu() {
    echo ""
    _cyan "╔══════════════════════════════════════════════════════════════╗"
    _cyan "║                       管理菜单                              ║"
    _cyan "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    _yellow "1️⃣  安装fail2ban"
    _yellow "2️⃣  添加当前IP到白名单"
    _yellow "3️⃣  查看状态"
    _yellow "4️⃣  重启服务"
    _yellow "5️⃣  查看日志"
    _yellow "0️⃣  退出程序"
    echo ""
}

# 查看日志
view_logs() {
    show_title
    _blue "📋 === fail2ban日志 (最近20行) ==="
    echo ""
    tail -20 /var/log/fail2ban.log | sed 's/^/   /'
    
    echo ""
    _blue "🔍 === SSH攻击日志 (最近10行) ==="
    echo ""
    journalctl -u ssh --since "1 hour ago" | grep -E "Failed password|Invalid user" | tail -10 | sed 's/^/   /'
}

# 主程序
main() {
    while true; do
        show_title
        show_menu
        read -p "$(_green "请选择操作 [0-5]: ")" choice
        
        case $choice in
            1)
                if check_fail2ban_installed; then
                    _yellow "⚠️  fail2ban已安装"
                    if check_fail2ban_status; then
                        _green "✅ fail2ban服务正在运行"
                    else
                        _yellow "⚠️  fail2ban服务未运行，正在启动..."
                        systemctl start fail2ban
                        systemctl enable fail2ban
                    fi
                else
                    install_fail2ban
                fi
                ;;
            2)
                if check_fail2ban_installed && check_fail2ban_status; then
                    add_current_ip_to_whitelist
                else
                    _red "❌ fail2ban未安装或服务未运行"
                fi
                ;;
            3)
                if check_fail2ban_installed && check_fail2ban_status; then
                    show_status
                else
                    _red "❌ fail2ban未安装或服务未运行"
                fi
                ;;
            4)
                if check_fail2ban_installed; then
                    _green "🔄 重启fail2ban服务..."
                    systemctl restart fail2ban
                    if systemctl is-active --quiet fail2ban; then
                        _green "✅ 服务重启成功"
                    else
                        _red "❌ 服务重启失败"
                    fi
                else
                    _red "❌ fail2ban未安装"
                fi
                ;;
            5)
                if check_fail2ban_installed; then
                    view_logs
                else
                    _red "❌ fail2ban未安装"
                fi
                ;;
            0)
                show_title
                _green "👋 感谢使用fail2ban管理工具！"
                _green "🕐 退出时间: $(get_datetime)"
                exit 0
                ;;
            *)
                _red "❌ 无效选择，请重新输入"
                ;;
        esac
        
        echo ""
        read -p "$(_yellow "按回车键继续...")" 
    done
}

# 运行主程序
main
