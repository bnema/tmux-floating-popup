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
sock="tfp_test_foreign_session.$$.$RANDOM"
client_log="$work_dir/client.log"
script_probe_log="$work_dir/script-probe.log"
fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"

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

popup_client_name() {
  local client_name='' _session_name='' popup_flag=''
  while IFS='|' read -r client_name _session_name popup_flag; do
    if [ "$popup_flag" = '1' ]; then
      printf '%s' "$client_name"
      return 0
    fi
  done < <(env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}|#{session_name}|#{@floating-popup-session}' 2>/dev/null || true)
}

client_exists() {
  local wanted="$1" client_name=''
  while IFS= read -r client_name; do
    [ "$client_name" = "$wanted" ] && return 0
  done < <(env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}' 2>/dev/null || true)
  return 1
}

wait_for() {
  local timeout="$1" message="$2"
  shift 2
  local deadline=$((SECONDS + timeout))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if "$@"; then
      return 0
    fi
    sleep 1
  done
  echo "$message" >&2
  return 1
}

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s base 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux new-session -d -s foreign 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux run-shell "$REPO_DIR/tmux-floating-popup.tmux"
"$SCRIPT_BIN" -q -c "env -u TMUX PATH='$fake_bin:$PATH' TERM=xterm-256color tmux attach-session -t base" "$client_log" >/dev/null 2>&1 &
client_pid=$!
sleep 1

owner_client=''
for _ in 1 2 3 4 5; do
  owner_client="$(env -u TMUX PATH="$fake_bin:$PATH" tmux list-clients -F '#{client_name}' | head -n1)"
  [ -n "$owner_client" ] && break
  sleep 1
done
[ -n "$owner_client" ] || { echo 'no tmux client found' >&2; exit 1; }

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$owner_client" "$work_dir" >/dev/null 2>&1 &
open_popup_pid=$!
sleep 1

popup_client="$(popup_client_name)"
[ -n "$popup_client" ] || { echo 'expected popup client after open' >&2; exit 1; }

env -u TMUX PATH="$fake_bin:$PATH" tmux switch-client -c "$popup_client" -t foreign
sleep 1

current_session="$(env -u TMUX PATH="$fake_bin:$PATH" tmux display-message -p -t "$popup_client" '#{client_session}')"
[ "$current_session" = 'foreign' ] || {
  echo "expected popup client to be switched to foreign, got: $current_session" >&2
  exit 1
}

# Escape from a popup client displaying a user session should close only the popup client.
env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/smart-escape.sh" "$popup_client"
wait_for 5 'expected Escape to detach the popup client from the foreign session' bash -c "! PATH='$fake_bin:$PATH' tmux list-clients -F '#{client_name}' | grep -Fxq '$popup_client'"
wait "$open_popup_pid" || true

env -u TMUX PATH="$fake_bin:$PATH" tmux has-session -t '=foreign' 2>/dev/null || {
  echo 'expected Escape not to kill the foreign user session' >&2
  exit 1
}

# Alt-f from a popup client displaying a user session should also hide only that popup client.
env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$owner_client" "$work_dir" >/dev/null 2>&1 &
reopen_popup_pid=$!
sleep 1
popup_client="$(popup_client_name)"
[ -n "$popup_client" ] || { echo 'expected popup client after reopen' >&2; exit 1; }
env -u TMUX PATH="$fake_bin:$PATH" tmux switch-client -c "$popup_client" -t foreign
sleep 1

env -u TMUX PATH="$fake_bin:$PATH" "$REPO_DIR/scripts/open-popup.sh" "$popup_client" "$work_dir"
wait_for 5 'expected Alt-f to detach the popup client from the foreign session' bash -c "! PATH='$fake_bin:$PATH' tmux list-clients -F '#{client_name}' | grep -Fxq '$popup_client'"
wait "$reopen_popup_pid" || true

env -u TMUX PATH="$fake_bin:$PATH" tmux has-session -t '=foreign' 2>/dev/null || {
  echo 'expected Alt-f not to kill the foreign user session' >&2
  exit 1
}

kill "$client_pid" 2>/dev/null || true

echo 'ok: popup client identity survives switching to a foreign session and only the popup client is closed'
