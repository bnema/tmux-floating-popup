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
sock="tfp_test_session_aware.$$.$RANDOM"
fake_bin="$work_dir/bin"
base_dir="$work_dir/base"
project_dir="$work_dir/project"
mkdir -p "$fake_bin" "$base_dir" "$project_dir"

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

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s regular 'sleep 9999'

resolve_popup_session() {
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    floating_popup_resolve_session_for_client "$2" "$3" "$4"
  ' bash "$REPO_DIR" "$1" "$2" "$3"
}

popup_path() {
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-panes -t "=$1:" -F '#{pane_current_path}' | head -n1
}

client_name='/dev/pts/10'
base_popup="$(resolve_popup_session "$client_name" "$base_dir" base)"
base_popup_again="$(resolve_popup_session "$client_name" "$base_dir" base)"
project_popup="$(resolve_popup_session "$client_name" "$project_dir" project)"
dash_popup="$(resolve_popup_session "$client_name" "$work_dir" foo-bar)"
underscore_popup="$(resolve_popup_session "$client_name" "$work_dir" foo_bar)"
dash_popup_again="$(resolve_popup_session "$client_name" "$work_dir" foo-bar)"

case "$base_popup" in
  __floating-popup-*) ;;
  *) echo "expected base popup session to start with __floating-popup-, got: $base_popup" >&2; exit 1 ;;
esac

case "$project_popup" in
  __floating-popup-*) ;;
  *) echo "expected project popup session to start with __floating-popup-, got: $project_popup" >&2; exit 1 ;;
esac

[ "$base_popup_again" = "$base_popup" ] || {
  echo "expected same client/session to reuse $base_popup, got: $base_popup_again" >&2
  exit 1
}

[ "$project_popup" != "$base_popup" ] || {
  echo "expected same client in a different tmux session to get a separate popup session" >&2
  exit 1
}

[ "$dash_popup" != "$underscore_popup" ] || {
  echo 'expected similar session names foo-bar and foo_bar to use separate popup sessions' >&2
  exit 1
}

[ "$dash_popup_again" = "$dash_popup" ] || {
  echo "expected foo-bar to reuse $dash_popup after resolving foo_bar, got: $dash_popup_again" >&2
  exit 1
}

[ "$(popup_path "$base_popup")" = "$base_dir" ] || {
  echo "expected base popup to start in $base_dir, got: $(popup_path "$base_popup")" >&2
  exit 1
}

[ "$(popup_path "$project_popup")" = "$project_dir" ] || {
  echo "expected project popup to start in $project_dir, got: $(popup_path "$project_popup")" >&2
  exit 1
}

echo 'ok: popup sessions are keyed by client and tmux session and keep their own start directories'
