#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
GREP_BIN="$(command -v grep 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
[ -n "$GREP_BIN" ] || { echo 'grep not found' >&2; exit 1; }
REPO_DIR="$(cd "$("$DIRNAME_BIN" "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

sock="tfp_test_cleanup_hooks.$$.$RANDOM"
cleanup() {
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
}
trap cleanup EXIT

show_hook() {
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" show-hooks -g "$1" 2>/dev/null || true
}

cleanup_hook_count() {
  local hook_name="$1"
  show_hook "$hook_name" | "$GREP_BIN" -Fc 'scripts/cleanup-popup-sessions.sh' || true
}

wait_for_cleanup_hook() {
  local hook_name="$1" hook_value=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    hook_value="$(show_hook "$hook_name")"
    if printf '%s\n' "$hook_value" | "$GREP_BIN" -Fq 'scripts/cleanup-popup-sessions.sh'; then
      printf '%s' "$hook_value"
      return 0
    fi
    sleep 1
  done
  return 1
}

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
env -u TMUX "$REAL_TMUX_BIN" -f /dev/null -L "$sock" new-session -d -s base 'sleep 9999'

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" run-shell "$REPO_DIR/tmux-floating-popup.tmux"
session_closed_hook="$(wait_for_cleanup_hook session-closed)"
client_detached_hook="$(wait_for_cleanup_hook client-detached)"
initial_session_closed_count="$(cleanup_hook_count session-closed)"
initial_client_detached_count="$(cleanup_hook_count client-detached)"

printf '%s\n%s\n' "$session_closed_hook" "$client_detached_hook" | "$GREP_BIN" -Fq 'scripts/cleanup-popup-sessions.sh' || {
  echo 'expected cleanup hooks to reference scripts/cleanup-popup-sessions.sh' >&2
  exit 1
}

[ "$initial_session_closed_count" -eq 1 ] || {
  echo "expected session-closed cleanup hook to be installed once; found $initial_session_closed_count reference(s)" >&2
  exit 1
}

[ "$initial_client_detached_count" -eq 1 ] || {
  echo "expected client-detached cleanup hook to be installed once; found $initial_client_detached_count reference(s)" >&2
  exit 1
}

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" run-shell "$REPO_DIR/tmux-floating-popup.tmux"
reloaded_session_closed_hook="$(wait_for_cleanup_hook session-closed)"
reloaded_client_detached_hook="$(wait_for_cleanup_hook client-detached)"
reloaded_session_closed_count="$(cleanup_hook_count session-closed)"
reloaded_client_detached_count="$(cleanup_hook_count client-detached)"

[ "$reloaded_session_closed_count" -eq 1 ] || {
  echo "expected session-closed cleanup hook reload to stay single; found $reloaded_session_closed_count reference(s)" >&2
  exit 1
}

[ "$reloaded_client_detached_count" -eq 1 ] || {
  echo "expected client-detached cleanup hook reload to stay single; found $reloaded_client_detached_count reference(s)" >&2
  exit 1
}

printf '%s\n%s\n' "$reloaded_session_closed_hook" "$reloaded_client_detached_hook" | "$GREP_BIN" -Fq 'scripts/cleanup-popup-sessions.sh' || {
  echo 'expected cleanup hooks to remain installed after reload' >&2
  exit 1
}

echo 'ok: cleanup hooks are installed once and reload without duplicates'
