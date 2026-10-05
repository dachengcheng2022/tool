#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

fail() {
    printf '错误：%s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "请使用 root 执行：sudo bash $0"
for command_name in ssh-keygen sshd systemctl; do
    command -v "$command_name" >/dev/null 2>&1 || fail "缺少命令：$command_name"
done

ssh_dir=/root/.ssh
authorized_keys="$ssh_dir/authorized_keys"
config=/etc/ssh/sshd_config
[[ -f "$config" && ! -L "$config" ]] || fail "SSH 配置不存在或为符号链接：$config"
[[ ! -L "$ssh_dir" && ! -L "$authorized_keys" ]] || fail '公钥目录或文件不能为符号链接。'

work_dir=$(mktemp -d)
backup=''
config_changed=false
cleanup() {
    local status=$?
    trap - EXIT
    if [[ "$status" -ne 0 && "$config_changed" == true ]]; then
        if cp -p "$backup" "$config"; then
            printf '执行失败，已恢复 SSH 配置：%s\n' "$backup" >&2
        else
            printf '恢复失败，请手动恢复备份：%s\n' "$backup" >&2
        fi
    fi
    rm -rf "$work_dir"
    exit "$status"
}
trap cleanup EXIT

printf '请输入 root 登录使用的完整 SSH 公钥（单行）：\n'
IFS= read -r public_key || fail '未读取到公钥。'
read -r key_type key_data _ <<< "$public_key"
[[ "$key_type" =~ ^(ssh-|ecdsa-|sk-) && -n "$key_data" ]] || fail '请输入完整的 OpenSSH 公钥，不能输入私钥。'
printf '%s\n' "$public_key" > "$work_dir/public_key"
ssh-keygen -l -f "$work_dir/public_key" >/dev/null 2>&1 || fail '公钥格式无效。'

mkdir -p "$ssh_dir"
touch "$authorized_keys"
chown root:root "$ssh_dir" "$authorized_keys"
chmod 700 "$ssh_dir"
chmod 600 "$authorized_keys"
if awk -v type="$key_type" -v data="$key_data" \
    '$1 == type && $2 == data { found=1 } END { exit !found }' "$authorized_keys"; then
    printf '公钥已存在，跳过追加。\n'
else
    # 兼容已有文件最后一行没有换行符的情况。
    if [[ -s "$authorized_keys" && -n "$(tail -c 1 "$authorized_keys")" ]]; then
        printf '\n' >> "$authorized_keys"
    fi
    printf '%s\n' "$public_key" >> "$authorized_keys"
fi

backup=$(mktemp "${config}.bak.XXXXXXXX")
cp -p "$config" "$backup"
# OpenSSH 使用首次出现的值；放在 Include 和 Match 之前，确保全局配置生效。
{
    printf 'PasswordAuthentication no\nPubkeyAuthentication yes\nKbdInteractiveAuthentication no\n'
    awk '
        tolower($1) == "match" { in_match=1 }
        !in_match && tolower($1) ~ /^(passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication)$/ { next }
        { print }
    ' "$backup"
} > "$work_dir/sshd_config"
config_changed=true
cat "$work_dir/sshd_config" > "$config"
sshd -t -f "$config" || fail 'SSH 配置校验失败，不执行重载。'
sshd -T -f "$config" -C user=root,host=localhost,addr=127.0.0.1 > "$work_dir/effective"
for setting in 'passwordauthentication no' 'pubkeyauthentication yes' 'kbdinteractiveauthentication no'; do
    grep -Fxq "$setting" "$work_dir/effective" || fail "有效配置不符合预期：$setting，请检查 Include/Match 配置。"
done
if grep -Fxq 'permitrootlogin no' "$work_dir/effective"; then
    printf '提示：当前 PermitRootLogin 禁止 root 登录，需单独调整此策略后才能使用 root 公钥登录。\n' >&2
fi

systemctl reload ssh
config_changed=false
printf '完成：公钥已写入 %s，SSH 配置已重载。备份：%s\n' "$authorized_keys" "$backup"
printf '请保留当前连接，并新开终端验证 root 公钥登录。\n'
