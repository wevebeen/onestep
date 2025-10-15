#!/bin/bash
# fail2ban智能安装和管理脚本
# 创建时间: 2025-01-15
# 版本: 4.0.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 显示颜色文本
show_red() { echo "$1"; }
show_green() { echo "$1"; }
show_yellow() { echo "$1"; }
show_blue() { echo "$1"; }
show_cyan() { echo "$1"; }
show_magenta() { echo "$1"; }

# 获取当前日期时间
get_datetime() {
    echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

# 显示标题和菜单
show_title() {
    clear
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "                    fail2ban 智能管理工具"
    echo "                        版本号: 4.0.4"
    echo ""
    echo "         [1] 安装fail2ban  [2] 添加白名单     [3] 查看状态"
    echo "         [4] 重启服务       [5] 查看日志      [0] 退出程序"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo ""

    echo ""
}

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then
    show_title
    echo "❌ 错误: 请以root用户运行此脚本"
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
    command -v fail2ban-client >/dev/null 2>&1
}

# 检查fail2ban服务状态
check_fail2ban_status() {
    systemctl is-active --quiet fail2ban
}

# 安装fail2ban
install_fail2ban() {
    show_title
    echo "🚀 开始安装fail2ban防火墙..."
    
    CURRENT_IP=$(get_current_ip)
    echo "📍 检测到当前用户IP: $CURRENT_IP"
    echo ""
    
    # 1. 更新软件包列表
    echo "📦 1. 更新软件包列表..."
    apt update
    
    # 2. 安装fail2ban
    echo "📦 2. 安装fail2ban..."
    apt install -y fail2ban whois python3-systemd
    
    # 3. 创建配置文件
    echo "⚙️  3. 创建配置文件..."
    
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
    echo "🔄 4. 启动fail2ban服务..."
    systemctl start fail2ban
    systemctl enable fail2ban
    
    # 5. 检查服务状态
    echo "✅ 5. 检查服务状态..."
    if systemctl is-active --quiet fail2ban; then
        echo "✅ fail2ban服务启动成功"
    else
        echo "❌ fail2ban服务启动失败"
        return 1
    fi
    
    echo ""
    echo "🎉 fail2ban安装完成！"
    show_status
}

# 添加当前IP到白名单
add_current_ip_to_whitelist() {
    show_title
    CURRENT_IP=$(get_current_ip)
    if [ -z "$CURRENT_IP" ]; then
        show_red "❌ 无法检测到当前用户IP"
        return 1
    fi
    
    show_blue "📍 当前用户IP: $CURRENT_IP"
    echo ""
    
    # 检查IP是否已在白名单中
    if fail2ban-client get sshd ignoreip | grep -q "$CURRENT_IP"; then
        show_yellow "⚠️  IP $CURRENT_IP 已在白名单中"
        return 0
    fi
    
    # 添加到白名单
    show_green "➕ 添加IP $CURRENT_IP 到白名单..."
    
    # 更新配置文件
    sed -i "s/ignoreip = 127.0.0.1\/8 ::1 10.0.0.0\/8 172.16.0.0\/12 192.168.0.0\/16/ignoreip = 127.0.0.1\/8 ::1 10.0.0.0\/8 172.16.0.0\/12 192.168.0.0\/16 $CURRENT_IP/g" /etc/fail2ban/jail.local
    sed -i "s/ignoreip = 127.0.0.1\/8 ::1 10.0.0.0\/8 172.16.0.0\/12 192.168.0.0\/16/ignoreip = 127.0.0.1\/8 ::1 10.0.0.0\/8 172.16.0.0\/12 192.168.0.0\/16 $CURRENT_IP/g" /etc/fail2ban/jail.d/sshd.local
    
    # 重启服务
    systemctl restart fail2ban
    
    if systemctl is-active --quiet fail2ban; then
        show_green "✅ IP $CURRENT_IP 已成功添加到白名单"
    else
        show_red "❌ 添加白名单失败，服务重启失败"
        return 1
    fi
}

