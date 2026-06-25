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
sock="tfp_test_stale_client_session.$$.$RANDOM"
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

regular_session='regular'
env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s "$regular_session" 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s base 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux set-option -t "$regular_session" -q @floating-popup-session 1
env -u TMUX PATH="$fake_bin:$PATH" tmux set-option -t "$regular_session" -q @floating-popup-owner-session base
legacy_client_session_option="$(
  # shellcheck disable=SC2016 # inner bash expands $1 and helper outputs
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    client_suffix="$(floating_popup_client_option_suffix /dev/pts/10)"
    printf "@floating-popup-client-%s-session" "$client_suffix"
  ' bash "$REPO_DIR"
)"
env -u TMUX PATH="$fake_bin:$PATH" tmux set-option -gq "$legacy_client_session_option" "$regular_session"

resolved_session="$(
  # shellcheck disable=SC2016 # inner bash expands $1/$2 after argv injection
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    floating_popup_resolve_session_for_client /dev/pts/10 "$2" base
  ' bash "$REPO_DIR" "$work_dir"
)"

[ "$resolved_session" != "$regular_session" ] || {
  echo 'expected stale client mapping to a non-internal session to be ignored' >&2
  exit 1
}
case "$resolved_session" in
  __floating-popup-*) ;;
  *)
    echo "expected new popup session to use __floating-popup- prefix, got: $resolved_session" >&2
    exit 1
    ;;
esac

legacy_flag="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t "$regular_session" -qv @floating-popup-session 2>/dev/null || true)"
legacy_owner_session="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t "$regular_session" -qv @floating-popup-owner-session 2>/dev/null || true)"
owner_session_id="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t "$regular_session" -qv @floating-popup-owner-session-id 2>/dev/null || true)"
regular_status="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t "$regular_session" -qv status 2>/dev/null || true)"
[ "$legacy_flag" = '1' ] || { echo "expected legacy session flag to stay untouched, got: $legacy_flag" >&2; exit 1; }
[ "$legacy_owner_session" = 'base' ] || { echo "expected legacy session owner session to stay untouched, got: $legacy_owner_session" >&2; exit 1; }
[ -z "$owner_session_id" ] || { echo "expected regular session not to acquire an owner session id, got: $owner_session_id" >&2; exit 1; }
[ "$regular_status" != 'off' ] || { echo 'expected non-internal session status not to be forced off' >&2; exit 1; }

echo 'ok: stale client mappings are ignored and do not claim non-internal sessions as popup sessions'
