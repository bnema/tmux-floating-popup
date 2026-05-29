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

floating_popup_resolve_command() {
  local name="$1" candidate="${2:-}" resolved=""
  if [ -n "$candidate" ]; then
    resolved="$(command -v "$candidate" 2>/dev/null || true)"
    if [ -n "$resolved" ]; then
      printf '%s' "$resolved"
      return 0
    fi
  fi
  floating_popup_require_command "$name"
}

TMUX_BIN="$(floating_popup_resolve_command tmux "${TMUX_BIN:-}")" || _floating_popup_return_or_exit 1

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

floating_popup_set_option() {
  local option="$1" value="$2"
  "$TMUX_BIN" set-option -gq "$option" "$value"
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

floating_popup_current_session() {
  local client_name
  client_name="$(floating_popup_current_client "$@")" || return 1
  "$TMUX_BIN" display-message -p -t "$client_name" '#{client_session}'
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

floating_popup_session_exists() {
  local session_name="$1"
  [ -n "$session_name" ] && "$TMUX_BIN" has-session -t "=$session_name" 2>/dev/null
}

floating_popup_is_internal_session_name() {
  local session_name="$1"
  case "$session_name" in
    __floating-popup-*) return 0 ;;
    *) return 1 ;;
  esac
}

floating_popup_session_flag() {
  printf '@floating-popup-session'
}

floating_popup_owner_option() {
  printf '@floating-popup-owner-client'
}

floating_popup_owner_session_option() {
  printf '@floating-popup-owner-session'
}

floating_popup_session_option() {
  local session_name="$1" option="$2" default_value="${3:-}"
  local value=""
  [ -n "$session_name" ] || {
    printf '%s' "$default_value"
    return 0
  }
  value="$("$TMUX_BIN" show-options -t "$session_name" -qv "$option" 2>/dev/null)" || true
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}

floating_popup_client_is_popup_session() {
  local client_name="$1"
  local flag=""
  client_name="$(floating_popup_current_client "$client_name")" || return 1
  flag="$("$TMUX_BIN" display-message -p -t "$client_name" '#{@floating-popup-session}' 2>/dev/null || true)"
  [ "$flag" = '1' ]
}

floating_popup_owner_client_for_session() {
  local session_name="$1"
  floating_popup_session_option "$session_name" "$(floating_popup_owner_option)" ''
}

floating_popup_owner_session_for_session() {
  local session_name="$1"
  floating_popup_session_option "$session_name" "$(floating_popup_owner_session_option)" ''
}

floating_popup_client_option_suffix() {
  local value="$1"
  local index char suffix="" byte=""

  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    printf -v byte '%02x' "'$char"
    suffix="${suffix}_${byte}"
  done

  printf '%s' "${suffix:-_}"
}

floating_popup_client_session_option() {
  local client_name="$1" owner_session="${2:-}"
  local suffix
  suffix="$(floating_popup_client_option_suffix "$client_name")"
  if [ -n "$owner_session" ]; then
    suffix="${suffix}-$(floating_popup_client_option_suffix "$owner_session")"
  fi
  printf '@floating-popup-client-%s-session' "$suffix"
}

floating_popup_client_marker_option() {
  local client_name="$1"
  printf '@floating-popup-popup-client%s' "$(floating_popup_client_option_suffix "$client_name")"
}

floating_popup_client_pid_option() {
  local client_name="$1"
  printf '@floating-popup-popup-client%s-pid' "$(floating_popup_client_option_suffix "$client_name")"
}

floating_popup_mark_popup_client() {
  local client_name="$1" client_pid="$2"
  [ -n "$client_name" ] || return 1
  [ -n "$client_pid" ] || return 1
  floating_popup_set_option "$(floating_popup_client_marker_option "$client_name")" 1
  floating_popup_set_option "$(floating_popup_client_pid_option "$client_name")" "$client_pid"
}

floating_popup_clear_popup_client() {
  local client_name="$1"
  [ -n "$client_name" ] || return 0
  floating_popup_set_option "$(floating_popup_client_marker_option "$client_name")" ''
  floating_popup_set_option "$(floating_popup_client_pid_option "$client_name")" ''
}

floating_popup_get_client_session() {
  local client_name="$1" owner_session="${2:-}"
  floating_popup_get_option "$(floating_popup_client_session_option "$client_name" "$owner_session")" ''
}

floating_popup_client_exists() {
  local client_name="$1" existing_client=""
  [ -n "$client_name" ] || return 1

  while IFS= read -r existing_client; do
    if [ "$existing_client" = "$client_name" ]; then
      return 0
    fi
  done < <("$TMUX_BIN" list-clients -F '#{client_name}' 2>/dev/null || true)

  return 1
}

floating_popup_client_is_popup_client() {
  local client_name="$1" marker="" expected_pid="" actual_pid=""
  client_name="$(floating_popup_current_client "$client_name")" || return 1
  marker="$(floating_popup_get_option "$(floating_popup_client_marker_option "$client_name")" '')"
  [ "$marker" = '1' ] || return 1
  floating_popup_client_exists "$client_name" || return 1

  expected_pid="$(floating_popup_get_option "$(floating_popup_client_pid_option "$client_name")" '')"
  actual_pid="$("$TMUX_BIN" display-message -p -t "$client_name" '#{client_pid}' 2>/dev/null || true)"
  [ -n "$expected_pid" ] && [ "$actual_pid" = "$expected_pid" ]
}

