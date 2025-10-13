# PVE一键安装脚本 - 直接下载执行命令

## 主安装脚本

```bash
# 下载并执行主安装脚本（无缓存版本）
curl -L "https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh?t=$(date +%s)" -o pve_install.sh && chmod +x pve_install.sh && bash pve_install.sh
```

```bash
# 一键执行（无需下载文件）
bash <(curl -L "https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh?t=$(date +%s)")
```

## 📋 版本信息
- **当前版本**: v1.0.0
- **构建时间**: 2025-01-13 00:00:00

## 使用说明

### 推荐使用方式

**生产环境**：
```bash
curl -L https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh -o pve_install.sh && chmod +x pve_install.sh && bash pve_install.sh
```

**快速安装**：
```bash
bash <(curl -L https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh)
```

### 注意事项

1. **需要root权限**：确保以root用户执行
2. **网络要求**：需要能够访问GitHub
3. **系统要求**：Debian 12+，至少2GB内存，20GB存储
4. **执行环境**：必须在Linux服务器上执行

### 故障排除

如果curl下载失败，可以尝试：

```bash
# 使用wget下载
wget https://raw.githubusercontent.com/wevebeen/onestep/main/pve_install.sh -O pve_install.sh && chmod +x pve_install.sh && bash pve_install.sh
```

```bash
# 使用国内镜像（如果有）
curl -L https://cdn.jsdelivr.net/gh/wevebeen/onestep@main/pve_install.sh -o pve_install.sh && chmod +x pve_install.sh && bash pve_install.sh
```