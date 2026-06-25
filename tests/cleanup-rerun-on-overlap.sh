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
sock="tfp_test_cleanup_rerun.$$.$RANDOM"
fake_bin="$work_dir/bin"
block_dir="$work_dir/block"
mkdir -p "$fake_bin" "$block_dir"

cleanup() {
  : > "$block_dir/continue-kill" 2>/dev/null || true
  for pid in "${first_cleanup_pid:-}" "${second_cleanup_pid:-}"; do
    [ -n "$pid" ] || continue
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true

cat >"$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
if [ "${TFP_BLOCK_KILL_ONCE:-0}" = '1' ] && [ "${1:-}" = 'kill-session' ] && [ "${2:-}" = '-t' ] && [ ! -f "__BLOCK_DIR__/blocked-once" ]; then
  : > "__BLOCK_DIR__/blocked-once"
  : > "__BLOCK_DIR__/kill-started"
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50; do
    if [ -f "__BLOCK_DIR__/continue-kill" ]; then
      break
    fi
    sleep 0.1
  done
fi
exec "__REAL_TMUX_BIN__" -L "__SOCK__" "$@"
EOF
sed -i "s|__BLOCK_DIR__|$block_dir|g; s|__REAL_TMUX_BIN__|$REAL_TMUX_BIN|g; s|__SOCK__|$sock|g" "$fake_bin/tmux"
chmod +x "$fake_bin/tmux"

export PATH="$fake_bin:$PATH"

# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/tmux.sh"

tmux -f /dev/null new-session -d -s base -c "$work_dir" 'sleep 9999'
parent_id="$(floating_popup_session_id_for_target '=base')"

for popup_session in __floating-popup-duplicate-a __floating-popup-duplicate-b; do
  tmux new-session -d -s "$popup_session" -c "$work_dir" 'sleep 9999'
  tmux set-option -t "$popup_session" -q "$(floating_popup_session_flag)" 1
  tmux set-option -t "$popup_session" -q "$(floating_popup_owner_session_option)" base
  tmux set-option -t "$popup_session" -q "$(floating_popup_owner_session_id_option)" "$parent_id"
done

marked_popups_for_parent() {
  local count=0 session_id='' flag='' owner_id=''
  while IFS= read -r session_id; do
    [ -n "$session_id" ] || continue
    flag="$(tmux show-options -t "$session_id" -qv "$(floating_popup_session_flag)" 2>/dev/null || true)"
    owner_id="$(tmux show-options -t "$session_id" -qv "$(floating_popup_owner_session_id_option)" 2>/dev/null || true)"
    if [ "$flag" = '1' ] && [ "$owner_id" = "$parent_id" ]; then
      count=$((count + 1))
    fi
  done < <(tmux list-sessions -F '#{session_id}')
  printf '%s' "$count"
}

[ "$(marked_popups_for_parent)" = '2' ] || {
  echo 'test setup failed: expected two duplicate popup sessions before cleanup overlap test' >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" TFP_BLOCK_KILL_ONCE=1 "$TIMEOUT_BIN" 20 "$REPO_DIR/scripts/cleanup-popup-sessions.sh" &
first_cleanup_pid=$!

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
  if [ -f "$block_dir/kill-started" ]; then
    break
  fi
  sleep 0.1
done
[ -f "$block_dir/kill-started" ] || {
  echo 'expected the first cleanup run to block during duplicate kill' >&2
  exit 1
}

tmux new-session -d -s __floating-popup-duplicate-c -c "$work_dir" 'sleep 9999'
tmux set-option -t __floating-popup-duplicate-c -q "$(floating_popup_session_flag)" 1
tmux set-option -t __floating-popup-duplicate-c -q "$(floating_popup_owner_session_option)" base
tmux set-option -t __floating-popup-duplicate-c -q "$(floating_popup_owner_session_id_option)" "$parent_id"

env -u TMUX PATH="$fake_bin:$PATH" "$TIMEOUT_BIN" 20 "$REPO_DIR/scripts/cleanup-popup-sessions.sh" &
second_cleanup_pid=$!

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
  if [ -n "$(tmux show-options -gqv @floating-popup-cleanup-pending 2>/dev/null || true)" ]; then
    break
  fi
  sleep 0.1
done
[ -n "$(tmux show-options -gqv @floating-popup-cleanup-pending 2>/dev/null || true)" ] || {
  echo 'expected the second cleanup run to mark a pending rerun' >&2
  exit 1
}

: > "$block_dir/continue-kill"

wait "$first_cleanup_pid"
wait "$second_cleanup_pid"

remaining_count="$(marked_popups_for_parent)"
[ "$remaining_count" = '1' ] || {
  echo "expected overlapping cleanup runs to drain pending rerun and leave one popup, got: $remaining_count" >&2
  exit 1
}

running_flag="$(tmux show-options -gqv @floating-popup-cleanup-running 2>/dev/null || true)"
pending_flag="$(tmux show-options -gqv @floating-popup-cleanup-pending 2>/dev/null || true)"
runner_pid="$(tmux show-options -gqv @floating-popup-cleanup-runner-pid 2>/dev/null || true)"
[ -z "$running_flag" ] || {
  echo "expected cleanup running flag to be cleared, got: $running_flag" >&2
  exit 1
}
[ -z "$pending_flag" ] || {
  echo "expected cleanup pending flag to be cleared, got: $pending_flag" >&2
  exit 1
}
[ -z "$runner_pid" ] || {
  echo "expected cleanup runner pid to be cleared, got: $runner_pid" >&2
  exit 1
}

echo 'ok: overlapping cleanup runs queue and drain a pending rerun'
