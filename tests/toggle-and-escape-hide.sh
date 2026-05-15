#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
PYTHON_BIN="$(command -v python3 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
[ -n "$PYTHON_BIN" ] || { echo 'python3 not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_toggle_escape_hide.$$.$RANDOM"
fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"

cleanup() {
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true

cat >"$fake_bin/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX_BIN" -L "$sock" "\$@"
EOF
chmod +x "$fake_bin/tmux"

export TFP_REPO_DIR="$REPO_DIR"
export TFP_FAKE_PATH="$fake_bin:$PATH"

"$PYTHON_BIN" <<'PY'
import os
import pty
import subprocess
import time

repo_dir = os.environ['TFP_REPO_DIR']
env = os.environ.copy()
env.pop('TMUX', None)
env['PATH'] = os.environ['TFP_FAKE_PATH']
env['TERM'] = 'xterm-256color'


def run(*args, check=True):
    return subprocess.run(args, env=env, text=True, capture_output=True, check=check)


def stdout(*args):
    return run(*args).stdout.strip()


def popup_rows():
    rows = []
    for line in stdout('tmux', 'list-clients', '-F', '#{client_name}|#{session_name}').splitlines():
        if not line:
            continue
        client_name, session_name = line.split('|', 1)
        if session_name.isdigit():
            rows.append((client_name, session_name))
    return rows


def popup_session_name():
    rows = popup_rows()
    return rows[0][1] if rows else ''


def popup_client_name():
    rows = popup_rows()
    return rows[0][0] if rows else ''


def attached_client_name():
    for line in stdout('tmux', 'list-clients', '-F', '#{client_name}|#{session_name}').splitlines():
        if not line:
            continue
        client_name, session_name = line.split('|', 1)
        if session_name == 'base':
            return client_name
    return ''


def popup_session_exists(name):
    if not name:
        return False
    return run('tmux', 'has-session', '-t', f'={name}', check=False).returncode == 0


def popup_pane_id(name):
    for line in stdout('tmux', 'list-panes', '-a', '-F', '#{session_name}|#{pane_id}').splitlines():
        if not line:
            continue
        session_name, pane_id = line.split('|', 1)
        if session_name == name:
            return pane_id
    return ''


def popup_capture(name):
    pane_id = popup_pane_id(name)
    if not pane_id:
        return ''
    return stdout('tmux', 'capture-pane', '-p', '-t', pane_id)


def wait_for(predicate, timeout_seconds, message):
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.2)
    raise SystemExit(message)

run('tmux', '-f', '/dev/null', 'new-session', '-d', '-s', 'base', 'sleep 9999')
run('tmux', 'run-shell', os.path.join(repo_dir, 'tmux-floating-popup.tmux'))

master_fd, slave_fd = pty.openpty()
client = subprocess.Popen(
    ['tmux', 'attach-session', '-t', 'base'],
    env=env,
    stdin=slave_fd,
    stdout=slave_fd,
    stderr=slave_fd,
    start_new_session=True,
)
os.close(slave_fd)

try:
    wait_for(attached_client_name, 5, 'attached client ready')

    os.write(master_fd, b'\x1bf')
    first_session = wait_for(popup_session_name, 5, 'expected popup session after first Alt-f')
    wait_for(popup_client_name, 5, 'expected popup client after first Alt-f')

    os.write(master_fd, b'echo __popup_ok__\r')
    wait_for(lambda: '__popup_ok__' in popup_capture(first_session), 5, 'expected typed command to reach the popup shell')

    os.write(master_fd, b'\x1bf')
    wait_for(lambda: popup_client_name() == '', 5, 'expected popup to hide after second Alt-f')
    if not popup_session_exists(first_session):
        raise SystemExit('expected Alt-f hide to preserve the popup session')

    os.write(master_fd, b'\x1bf')
    reopened_session = wait_for(popup_session_name, 5, 'expected popup session after Alt-f reopen')
    if reopened_session != first_session:
        raise SystemExit(f'expected Alt-f reopen to reuse {first_session}, got {reopened_session}')

    os.write(master_fd, b'\x1b')
    wait_for(lambda: popup_client_name() == '', 5, 'expected popup to close after Esc')
    wait_for(lambda: not popup_session_exists(first_session), 5, 'expected Esc to destroy the popup session')

    os.write(master_fd, b'\x1bf')
    second_session = wait_for(popup_session_name, 5, 'expected popup session after reopening from Esc')
    if second_session == first_session:
        raise SystemExit('expected a new popup session id after Esc destroyed the old one')
finally:
    try:
        os.close(master_fd)
    except OSError:
        pass
    client.terminate()
    try:
        client.wait(timeout=5)
    except subprocess.TimeoutExpired:
        client.kill()
        client.wait(timeout=5)

print('ok: popup stays interactive, Alt-f hides and reuses the session, and Esc destroys it for a fresh next open')
PY
