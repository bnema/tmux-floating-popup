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
sock="tfp_test_parent_cleanup.$$.$RANDOM"
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

tmux -f /dev/null new-session -d -s base -c "$work_dir" 'sleep 9999'
tmux new-session -d -s __floating-popup-parent-owned -c "$work_dir"
floating_popup_prepare_session __floating-popup-parent-owned base "$work_dir"

tmux new-session -d -s __floating-popup-user-session -c "$work_dir"

tmux kill-session -t =base

floating_popup_reconcile_sessions

if tmux has-session -t =__floating-popup-parent-owned 2>/dev/null; then
  echo 'expected popup session owned by the deleted parent session to be removed' >&2
  exit 1
fi

if ! tmux has-session -t =__floating-popup-user-session 2>/dev/null; then
  echo 'expected unmarked internal-name user session to survive cleanup' >&2
  exit 1
fi

tmux new-session -d -s recycled -c "$work_dir" 'sleep 9999'
old_recycled_id="$(floating_popup_session_id_for_target '=recycled')"
tmux new-session -d -s __floating-popup-recycled -c "$work_dir"
floating_popup_prepare_session __floating-popup-recycled recycled "$work_dir"

stored_recycled_id="$(floating_popup_owner_session_id_for_session __floating-popup-recycled)"
[ "$stored_recycled_id" = "$old_recycled_id" ] || {
  echo "expected recycled popup to store parent id $old_recycled_id, got: $stored_recycled_id" >&2
  exit 1
}

tmux kill-session -t =recycled
tmux new-session -d -s recycled -c "$work_dir" 'sleep 9999'
new_recycled_id="$(floating_popup_session_id_for_target '=recycled')"
[ "$new_recycled_id" != "$old_recycled_id" ] || {
  echo 'test setup failed: recreated parent session kept the same session id' >&2
  exit 1
}

floating_popup_reconcile_sessions

if tmux has-session -t =__floating-popup-recycled 2>/dev/null; then
  echo 'expected popup session owned by the old parent id to be removed after same-name parent recreation' >&2
  exit 1
fi

recreated_popup="$(floating_popup_resolve_session_for_client_locked "$work_dir" recycled 1 "$old_recycled_id")" || {
  echo 'expected stale requested owner session id to refresh to the live recycled parent' >&2
  exit 1
}
recreated_popup_owner_id="$(floating_popup_owner_session_id_for_session "$recreated_popup")"
[ "$recreated_popup_owner_id" = "$new_recycled_id" ] || {
  echo "expected recreated popup to refresh owner session id to $new_recycled_id, got: $recreated_popup_owner_id" >&2
  exit 1
}

tmux new-session -d -s legacy-recycled -c "$work_dir" 'sleep 9999'
tmux new-session -d -s __floating-popup-legacy-recycled -c "$work_dir"
tmux set-option -t __floating-popup-legacy-recycled -q "$(floating_popup_session_flag)" 1
tmux set-option -t __floating-popup-legacy-recycled -q "$(floating_popup_owner_session_option)" legacy-recycled

tmux kill-session -t =legacy-recycled
tmux new-session -d -s legacy-recycled -c "$work_dir" 'sleep 9999'

floating_popup_reconcile_sessions

if tmux has-session -t =__floating-popup-legacy-recycled 2>/dev/null; then
  echo 'expected legacy no-id popup to be removed instead of re-parented after same-name parent recreation' >&2
  exit 1
fi

echo 'ok: popup sessions are reconciled against parent session ownership safely'
