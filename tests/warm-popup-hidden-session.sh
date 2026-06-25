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
sock="tfp_test_warm_popup_hidden.$$.$RANDOM"
client_log="$work_dir/client.log"
script_probe_log="$work_dir/script-probe.log"
fake_bin="$work_dir/bin"
start_dir="$work_dir/start"
mkdir -p "$fake_bin" "$start_dir"

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

popup_session_row() {
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-sessions -F '#{session_name}|#{session_attached}|#{@floating-popup-session}|#{@floating-popup-owner-session-id}|#{@floating-popup-owner-session}' 2>/dev/null \
    | awk -F'|' '$3 == "1" { print; exit }'
}

popup_path_for_session() {
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-panes -t "=$1:" -F '#{pane_current_path}' 2>/dev/null | head -n1
}

popup_client_name() {
  env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}|#{session_name}|#{@floating-popup-session}' 2>/dev/null \
    | awk -F'|' '$3 == "1" { print $1; exit }'
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
"$SCRIPT_BIN" -q -c "env -u TMUX PATH='$fake_bin:$PATH' TERM=xterm-256color tmux attach-session -t base" "$client_log" >/dev/null 2>&1 &
client_pid=$!

client_name="$(wait_for_attached_client)"
[ -n "$client_name" ] || { echo 'no tmux client found' >&2; exit 1; }

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/warm-popup.sh" "$client_name" "$start_dir"

popup_row="$(popup_session_row)"
[ -n "$popup_row" ] || {
  echo 'expected warm-up to create an internal popup session' >&2
  exit 1
}

IFS='|' read -r popup_session attached popup_flag owner_session_id owner_session <<<"$popup_row"
popup_path=''
for _ in 1 2 3 4 5 6 7 8 9 10; do
  popup_path="$(popup_path_for_session "$popup_session")"
  if [ "$popup_path" = "$start_dir" ]; then
    break
  fi
  sleep 1
done

case "$popup_session" in
  __floating-popup-*) ;;
  *)
    echo "expected warm-up session name to use __floating-popup- prefix, got: $popup_session" >&2
    exit 1
    ;;
esac

[ "$popup_flag" = '1' ] || {
  echo "expected popup session flag to be 1, got: $popup_flag" >&2
  exit 1
}

[ "$attached" = '0' ] || {
  echo "expected warm-up session to stay detached, got attached=$attached" >&2
  exit 1
}

[ "$popup_path" = "$start_dir" ] || {
  echo "expected warm-up session to start in $start_dir, got: $popup_path" >&2
  exit 1
}

base_session_id="$(env -u TMUX PATH="$fake_bin:$PATH" tmux display-message -p -t '=base:' '#{session_id}')"
[ "$owner_session_id" = "$base_session_id" ] || {
  echo "expected popup owner session id to be $base_session_id, got: $owner_session_id" >&2
  exit 1
}

[ "$owner_session" = 'base' ] || {
  echo "expected popup owner session to be base, got: $owner_session" >&2
  exit 1
}

[ -z "$(popup_client_name)" ] || {
  echo 'expected warm-up not to create a visible popup client' >&2
  exit 1
}

kill "$client_pid" 2>/dev/null || true

echo 'ok: warm-up creates a hidden detached popup session without opening a popup client'
