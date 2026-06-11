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
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

sock="tfp_test_warmup_hooks.$$.$RANDOM"
cleanup() {
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
}
trap cleanup EXIT

show_hook() {
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" show-hooks -g "$1" 2>/dev/null || true
}

wait_for_hook_contains() {
  local hook_name="$1" needle="$2" hook_value=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    hook_value="$(show_hook "$hook_name")"
    if printf '%s\n' "$hook_value" | "$GREP_BIN" -Fq "$needle"; then
      printf '%s' "$hook_value"
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_hook_absent() {
  local hook_name="$1" needle="$2" hook_value=''
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    hook_value="$(show_hook "$hook_name")"
    if ! printf '%s\n' "$hook_value" | "$GREP_BIN" -Fq "$needle"; then
      printf '%s' "$hook_value"
      return 0
    fi
    sleep 1
  done
  return 1
}

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
env -u TMUX "$REAL_TMUX_BIN" -f /dev/null -L "$sock" new-session -d -s base 'sleep 9999'

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" set-option -gq @floating-popup-warmup on
env -u TMUX "$REAL_TMUX_BIN" -L "$sock" run-shell "$REPO_DIR/tmux-floating-popup.tmux"

attached_hook="$(wait_for_hook_contains client-attached 'scripts/warm-popup.sh')"
session_changed_hook="$(wait_for_hook_contains client-session-changed 'scripts/warm-popup.sh')"

printf '%s\n' "$attached_hook" | "$GREP_BIN" -Fq 'scripts/warm-popup.sh' || {
  echo 'expected warm-up hook on client-attached when @floating-popup-warmup is on' >&2
  exit 1
}

printf '%s\n' "$session_changed_hook" | "$GREP_BIN" -Fq 'scripts/warm-popup.sh' || {
  echo 'expected warm-up hook on client-session-changed when @floating-popup-warmup is on' >&2
  exit 1
}

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" run-shell "$REPO_DIR/tmux-floating-popup.tmux"
reattached_hook="$(wait_for_hook_contains client-attached 'scripts/warm-popup.sh')"
resession_changed_hook="$(wait_for_hook_contains client-session-changed 'scripts/warm-popup.sh')"

[ "$(printf '%s\n' "$reattached_hook" | "$GREP_BIN" -Fc 'scripts/warm-popup.sh')" -eq 1 ] || {
  echo 'expected warm-up hook reload to stay single on client-attached' >&2
  exit 1
}

[ "$(printf '%s\n' "$resession_changed_hook" | "$GREP_BIN" -Fc 'scripts/warm-popup.sh')" -eq 1 ] || {
  echo 'expected warm-up hook reload to stay single on client-session-changed' >&2
  exit 1
}

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" set-option -gq @floating-popup-warmup off
env -u TMUX "$REAL_TMUX_BIN" -L "$sock" run-shell "$REPO_DIR/tmux-floating-popup.tmux"

attached_hook_off="$(wait_for_hook_absent client-attached 'scripts/warm-popup.sh')"
session_changed_hook_off="$(wait_for_hook_absent client-session-changed 'scripts/warm-popup.sh')"

if printf '%s\n' "$attached_hook_off" | "$GREP_BIN" -Fq 'scripts/warm-popup.sh'; then
  echo 'expected warm-up hook to be removed from client-attached when disabled' >&2
  exit 1
fi

if printf '%s\n' "$session_changed_hook_off" | "$GREP_BIN" -Fq 'scripts/warm-popup.sh'; then
  echo 'expected warm-up hook to be removed from client-session-changed when disabled' >&2
  exit 1
fi

echo 'ok: warm-up hooks are installed once when enabled and removed cleanly when disabled'
