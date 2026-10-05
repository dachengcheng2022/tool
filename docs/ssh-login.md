# SSH 公钥登录配置

## 适用范围和执行方式

适用于已安装 OpenSSH Server、使用 systemd 且服务名为 `ssh` 的 Linux 系统
（例如 Ubuntu）。使用 root 权限执行：

```bash
sudo bash docker/ssh_login.sh
```

也支持在交互终端中通过管道执行（远程分支须先更新为本次修复版本）：

```bash
wget -qO- https://raw.githubusercontent.com/dachengcheng2022/tool/refs/heads/test/docker/ssh_login.sh | sudo bash
```

公钥从 `/dev/tty` 读取，避免与管道传入的脚本共用标准输入。
没有控制终端时会明确报错退出；通过 SSH 远程执行请分配终端（`ssh -t`）。

提示出现后，粘贴客户端 `.pub` 文件中的完整单行公钥，然后按回车。
不要输入私钥。无论调用 sudo 的用户是谁，目标始终为
`/root/.ssh/authorized_keys`。

## 执行流程与设计

1. 检查 root 权限、所需命令和文件路径，用 `ssh-keygen` 校验公钥。
2. 保留已有公钥，按公钥类型和内容去重追加（忽略注释差异）。
   将 `.ssh` 和 `authorized_keys` 的所有者设为 root，权限分别设为 700 和 600。
3. 在 `/etc/ssh/sshd_config.bak.XXXXXXXX` 留存原配置备份。
4. 在配置文件最前面设置以下全局选项，优先于 Include；删除主文件中
   原有的同名全局配置，保留其他设置及 Match 块，重复执行不会累积这些选项：

   ```text
   PasswordAuthentication no
   PubkeyAuthentication yes
   KbdInteractiveAuthentication no
   ```

   关闭键盘交互认证是为了避免 PAM 等通过该认证方式继续接受密码。
5. 用 `sshd -t` 检查语法，再用 `sshd -T -C` 检查 root/localhost/127.0.0.1
   上下文的有效认证配置。检查通过后执行 `systemctl reload ssh`，这是配置重载。
6. 校验或重载失败时恢复原 SSH 配置并非零退出；已添加的公钥会保留。
   重载失败时需检查服务状态，必要时恢复配置后手动重载。

## root 登录和验证

脚本保留 `PermitRootLogin` 现有策略；如果有效值为 `no`，会提示。
写入 root 公钥不意味着服务器已经允许 root 登录，其他权限策略、
`AuthorizedKeysFile` 自定义路径和 PAM 策略也可能影响认证。
`Match` 配置可能按来源地址或主机名改变行为，上述本地上下文检查不能覆盖所有来源。

执行时应保留当前 SSH 连接，并从实际客户端新开终端验证：

```bash
ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no -i ~/.ssh/id_ed25519 root@服务器地址
```

确认登录成功后再关闭原连接。如需恢复配置，使用脚本输出的备份路径覆盖
`/etc/ssh/sshd_config`，执行 `sshd -t`，成功后执行 `systemctl reload ssh`。

## 本地验证

```bash
bash -n docker/ssh_login.sh
python3 tests/ssh_login_test.py
```

行为测试在临时目录中使用真实公钥校验，替代 root 身份、文件所有权设置、
sshd 和 systemd 边界；覆盖重复执行、无效公钥、配置校验失败、重载失败和
已有文件缺少末尾换行、管道执行交互、空公钥和无控制终端。当前沙箱禁止打开 `/dev/tty`，终端测试用继承的真实伪终端文件描述符替代该打开操作。
实际 `/dev/tty` 交互、sshd 解析与远程登录仍须在目标服务器验证。
