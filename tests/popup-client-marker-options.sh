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
sock="tfp_test_popup_client_markers.$$.$RANDOM"
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

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s base 'sleep 9999'

marker_option=''
pid_option=''
eval "$(env -u TMUX PATH="$fake_bin:$PATH" REPO_DIR="$REPO_DIR" bash <<'BASH'
source "$REPO_DIR/scripts/lib/tmux.sh"
client_name='/dev/pts/99'
marker_option="$(floating_popup_client_marker_option "$client_name")"
pid_option="$(floating_popup_client_pid_option "$client_name")"
printf 'marker_option=%q\n' "$marker_option"
printf 'pid_option=%q\n' "$pid_option"
case "$marker_option" in
  @floating-popup-client-marker_*) ;;
  *) echo "unexpected marker option: $marker_option" >&2; exit 1 ;;
esac
case "$pid_option" in
  @floating-popup-client_*-pid) ;;
  *) echo "unexpected pid option: $pid_option" >&2; exit 1 ;;
esac
case "$marker_option $pid_option" in
  *popup-popup*) echo 'option names should not contain duplicated popup segment' >&2; exit 1 ;;
esac
if floating_popup_mark_popup_client "$client_name" not-a-pid; then
  echo 'expected non-numeric client pid to be rejected' >&2
  exit 1
fi
floating_popup_mark_popup_client "$client_name" 12345
floating_popup_cleanup_stale_popup_clients
BASH
)"

marker_value="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -gqv "$marker_option" 2>/dev/null || true)"
pid_value="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -gqv "$pid_option" 2>/dev/null || true)"

[ -z "$marker_value" ] || {
  echo "expected stale marker option to be cleared, got: $marker_value" >&2
  exit 1
}
[ -z "$pid_value" ] || {
  echo "expected stale pid option to be cleared, got: $pid_value" >&2
  exit 1
}

echo 'ok: popup client marker options are named clearly, validate pids, and clean stale entries'
