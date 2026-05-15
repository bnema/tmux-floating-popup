#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
GREP_BIN="$(command -v grep 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'tmux-floating-popup: dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'tmux-floating-popup: pwd not found' >&2; exit 1; }
[ -n "$TMUX_BIN" ] || { echo 'tmux-floating-popup: tmux not found' >&2; exit 1; }
[ -n "$GREP_BIN" ] || { echo 'tmux-floating-popup: grep not found' >&2; exit 1; }
PLUGIN_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")" && "$PWD_BIN")" || exit 1
SCRIPTS_DIR="$PLUGIN_DIR/scripts"
OPEN_SCRIPT="$SCRIPTS_DIR/open-popup.sh"
CLOSE_SCRIPT="$SCRIPTS_DIR/close-popup.sh"
LEGACY_POPUP_KEY_TABLE='floating-popup'

set_default() {
  local option="$1" default_value="$2"
  if [ -z "$("$TMUX_BIN" show-options -gvq "$option" 2>/dev/null)" ]; then
    "$TMUX_BIN" set-option -gq "$option" "$default_value"
  fi
}

binding_belongs_to_plugin() {
  local table="$1" key="$2" marker="$3" binding
  [ -n "$table" ] || return 1
  [ -n "$key" ] || return 1
  [ -n "$marker" ] || return 1
  binding="$("$TMUX_BIN" list-keys -T "$table" "$key" 2>/dev/null || true)"
  [ -n "$binding" ] && printf '%s\n' "$binding" | "$GREP_BIN" -Fq "$marker"
}

unbind_plugin_binding() {
  local table="$1" key="$2" marker="$3"
  [ -n "$key" ] || return 0
  if binding_belongs_to_plugin "$table" "$key" "$marker"; then
    "$TMUX_BIN" unbind-key -T "$table" "$key" 2>/dev/null || true
  fi
}

main() {
  set_default @floating-popup-key M-f
  set_default @floating-popup-width 80%
  set_default @floating-popup-height 80%
  set_default @floating-popup-session-name tmux-floating-popup
  set_default @floating-popup-title 'Floating Popup'
  set_default @floating-popup-next-id 1

  local popup_key previous_key quoted_open_script quoted_close_script
  popup_key="$("$TMUX_BIN" show-options -gvq @floating-popup-key)"
  previous_key="$("$TMUX_BIN" show-options -gvq @floating-popup-bound-key 2>/dev/null || true)"
  printf -v quoted_open_script '%q' "$OPEN_SCRIPT"
  printf -v quoted_close_script '%q' "$CLOSE_SCRIPT"

  if [ -n "$previous_key" ] && [ "$previous_key" != "$popup_key" ]; then
    unbind_plugin_binding root "$previous_key" "$OPEN_SCRIPT"
    "$TMUX_BIN" unbind-key -T popup "$previous_key" 2>/dev/null || true
    "$TMUX_BIN" unbind-key -T "$LEGACY_POPUP_KEY_TABLE" "$previous_key" 2>/dev/null || true
  fi

  "$TMUX_BIN" unbind-key -T popup "$popup_key" 2>/dev/null || true
  "$TMUX_BIN" unbind-key -T "$LEGACY_POPUP_KEY_TABLE" "$popup_key" 2>/dev/null || true
  "$TMUX_BIN" unbind-key -T "$LEGACY_POPUP_KEY_TABLE" Escape 2>/dev/null || true

  "$TMUX_BIN" bind-key -T root "$popup_key" \
    run-shell "$quoted_open_script #{q:client_name} #{q:pane_current_path}"
  "$TMUX_BIN" bind-key -T root Escape \
    if-shell -F '#{==:#{@floating-popup-session},1}' \
      "run-shell \"$quoted_close_script #{q:client_name}\"" \
      'send-keys Escape'
  "$TMUX_BIN" set-option -gq @floating-popup-bound-key "$popup_key"
}

main
