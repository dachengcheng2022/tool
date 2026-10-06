#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$PROJECT_ROOT/docker/docker_install.sh"

new_fixture() {
    FIXTURE_DIR=$(mktemp -d)
    FAKE_BIN="$FIXTURE_DIR/bin"
    COMMAND_LOG="$FIXTURE_DIR/commands.log"
    APT_SOURCES_LIST="$FIXTURE_DIR/sources.list"
    APT_SOURCES_DIR="$FIXTURE_DIR/sources.list.d"
    mkdir -p "$FAKE_BIN"
    mkdir -p "$APT_SOURCES_DIR"
    : > "$COMMAND_LOG"
    : > "$APT_SOURCES_LIST"

    for command in apt-get curl install chmod dpkg systemctl timedatectl docker tee; do
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
if [[ " $* " == *" update "* ]]; then
    exit 42
fi
exit 0
STUB
    chmod +x "$FAKE_BIN/apt-get"

    set +e
    PATH="$FAKE_BIN:$PATH" COMMAND_LOG="$COMMAND_LOG" \
        APT_SOURCES_LIST="$APT_SOURCES_LIST" APT_SOURCES_DIR="$APT_SOURCES_DIR" \
        ID=ubuntu VERSION_CODENAME=noble bash "$SCRIPT" >/dev/null 2>&1
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

    PATH="$FAKE_BIN:$PATH" COMMAND_LOG="$COMMAND_LOG" \
        APT_SOURCES_LIST="$APT_SOURCES_LIST" APT_SOURCES_DIR="$APT_SOURCES_DIR" \
        ID=ubuntu VERSION_CODENAME=noble bash "$SCRIPT" >/dev/null 2>&1

    assert_log_contains 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg'
    assert_log_contains 'apt-get -o DPkg::Lock::Timeout=300 install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin'
    assert_log_contains 'systemctl enable --now docker'
    assert_log_contains 'apt-get -o DPkg::Lock::Timeout=300 install -y ca-certificates curl tzdata'
    assert_log_contains 'timedatectl set-timezone Asia/Shanghai'
    assert_log_contains 'docker compose version'
}

test_removes_legacy_aliyun_source_before_first_update() {
    new_fixture
    trap cleanup_fixture RETURN

    printf '%s\n' \
        'deb http://archive.ubuntu.com/ubuntu noble main' \
        'deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu noble stable' \
        > "$APT_SOURCES_LIST"
    printf '%s\n' \
        'deb [arch=amd64] http://mirrors.aliyun.com/docker-ce/linux/ubuntu noble stable' \
        > "$APT_SOURCES_DIR/docker-ce.list"

    cat > "$FAKE_BIN/apt-get" <<'STUB'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$COMMAND_LOG"
if [[ " $* " == *" update "* ]] && grep -RqsF 'mirrors.aliyun.com/docker-ce/linux/ubuntu' \
    "$APT_SOURCES_LIST" "$APT_SOURCES_DIR"; then
    exit 73
fi
exit 0
STUB
    chmod +x "$FAKE_BIN/apt-get"

    PATH="$FAKE_BIN:$PATH" COMMAND_LOG="$COMMAND_LOG" \
        APT_SOURCES_LIST="$APT_SOURCES_LIST" APT_SOURCES_DIR="$APT_SOURCES_DIR" \
        ID=ubuntu VERSION_CODENAME=noble bash "$SCRIPT" >/dev/null 2>&1

    if grep -RqsF 'mirrors.aliyun.com/docker-ce/linux/ubuntu' \
        "$APT_SOURCES_LIST" "$APT_SOURCES_DIR"; then
        printf 'Legacy Aliyun Docker source was not removed\n' >&2
        return 1
    fi
    assert_log_contains 'apt-get -o DPkg::Lock::Timeout=300 update'
}

test_all_apt_operations_wait_for_dpkg_lock() {
    new_fixture
    trap cleanup_fixture RETURN

    PATH="$FAKE_BIN:$PATH" COMMAND_LOG="$COMMAND_LOG" \
        APT_SOURCES_LIST="$APT_SOURCES_LIST" APT_SOURCES_DIR="$APT_SOURCES_DIR" \
        ID=ubuntu VERSION_CODENAME=noble bash "$SCRIPT" >/dev/null 2>&1

    if grep '^apt-get ' "$COMMAND_LOG" | grep -Fqv 'apt-get -o DPkg::Lock::Timeout=300 '; then
        printf 'Every apt-get operation must wait for the dpkg lock\n' >&2
        cat "$COMMAND_LOG" >&2
        return 1
    fi
}

test_stops_when_apt_update_fails
test_installs_from_official_repository_with_compose_plugin
test_removes_legacy_aliyun_source_before_first_update
test_all_apt_operations_wait_for_dpkg_lock
printf 'docker_install tests passed\n'
