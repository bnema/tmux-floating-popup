#!/usr/bin/env bash
# Strict mode is intentionally not enabled here because this file is sourced by
# other scripts and must not silently change the caller's shell options.
# tmux-floating-popup — shared tmux helpers

_floating_popup_return_or_exit() {
  local code="${1:-1}"
  if (return 0 2>/dev/null); then
    return "$code"
  fi
  exit "$code"
}

floating_popup_require_command() {
  local name="$1"
  local resolved=""
  resolved="$(command -v "$name" 2>/dev/null || true)"
  if [ -z "$resolved" ]; then
    echo "tmux-floating-popup: required command not found: $name" >&2
    return 1
  fi
  printf '%s' "$resolved"
}

if [ -z "${TMUX_BIN:-}" ]; then
  TMUX_BIN="$(floating_popup_require_command tmux)" || _floating_popup_return_or_exit 1
fi

floating_popup_get_option() {
  local option="$1" default_value="${2:-}"
  local value
  value="$("$TMUX_BIN" show-options -gvq "$option" 2>/dev/null)" || true
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}

floating_popup_current_client() {
  if [ $# -ge 1 ] && [ -n "$1" ]; then
    printf '%s' "$1"
  elif [ -n "${TMUX:-}" ]; then
    "$TMUX_BIN" display-message -p '#{client_name}'
  else
    echo 'tmux-floating-popup: no tmux client available' >&2
    return 1
  fi
}

floating_popup_current_path() {
  if [ $# -ge 1 ] && [ -n "$1" ]; then
    printf '%s' "$1"
  elif [ -n "${TMUX:-}" ]; then
    "$TMUX_BIN" display-message -p '#{pane_current_path}'
  else
    echo 'tmux-floating-popup: no tmux pane path available' >&2
    return 1
  fi
}

floating_popup_session_name() {
  floating_popup_get_option @floating-popup-session-name tmux-floating-popup
}

floating_popup_width() {
  floating_popup_get_option @floating-popup-width 80%
}

floating_popup_height() {
  floating_popup_get_option @floating-popup-height 80%
}

floating_popup_title() {
  floating_popup_get_option @floating-popup-title 'Floating Popup'
}

floating_popup_attach_command() {
  local session_name="$1"
  local start_path="$2"
  local command=""
  printf -v command 'tmux new-session -A -s %q -c %q' "$session_name" "$start_path"
  printf '%s' "$command"
}
