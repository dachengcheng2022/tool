"""隔离文件系统；仅替换需要 root/systemd 的系统边界。"""
import os
import errno
import pty
import select
import time
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'docker/ssh_login.sh'


class SSHLoginTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ssh = self.root / 'root/.ssh'
        self.config = self.root / 'sshd_config'
        self.original = '# existing settings\nPasswordAuthentication yes\nPubkeyAuthentication no\n'
        self.config.write_text(self.original)
        binary = self.root / 'bin'
        binary.mkdir()
        commands = {
            'id': 'echo 0',
            'chown': 'exit 0',
            'systemctl': 'printf "%s\\n" "$*" >> "$TEST_ROOT/reload"; exit "${FAIL_RELOAD:-0}"',
            'sshd': '''if [ "$1" = -t ]; then exit "${FAIL_VALIDATE:-0}"; fi
printf 'passwordauthentication no\npubkeyauthentication yes\nkbdinteractiveauthentication no\npermitrootlogin prohibit-password\n'
''',
        }
        for name, body in commands.items():
            path = binary / name
            path.write_text('#!/bin/sh\n' + body + '\n')
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{binary}:' + os.environ['PATH'], TEST_ROOT=str(self.root))
        subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(self.root / 'key')], check=True)
        self.key = (self.root / 'key.pub').read_text().strip()
        source = SOURCE.read_text().replace('/root/.ssh', str(self.ssh)).replace('/etc/ssh/sshd_config', str(self.config))
        self.script = self.root / 'script.sh'
        self.script.write_text(source)

    def run_script(self, key=None, **env):
        return self.run_terminal(key=key, **env)

    def run_terminal(self, key=None, piped=False, **env):
        # 子进程拥有独立控制终端；管道中的 stdin 仅用于传输脚本。
        pid, terminal = pty.fork()
        if pid == 0:
            # 当前沙箱禁止打开 /dev/tty，继承同一个真实终端作为 fd 4。
            os.dup2(0, 4)
            os.set_inheritable(4, True)
            terminal_script = self.root / 'terminal_script.sh'
            terminal_script.write_text(self.script.read_text().replace('exec 3<> /dev/tty', 'exec 3<&4'))
            command = 'cat "$TEST_SCRIPT" | bash' if piped else 'bash "$TEST_SCRIPT" < /dev/null'
            os.execvpe('bash', ['bash', '-c', command],
                       dict(self.env, TEST_SCRIPT=str(terminal_script), **env))
        output = b''
        sent = False
        deadline = time.monotonic() + 15
        try:
            while time.monotonic() < deadline:
                readable, _, _ = select.select([terminal], [], [], 0.1)
                if readable:
                    try:
                        chunk = os.read(terminal, 65536)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        break
                    if not chunk:
                        break
                    output += chunk
                    if not sent and '完整 SSH 公钥'.encode() in output:
                        os.write(terminal, ((self.key if key is None else key) + '\n').encode())
                        sent = True
            else:
                os.kill(pid, 9)
                self.fail('交互读取超时')
        finally:
            os.close(terminal)
            _, status = os.waitpid(pid, 0)
        return subprocess.CompletedProcess([], os.waitstatus_to_exitcode(status),
                                           output.decode(errors='replace'), '')

    def test_pipeline_reads_key_from_terminal(self):
        result = self.run_terminal(piped=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((self.ssh / 'authorized_keys').exists(), result.stdout)
        self.assertEqual((self.ssh / 'authorized_keys').read_text().splitlines(), [self.key])

    def test_add_key_and_repeat_without_duplicates(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout)
        authorized = self.ssh / 'authorized_keys'
        self.assertEqual(authorized.read_text().splitlines(), [self.key])
        self.assertEqual(authorized.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.ssh.stat().st_mode & 0o777, 0o700)
        first_config = self.config.read_text()
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.config.read_text(), first_config)
        self.assertEqual(authorized.read_text().splitlines(), [self.key])
        self.assertEqual((self.root / 'reload').read_text().splitlines(), ['reload ssh', 'reload ssh'])

    def test_empty_key_has_clear_error(self):
        result = self.run_script('')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn('unbound variable', result.stdout)
        self.assertEqual(self.config.read_text(), self.original)

    def test_without_terminal_fails_without_changes(self):
        result = subprocess.run(['bash', str(self.script)], stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, env=self.env,
                                start_new_session=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('无法打开交互终端', result.stderr)
        self.assertEqual(self.config.read_text(), self.original)
        self.assertFalse(self.ssh.exists())

    def test_invalid_key_leaves_config_unchanged(self):
        self.assertNotEqual(self.run_script('not a public key').returncode, 0)
        self.assertEqual(self.config.read_text(), self.original)
        self.assertFalse((self.root / 'reload').exists())

    def test_validation_failure_restores_config_without_reload(self):
        self.assertNotEqual(self.run_script(FAIL_VALIDATE='1').returncode, 0)
        self.assertEqual(self.config.read_text(), self.original)
        self.assertFalse((self.root / 'reload').exists())

    def test_reload_failure_restores_config(self):
        self.assertNotEqual(self.run_script(FAIL_RELOAD='1').returncode, 0)
        self.assertEqual(self.config.read_text(), self.original)

    def test_existing_key_without_newline_is_preserved(self):
        self.ssh.mkdir(parents=True)
        authorized = self.ssh / 'authorized_keys'
        authorized.write_text('# existing entry')
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(authorized.read_text().splitlines(), ['# existing entry', self.key])


if __name__ == '__main__':
    unittest.main()
