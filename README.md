# 运维工具脚本

## Docker 安装

Ubuntu 系统使用：

```bash
sudo bash docker/docker_install.sh
```

脚本使用 Docker 官方 HTTPS APT 仓库，安装 Docker Engine、Buildx 和
Compose Plugin。执行时会先清理旧脚本遗留的阿里云 Docker CE 仓库配置，
避免镜像同步错误阻断首次 `apt-get update`。APT 被系统后台升级占用时，
脚本会等待最多 5 分钟。安装后请使用 `docker compose`，不要再使用旧版
`docker-compose` 命令。

支持范围、执行行为和故障排查参见 [Docker 安装说明](docs/docker-install.md)。

## SSH 公钥登录

```bash
sudo bash docker/ssh_login.sh
```

也支持在交互终端中通过管道执行（远程分支须先更新为本次修复版本）：

```bash
wget -qO- https://raw.githubusercontent.com/dachengcheng2022/tool/refs/heads/test/docker/ssh_login.sh | sudo bash
```

公钥从 `/dev/tty` 读取，避免与管道传入的脚本共用标准输入。
没有控制终端时会明确报错退出；通过 SSH 远程执行请分配终端（`ssh -t`）。

交互输入完整的单行 SSH 公钥，始终写入 `/root/.ssh/authorized_keys`。
脚本关闭密码和键盘交互认证，开启公钥认证，校验配置后执行
`systemctl reload ssh`。使用前确保持有对应私钥；执行后保留当前连接，
新开终端验证 root 公钥登录。详见 [SSH 公钥登录说明](docs/ssh-login.md)。
