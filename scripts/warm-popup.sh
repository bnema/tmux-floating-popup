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
source_path="${2:-}"

client_name="$(floating_popup_current_client "$client_name")" || exit 1
source_path="$(floating_popup_current_path "$source_path")" || exit 1

if floating_popup_client_is_popup_client "$client_name" || floating_popup_client_is_popup_session "$client_name"; then
  exit 0
fi

floating_popup_warm_session_for_client "$client_name" "$source_path" >/dev/null || exit 1
