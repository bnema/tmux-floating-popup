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

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s 1 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux set-option -t 1 -q @floating-popup-session 1
env -u TMUX PATH="$fake_bin:$PATH" tmux set-option -t 1 -q @floating-popup-owner-client /dev/pts/10
env -u TMUX PATH="$fake_bin:$PATH" tmux set-option -t 1 -q @floating-popup-owner-session base
client_session_option="$(
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    floating_popup_client_session_option /dev/pts/10 base
  ' bash "$REPO_DIR"
)"
env -u TMUX PATH="$fake_bin:$PATH" tmux set-option -gq "$client_session_option" 1

resolved_session="$(
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    floating_popup_resolve_session_for_client /dev/pts/10 "$2" base
  ' bash "$REPO_DIR" "$work_dir"
)"

[ "$resolved_session" != '1' ] || {
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

legacy_flag="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t 1 -qv @floating-popup-session 2>/dev/null || true)"
legacy_owner="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t 1 -qv @floating-popup-owner-client 2>/dev/null || true)"
legacy_owner_session="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t 1 -qv @floating-popup-owner-session 2>/dev/null || true)"
regular_status="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t 1 -qv status 2>/dev/null || true)"
stale_mapping="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -gqv "$client_session_option" 2>/dev/null || true)"

[ "$legacy_flag" = '1' ] || { echo "expected legacy session flag to stay untouched, got: $legacy_flag" >&2; exit 1; }
[ "$legacy_owner" = '/dev/pts/10' ] || { echo "expected legacy session owner to stay untouched, got: $legacy_owner" >&2; exit 1; }
[ "$legacy_owner_session" = 'base' ] || { echo "expected legacy session owner session to stay untouched, got: $legacy_owner_session" >&2; exit 1; }
[ "$regular_status" != 'off' ] || { echo 'expected non-internal session status not to be forced off' >&2; exit 1; }
[ "$stale_mapping" = "$resolved_session" ] || { echo "expected client mapping to be updated to $resolved_session, got: $stale_mapping" >&2; exit 1; }

echo 'ok: stale client mappings do not claim non-internal sessions as popup sessions'
