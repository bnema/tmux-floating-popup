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
sock="tfp_test_lock_stable_parent_recreate.$$.$RANDOM"
fake_bin="$work_dir/bin"
block_dir="$work_dir/block"
mkdir -p "$fake_bin" "$block_dir"

cleanup() {
  : > "$block_dir/continue-first" 2>/dev/null || true
  for pid in "${first_pid:-}" "${second_pid:-}"; do
    [ -n "$pid" ] || continue
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
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

marked_popups_for_parent() {
  local parent_id="$1"
  local count=0 session_id='' owner_id='' flag=''
  while IFS= read -r session_id; do
    [ -n "$session_id" ] || continue
    flag="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t "$session_id" -qv @floating-popup-session 2>/dev/null || true)"
    owner_id="$(env -u TMUX PATH="$fake_bin:$PATH" tmux show-options -t "$session_id" -qv @floating-popup-owner-session-id 2>/dev/null || true)"
    if [ "$flag" = '1' ] && [ "$owner_id" = "$parent_id" ]; then
      count=$((count + 1))
    fi
  done < <(env -u TMUX PATH="$fake_bin:$PATH" tmux list-sessions -F '#{session_id}' 2>/dev/null || true)
  printf '%s' "$count"
}

env -u TMUX PATH="$fake_bin:$PATH" tmux -f /dev/null new-session -d -s anchor -c "$work_dir" 'sleep 9999'
env -u TMUX PATH="$fake_bin:$PATH" tmux new-session -d -s base -c "$work_dir" 'sleep 9999'
old_parent_id="$(env -u TMUX PATH="$fake_bin:$PATH" tmux display-message -p -t '=base:' '#{session_id}')"

first_stdout="$work_dir/first.stdout"
second_stdout="$work_dir/second.stdout"

# shellcheck disable=SC2016 # inner bash expands runtime vars/argv after injection
env -u TMUX PATH="$fake_bin:$PATH" bash -c '
  set -euo pipefail
  block_dir="$1"
  repo_dir="$2"
  start_path="$3"
  # shellcheck source=/dev/null
  source "$repo_dir/scripts/lib/tmux.sh"
  original_locked_def="$(declare -f floating_popup_resolve_session_for_client_locked)"
  original_locked_def="${original_locked_def/floating_popup_resolve_session_for_client_locked/original_floating_popup_resolve_session_for_client_locked}"
  eval "$original_locked_def"
  floating_popup_resolve_session_for_client_locked() {
    : > "$block_dir/first-locked"
    while [ ! -f "$block_dir/continue-first" ]; do
      sleep 0.1
    done
    original_floating_popup_resolve_session_for_client_locked "$@"
  }
  floating_popup_resolve_session_for_client_with_mode /dev/pts/test "$start_path" base 1
' bash "$block_dir" "$REPO_DIR" "$work_dir" >"$first_stdout" &
first_pid=$!

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if [ -f "$block_dir/first-locked" ]; then
    break
  fi
  sleep 0.1
done
[ -f "$block_dir/first-locked" ] || {
  echo 'expected first resolve to acquire the session lock before recreate test proceeds' >&2
  exit 1
}

env -u TMUX PATH="$fake_bin:$PATH" tmux kill-session -t =base
env -u TMUX PATH="$fake_bin:$PATH" tmux new-session -d -s base -c "$work_dir" 'sleep 9999'
new_parent_id="$(env -u TMUX PATH="$fake_bin:$PATH" tmux display-message -p -t '=base:' '#{session_id}')"
[ "$new_parent_id" != "$old_parent_id" ] || {
  echo 'test setup failed: recreated parent session kept the same id' >&2
  exit 1
}

# shellcheck disable=SC2016 # inner bash expands runtime vars/argv after injection
env -u TMUX PATH="$fake_bin:$PATH" bash -c '
  set -euo pipefail
  repo_dir="$1"
  start_path="$2"
  # shellcheck source=/dev/null
  source "$repo_dir/scripts/lib/tmux.sh"
  floating_popup_resolve_session_for_client_with_mode /dev/pts/test "$start_path" base 1
' bash "$REPO_DIR" "$work_dir" >"$second_stdout" &
second_pid=$!

sleep 1
if ! kill -0 "$second_pid" 2>/dev/null; then
  echo 'expected second resolve to remain blocked on the stable session lock during same-name parent recreation' >&2
  echo "first resolved: $(cat "$first_stdout" 2>/dev/null || true)" >&2
  echo "second resolved: $(cat "$second_stdout" 2>/dev/null || true)" >&2
  exit 1
fi

[ "$(marked_popups_for_parent "$new_parent_id")" = '0' ] || {
  echo 'expected no popup session to be created before the first locked resolve continues' >&2
  exit 1
}

: > "$block_dir/continue-first"
wait "$first_pid"
wait "$second_pid"

remaining_count="$(marked_popups_for_parent "$new_parent_id")"
[ "$remaining_count" = '1' ] || {
  echo "expected exactly one popup session for recreated parent after serialized resolves, got: $remaining_count" >&2
  exit 1
}

first_session="$(cat "$first_stdout")"
second_session="$(cat "$second_stdout")"
[ "$first_session" = "$second_session" ] || {
  echo "expected both resolves to return the same popup session, got first=$first_session second=$second_session" >&2
  exit 1
}

echo 'ok: public resolve stays serialized across same-name parent recreation'
