# PVE一键安装脚本使用说明

## 📋 版本信息

- **当前版本**: v1.0.4
- **构建时间**: 2025-10-13 00:00:00
- **最后更新**: 重置为初始版本，删除多余脚本

## 📁 脚本文件说明

本项目提供PVE一键安装脚本：

### pve_install.sh - 主安装脚本 (v1.4.0)
- **功能全面**：包含完整的日志记录、错误处理、状态检测
- **适用场景**：生产环境、问题排查、开发调试
- **特点**：
  - 详细的调试日志
  - 自动备份功能
  - 执行流程跟踪
  - 错误分析
  - 安装结果验证

## 🔧 版本管理

### 自动版本管理
项目集成了自动版本管理系统：

- **Git Hook**: 每次 `git push` 时自动递增版本号
- **手动管理**: 使用 `auto_version.sh` 脚本手动更新版本号
- **版本格式**: 主版本.次版本.修订版本

### 版本管理工具

**智能提交**（推荐）：
```bash
# 使用智能提交脚本，自动添加版本号
./smart_commit.sh "feat: 添加新功能"
./smart_commit.sh "fix: 修复bug"
./smart_commit.sh "docs: 更新文档"
```

**自动版本管理**：
```bash
# 每次git push时自动更新版本号
git add .
git commit -m "feat: 添加新功能"
git push origin main  # 自动递增版本号
```

**手动版本管理**：
```bash
# 手动更新版本号
./auto_version.sh         # 递增修订版本 (1.0.0 -> 1.0.1)
./auto_version.sh minor   # 递增次版本 (1.0.0 -> 1.1.0)
./auto_version.sh major   # 递增主版本 (1.0.0 -> 2.0.0)
```

### 版本历史
- **v1.4.2** (2025-10-13): 添加智能提交脚本和备份检查功能
- **v1.4.1** (2025-01-15): 添加自动版本管理系统
- **v1.4.0** (2025-01-15): 简化项目结构，只保留调试版本
- **v1.3.0**: 修复状态检测函数返回值问题
- **v1.2.0**: 添加调试版本和详细日志
- **v1.1.0**: 修复脚本执行逻辑问题
- **v1.0.0**: 初始版本发布

## 使用方法

### 推荐使用方式

**推荐使用**：
```bash
# 下载并执行主安装脚本
curl -L https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh -o pve_install.sh && chmod +x pve_install.sh && bash pve_install.sh
```

**一键执行**：
```bash
# 直接执行（无需下载文件）
bash <(curl -L https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh)
```

## 系统要求

### 硬件要求
- **CPU**：x86_64 或 ARM64
- **内存**：至少2GB（推荐4GB+）
- **存储**：至少20GB可用空间
- **网络**：稳定的网络连接

### 软件要求
- **操作系统**：Debian 12+（推荐）
- **权限**：root权限
- **网络**：能够访问GitHub和镜像源

## 安装流程

### 完整安装流程
1. **环境检查**：检查系统、权限、网络
2. **第一次执行**：下载并执行PVE安装脚本
3. **模拟重启**：创建重启标记文件
4. **第二次执行**：继续执行PVE安装
5. **后端配置**：执行后端配置脚本
6. **验证安装**：检查安装结果
7. **清理文件**：清理临时文件

### 关键文件说明
- `/usr/local/bin/reboot_pve.txt`：重启标记文件
- `/usr/local/bin/build_backend_pve.txt`：后端配置标记文件
- `install.log`：安装日志文件（完整版本）

## 故障排除

### 常见问题

**1. 权限问题**
```bash
# 确保以root用户执行
sudo bash pve_install.sh
```

**2. 网络问题**
```bash
# 检查网络连接
ping 8.8.8.8
ping github.com
```

**3. 存储空间不足**
```bash
# 检查磁盘空间
df -h
# 清理不必要的文件
apt clean
```

**4. 内存不足**
```bash
# 检查内存使用
free -h
# 增加swap空间
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

### 手动恢复

**如果安装中断**：
```bash
# 检查当前状态
ls -la /usr/local/bin/reboot_pve.txt
ls -la /usr/local/bin/build_backend_pve.txt

# 手动清理标记文件
rm -f /usr/local/bin/reboot_pve.txt
rm -f /usr/local/bin/build_backend_pve.txt

# 重新执行安装
bash pve_install.sh
```

## 安装后配置

### 访问PVE
- **Web界面**：https://服务器IP:8006
- **用户名**：root
- **密码**：服务器root密码

### 基本配置
1. **更新系统**：在PVE Web界面中更新系统
2. **配置存储**：添加存储池
3. **网络配置**：检查网络设置
4. **创建虚拟机**：开始使用PVE

### 安全建议
1. **更改默认密码**：修改root密码
2. **配置防火墙**：限制访问端口
3. **定期备份**：备份重要配置
4. **监控系统**：监控系统状态

## 技术支持

### 日志文件
- **完整版本**：查看 `install.log` 文件
- **系统日志**：查看 `/var/log/syslog`
- **PVE日志**：查看 `/var/log/pve/`

### 常用命令
```bash
# 查看PVE版本
pveversion

# 查看PVE状态
systemctl status pveproxy

# 查看网络配置
ip addr show
ip route show

# 查看存储
pvesm status
```

### 联系支持
如果遇到问题，请提供：
1. 系统信息（`uname -a`）
2. 安装日志（`install.log`）
3. 错误信息截图
4. 执行的具体命令

## 更新日志

### v1.0 (2025-01-15)
- ✅ 初始版本发布
- ✅ 支持4种不同安装模式
- ✅ 完整的错误处理和日志记录
- ✅ 智能状态检测和断点续传
- ✅ 详细的安装验证和故障排除
