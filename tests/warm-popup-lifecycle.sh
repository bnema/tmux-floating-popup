#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
AWK_BIN="$(command -v awk 2>/dev/null || true)"
SCRIPT_BIN="$(command -v script 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
[ -n "$AWK_BIN" ] || { echo 'awk not found' >&2; exit 1; }
[ -n "$SCRIPT_BIN" ] || { echo 'script not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_warm_popup_lifecycle.$$.$RANDOM"
client_log="$work_dir/client.log"
script_probe_log="$work_dir/script-probe.log"
fake_bin="$work_dir/bin"
base_dir="$work_dir/base"
stale_dir="$work_dir/stale"
fresh_dir="$work_dir/fresh"
mkdir -p "$fake_bin" "$base_dir" "$stale_dir" "$fresh_dir"

if ! "$SCRIPT_BIN" -q -c true "$script_probe_log" >/dev/null 2>&1; then
  echo 'script -c not supported' >&2
  exit 1
fi
rm -f "$script_probe_log"

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

popup_session_for_owner() {
  local owner_session="$1"
  # shellcheck disable=SC2016 # awk program uses its own $-fields, not shell expansion
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-sessions -F '#{session_name}|#{pane_current_path}|#{@floating-popup-session}|#{@floating-popup-owner-session}' 2>/dev/null \
    | "$AWK_BIN" -F'|' -v owner_session="$owner_session" '$3 == "1" && $4 == owner_session { print $1; exit }'
}

popup_path_for_session() {
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-panes -t "=$1:" -F '#{pane_current_path}' 2>/dev/null | head -n1
}

popup_client_row() {
  # shellcheck disable=SC2016 # awk program uses its own $-fields, not shell expansion
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}|#{session_name}|#{@floating-popup-session}' 2>/dev/null \
    | "$AWK_BIN" -F'|' '$3 == "1" { print; exit }'
}

wait_for_popup_client() {
  local popup_row=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    popup_row="$(popup_client_row)"
    if [ -n "$popup_row" ]; then
      printf '%s' "$popup_row"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_no_popup_client() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [ -z "$(popup_client_row)" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_attached_client() {
  local client_name=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    client_name="$(env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}' 2>/dev/null | head -n1)"
    if [ -n "$client_name" ]; then
      printf '%s' "$client_name"
      return 0
    fi
    sleep 1
  done
  return 1
}

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s base 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux new-session -d -s project 'sleep 9999'
"$SCRIPT_BIN" -q -c "env -u TMUX PATH='$fake_bin:$PATH' TERM=xterm-256color tmux attach-session -t base" "$client_log" >/dev/null 2>&1 &
client_pid=$!

client_name="$(wait_for_attached_client)"
[ -n "$client_name" ] || { echo 'no tmux client found' >&2; exit 1; }

# Same-path warm-up should be reused by the first visible open.
env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/warm-popup.sh" "$client_name" "$base_dir"
warmed_base_session="$(popup_session_for_owner base)"
[ -n "$warmed_base_session" ] || {
  echo 'expected hidden warm-up session for base' >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$client_name" "$base_dir" >/dev/null 2>&1 &
open_base_pid=$!
sleep 1

base_popup_row="$(wait_for_popup_client)" || {
  echo 'expected popup client for warmed base session' >&2
  exit 1
}
IFS='|' read -r base_popup_client base_opened_session _ <<<"$base_popup_row"

[ "$base_opened_session" = "$warmed_base_session" ] || {
  echo "expected first visible open to reuse $warmed_base_session, got: $base_opened_session" >&2
  exit 1
}

[ "$(popup_path_for_session "$base_opened_session")" = "$base_dir" ] || {
  echo "expected reused warm-up session to keep start path $base_dir, got: $(popup_path_for_session "$base_opened_session")" >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/close-popup.sh" "$base_popup_client"
wait "$open_base_pid" || true
wait_for_no_popup_client || {
  echo 'expected popup client to disappear after closing reused warm-up session' >&2
  exit 1
}

# A never-opened warm-up session should refresh to the current path before first visible open.
env -u TMUX PATH="$fake_bin:$PATH" tmux switch-client -c "$client_name" -t project
sleep 1

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/warm-popup.sh" "$client_name" "$stale_dir"
stale_warm_session="$(popup_session_for_owner project)"
[ -n "$stale_warm_session" ] || {
  echo 'expected hidden warm-up session for project' >&2
  exit 1
}

[ "$(popup_path_for_session "$stale_warm_session")" = "$stale_dir" ] || {
  echo "expected hidden warm-up session to start in $stale_dir, got: $(popup_path_for_session "$stale_warm_session")" >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$client_name" "$fresh_dir" >/dev/null 2>&1 &
open_project_pid=$!
sleep 1

project_popup_row="$(wait_for_popup_client)" || {
  echo 'expected popup client for refreshed project session' >&2
  exit 1
}
IFS='|' read -r project_popup_client refreshed_session _ <<<"$project_popup_row"

[ "$refreshed_session" != "$stale_warm_session" ] || {
  echo 'expected first open from a stale warm-up session to refresh to a new popup session' >&2
  exit 1
}

[ "$(popup_path_for_session "$refreshed_session")" = "$fresh_dir" ] || {
  echo "expected refreshed popup session to start in $fresh_dir, got: $(popup_path_for_session "$refreshed_session")" >&2
  exit 1
}

if env -u TMUX PATH="$fake_bin:$PATH" tmux has-session -t "=$stale_warm_session" 2>/dev/null; then
  echo 'expected stale unused warm-up session to be removed after path refresh' >&2
  exit 1
fi

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/close-popup.sh" "$project_popup_client"
wait "$open_project_pid" || true
wait_for_no_popup_client || {
  echo 'expected refreshed popup client to disappear after close' >&2
  exit 1
}

kill "$client_pid" 2>/dev/null || true

echo 'ok: first open reuses same-path warm-up sessions and refreshes unused stale warm-up sessions before activation'
