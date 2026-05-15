#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

sock="tfp_test_key_bindings"
cleanup() {
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
}
trap cleanup EXIT

env -u TMUX "$REAL_TMUX_BIN" -f /dev/null -L "$sock" new-session -d -s base 'sleep 9999'
env -u TMUX "$REAL_TMUX_BIN" -L "$sock" run-shell "$REPO_DIR/tmux-floating-popup.tmux"

root_binding="$(env -u TMUX "$REAL_TMUX_BIN" -L "$sock" list-keys -T root M-f 2>/dev/null || true)"
popup_binding="$(env -u TMUX "$REAL_TMUX_BIN" -L "$sock" list-keys -T popup M-f 2>/dev/null || true)"

printf '%s\n' "$root_binding" | grep -Fq 'scripts/open-popup.sh' || {
  echo 'expected root M-f binding for scripts/open-popup.sh' >&2
  exit 1
}

printf '%s\n' "$popup_binding" | grep -Fq 'scripts/close-popup.sh' || {
  echo 'expected popup M-f binding for scripts/close-popup.sh' >&2
  exit 1
}

echo 'ok: plugin installs root and popup M-f bindings'
