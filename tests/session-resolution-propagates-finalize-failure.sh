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
sock="tfp_test_finalize_failure.$$.$RANDOM"
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
unset TMUX

# shellcheck source=/dev/null
source "$REPO_DIR/scripts/lib/tmux.sh"

env -u TMUX tmux -f /dev/null new-session -d -s base -c "$work_dir" 'sleep 9999'
base_session_id="$(floating_popup_session_id_for_target '=base')"
popup_session="$(floating_popup_create_session base "$work_dir" 1 "$base_session_id")"
[ -n "$popup_session" ] || {
  echo 'expected popup session to be created for finalize failure regression' >&2
  exit 1
}

floating_popup_finalize_session_resolution() {
  return 1
}

if resolved_session="$(floating_popup_resolve_session_for_client_locked "$work_dir" base 1 "$base_session_id")"; then
  echo "expected resolve_session_for_client_locked to return non-zero when finalize fails, got: $resolved_session" >&2
  exit 1
fi

[ -z "${resolved_session:-}" ] || {
  echo "expected resolve_session_for_client_locked not to print a session when finalize fails, got: $resolved_session" >&2
  exit 1
}

echo 'ok: session resolution propagates finalize-session failures'
