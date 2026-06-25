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
  "$TMUX_BIN" display-message -p -c "$client_name" '#{client_session}'
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

floating_popup_warmup() {
  floating_popup_get_option @floating-popup-warmup off
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

floating_popup_owner_session_option() {
  printf '@floating-popup-owner-session'
}

floating_popup_owner_session_id_option() {
  printf '@floating-popup-owner-session-id'
}

floating_popup_legacy_parent_session_id_option() {
  printf '@floating-popup-parent-session-id'
}

floating_popup_start_path_option() {
  printf '@floating-popup-start-path'
}

floating_popup_activated_option() {
  printf '@floating-popup-activated'
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

floating_popup_owner_session_id_for_session() {
  local session_name="$1" value=""
  value="$(floating_popup_session_option "$session_name" "$(floating_popup_owner_session_id_option)" '')"
  if [ -z "$value" ]; then
    value="$(floating_popup_session_option "$session_name" "$(floating_popup_legacy_parent_session_id_option)" '')"
  fi
  printf '%s' "$value"
}

floating_popup_start_path_for_session() {
  local session_name="$1"
  floating_popup_session_option "$session_name" "$(floating_popup_start_path_option)" ''
}

floating_popup_activation_state_for_session() {
  local session_name="$1"
  floating_popup_session_option "$session_name" "$(floating_popup_activated_option)" 1
}

floating_popup_session_has_been_activated() {
  local session_name="$1"
  [ "$(floating_popup_activation_state_for_session "$session_name")" = '1' ]
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

floating_popup_client_marker_option() {
  local client_name="$1"
  printf '@floating-popup-client-marker%s' "$(floating_popup_client_option_suffix "$client_name")"
}

floating_popup_client_pid_option() {
  local client_name="$1"
  printf '@floating-popup-client%s-pid' "$(floating_popup_client_option_suffix "$client_name")"
}

floating_popup_lock_channel() {
  local client_name="$1" owner_session="$2"
  printf 'floating-popup-lock%s' "$(floating_popup_client_option_suffix "$client_name-$owner_session")"
}

floating_popup_session_id_for_target() {
  local target="$1" session_name=""
  [ -n "$target" ] || return 1
  case "$target" in
    =*)
      session_name="${target#=}"
      "$TMUX_BIN" display-message -p -t "=$session_name:" '#{session_id}' 2>/dev/null
      ;;
    *)
      "$TMUX_BIN" display-message -p -t "$target" '#{session_id}' 2>/dev/null
      ;;
  esac
}

floating_popup_current_session_id() {
  local session_name=''
  session_name="$(floating_popup_current_session "$@")" || return 1
  floating_popup_session_id_for_target "=$session_name"
}

floating_popup_session_is_internal_popup() {
  local session_name="$1"
  [ -n "$session_name" ] || return 1
  floating_popup_is_internal_session_name "$session_name" || return 1
  [ "$(floating_popup_session_option "$session_name" "$(floating_popup_session_flag)" '')" = '1' ]
}

floating_popup_parent_session_exists() {
  local session_id="$1" session_name="${2:-}" existing_id="" existing_name=""

  while IFS='|' read -r existing_id existing_name; do
    [ -n "$existing_id" ] || continue
    floating_popup_session_is_internal_popup "$existing_name" && continue
    if [ -n "$session_id" ]; then
      [ "$existing_id" = "$session_id" ] && return 0
    elif [ -n "$session_name" ] && [ "$existing_name" = "$session_name" ]; then
      return 0
    fi
  done < <("$TMUX_BIN" list-sessions -F '#{session_id}|#{session_name}' 2>/dev/null || true)

  return 1
}

floating_popup_session_name_for_target() {
  local target="$1" session_name=''
  [ -n "$target" ] || return 1
  case "$target" in
    =*)
      session_name="${target#=}"
      floating_popup_session_exists "$session_name" || return 1
      ;;
    *)
      session_name="$("$TMUX_BIN" display-message -p -t "$target" '#{session_name}' 2>/dev/null || true)"
      ;;
  esac
  [ -n "$session_name" ] || return 1
  floating_popup_session_is_internal_popup "$session_name" && return 1
  printf '%s' "$session_name"
}

