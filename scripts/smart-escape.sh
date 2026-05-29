#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'tmux-floating-popup: dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'tmux-floating-popup: pwd not found' >&2; exit 1; }
SCRIPT_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")" && "$PWD_BIN")" || exit 1
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/tmux.sh"

client_name="${1:-}"
client_name="$(floating_popup_current_client "$client_name")" || exit 1

is_interactive_shell() {
  local command_name="$1"
  command_name="${command_name##*/}"
  command_name="${command_name#-}"

  case "$command_name" in
    sh|bash|zsh|fish|dash|ksh|mksh|pdksh|oksh|csh|tcsh|nu|xonsh|elvish)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if floating_popup_client_is_popup_session "$client_name"; then
  pane_command="$($TMUX_BIN display-message -p -t "$client_name" '#{pane_current_command}' 2>/dev/null || true)"
  if is_interactive_shell "$pane_command"; then
    "$SCRIPT_DIR/close-popup.sh" "$client_name"
  else
    "$TMUX_BIN" send-keys -t "$client_name" Escape
  fi
elif floating_popup_client_is_popup_client "$client_name"; then
  floating_popup_hide_popup_session "$client_name"
else
  "$TMUX_BIN" send-keys -t "$client_name" Escape
fi