floating_popup_cleanup_stale_sessions() {
  local session_name="" owner_client="" owner_session="" attached=""

  while IFS='|' read -r session_name owner_client owner_session attached; do
    [ -n "$session_name" ] || continue
    floating_popup_is_internal_session_name "$session_name" || continue
    [ -n "$owner_client" ] || continue
    [ "$attached" = '0' ] || continue

    if ! floating_popup_client_exists "$owner_client"; then
      if [ -n "$owner_session" ]; then
        floating_popup_clear_client_session "$owner_client" "$owner_session"
      fi
      "$TMUX_BIN" kill-session -t "=$session_name" 2>/dev/null || true
    fi
  done < <("$TMUX_BIN" list-sessions -F '#{session_name}|#{@floating-popup-owner-client}|#{@floating-popup-owner-session}|#{session_attached}' 2>/dev/null || true)
}

floating_popup_session_is_owned_by_client_session() {
  local session_name="$1" client_name="$2" owner_session="$3"
  [ -n "$session_name" ] || return 1
  [ -n "$client_name" ] || return 1
  [ -n "$owner_session" ] || return 1
  floating_popup_is_internal_session_name "$session_name" || return 1
  [ "$(floating_popup_session_option "$session_name" "$(floating_popup_session_flag)" '')" = '1' ] || return 1
  [ "$(floating_popup_owner_client_for_session "$session_name")" = "$client_name" ] || return 1
  [ "$(floating_popup_owner_session_for_session "$session_name")" = "$owner_session" ] || return 1
}

floating_popup_set_client_session() {
  local client_name="$1" owner_session="$2" session_name="$3"
  floating_popup_set_option "$(floating_popup_client_session_option "$client_name" "$owner_session")" "$session_name"
}

floating_popup_clear_client_session() {
  local client_name="$1" owner_session="$2"
  floating_popup_set_client_session "$client_name" "$owner_session" ''
}

floating_popup_allocate_session_id() {
  local raw_id next_id
  raw_id="$(floating_popup_get_option @floating-popup-next-id 1)"
  case "$raw_id" in
    ''|*[!0-9]*) raw_id=1 ;;
  esac
  next_id=$((raw_id + 1))
  floating_popup_set_option @floating-popup-next-id "$next_id"
  printf '%s' "$raw_id"
}

floating_popup_prepare_session() {
  local session_name="$1" owner_client="$2" owner_session="$3"
  [ -n "$session_name" ] || return 1
  [ -n "$owner_client" ] || return 1
  [ -n "$owner_session" ] || return 1

  "$TMUX_BIN" set-option -q -t "$session_name" "$(floating_popup_session_flag)" 1
  "$TMUX_BIN" set-option -q -t "$session_name" "$(floating_popup_owner_option)" "$owner_client"
  "$TMUX_BIN" set-option -q -t "$session_name" "$(floating_popup_owner_session_option)" "$owner_session"
  "$TMUX_BIN" set-option -q -t "$session_name" destroy-unattached off
  "$TMUX_BIN" set-option -q -t "$session_name" status off
}

floating_popup_create_session() {
  local owner_client="$1" owner_session="$2" start_path="$3"
  local session_id session_name

  while :; do
    session_id="$(floating_popup_allocate_session_id)"
    session_name="__floating-popup-$session_id"
    if ! floating_popup_session_exists "$session_name"; then
      break
    fi
  done

  "$TMUX_BIN" new-session -d -s "$session_name" -c "$start_path"
  floating_popup_prepare_session "$session_name" "$owner_client" "$owner_session"
  printf '%s' "$session_name"
}

floating_popup_resolve_session_for_client() {
  local client_name="$1" start_path="$2" requested_owner_session="${3:-}"
  local owner_session="" session_name=""

  if floating_popup_client_exists "$client_name"; then
    floating_popup_cleanup_stale_sessions
  fi

  if [ -n "$requested_owner_session" ]; then
    owner_session="$requested_owner_session"
  else
    owner_session="$(floating_popup_current_session "$client_name")" || return 1
  fi
  session_name="$(floating_popup_get_client_session "$client_name" "$owner_session")"
  if [ -n "$session_name" ] && floating_popup_session_exists "$session_name"; then
    if floating_popup_session_is_owned_by_client_session "$session_name" "$client_name" "$owner_session"; then
      floating_popup_prepare_session "$session_name" "$client_name" "$owner_session"
      printf '%s' "$session_name"
      return 0
    fi
    floating_popup_clear_client_session "$client_name" "$owner_session"
  fi

  session_name="$(floating_popup_create_session "$client_name" "$owner_session" "$start_path")" || return 1
  floating_popup_set_client_session "$client_name" "$owner_session" "$session_name"
  printf '%s' "$session_name"
}

floating_popup_hide_popup_session() {
  local client_name="$1"
  client_name="$(floating_popup_current_client "$client_name")" || return 1
  floating_popup_clear_popup_client "$client_name"
  "$TMUX_BIN" detach-client -t "$client_name"
}

floating_popup_destroy_popup_session() {
  local client_name="$1"
  local session_name="" owner_client="" owner_session=""

  client_name="$(floating_popup_current_client "$client_name")" || return 1
  session_name="$(floating_popup_current_session "$client_name")" || return 1
  owner_client="$(floating_popup_owner_client_for_session "$session_name")"
  owner_session="$(floating_popup_owner_session_for_session "$session_name")"

  if [ -n "$owner_client" ] && [ -n "$owner_session" ]; then
    floating_popup_clear_client_session "$owner_client" "$owner_session"
  fi

  floating_popup_clear_popup_client "$client_name"
  "$TMUX_BIN" kill-session -t "$session_name"
}