# 显示状态信息
show_status() {
    show_title
    echo "📊 === fail2ban状态 ==="
    fail2ban-client status | sed 's/Status for the jail:/监控状态:/; s/|- Filter/|- 过滤器/; s/|- Currently failed:/|- 当前失败次数:/; s/|- Total failed:/|- 总失败次数:/; s/`- Journal matches:/`- 日志匹配:/; s/`- Actions/`- 动作/; s/|- Currently banned:/|- 当前封禁:/; s/|- Total banned:/|- 总封禁:/; s/`- Banned IP list:/`- 封禁IP列表:/'
    
    echo ""
    echo "🛡️  === SSH防护状态 ==="
    fail2ban-client status sshd | sed 's/Status for the jail:/监控状态:/; s/|- Filter/|- 过滤器/; s/|- Currently failed:/|- 当前失败次数:/; s/|- Total failed:/|- 总失败次数:/; s/`- Journal matches:/`- 日志匹配:/; s/`- Actions/`- 动作/; s/|- Currently banned:/|- 当前封禁:/; s/|- Total banned:/|- 总封禁:/; s/`- Banned IP list:/`- 封禁IP列表:/'
    
    echo ""
    echo "🚫 === 当前封禁的IP及攻击次数 ==="
    BANNED_IPS=$(iptables -L f2b-sshd -n | grep REJECT | awk '{print $4}')
    if [ -z "$BANNED_IPS" ]; then
        echo "✅ 当前没有封禁的IP"
    else
        echo "$BANNED_IPS" | while read ip; do
            # 获取该IP的攻击次数
            ATTACK_COUNT=$(fail2ban-client get sshd banip $ip 2>/dev/null | grep -o "bantime" || echo "0")
            if [ "$ATTACK_COUNT" = "0" ]; then
                # 从日志中统计攻击次数
                ATTACK_COUNT=$(journalctl -u ssh --since "24 hours ago" | grep "Failed password" | grep "$ip" | wc -l)
            fi
            echo "🚫 $ip (攻击次数: $ATTACK_COUNT)"
        done
    fi
    
    echo ""
    echo "⚙️  === 配置信息 ==="
    BANTIME=$(fail2ban-client get sshd bantime)
    FINDTIME=$(fail2ban-client get sshd findtime)
    MAXRETRY=$(fail2ban-client get sshd maxretry)
    
    echo "⏰ 封禁时间: $BANTIME 秒 ($(($BANTIME/3600)) 小时)"
    echo "🔍 检测窗口: $FINDTIME 秒 ($(($FINDTIME/60)) 分钟) - 在此时间内监控登录失败次数"
    echo "🔢 最大重试: $MAXRETRY 次 - 超过此次数将被封禁"
    
    echo ""
    echo "📋 白名单IP:"
    fail2ban-client get sshd ignoreip | sed 's/These IP addresses\/networks are ignored:/这些IP地址\/网络被忽略:/'
}

# 查看日志
view_logs() {
    show_title
    show_blue "📋 === fail2ban日志 (最近20行) ==="
    echo ""
    tail -20 /var/log/fail2ban.log | sed 's/^/   /'
    
    echo ""
    show_blue "🔍 === SSH攻击日志 (最近10行) ==="
    echo ""
    journalctl -u ssh --since "1 hour ago" | grep -E "Failed password|Invalid user" | tail -10 | sed 's/^/   /'
}

# 等待用户输入
wait_for_user() {
    echo ""
    read -p "$(show_yellow "按回车键继续...")" 
}

# 主程序
main() {
    while true; do
        show_title
        
        printf "${GREEN}请选择操作 [0-5]: ${NC}"
        read choice
        
        case $choice in
            1)
                if check_fail2ban_installed; then
                    show_yellow "⚠️  fail2ban已安装"
                    if check_fail2ban_status; then
                        show_green "✅ fail2ban服务正在运行"
                    else
                        show_yellow "⚠️  fail2ban服务未运行，正在启动..."
                        systemctl start fail2ban
                        systemctl enable fail2ban
                    fi
                else
                    install_fail2ban
                fi
                wait_for_user
                ;;
            2)
                if check_fail2ban_installed; then
                    if check_fail2ban_status; then
                        add_current_ip_to_whitelist
                    else
                        show_red "❌ fail2ban服务未运行，请先启动服务"
                    fi
                else
                    show_red "❌ fail2ban未安装，请先安装fail2ban"
                fi
                wait_for_user
                ;;
            3)
                if check_fail2ban_installed; then
                    if check_fail2ban_status; then
                        show_status
                    else
                        show_red "❌ fail2ban服务未运行，请先启动服务"
                    fi
                else
                    show_red "❌ fail2ban未安装，请先安装fail2ban"
                fi
                wait_for_user
                ;;
            4)
                if check_fail2ban_installed; then
                    show_green "🔄 重启fail2ban服务..."
                    systemctl restart fail2ban
                    if systemctl is-active --quiet fail2ban; then
                        show_green "✅ 服务重启成功"
                    else
                        show_red "❌ 服务重启失败"
                    fi
                else
                    show_red "❌ fail2ban未安装"
                fi
                wait_for_user
                ;;
            5)
                if check_fail2ban_installed; then
                    view_logs
                else
                    show_red "❌ fail2ban未安装，请先安装fail2ban"
                fi
                wait_for_user
                ;;
            0)
                show_title
                show_green "👋 感谢使用fail2ban管理工具！"
                show_green "🕐 退出时间: $(get_datetime)"
                exit 0
                ;;
            *)
                show_red "❌ 无效选择，请重新输入"
                wait_for_user
                ;;
        esac
    done
}

# 运行主程序
main