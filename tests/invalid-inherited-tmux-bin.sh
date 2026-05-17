#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
REPO_DIR="$(cd "$($DIRNAME_BIN "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

cat >"$fake_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
printf 'fake tmux invoked\n'
TMUX
chmod +x "$fake_bin/tmux"

resolved_invalid="$({
  # shellcheck disable=SC2016
  TMUX_BIN='$(command -v tmux 2>/dev/null || true)'
  PATH="$fake_bin:$PATH"
  # shellcheck source=/dev/null
  source "$REPO_DIR/scripts/lib/tmux.sh"
  printf '%s' "$TMUX_BIN"
})"

expected="$fake_bin/tmux"
[ "$resolved_invalid" = "$expected" ] || {
  echo "expected invalid inherited TMUX_BIN to resolve to $expected" >&2
  echo "got: $resolved_invalid" >&2
  exit 1
}

valid_override="$work_dir/custom-tmux"
cat >"$valid_override" <<'TMUX'
#!/usr/bin/env bash
printf 'custom tmux invoked\n'
TMUX
chmod +x "$valid_override"

resolved_valid="$({
  TMUX_BIN="$valid_override"
  PATH="$fake_bin:$PATH"
  # shellcheck source=/dev/null
  source "$REPO_DIR/scripts/lib/tmux.sh"
  printf '%s' "$TMUX_BIN"
})"

[ "$resolved_valid" = "$valid_override" ] || {
  echo "expected valid inherited TMUX_BIN to be preserved as $valid_override" >&2
  echo "got: $resolved_valid" >&2
  exit 1
}

echo 'ok: invalid inherited TMUX_BIN is ignored and valid inherited TMUX_BIN is preserved'
