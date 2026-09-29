#!/usr/bin/env bash
set -Eeuo pipefail

trap 'printf "安装失败：第 %s 行命令执行异常。\n" "$LINENO" >&2' ERR

if [[ "$(id -u)" -ne 0 ]]; then
    printf '请使用 root 用户运行，或执行：sudo bash %s\n' "$0" >&2
    exit 1
fi

if [[ -z "${ID:-}" || -z "${VERSION_CODENAME:-}" ]]; then
    if [[ ! -r /etc/os-release ]]; then
        printf '无法识别操作系统：/etc/os-release 不存在。\n' >&2
        exit 1
    fi
    # shellcheck source=/etc/os-release
    . /etc/os-release
fi

if [[ "${ID:-}" != "ubuntu" || -z "${VERSION_CODENAME:-}" ]]; then
    printf '当前脚本仅支持 Ubuntu，检测到 ID=%s VERSION_CODENAME=%s。\n' \
        "${ID:-unknown}" "${VERSION_CODENAME:-unknown}" >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

printf '更新系统软件索引...\n'
apt-get update

printf '移除可能冲突的软件包...\n'
apt-get remove -y docker.io docker-compose docker-compose-v2 podman-docker containerd runc

printf '安装仓库依赖...\n'
apt-get install -y ca-certificates curl

printf '配置 Docker 官方 APT 仓库...\n'
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

architecture=$(dpkg --print-architecture)
printf '%s\n' \
    "deb [arch=${architecture} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | tee /etc/apt/sources.list.d/docker.list >/dev/null

apt-get update

printf '安装 Docker Engine、Buildx 和 Compose Plugin...\n'
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

printf '启用并启动 Docker 服务...\n'
systemctl enable --now docker

printf '验证安装结果...\n'
docker version
docker compose version

printf 'Docker 安装完成。\n'
