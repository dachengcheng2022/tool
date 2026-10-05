"""隔离文件系统；仅替换需要 root/systemd 的系统边界。"""
import os
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
        return subprocess.run(['bash', str(self.script)], input=(self.key if key is None else key) + '\n',
                              text=True, capture_output=True, env=dict(self.env, **env))

    def test_add_key_and_repeat_without_duplicates(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        authorized = self.ssh / 'authorized_keys'
        self.assertEqual(authorized.read_text().splitlines(), [self.key])
        self.assertEqual(authorized.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.ssh.stat().st_mode & 0o777, 0o700)
        first_config = self.config.read_text()
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.config.read_text(), first_config)
        self.assertEqual(authorized.read_text().splitlines(), [self.key])
        self.assertEqual((self.root / 'reload').read_text().splitlines(), ['reload ssh', 'reload ssh'])

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
