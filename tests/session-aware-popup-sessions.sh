#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
SCRIPT_BIN="$(command -v script 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
[ -n "$SCRIPT_BIN" ] || { echo 'script not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_session_aware.$$.$RANDOM"
client_log="$work_dir/client.log"
other_client_log="$work_dir/other-client.log"
script_probe_log="$work_dir/script-probe.log"
fake_bin="$work_dir/bin"
base_dir="$work_dir/base"
project_dir="$work_dir/project"
mkdir -p "$fake_bin" "$base_dir" "$project_dir"

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

create_parent_session() {
  local session_name="$1" start_path="$2"
  env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s "$session_name" -c "$start_path" 'sleep 9999'
}

create_parent_session base "$base_dir"
create_parent_session project "$project_dir"
create_parent_session foo-bar "$work_dir"
create_parent_session foo_bar "$work_dir"
create_parent_session __floating-popup-user "$work_dir"

resolve_popup_session_for_client() {
  # shellcheck disable=SC2016 # inner bash expands $1/$2/$3 after argv injection
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    floating_popup_resolve_session_for_client "$2" "$3"
  ' bash "$REPO_DIR" "$1" "$2"
}

resolve_popup_session_for_owner() {
  # shellcheck disable=SC2016 # inner bash expands $1/$2/$3/$4 after argv injection
  env -u TMUX PATH="$fake_bin:$PATH" bash -c '
    source "$1/scripts/lib/tmux.sh"
    floating_popup_resolve_session_for_client "$2" "$3" "$4"
  ' bash "$REPO_DIR" "$1" "$2" "$3"
}

attached_base_clients() {
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}|#{session_name}' 2>/dev/null \
    | awk -F'|' '$2 == "base" { print $1 }'
}

wait_for_base_clients() {
  local expected="$1" clients='' count=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    clients="$(attached_base_clients)"
    count="$(printf '%s\n' "$clients" | awk 'NF { count++ } END { print count + 0 }')"
    if [ "$count" -ge "$expected" ]; then
      printf '%s' "$clients"
      return 0
    fi
    sleep 1
  done
  return 1
}

popup_path() {
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-panes -t "=$1:" -F '#{pane_current_path}' | head -n1
}

"$SCRIPT_BIN" -q -c "env -u TMUX PATH='$fake_bin:$PATH' TERM=xterm-256color tmux attach-session -t base" "$client_log" >/dev/null 2>&1 &
client_pid=$!
"$SCRIPT_BIN" -q -c "env -u TMUX PATH='$fake_bin:$PATH' TERM=xterm-256color tmux attach-session -t base" "$other_client_log" >/dev/null 2>&1 &
other_client_pid=$!

base_clients="$(wait_for_base_clients 2)" || {
  echo 'expected two attached tmux clients for base session' >&2
  exit 1
}
client_name="$(printf '%s\n' "$base_clients" | sed -n '1p')"
other_client_name="$(printf '%s\n' "$base_clients" | sed -n '2p')"
[ -n "$client_name" ] || { echo 'expected first base client name' >&2; exit 1; }
[ -n "$other_client_name" ] || { echo 'expected second base client name' >&2; exit 1; }
[ "$client_name" != "$other_client_name" ] || {
  echo 'expected two distinct attached base clients' >&2
  exit 1
}

base_session_id="$(env -u TMUX PATH="$fake_bin:$PATH" tmux display-message -p -t '=base:' '#{session_id}')"
base_popup="$(resolve_popup_session_for_client "$client_name" "$base_dir")"
base_popup_again="$(resolve_popup_session_for_client "$client_name" "$base_dir")"
base_popup_other_client="$(resolve_popup_session_for_client "$other_client_name" "$base_dir")"
base_popup_by_id="$(resolve_popup_session_for_owner "$client_name" "$base_dir" "$base_session_id")"
base_popup_by_target="$(resolve_popup_session_for_owner "$client_name" "$base_dir" '=base')"
project_popup="$(resolve_popup_session_for_owner "$client_name" "$project_dir" project)"
dash_popup="$(resolve_popup_session_for_owner "$client_name" "$work_dir" foo-bar)"
underscore_popup="$(resolve_popup_session_for_owner "$client_name" "$work_dir" foo_bar)"
dash_popup_again="$(resolve_popup_session_for_owner "$client_name" "$work_dir" foo-bar)"
user_named_popup="$(resolve_popup_session_for_owner "$client_name" "$work_dir" __floating-popup-user)"

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

[ "$base_popup_other_client" = "$base_popup" ] || {
  echo "expected different clients in the same tmux session to reuse $base_popup, got: $base_popup_other_client" >&2
  exit 1
}

[ "$base_popup_by_id" = "$base_popup" ] || {
  echo "expected requested owner session id to canonicalize to $base_popup, got: $base_popup_by_id" >&2
  exit 1
}

[ "$base_popup_by_target" = "$base_popup" ] || {
  echo "expected requested owner target =base to canonicalize to $base_popup, got: $base_popup_by_target" >&2
  exit 1
}

[ "$project_popup" != "$base_popup" ] || {
  echo "expected different tmux sessions to get separate popup sessions" >&2
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

[ "$user_named_popup" != '__floating-popup-user' ] || {
  echo 'expected unflagged __floating-popup-user parent session not to be treated as an internal popup session' >&2
  exit 1
}

case "$user_named_popup" in
  __floating-popup-*) ;;
  *)
    echo "expected user-named parent session to still resolve to a managed popup session, got: $user_named_popup" >&2
    exit 1
    ;;
esac

[ "$(popup_path "$base_popup")" = "$base_dir" ] || {
  echo "expected base popup to start in $base_dir, got: $(popup_path "$base_popup")" >&2
  exit 1
}

[ "$(popup_path "$project_popup")" = "$project_dir" ] || {
  echo "expected project popup to start in $project_dir, got: $(popup_path "$project_popup")" >&2
  exit 1
}

kill "$client_pid" "$other_client_pid" 2>/dev/null || true

echo 'ok: popup sessions are keyed by tmux session and keep their own start directories'
