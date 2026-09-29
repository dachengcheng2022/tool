# Docker 安装说明

## 适用范围

- Ubuntu 系统，包括 Ubuntu 24.04（Noble）
- `amd64`、`arm64` 等由 Ubuntu APT 和 Docker 官方仓库共同支持的架构
- 使用 root 权限执行

## 安装方式

```bash
sudo bash docker/docker_install.sh
```

脚本会：

1. 清理旧脚本遗留的阿里云 Docker CE APT 源，不影响其他 Ubuntu 软件源。
2. 在任何关键命令失败时立即退出，避免继续执行产生误导性错误。
3. 移除 Docker 官方列出的冲突软件包。
4. 通过 `/etc/apt/keyrings/docker.asc` 配置 Docker 官方签名密钥。
5. 使用 `https://download.docker.com/linux/ubuntu` 官方 APT 仓库。
6. 根据当前系统自动识别 Ubuntu 代号和 CPU 架构。
7. 安装 Docker Engine、CLI、containerd、Buildx 和 Compose Plugin。
8. 启用并启动 Docker 服务，随后验证 Engine 和 Compose。

## Compose 命令

Compose V2 以 Docker CLI 插件形式安装：

```bash
docker compose version
docker compose up -d
```

旧版 `docker-compose` 独立二进制不会被安装。

## 常见故障

### APT 索引大小或哈希不一致

`File has unexpected size` 通常表示镜像站正在同步，仓库元数据与软件包索引暂时不一致。当前脚本使用 Docker 官方 HTTPS 仓库，不再依赖阿里云 Docker CE 镜像。

如果官方仓库索引下载仍失败，可清理本地索引后重试：

```bash
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo bash docker/docker_install.sh
```

执行清理前请确认系统没有其他正在运行的 APT 或 dpkg 任务。

### 网络不可达

确认服务器能访问以下地址：

- `https://download.docker.com`
- Ubuntu 系统自身配置的软件源

脚本不会在仓库更新失败后继续安装或启动 Docker。
