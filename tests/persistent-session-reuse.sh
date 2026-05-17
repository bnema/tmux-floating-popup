#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
AWK_BIN="$(command -v awk 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
[ -n "$AWK_BIN" ] || { echo 'awk not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_persistent_reuse"
client_log="$work_dir/client.log"
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

popup_session_name() {
  local session_name='' popup_flag=''
  while IFS='|' read -r session_name popup_flag; do
    if [ "$popup_flag" = '1' ]; then
      printf '%s' "$session_name"
      return 0
    fi
  done < <(env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{session_name}|#{@floating-popup-session}')
}

popup_session_client() {
  local client_name='' session_name='' popup_flag=''
  while IFS='|' read -r client_name session_name popup_flag; do
    if [ "$popup_flag" = '1' ]; then
      printf '%s' "$client_name"
      return 0
    fi
  done < <(env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}|#{session_name}|#{@floating-popup-session}')
}

wait_for_popup_client() {
  local popup_session="" popup_client=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    popup_session="$(popup_session_name)"
    popup_client="$(popup_session_client)"
    if [ -n "$popup_session" ] && [ -n "$popup_client" ]; then
      printf '%s	%s' "$popup_session" "$popup_client"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_no_popup_client() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if [ -z "$(popup_session_client)" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s base 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux run-shell "$REPO_DIR/tmux-floating-popup.tmux"
script -q -c "env -u TMUX PATH='$fake_bin:$PATH' TERM=xterm-256color tmux attach-session -t base" "$client_log" >/dev/null 2>&1 &
client_pid=$!
sleep 1

client_name="$(env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}' | head -n1)"
[ -n "$client_name" ] || { echo 'no tmux client found' >&2; exit 1; }

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$client_name" "$work_dir" >/dev/null 2>&1 &
open_popup_pid=$!
sleep 1

first_popup="$(wait_for_popup_client)" || {
  echo 'expected popup client after first Alt-f open' >&2
  exit 1
}
first_session="${first_popup%%$'\t'*}"
popup_client="${first_popup#*$'\t'}"

status_option="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t "$first_session" -qv status 2>/dev/null || true)"
[ "$status_option" = 'off' ] || {
  echo "expected popup session status to be off, got: $status_option" >&2
  exit 1
}

owner_client="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t "$first_session" -qv @floating-popup-owner-client 2>/dev/null || true)"
[ "$owner_client" = "$client_name" ] || {
  echo "expected popup owner client to be $client_name, got: $owner_client" >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$popup_client" "$work_dir"
wait "$open_popup_pid" || true
wait_for_no_popup_client || {
  echo 'expected popup client to detach after Alt-f hide' >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" tmux has-session -t "=$first_session" 2>/dev/null || {
  echo 'expected popup session to survive Alt-f hide' >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$client_name" "$work_dir" >/dev/null 2>&1 &
reopen_popup_pid=$!
sleep 1

reopened_popup="$(wait_for_popup_client)" || {
  echo 'expected popup client after reopening with Alt-f' >&2
  exit 1
}
reopened_session="${reopened_popup%%$'\t'*}"
reopened_popup_client="${reopened_popup#*$'\t'}"
[ "$reopened_session" = "$first_session" ] || {
  echo "expected Alt-f reopen to reuse $first_session, got: $reopened_session" >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/close-popup.sh" "$reopened_popup_client"
wait "$reopen_popup_pid" || true
wait_for_no_popup_client || {
  echo 'expected popup client to disappear after Esc close' >&2
  exit 1
}

if env -u TMUX PATH="$fake_bin:$PATH" tmux has-session -t "=$first_session" 2>/dev/null; then
  echo 'expected Esc close to destroy the popup session' >&2
  exit 1
fi

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$client_name" "$work_dir" >/dev/null 2>&1 &
new_popup_pid=$!
sleep 1

second_popup="$(wait_for_popup_client)" || {
  echo 'expected popup client after creating a fresh session' >&2
  exit 1
}
second_session="${second_popup%%$'\t'*}"
second_popup_client="${second_popup#*$'\t'}"
[ "$second_session" != "$first_session" ] || {
  echo "expected a fresh popup session after Esc close, but reused: $second_session" >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/close-popup.sh" "$second_popup_client"
wait "$new_popup_pid" || true
kill "$client_pid" 2>/dev/null || true

echo 'ok: Alt-f reuses the hidden popup session and Esc destroys it so the next open gets a new session id'
