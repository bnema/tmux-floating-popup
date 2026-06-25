#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_stale_owner_cleanup.$$.$RANDOM"
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

export PATH="$fake_bin:$PATH"

source "$REPO_DIR/scripts/lib/tmux.sh"

tmux -f /dev/null new-session -d -s base 'sleep 9999'
owner_session_id="$(floating_popup_session_id_for_target '=base')"
[ -n "$owner_session_id" ] || {
  echo 'test setup failed: could not resolve parent session id for base' >&2
  exit 1
}
tmux new-session -d -s __floating-popup-stale -c "$work_dir"
tmux set-option -t __floating-popup-stale -q "$(floating_popup_owner_session_option)" base
tmux set-option -t __floating-popup-stale -q "$(floating_popup_owner_session_id_option)" "$owner_session_id"
tmux set-option -t __floating-popup-stale -q status off
tmux set-option -t __floating-popup-stale -q "$(floating_popup_session_flag)" 1

tmux kill-session -t =base
floating_popup_cleanup_stale_sessions

if tmux has-session -t =__floating-popup-stale 2>/dev/null; then
  echo 'expected stale popup session to be removed after its parent session disappeared' >&2
  exit 1
fi

echo 'ok: popup sessions are cleaned up when their parent session disappears'