floating_popup_live_owner_session_id() {
  local owner_session="$1" owner_session_id="${2:-}" live_owner_session_id='' live_owner_session_name=''

  if [ -n "$owner_session_id" ] && floating_popup_parent_session_exists "$owner_session_id"; then
    printf '%s' "$owner_session_id"
    return 0
  fi

  [ -n "$owner_session" ] || return 1
  live_owner_session_name="$(floating_popup_session_name_for_target "$owner_session" 2>/dev/null || true)"
  [ -n "$live_owner_session_name" ] || return 1
  live_owner_session_id="$(floating_popup_session_id_for_target "=$live_owner_session_name" 2>/dev/null || true)"
  [ -n "$live_owner_session_id" ] || return 1
  printf '%s' "$live_owner_session_id"
}

floating_popup_mark_popup_client() {
  local client_name="$1" client_pid="$2"
  [ -n "$client_name" ] || return 1
  [ -n "$client_pid" ] || return 1
  case "$client_pid" in
    *[!0-9]*) return 1 ;;
  esac
  floating_popup_set_option "$(floating_popup_client_marker_option "$client_name")" 1
  floating_popup_set_option "$(floating_popup_client_pid_option "$client_name")" "$client_pid"
}

floating_popup_clear_popup_client() {
  local client_name="$1"
  [ -n "$client_name" ] || return 0
  floating_popup_set_option "$(floating_popup_client_marker_option "$client_name")" ''
  floating_popup_set_option "$(floating_popup_client_pid_option "$client_name")" ''
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

floating_popup_cleanup_stale_popup_clients() {
  local live_options=$'\n' client_name="" marker_option="" pid_option="" option_line="" option_name=""

  while IFS= read -r client_name; do
    [ -n "$client_name" ] || continue
    marker_option="$(floating_popup_client_marker_option "$client_name")"
    pid_option="$(floating_popup_client_pid_option "$client_name")"
    if floating_popup_client_is_popup_client "$client_name"; then
      live_options="${live_options}${marker_option}"$'\n'"${pid_option}"$'\n'
    else
      floating_popup_clear_popup_client "$client_name"
    fi
  done < <("$TMUX_BIN" list-clients -F '#{client_name}' 2>/dev/null || true)

  while IFS= read -r option_line; do
    option_name="${option_line%% *}"
    case "$option_name" in
      @floating-popup-client-marker_*|@floating-popup-client_*-pid)
        case "$live_options" in
          *$'\n'"$option_name"$'\n'*) ;;
          *) floating_popup_set_option "$option_name" '' ;;
        esac
        ;;
    esac
  done < <("$TMUX_BIN" show-options -g 2>/dev/null || true)
}

floating_popup_popup_internal_id() {
  local session_name="$1"
  case "$session_name" in
    __floating-popup-[0-9]*) printf '%s' "${session_name#__floating-popup-}" ;;
    *) printf '999999999' ;;
  esac
}

floating_popup_session_rank() {
  local session_name="$1" attached="$2" activated="$3" internal_id=""
  internal_id="$(floating_popup_popup_internal_id "$session_name")"
  case "$internal_id" in
    ''|*[!0-9]*) internal_id=999999999 ;;
  esac
  # Lower rank is preferred: attached first, then activated, then lowest internal id.
  printf '%s|%s|%09d' "$([ "$attached" != '0' ] && printf 0 || printf 1)" "$([ "$activated" = '1' ] && printf 0 || printf 1)" "$internal_id"
}

