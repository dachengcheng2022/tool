# 运维工具脚本

## Docker 安装

Ubuntu 系统使用：

```bash
sudo bash docker/docker_install.sh
```

脚本使用 Docker 官方 HTTPS APT 仓库，安装 Docker Engine、Buildx 和
Compose Plugin。安装后请使用 `docker compose`，不要再使用旧版
`docker-compose` 命令。

支持范围、执行行为和故障排查参见 [Docker 安装说明](docs/docker-install.md)。
