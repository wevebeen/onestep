# PVE一键安装脚本 - curl命令集合

## 📋 项目信息
- **项目名称**: onestep
- **GitHub仓库**: https://github.com/wevebeen/onestep
- **当前版本**: v1.0.5
- **最后更新**: 2025-01-15

## 🚀 脚本curl命令

### 1. PVE主安装脚本 (pve_install.sh)

#### 标准版
```bash
curl -fsSL https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh | sudo bash
```

#### 无缓存版
```bash
curl -fsSL \
  -H "Cache-Control: no-cache, no-store, must-revalidate" \
  -H "Pragma: no-cache" \
  -H "Expires: 0" \
  "https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh?t=$(date +%s)" | sudo bash
```

### 2. Fail2ban安全脚本 (fail2ban.sh)

#### 标准版
```bash
curl -fsSL https://raw.githubusercontent.com/wevebeen/onestep/main/fail2ban.sh | sudo bash
```

#### 无缓存版
```bash
curl -fsSL \
  -H "Cache-Control: no-cache, no-store, must-revalidate" \
  -H "Pragma: no-cache" \
  -H "Expires: 0" \
  "https://raw.githubusercontent.com/wevebeen/onestep/main/fail2ban.sh?t=$(date +%s)" | sudo bash
```

### 3. 网络修复脚本 (network_fix.sh)

#### 标准版
```bash
curl -fsSL https://raw.githubusercontent.com/wevebeen/onestep/main/network_fix.sh | sudo bash
```

#### 无缓存版
```bash
curl -fsSL \
  -H "Cache-Control: no-cache, no-store, must-revalidate" \
  -H "Pragma: no-cache" \
  -H "Expires: 0" \
  "https://raw.githubusercontent.com/wevebeen/onestep/main/network_fix.sh?t=$(date +%s)" | sudo bash
```

### 4. LXC容器管理脚本 (lxc.sh)

#### 标准版
```bash
curl -fsSL https://raw.githubusercontent.com/wevebeen/onestep/main/lxc.sh | sudo bash
```

#### 无缓存版
```bash
curl -fsSL \
  -H "Cache-Control: no-cache, no-store, must-revalidate" \
  -H "Pragma: no-cache" \
  -H "Expires: 0" \
  "https://raw.githubusercontent.com/wevebeen/onestep/main/lxc.sh?t=$(date +%s)" | sudo bash
```

### 5. 默认容器安装脚本 (install_default_containers.sh)

#### 标准版
```bash
curl -fsSL https://raw.githubusercontent.com/wevebeen/onestep/main/install_default_containers.sh | sudo bash
```

#### 无缓存版
```bash
curl -fsSL \
  -H "Cache-Control: no-cache, no-store, must-revalidate" \
  -H "Pragma: no-cache" \
  -H "Expires: 0" \
  "https://raw.githubusercontent.com/wevebeen/onestep/main/install_default_containers.sh?t=$(date +%s)" | sudo bash
```

### 6. PVE版本管理脚本 (pve_version_manager.sh)

#### 标准版
```bash
curl -fsSL https://raw.githubusercontent.com/wevebeen/onestep/main/pve_version_manager.sh | sudo bash
```

#### 无缓存版
```bash
curl -fsSL \
  -H "Cache-Control: no-cache, no-store, must-revalidate" \
  -H "Pragma: no-cache" \
  -H "Expires: 0" \
  "https://raw.githubusercontent.com/wevebeen/onestep/main/pve_version_manager.sh?t=$(date +%s)" | sudo bash
```

## 📝 使用说明

### 推荐使用方式
1. **PVE完整安装**: 使用 `pve_install.sh`
2. **安全加固**: 使用 `fail2ban.sh`
3. **网络诊断**: 使用 `network_fix.sh`
4. **容器管理**: 使用 `lxc.sh`
5. **默认容器**: 使用 `install_default_containers.sh`
6. **版本管理**: 使用 `pve_version_manager.sh`

### 系统要求
- **操作系统**: Debian 12+ (推荐)
- **权限**: root权限
- **网络**: 稳定的网络连接
- **存储**: 至少20GB可用空间

### 注意事项
- 建议在测试环境中先验证脚本功能
- 执行前请确保系统已备份重要数据
- 网络问题可能导致脚本下载失败
- 某些脚本需要重启系统才能完全生效

## 🔄 版本历史

### v1.0.5 (2025-01-15)
- ✅ 添加规则文档和curl命令集合
- ✅ 完善项目结构和文档
- ✅ 统一脚本格式和命名规范

### v1.0.0 (2025-01-15)
- ✅ 初始版本发布
- ✅ 包含6个核心脚本文件
- ✅ 支持PVE一键安装和管理
