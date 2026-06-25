#!/usr/bin/env bash
# shellcheck disable=SC2153 # TMUX_BIN is provided by sourced lib/tmux.sh
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
MKTEMP_BIN="$(command -v mktemp 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'tmux-floating-popup: dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'tmux-floating-popup: pwd not found' >&2; exit 1; }
[ -n "$MKTEMP_BIN" ] || { echo 'tmux-floating-popup: mktemp not found' >&2; exit 1; }
SCRIPT_DIR="$(cd "$("$DIRNAME_BIN" "${BASH_SOURCE[0]}")" && "$PWD_BIN")" || exit 1
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/tmux.sh"

cleanup_lock_option='@floating-popup-cleanup-running'
cleanup_pending_option='@floating-popup-cleanup-pending'
cleanup_runner_pid_option='@floating-popup-cleanup-runner-pid'
cleanup_legacy_lock_owner_pid_option='@floating-popup-cleanup-lock-owner-pid'
cleanup_lock_channel="$(floating_popup_lock_channel cleanup sessions)"
cleanup_lock_held=0
cleanup_is_runner=0
cleanup_parent_pid="$$"
cleanup_watchdog_pid=''
cleanup_lock_guard_pid=''
cleanup_lock_guard_dir=''

cleanup_pid_is_alive() {
  local pid="$1"
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid" 2>/dev/null
}

cleanup_reset_lock_guard_state() {
  cleanup_lock_guard_pid=''
  cleanup_lock_guard_dir=''
  cleanup_lock_held=0
}

cleanup_remove_lock_guard_dir() {
  local guard_dir="$cleanup_lock_guard_dir"
  if [ -n "$guard_dir" ] && [ -d "$guard_dir" ]; then
    rm -rf "$guard_dir"
  fi
}

cleanup_acquire_lock() {
  local guard_dir='' guard_pid=''
  [ "$cleanup_lock_held" = '1' ] && return 0

  guard_dir="$("$MKTEMP_BIN" -d "${TMPDIR:-/tmp}/tmux-floating-popup-cleanup.XXXXXX")" || return 1
  cleanup_lock_guard_dir="$guard_dir"

  (
    trap '' HUP
    if ! "$TMUX_BIN" wait-for -L "$cleanup_lock_channel"; then
      : > "$guard_dir/failed"
      exit 1
    fi
    : > "$guard_dir/acquired"
    while kill -0 "$cleanup_parent_pid" 2>/dev/null; do
      [ -f "$guard_dir/release" ] && break
      sleep 1
    done
    "$TMUX_BIN" wait-for -U "$cleanup_lock_channel" 2>/dev/null || true
  ) &
  guard_pid=$!
  cleanup_lock_guard_pid="$guard_pid"

  while :; do
    if [ -f "$guard_dir/acquired" ]; then
      cleanup_lock_held=1
      return 0
    fi
    if [ -f "$guard_dir/failed" ]; then
      wait "$guard_pid" 2>/dev/null || true
      cleanup_remove_lock_guard_dir
      cleanup_reset_lock_guard_state
      return 1
    fi
    if ! kill -0 "$guard_pid" 2>/dev/null; then
      wait "$guard_pid" 2>/dev/null || true
      cleanup_remove_lock_guard_dir
      cleanup_reset_lock_guard_state
      return 1
    fi
    sleep 0.1
  done
}

cleanup_request_guard_release() {
  local guard_dir="$cleanup_lock_guard_dir"
  if [ -n "$guard_dir" ] && [ -d "$guard_dir" ]; then
    : > "$guard_dir/release"
  fi
}

cleanup_release_lock() {
  local guard_pid="$cleanup_lock_guard_pid"

  cleanup_request_guard_release
  if [ -n "$guard_pid" ]; then
    wait "$guard_pid" 2>/dev/null || true
  fi

  cleanup_remove_lock_guard_dir
  cleanup_reset_lock_guard_state
}

cleanup_recover_stale_state_locked() {
  local running pending runner_pid legacy_lock_owner_pid
  running="$(floating_popup_get_option "$cleanup_lock_option" '')"
  pending="$(floating_popup_get_option "$cleanup_pending_option" '')"
  runner_pid="$(floating_popup_get_option "$cleanup_runner_pid_option" '')"
  legacy_lock_owner_pid="$(floating_popup_get_option "$cleanup_legacy_lock_owner_pid_option" '')"

  if [ -n "$legacy_lock_owner_pid" ]; then
    floating_popup_set_option "$cleanup_legacy_lock_owner_pid_option" ''
  fi

  if [ "$running" = '1' ] && ! cleanup_pid_is_alive "$runner_pid"; then
    floating_popup_set_option "$cleanup_lock_option" ''
    floating_popup_set_option "$cleanup_pending_option" ''
    floating_popup_set_option "$cleanup_runner_pid_option" ''
    return 0
  fi

  if [ "$running" != '1' ] && { [ -n "$pending" ] || [ -n "$runner_pid" ]; }; then
    floating_popup_set_option "$cleanup_pending_option" ''
    floating_popup_set_option "$cleanup_runner_pid_option" ''
  fi
}