floating_popup_reconcile_sessions() {
  local requested_owner_session_id="${1:-}" requested_owner_session="${2:-}" requested_parent_key="" requested_session_id=""
  local session_id="" session_name="" flag="" owner_session_id="" legacy_owner_session_id="" owner_session="" attached="" activated=""
  local parent_key="" candidate_rank="" duplicate_sessions=$'\n'
  local field_sep=$'\037' kept_rows="" next_kept_rows="" found=""
  local kept_parent_key="" kept_session_id="" kept_rank="" duplicate_session_id="" duplicate_session_name=""

  if [ -z "$requested_owner_session_id" ] && [ -n "$requested_owner_session" ]; then
    requested_owner_session_id="$(floating_popup_session_id_for_target "=$requested_owner_session" 2>/dev/null || true)"
  fi
  requested_parent_key="${requested_owner_session_id:-$requested_owner_session}"
  floating_popup_cleanup_stale_popup_clients

  while IFS='|' read -r session_id attached session_name; do
    [ -n "$session_id" ] || continue
    [ -n "$session_name" ] || continue
    floating_popup_is_internal_session_name "$session_name" || continue

    flag="$(floating_popup_session_option "$session_id" "$(floating_popup_session_flag)" '')"
    [ "$flag" = '1' ] || continue
    owner_session_id="$(floating_popup_session_option "$session_id" "$(floating_popup_owner_session_id_option)" '')"
    legacy_owner_session_id="$(floating_popup_session_option "$session_id" "$(floating_popup_legacy_parent_session_id_option)" '')"
    owner_session="$(floating_popup_session_option "$session_id" "$(floating_popup_owner_session_option)" '')"
    activated="$(floating_popup_session_option "$session_id" "$(floating_popup_activated_option)" '')"

    [ -n "$owner_session_id" ] || owner_session_id="$legacy_owner_session_id"
    if [ -z "$owner_session_id" ]; then
      # Legacy popup sessions without a stable parent session id cannot be
      # safely re-parented after same-name parent recreation, so treat them as
      # invalid and remove them instead of adopting by owner session name.
      "$TMUX_BIN" kill-session -t "$session_id" 2>/dev/null || true
      continue
    fi

    if ! floating_popup_parent_session_exists "$owner_session_id" "$owner_session"; then
      "$TMUX_BIN" kill-session -t "$session_id" 2>/dev/null || true
      continue
    fi

    parent_key="$owner_session_id"
    candidate_rank="$(floating_popup_session_rank "$session_name" "$attached" "$activated")"
    found=0
    next_kept_rows=""
    while IFS="$field_sep" read -r kept_parent_key kept_session_id kept_rank; do
      [ -n "$kept_parent_key" ] || continue
      if [ "$kept_parent_key" = "$parent_key" ]; then
        found=1
        if [[ "$candidate_rank" < "$kept_rank" ]]; then
          duplicate_sessions="${duplicate_sessions}${kept_session_id}"$'\n'
          next_kept_rows="${next_kept_rows}${parent_key}${field_sep}${session_id}${field_sep}${candidate_rank}"$'\n'
          [ "$parent_key" = "$requested_parent_key" ] && requested_session_id="$session_id"
        else
          duplicate_sessions="${duplicate_sessions}${session_id}"$'\n'
          next_kept_rows="${next_kept_rows}${kept_parent_key}${field_sep}${kept_session_id}${field_sep}${kept_rank}"$'\n'
          [ "$parent_key" = "$requested_parent_key" ] && requested_session_id="$kept_session_id"
        fi
      else
        next_kept_rows="${next_kept_rows}${kept_parent_key}${field_sep}${kept_session_id}${field_sep}${kept_rank}"$'\n'
      fi
    done <<< "$kept_rows"

    if [ "$found" = '0' ]; then
      kept_rows="${kept_rows}${parent_key}${field_sep}${session_id}${field_sep}${candidate_rank}"$'\n'
      [ "$parent_key" = "$requested_parent_key" ] && requested_session_id="$session_id"
    else
      kept_rows="$next_kept_rows"
    fi
  done < <("$TMUX_BIN" list-sessions -F '#{session_id}|#{session_attached}|#{session_name}' 2>/dev/null || true)

  while IFS= read -r duplicate_session_id; do
    [ -n "$duplicate_session_id" ] || continue
    duplicate_session_name="$("$TMUX_BIN" display-message -p -t "$duplicate_session_id:" '#{session_name}' 2>/dev/null || true)"
    [ -n "$duplicate_session_name" ] || continue
    if [ "$(floating_popup_session_option "$duplicate_session_id" "$(floating_popup_session_flag)" '')" = '1' ] \
      && floating_popup_is_internal_session_name "$duplicate_session_name"; then
      "$TMUX_BIN" kill-session -t "$duplicate_session_id" 2>/dev/null || true
    fi
  done <<< "$duplicate_sessions"

  if [ -n "$requested_session_id" ]; then
    "$TMUX_BIN" display-message -p -t "$requested_session_id:" '#{session_name}' 2>/dev/null || true
  fi
}

