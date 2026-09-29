#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$PROJECT_ROOT/docker/docker_install.sh"

new_fixture() {
    FIXTURE_DIR=$(mktemp -d)
    FAKE_BIN="$FIXTURE_DIR/bin"
    COMMAND_LOG="$FIXTURE_DIR/commands.log"
    mkdir -p "$FAKE_BIN"
    : > "$COMMAND_LOG"

    for command in apt-get curl install chmod dpkg systemctl docker tee; do
        cat > "$FAKE_BIN/$command" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$COMMAND_LOG"
if [[ "$(basename "$0")" == "dpkg" && "${1:-}" == "--print-architecture" ]]; then
    printf 'amd64\n'
fi
exit 0
STUB
        chmod +x "$FAKE_BIN/$command"
    done

    cat > "$FAKE_BIN/id" <<'STUB'
#!/usr/bin/env bash
printf '0\n'
STUB
    chmod +x "$FAKE_BIN/id"

    cat > "$FAKE_BIN/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$COMMAND_LOG"
exit 0
STUB
    chmod +x "$FAKE_BIN/sudo"
}

cleanup_fixture() {
    rm -rf "$FIXTURE_DIR"
}

assert_log_contains() {
    local expected=$1
    if ! grep -Fq -- "$expected" "$COMMAND_LOG"; then
        printf 'Expected command log to contain: %s\n' "$expected" >&2
        cat "$COMMAND_LOG" >&2
        return 1
    fi
}

test_stops_when_apt_update_fails() {
    new_fixture
    trap cleanup_fixture RETURN

    cat > "$FAKE_BIN/apt-get" <<'STUB'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$COMMAND_LOG"
if [[ "${1:-}" == "update" ]]; then
    exit 42
fi
exit 0
STUB
    chmod +x "$FAKE_BIN/apt-get"

    set +e
    PATH="$FAKE_BIN:$PATH" COMMAND_LOG="$COMMAND_LOG" ID=ubuntu VERSION_CODENAME=noble bash "$SCRIPT" >/dev/null 2>&1
    local status=$?
    set -e

    if [[ $status -ne 42 ]]; then
        printf 'Expected apt update failure status 42, got %s\n' "$status" >&2
        return 1
    fi
    if grep -Fq 'systemctl' "$COMMAND_LOG"; then
        printf 'Docker service must not be started after apt update fails\n' >&2
        return 1
    fi
}

test_installs_from_official_repository_with_compose_plugin() {
    new_fixture
    trap cleanup_fixture RETURN

    PATH="$FAKE_BIN:$PATH" COMMAND_LOG="$COMMAND_LOG" ID=ubuntu VERSION_CODENAME=noble bash "$SCRIPT" >/dev/null 2>&1

    assert_log_contains 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg'
    assert_log_contains 'apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
    assert_log_contains 'systemctl enable --now docker'
    assert_log_contains 'docker compose version'
}

test_stops_when_apt_update_fails
test_installs_from_official_repository_with_compose_plugin
printf 'docker_install tests passed\n'
