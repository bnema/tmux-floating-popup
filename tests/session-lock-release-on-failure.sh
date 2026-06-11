#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
[ -n "$TIMEOUT_BIN" ] || { echo 'timeout not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_lock_release.$$.$RANDOM"
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
if [ "\${TFP_FAIL_UNLOCK:-0}" = '1' ] && [ "\${1:-}" = 'wait-for' ] && [ "\${2:-}" = '-U' ]; then
  exit 23
fi
exec "$REAL_TMUX_BIN" -L "$sock" "\$@"
EOF
chmod +x "$fake_bin/tmux"

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s base 'sleep 9999'

lock_channel="$({
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    floating_popup_lock_channel /dev/pts/test owner
  ' bash "$REPO_DIR"
})"
[ -n "$lock_channel" ] || {
  echo 'floating_popup_lock_channel returned an empty lock channel' >&2
  exit 1
}

if env -u TMUX PATH="$fake_bin:$PATH" bash -c '
  set -euo pipefail
  source "$1/scripts/lib/tmux.sh"
  floating_popup_with_session_lock /dev/pts/test owner false
' bash "$REPO_DIR"; then
  echo 'expected the failing lock handler to return non-zero' >&2
  exit 1
fi

env -u TMUX PATH="$fake_bin:$PATH" "$TIMEOUT_BIN" 2 bash -c '
  tmux wait-for -L "$1"
  tmux wait-for -U "$1"
' bash "$lock_channel" || {
  echo 'expected lock to be released even when the handler fails' >&2
  exit 1
}

unlock_stderr="$work_dir/unlock-stderr.log"
set +e
env -u TMUX PATH="$fake_bin:$PATH" TFP_FAIL_UNLOCK=1 bash -c '
  set -euo pipefail
  source "$1/scripts/lib/tmux.sh"
  floating_popup_with_session_lock /dev/pts/test owner false
' bash "$REPO_DIR" 2>"$unlock_stderr"
unlock_status=$?
set -e

[ "$unlock_status" -eq 1 ] || {
  echo "expected lock helper to preserve handler exit status 1, got: $unlock_status" >&2
  exit 1
}

grep -Fq "tmux-floating-popup: failed to unlock channel $lock_channel (exit 23)" "$unlock_stderr" || {
  echo 'expected unlock failure to be logged with channel and exit code' >&2
  cat "$unlock_stderr" >&2
  exit 1
}

echo 'ok: failing lock handlers still release the tmux wait-for lock and log unlock failures'