floating_popup_cleanup_stale_sessions() {
  floating_popup_reconcile_sessions
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

floating_popup_detect_session_start_path() {
  local session_name="$1"
  "$TMUX_BIN" list-panes -t "=$session_name:" -F '#{pane_current_path}' 2>/dev/null | head -n1
}

floating_popup_prepare_session() {
  local session_name="$1" owner_session="$2" start_path="${3:-}" activated="${4:-1}" owner_session_id="${5:-}"
  [ -n "$session_name" ] || return 1
  [ -n "$owner_session" ] || return 1

  owner_session_id="$(floating_popup_live_owner_session_id "$owner_session" "$owner_session_id")" || return 1
  [ -n "$owner_session_id" ] || return 1

  if [ -z "$start_path" ]; then
    start_path="$(floating_popup_detect_session_start_path "$session_name")"
  fi

  "$TMUX_BIN" set-option -q -t "$session_name" "$(floating_popup_owner_session_option)" "$owner_session"
  "$TMUX_BIN" set-option -q -t "$session_name" "$(floating_popup_owner_session_id_option)" "$owner_session_id"
  "$TMUX_BIN" set-option -q -t "$session_name" "$(floating_popup_start_path_option)" "$start_path"
  "$TMUX_BIN" set-option -q -t "$session_name" "$(floating_popup_activated_option)" "$activated"
  "$TMUX_BIN" set-option -q -t "$session_name" destroy-unattached off
  "$TMUX_BIN" set-option -q -t "$session_name" status off
  "$TMUX_BIN" set-option -q -t "$session_name" "$(floating_popup_session_flag)" 1
}

floating_popup_create_session() {
  local owner_session="$1" start_path="$2" activated="${3:-1}" owner_session_id="${4:-}"
  local session_id session_name

  while :; do
    session_id="$(floating_popup_allocate_session_id)"
    session_name="__floating-popup-$session_id"
    if ! floating_popup_session_exists "$session_name"; then
      break
    fi
  done

  "$TMUX_BIN" new-session -d -s "$session_name" -c "$start_path" || return 1
  if ! floating_popup_prepare_session "$session_name" "$owner_session" "$start_path" "$activated" "$owner_session_id"; then
    "$TMUX_BIN" kill-session -t "=$session_name" 2>/dev/null || true
    return 1
  fi
  printf '%s' "$session_name"
}

floating_popup_destroy_popup_session_by_name() {
  local session_name="$1"
  [ -n "$session_name" ] || return 0
  if floating_popup_session_exists "$session_name"; then
    "$TMUX_BIN" kill-session -t "=$session_name" 2>/dev/null || true
  fi
}

floating_popup_replace_inactive_session_for_path() {
  local session_name="$1" owner_session="$2" start_path="$3" activate="$4" owner_session_id="${5:-}"
  [ -n "$session_name" ] || return 1
  floating_popup_destroy_popup_session_by_name "$session_name"
  session_name="$(floating_popup_create_session "$owner_session" "$start_path" "$activate" "$owner_session_id")" || return 1
  printf '%s' "$session_name"
}

floating_popup_finalize_session_resolution() {
  local session_name="$1" owner_session="$2" activate="$3" owner_session_id="${4:-}"
  local activated_state start_path
  [ -n "$session_name" ] || return 1
  start_path="$(floating_popup_start_path_for_session "$session_name")"
  activated_state="$(floating_popup_activation_state_for_session "$session_name")"
  if [ "$activate" = '1' ]; then
    activated_state=1
  fi
  floating_popup_prepare_session "$session_name" "$owner_session" "$start_path" "$activated_state" "$owner_session_id" || return 1
  printf '%s' "$session_name"
}

floating_popup_resolve_session_for_client_locked() {
  local start_path="$1" owner_session="$2" activate="$3" owner_session_id="${4:-}"
  local session_name=""

  owner_session_id="$(floating_popup_live_owner_session_id "$owner_session" "$owner_session_id")" || return 1
  session_name="$(floating_popup_reconcile_sessions "$owner_session_id" "$owner_session")"
  if [ -n "$session_name" ] && floating_popup_session_exists "$session_name"; then
    if ! floating_popup_session_has_been_activated "$session_name" \
      && [ "$(floating_popup_start_path_for_session "$session_name")" != "$start_path" ]; then
      session_name="$(floating_popup_replace_inactive_session_for_path "$session_name" "$owner_session" "$start_path" "$activate" "$owner_session_id")" || return 1
      printf '%s' "$session_name"
      return 0
    fi
    floating_popup_finalize_session_resolution "$session_name" "$owner_session" "$activate" "$owner_session_id" || return 1
    return 0
  fi

  session_name="$(floating_popup_create_session "$owner_session" "$start_path" "$activate" "$owner_session_id")" || return 1
  printf '%s' "$session_name"
}

floating_popup_with_session_lock() {
  local client_name="$1" owner_session="$2" handler="$3"
  shift 3
  local channel status unlock_status
  channel="$(floating_popup_lock_channel "$client_name" "$owner_session")"
  "$TMUX_BIN" wait-for -L "$channel" || return 1
  if "$handler" "$@"; then
    status=0
  else
    status=$?
  fi
  if "$TMUX_BIN" wait-for -U "$channel" 2>/dev/null; then
    unlock_status=0
  else
    unlock_status=$?
    printf 'tmux-floating-popup: failed to unlock channel %s (exit %s)\n' "$channel" "$unlock_status" >&2
  fi
  return "$status"
}

floating_popup_resolve_session_for_client_with_mode() {
  local client_name="$1" start_path="$2" requested_owner_session="${3:-}" activate="$4"
  local owner_session="" owner_session_id=""

  if [ -n "$requested_owner_session" ]; then
    owner_session_id="$(floating_popup_session_id_for_target "$requested_owner_session" 2>/dev/null || true)"
    owner_session="$(floating_popup_session_name_for_target "$requested_owner_session" 2>/dev/null || true)"
    [ -n "$owner_session" ] || owner_session="$requested_owner_session"
  else
    owner_session="$(floating_popup_current_session "$client_name")" || return 1
    owner_session_id="$(floating_popup_current_session_id "$client_name")" || return 1
  fi
  owner_session_id="$(floating_popup_live_owner_session_id "$owner_session" "$owner_session_id")" || return 1
  [ -n "$owner_session_id" ] || return 1

  floating_popup_with_session_lock \
    "" \
    "$owner_session" \
    floating_popup_resolve_session_for_client_locked \
    "$start_path" \
    "$owner_session" \
    "$activate" \
    "$owner_session_id"
}

floating_popup_open_session_for_client() {
  local client_name="$1" start_path="$2" requested_owner_session="${3:-}"
  floating_popup_resolve_session_for_client_with_mode "$client_name" "$start_path" "$requested_owner_session" 1
}

floating_popup_resolve_session_for_client() {
  floating_popup_open_session_for_client "$@"
}

floating_popup_warm_session_for_client() {
  local client_name="$1" start_path="$2" requested_owner_session="${3:-}"
  floating_popup_resolve_session_for_client_with_mode "$client_name" "$start_path" "$requested_owner_session" 0
}

floating_popup_hide_popup_session() {
  local client_name="$1"
  client_name="$(floating_popup_current_client "$client_name")" || return 1
  floating_popup_clear_popup_client "$client_name"
  "$TMUX_BIN" detach-client -t "$client_name"
}

floating_popup_destroy_popup_session() {
  local client_name="$1"
  local session_name=""

  client_name="$(floating_popup_current_client "$client_name")" || return 1
  session_name="$(floating_popup_current_session "$client_name")" || return 1

  floating_popup_clear_popup_client "$client_name"
  floating_popup_session_is_internal_popup "$session_name" || return 1
  "$TMUX_BIN" kill-session -t "=$session_name"
}