cleanup_start_watchdog() {
  if [ -n "$cleanup_watchdog_pid" ] && kill -0 "$cleanup_watchdog_pid" 2>/dev/null; then
    return 0
  fi

  (
    local parent_pid="$cleanup_parent_pid"
    local tmux_bin="$TMUX_BIN"
    local lock_option="$cleanup_lock_option"
    local pending_option="$cleanup_pending_option"
    local runner_pid_option="$cleanup_runner_pid_option"
    local legacy_lock_owner_pid_option="$cleanup_legacy_lock_owner_pid_option"
    local lock_channel="$cleanup_lock_channel"
    local current_runner_pid=''

    trap '' HUP
    while kill -0 "$parent_pid" 2>/dev/null; do
      sleep 1
    done

    if "$tmux_bin" wait-for -L "$lock_channel" 2>/dev/null; then
      current_runner_pid="$("$tmux_bin" show-options -gvq "$runner_pid_option" 2>/dev/null || true)"
      if [ "$current_runner_pid" = "$parent_pid" ]; then
        "$tmux_bin" set-option -gq "$lock_option" '' 2>/dev/null || true
        "$tmux_bin" set-option -gq "$pending_option" '' 2>/dev/null || true
        "$tmux_bin" set-option -gq "$runner_pid_option" '' 2>/dev/null || true
      fi
      "$tmux_bin" set-option -gq "$legacy_lock_owner_pid_option" '' 2>/dev/null || true
      "$tmux_bin" wait-for -U "$lock_channel" 2>/dev/null || true
    fi
  ) &

  cleanup_watchdog_pid=$!
}

cleanup_stop_watchdog() {
  local watchdog_pid="$cleanup_watchdog_pid"
  [ -n "$watchdog_pid" ] || return 0
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  cleanup_watchdog_pid=''
}

cleanup_unlock() {
  if [ "$cleanup_lock_held" != '1' ]; then
    cleanup_request_guard_release
    return 0
  fi
  if [ "$cleanup_is_runner" = '1' ]; then
    floating_popup_set_option "$cleanup_lock_option" '' || true
    floating_popup_set_option "$cleanup_pending_option" '' || true
    floating_popup_set_option "$cleanup_runner_pid_option" '' || true
  fi
  cleanup_release_lock
}

cleanup_runner_exit() {
  if [ "$cleanup_lock_held" = '1' ]; then
    cleanup_unlock
    cleanup_stop_watchdog
  else
    cleanup_request_guard_release
  fi
}

cleanup_pre_runner_exit() {
  cleanup_release_lock
  cleanup_stop_watchdog
}

cleanup_signal_exit() {
  local status="$1"
  cleanup_runner_exit
  trap - EXIT INT TERM
  exit "$status"
}

cleanup_release_and_exit() {
  local status="$1"
  cleanup_pre_runner_exit
  trap - EXIT INT TERM
  exit "$status"
}

cleanup_acquire_lock || exit 1
cleanup_start_watchdog
trap cleanup_pre_runner_exit EXIT
trap 'cleanup_release_and_exit 130' INT
trap 'cleanup_release_and_exit 143' TERM
cleanup_recover_stale_state_locked
if [ "$(floating_popup_get_option "$cleanup_lock_option" '')" = '1' ]; then
  floating_popup_set_option "$cleanup_pending_option" 1
  cleanup_release_lock
  cleanup_stop_watchdog
  trap - EXIT INT TERM
  exit 0
fi
cleanup_is_runner=1
floating_popup_set_option "$cleanup_runner_pid_option" "$cleanup_parent_pid"
trap cleanup_runner_exit EXIT
trap 'cleanup_signal_exit 130' INT
trap 'cleanup_signal_exit 143' TERM
floating_popup_set_option "$cleanup_lock_option" 1
floating_popup_set_option "$cleanup_pending_option" ''
cleanup_release_lock

while :; do
  floating_popup_reconcile_sessions

  cleanup_acquire_lock || exit 1
  cleanup_recover_stale_state_locked
  if [ "$(floating_popup_get_option "$cleanup_pending_option" '')" = '1' ]; then
    floating_popup_set_option "$cleanup_pending_option" ''
    cleanup_release_lock
    continue
  fi

  floating_popup_set_option "$cleanup_lock_option" ''
  floating_popup_set_option "$cleanup_pending_option" ''
  floating_popup_set_option "$cleanup_runner_pid_option" ''
  cleanup_is_runner=0
  cleanup_release_lock
  cleanup_stop_watchdog
  trap - EXIT INT TERM
  break
done
