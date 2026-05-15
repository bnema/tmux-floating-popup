#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
AWK_BIN="$(command -v awk 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
[ -n "$AWK_BIN" ] || { echo 'awk not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_persistent_reuse"
client_log="$work_dir/client.log"
fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"

cleanup() {
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

popup_session_client() {
  local awk_program="\$2 == \"tmux-floating-popup\" { print \$1; exit }"
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}	#{session_name}' |
    "$AWK_BIN" -F $'\t' "$awk_program"
}

cat >"$fake_bin/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX_BIN" -L "$sock" "\$@"
EOF
chmod +x "$fake_bin/tmux"

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s base 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux run-shell "$REPO_DIR/tmux-floating-popup.tmux"
script -q -c "env -u TMUX PATH='$fake_bin:$PATH' TERM=xterm-256color tmux attach-session -t base" "$client_log" >/dev/null 2>&1 &
client_pid=$!
sleep 1

client_name="$(env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}' | head -n1)"
[ -n "$client_name" ] || { echo 'no tmux client found' >&2; exit 1; }

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$client_name" "$work_dir" >/dev/null 2>&1 &
open_popup_pid=$!
sleep 1

if ! env -u TMUX PATH="$fake_bin:$PATH" tmux has-session -t '=tmux-floating-popup' 2>/dev/null; then
  echo 'expected popup session to be created' >&2
  exit 1
fi

popup_client=''
for _ in 1 2 3 4 5; do
  popup_client="$(popup_session_client)"
  [ -n "$popup_client" ] && break
  sleep 1
done
[ -n "$popup_client" ] || { echo 'expected a client attached to the popup session' >&2; exit 1; }

env -u TMUX PATH="$fake_bin:$PATH" tmux new-window -t '=tmux-floating-popup' -n persisted
env -u TMUX PATH="$fake_bin:$PATH" tmux select-window -t '=tmux-floating-popup:persisted'

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/close-popup.sh" "$client_name"
wait "$open_popup_pid" || true
sleep 1

if ! env -u TMUX PATH="$fake_bin:$PATH" tmux has-session -t '=tmux-floating-popup' 2>/dev/null; then
  echo 'expected popup session to survive after closing the popup' >&2
  exit 1
fi

if env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{session_name}' | grep -Fxq 'tmux-floating-popup'; then
  echo 'expected popup client to detach after closing the popup' >&2
  exit 1
fi

if ! env -u TMUX PATH="$fake_bin:$PATH" tmux list-windows -t '=tmux-floating-popup' -F '#{window_name}' | grep -Fxq 'persisted'; then
  echo 'expected persisted window to remain in popup session' >&2
  exit 1
fi

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$client_name" "$work_dir" >/dev/null 2>&1 &
reopen_popup_pid=$!
sleep 1

popup_client=''
for _ in 1 2 3 4 5; do
  popup_client="$(popup_session_client)"
  [ -n "$popup_client" ] && break
  sleep 1
done
[ -n "$popup_client" ] || { echo 'expected popup session to reattach on reopen' >&2; exit 1; }

active_window_awk="\$1 == \"1\" { print \$2; exit }"
active_window="$(env -u TMUX PATH="$fake_bin:$PATH" tmux list-windows -t '=tmux-floating-popup' -F '#{?window_active,1,0}	#{window_name}' |
  "$AWK_BIN" -F $'\t' "$active_window_awk")"
[ "$active_window" = 'persisted' ] || {
  echo "expected popup session to reopen on persisted window, got: $active_window" >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/close-popup.sh" "$client_name"
wait "$reopen_popup_pid" || true
kill "$client_pid" 2>/dev/null || true

echo 'ok: popup session persists across close and reopen'
