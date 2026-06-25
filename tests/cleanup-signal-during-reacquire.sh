#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
TIMEOUT_BIN="$(command -v timeout 2>/dev/null || true)"
SED_BIN="$(command -v sed 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
[ -n "$TIMEOUT_BIN" ] || { echo 'timeout not found' >&2; exit 1; }
[ -n "$SED_BIN" ] || { echo 'sed not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_cleanup_signal_reacquire.$$.$RANDOM"
fake_bin="$work_dir/bin"
block_dir="$work_dir/block"
cleanup_pid_file="$block_dir/cleanup-parent.pid"
mkdir -p "$fake_bin" "$block_dir"

cleanup() {
  : > "$block_dir/continue-lock-return" 2>/dev/null || true
  if [ -n "${cleanup_pid:-}" ]; then
    kill "$cleanup_pid" 2>/dev/null || true
    wait "$cleanup_pid" 2>/dev/null || true
  fi
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true

cat >"$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
if [ "${TFP_BLOCK_SECOND_LOCK_ONCE:-0}" = '1' ] && [ "${1:-}" = 'wait-for' ] && [ "${2:-}" = '-L' ] && [ "${3:-}" = '__LOCK_CHANNEL__' ]; then
  count_file='__BLOCK_DIR__/lock-count'
  count=0
  if [ -f "$count_file" ]; then
    count="$(cat "$count_file")"
  fi
  count=$((count + 1))
  printf '%s' "$count" >"$count_file"
  if [ "$count" = '2' ] && [ ! -f '__BLOCK_DIR__/blocked-once' ]; then
    "__REAL_TMUX_BIN__" -L "__SOCK__" "$@" || exit $?
    : > '__BLOCK_DIR__/blocked-once'
    : > '__BLOCK_DIR__/second-lock-acquired'
    while :; do
      if [ -f '__BLOCK_DIR__/continue-lock-return' ]; then
        break
      fi
      if [ -f '__PID_FILE__' ] && ! kill -0 "$(cat '__PID_FILE__')" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    exit 0
  fi
fi
exec "__REAL_TMUX_BIN__" -L "__SOCK__" "$@"
EOF
chmod +x "$fake_bin/tmux"

lock_channel="$({
  # shellcheck disable=SC2016 # inner bash expands runtime argv after injection
  # shellcheck source=/dev/null
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    floating_popup_lock_channel cleanup sessions
  ' bash "$REPO_DIR"
})"

"$SED_BIN" -i "s|__LOCK_CHANNEL__|$lock_channel|g; s|__BLOCK_DIR__|$block_dir|g; s|__PID_FILE__|$cleanup_pid_file|g; s|__REAL_TMUX_BIN__|$REAL_TMUX_BIN|g; s|__SOCK__|$sock|g" "$fake_bin/tmux"

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s base 'sleep 9999'

env -u TMUX PATH="$fake_bin:$PATH" TFP_BLOCK_SECOND_LOCK_ONCE=1 "$REPO_DIR/scripts/cleanup-popup-sessions.sh" &
cleanup_pid=$!
printf '%s' "$cleanup_pid" >"$cleanup_pid_file"

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
  if [ -f "$block_dir/second-lock-acquired" ]; then
    break
  fi
  sleep 0.1
done
[ -f "$block_dir/second-lock-acquired" ] || {
  echo 'expected cleanup runner to block during its second cleanup lock acquisition' >&2
  exit 1
}

kill -TERM "$cleanup_pid" 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if ! kill -0 "$cleanup_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if kill -0 "$cleanup_pid" 2>/dev/null; then
  echo 'expected TERM during cleanup lock reacquisition to exit promptly without hanging' >&2
  exit 1
fi
wait "$cleanup_pid" 2>/dev/null || true

env -u TMUX PATH="$fake_bin:$PATH" "$TIMEOUT_BIN" 5 "$REPO_DIR/scripts/cleanup-popup-sessions.sh" || {
  echo 'expected later cleanup run to recover after TERM during cleanup lock reacquisition' >&2
  exit 1
}

running_flag="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -gqv @floating-popup-cleanup-running 2>/dev/null || true)"
pending_flag="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -gqv @floating-popup-cleanup-pending 2>/dev/null || true)"
runner_pid="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -gqv @floating-popup-cleanup-runner-pid 2>/dev/null || true)"
[ -z "$running_flag" ] || {
  echo "expected cleanup running flag to be clear after TERM recovery, got: $running_flag" >&2
  exit 1
}
[ -z "$pending_flag" ] || {
  echo "expected cleanup pending flag to be clear after TERM recovery, got: $pending_flag" >&2
  exit 1
}
[ -z "$runner_pid" ] || {
  echo "expected cleanup runner pid to be clear after TERM recovery, got: $runner_pid" >&2
  exit 1
}

echo 'ok: TERM during cleanup lock reacquisition exits promptly and recovers cleanly'
