#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
fake_bin="$work_dir/bin"
log_file="$work_dir/tmux.log"
mkdir -p "$fake_bin"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

cat >"$fake_bin/tmux" <<'FAKE_TMUX'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TFP_LOG"

if [ "$1" = 'display-message' ] && [ "$2" = '-p' ] && [ "$3" = '-t' ]; then
  target="$4"
  format="$5"
  if [ "$target" = 'popup-client' ] && [ "$format" = '#{@floating-popup-session}' ]; then
    printf '1\n'
    exit 0
  fi
  if [ "$target" = 'popup-client' ] && [ "$format" = '#{pane_current_command}' ]; then
    printf '%s\n' "$TFP_PANE_COMMAND"
    exit 0
  fi
  if [ "$target" = 'popup-client' ] && [ "$format" = '#{client_session}' ]; then
    printf '__floating-popup-1\n'
    exit 0
  fi
fi

if [ "$1" = 'show-options' ] && [ "$2" = '-t' ] && [ "$3" = '__floating-popup-1' ] && [ "$4" = '-qv' ]; then
  case "$5" in
    @floating-popup-owner-client) printf 'owner-client\n'; exit 0 ;;
    @floating-popup-owner-session) printf 'base\n'; exit 0 ;;
  esac
fi

exit 0
FAKE_TMUX
chmod +x "$fake_bin/tmux"

run_smart_escape() {
  : >"$log_file"
  env -u TMUX PATH="$fake_bin:$PATH" TFP_LOG="$log_file" TFP_PANE_COMMAND="$1" \
    "$REPO_DIR/scripts/smart-escape.sh" popup-client
}

run_smart_escape nvim
if grep -Fq 'kill-session -t __floating-popup-1' "$log_file"; then
  echo 'expected Escape in nvim to be passed through, not close the popup' >&2
  exit 1
fi
grep -Fq 'send-keys -t popup-client Escape' "$log_file" || {
  echo 'expected Escape in nvim to be sent to the popup application' >&2
  exit 1
}

run_smart_escape bash
grep -Fq 'kill-session -t __floating-popup-1' "$log_file" || {
  echo 'expected Escape in a plain shell to close the popup session' >&2
  exit 1
}
if grep -Fq 'send-keys -t popup-client Escape' "$log_file"; then
  echo 'expected Escape in a plain shell not to be passed through' >&2
  exit 1
fi

echo 'ok: smart Escape closes only shell popups and passes through to applications'
