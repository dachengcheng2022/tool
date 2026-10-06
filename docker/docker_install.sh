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
APT_SOURCES_LIST=${APT_SOURCES_LIST:-/etc/apt/sources.list}
APT_SOURCES_DIR=${APT_SOURCES_DIR:-/etc/apt/sources.list.d}
APT_GET=(apt-get -o DPkg::Lock::Timeout=300)

remove_legacy_aliyun_docker_sources() {
    local source_file
    local backup_file
    local aliyun_docker_source='mirrors.aliyun.com/docker-ce/linux/ubuntu'

    if [[ -f "$APT_SOURCES_LIST" ]] && grep -Fq "$aliyun_docker_source" "$APT_SOURCES_LIST"; then
        backup_file="${APT_SOURCES_LIST}.bak"
        sed -i.bak "\|${aliyun_docker_source}|d" "$APT_SOURCES_LIST"
        rm -f "$backup_file"
    fi

    if [[ ! -d "$APT_SOURCES_DIR" ]]; then
        return
    fi

    while IFS= read -r -d '' source_file; do
        if ! grep -Fq "$aliyun_docker_source" "$source_file"; then
            continue
        fi

        case "$source_file" in
            *.list)
                backup_file="${source_file}.bak"
                sed -i.bak "\|${aliyun_docker_source}|d" "$source_file"
                rm -f "$backup_file"
                ;;
            *.sources)
                rm -f "$source_file"
                ;;
        esac
    done < <(find "$APT_SOURCES_DIR" -maxdepth 1 -type f \
        \( -name '*.list' -o -name '*.sources' \) -print0)
}

printf '清理旧的阿里云 Docker APT 源...\n'
remove_legacy_aliyun_docker_sources

printf '更新系统软件索引...\n'
"${APT_GET[@]}" update

printf '移除可能冲突的软件包...\n'
"${APT_GET[@]}" remove -y docker.io docker-compose docker-compose-v2 podman-docker containerd runc

printf '安装仓库依赖...\n'
"${APT_GET[@]}" install -y ca-certificates curl tzdata

printf '设置系统时区为北京时间（Asia/Shanghai）...\n'
timedatectl set-timezone Asia/Shanghai

printf '配置 Docker 官方 APT 仓库...\n'
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

architecture=$(dpkg --print-architecture)
printf '%s\n' \
    "deb [arch=${architecture} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | tee "$APT_SOURCES_DIR/docker.list" >/dev/null

"${APT_GET[@]}" update

printf '安装 Docker Engine、Buildx 和 Compose Plugin...\n'
"${APT_GET[@]}" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

printf '启用并启动 Docker 服务...\n'
systemctl enable --now docker

printf '验证安装结果...\n'
docker version
docker compose version

printf 'Docker 安装完成。\n'
