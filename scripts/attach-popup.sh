#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'tmux-floating-popup: dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'tmux-floating-popup: pwd not found' >&2; exit 1; }
SCRIPT_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")" && "$PWD_BIN")" || exit 1
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/tmux.sh"

session_name="${1:-}"
[ -n "$session_name" ] || { echo 'tmux-floating-popup: popup session name required' >&2; exit 1; }

client_name="$(tty 2>/dev/null || true)"
[ -n "$client_name" ] || { echo 'tmux-floating-popup: popup client tty not found' >&2; exit 1; }

floating_popup_mark_popup_client "$client_name" "$$"
exec "$TMUX_BIN" attach-session -t "=$session_name"
