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
tmux new-session -d -s __floating-popup-stale -c "$work_dir"
floating_popup_prepare_session __floating-popup-stale /dev/pts/missing base
floating_popup_set_client_session /dev/pts/missing base __floating-popup-stale

floating_popup_cleanup_stale_sessions

if tmux has-session -t =__floating-popup-stale 2>/dev/null; then
  echo 'expected stale popup session owned by a disconnected client to be removed' >&2
  exit 1
fi

stale_mapping="$(floating_popup_get_client_session /dev/pts/missing base)"
[ -z "$stale_mapping" ] || {
  echo "expected stale client mapping to be cleared, got: $stale_mapping" >&2
  exit 1
}

echo 'ok: stale popup sessions owned by disconnected clients are cleaned up'
