#!/usr/bin/env bash
set -euo pipefail

DIRNAME_BIN="$(command -v dirname 2>/dev/null || true)"
PWD_BIN="$(command -v pwd 2>/dev/null || true)"
REAL_TMUX_BIN="$(command -v tmux 2>/dev/null || true)"
[ -n "$DIRNAME_BIN" ] || { echo 'dirname not found' >&2; exit 1; }
[ -n "$PWD_BIN" ] || { echo 'pwd not found' >&2; exit 1; }
[ -n "$REAL_TMUX_BIN" ] || { echo 'tmux not found' >&2; exit 1; }
REPO_DIR="$(cd "$("$DIRNAME_BIN" "${BASH_SOURCE[0]}")/.." && "$PWD_BIN")" || exit 1

work_dir="$(mktemp -d)"
sock="tfp_test_duplicate_parent_cleanup.$$.$RANDOM"
fake_bin="$work_dir/bin"
mkdir -p "$fake_bin"

cleanup() {
  env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

env -u TMUX "$REAL_TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true

cat >"$fake_bin/tmux" <<EOF
#!/usr/bin/env bash
exec "$REAL_TMUX_BIN" -L "$sock" "\$@"
EOF
chmod +x "$fake_bin/tmux"

export PATH="$fake_bin:$PATH"

source "$REPO_DIR/scripts/lib/tmux.sh"

tmux -f /dev/null new-session -d -s legacy -c "$work_dir" 'sleep 9999'
legacy_parent_id="$(tmux list-sessions -F '#{session_name}|#{session_id}' | awk -F'|' '$1 == "legacy" { print $2; exit }')"
[ -n "$legacy_parent_id" ] || {
  echo 'test setup failed: could not resolve legacy parent session id' >&2
  exit 1
}
tmux new-session -d -s __floating-popup-legacy -c "$work_dir" 'sleep 9999'
tmux set-option -t __floating-popup-legacy -q "$(floating_popup_session_flag)" 1
tmux set-option -t __floating-popup-legacy -q "$(floating_popup_owner_session_option)" legacy

legacy_resolved="$(floating_popup_resolve_session_for_client /dev/pts/legacy "$work_dir" legacy)"
case "$legacy_resolved" in
  __floating-popup-*) ;;
  *)
    echo "expected live legacy no-id popup to be replaced by a marked popup, got: $legacy_resolved" >&2
    exit 1
    ;;
esac
[ "$legacy_resolved" != '__floating-popup-legacy' ] || {
  echo 'expected live legacy no-id popup to be removed instead of adopted by name' >&2
  exit 1
}
if tmux has-session -t =__floating-popup-legacy 2>/dev/null; then
  echo 'expected live legacy no-id popup to be removed before replacement' >&2
  exit 1
fi

legacy_stored_id="$(floating_popup_owner_session_id_for_session "$legacy_resolved")"
[ "$legacy_stored_id" = "$legacy_parent_id" ] || {
  echo "expected replacement popup to store parent id $legacy_parent_id, got: $legacy_stored_id" >&2
  exit 1
}

legacy_count="$(tmux list-sessions -F '#{session_name}|#{@floating-popup-session}|#{@floating-popup-owner-session-id}' \
  | awk -F'|' -v parent_id="$legacy_parent_id" '$2 == "1" && $3 == parent_id { count++ } END { print count + 0 }')"
[ "$legacy_count" = '1' ] || {
  echo "expected exactly one marked popup for live legacy parent, got: $legacy_count" >&2
  exit 1
}

pipe_parent='foo|bar'
tmux new-session -d -s "$pipe_parent" -c "$work_dir" 'sleep 9999'
pipe_parent_id="$(floating_popup_session_id_for_target "=$pipe_parent")"
[ -n "$pipe_parent_id" ] || {
  echo 'test setup failed: could not resolve pipe-named parent session id' >&2
  exit 1
}
tmux new-session -d -s __floating-popup-pipe-legacy -c "$work_dir" 'sleep 9999'
tmux set-option -t __floating-popup-pipe-legacy -q "$(floating_popup_session_flag)" 1
tmux set-option -t __floating-popup-pipe-legacy -q "$(floating_popup_owner_session_option)" "$pipe_parent"

pipe_resolved="$(floating_popup_resolve_session_for_client /dev/pts/pipe "$work_dir" "$pipe_parent")"
case "$pipe_resolved" in
  __floating-popup-*) ;;
  *)
    echo "expected pipe-named live legacy no-id popup to be replaced by a marked popup, got: $pipe_resolved" >&2
    exit 1
    ;;
esac
[ "$pipe_resolved" != '__floating-popup-pipe-legacy' ] || {
  echo 'expected pipe-named live legacy no-id popup to be removed instead of adopted by name' >&2
  exit 1
}
if tmux has-session -t =__floating-popup-pipe-legacy 2>/dev/null; then
  echo 'expected pipe-named live legacy no-id popup to be removed before replacement' >&2
  exit 1
fi

pipe_stored_id="$(floating_popup_owner_session_id_for_session "$pipe_resolved")"
[ "$pipe_stored_id" = "$pipe_parent_id" ] || {
  echo "expected pipe-named replacement popup to store parent id $pipe_parent_id, got: $pipe_stored_id" >&2
  exit 1
}

marked_popups_for_pipe_parent() {
  local count=0 session_id='' _session_name='' flag='' owner_id=''
  while IFS='|' read -r session_id _session_name; do
    [ -n "$session_id" ] || continue
    flag="$(tmux show-options -t "$session_id" -qv "$(floating_popup_session_flag)" 2>/dev/null || true)"
    owner_id="$(tmux show-options -t "$session_id" -qv "$(floating_popup_owner_session_id_option)" 2>/dev/null || true)"
    if [ "$flag" = '1' ] && [ "$owner_id" = "$pipe_parent_id" ]; then
      count=$((count + 1))
    fi
  done < <(tmux list-sessions -F '#{session_id}|#{session_name}')
  printf '%s' "$count"
}

pipe_count="$(marked_popups_for_pipe_parent)"
[ "$pipe_count" = '1' ] || {
  echo "expected exactly one marked popup for pipe-named live legacy parent, got: $pipe_count" >&2
  exit 1
}

tmux new-session -d -s base 'sleep 9999'
parent_id="$(tmux list-sessions -F '#{session_name}|#{session_id}' | awk -F'|' '$1 == "base" { print $2; exit }')"
[ -n "$parent_id" ] || {
  echo 'test setup failed: could not resolve base parent session id' >&2
  exit 1
}

tmux new-session -d -s __floating-popup-duplicate-a -c "$work_dir" 'sleep 9999'
tmux new-session -d -s __floating-popup-duplicate-b -c "$work_dir" 'sleep 9999'
tmux new-session -d -s __floating-popup-user -c "$work_dir" 'sleep 9999'

for popup_session in __floating-popup-duplicate-a __floating-popup-duplicate-b; do
  tmux set-option -t "$popup_session" -q "$(floating_popup_session_flag)" 1
  tmux set-option -t "$popup_session" -q "$(floating_popup_owner_session_option)" base
  tmux set-option -t "$popup_session" -q "$(floating_popup_owner_session_id_option)" "$parent_id"
done

marked_popups_for_parent() {
  local count=0 session_id='' _session_name='' flag='' owner_id=''
  while IFS='|' read -r session_id _session_name; do
    [ -n "$session_id" ] || continue
    flag="$(tmux show-options -t "$session_id" -qv "$(floating_popup_session_flag)" 2>/dev/null || true)"
    owner_id="$(tmux show-options -t "$session_id" -qv "$(floating_popup_owner_session_id_option)" 2>/dev/null || true)"
    if [ "$flag" = '1' ] && [ "$owner_id" = "$parent_id" ]; then
      count=$((count + 1))
    fi
  done < <(tmux list-sessions -F '#{session_id}|#{session_name}')
  printf '%s' "$count"
}

[ "$(marked_popups_for_parent)" = '2' ] || {
  echo 'test setup failed: expected two marked duplicate popup sessions for base' >&2
  exit 1
}

floating_popup_reconcile_sessions

remaining_count="$(marked_popups_for_parent)"
[ "$remaining_count" = '1' ] || {
  echo "expected duplicate marked popup sessions for base to be reduced to one, got: $remaining_count" >&2
  exit 1
}

returned_by_name="$(floating_popup_reconcile_sessions '' base)"
case "$returned_by_name" in
  __floating-popup-*) ;;
  *)
    echo "expected name-only reconcile lookup to return the base popup, got: $returned_by_name" >&2
    exit 1
    ;;
esac
returned_owner_id="$(floating_popup_owner_session_id_for_session "$returned_by_name")"
[ "$returned_owner_id" = "$parent_id" ] || {
  echo "expected name-only reconcile lookup survivor to store owner session id $parent_id, got: $returned_owner_id" >&2
  exit 1
}

if ! tmux has-session -t =__floating-popup-user 2>/dev/null; then
  echo 'expected non-flagged internal-name user session to survive reconciliation' >&2
  exit 1
fi

user_flag="$(tmux show-options -t =__floating-popup-user -qv "$(floating_popup_session_flag)" 2>/dev/null || true)"
[ -z "$user_flag" ] || {
  echo "expected safety session to remain unmarked, got flag: $user_flag" >&2
  exit 1
}

# shellcheck disable=SC2016 # literal command substitution text must not execute during reconciliation
malicious_session='__floating-popup-$(printf EVAL_EXECUTED >&2)'
tmux new-session -d -s "$malicious_session" -c "$work_dir" 'sleep 9999'
tmux set-option -t "$malicious_session" -q "$(floating_popup_session_flag)" 1
tmux set-option -t "$malicious_session" -q "$(floating_popup_owner_session_option)" base
tmux set-option -t "$malicious_session" -q "$(floating_popup_owner_session_id_option)" "$parent_id"

reconcile_output="$(floating_popup_reconcile_sessions 2>&1)"
case "$reconcile_output" in
  *EVAL_EXECUTED*)
    echo 'expected reconciliation not to evaluate popup session names as shell code' >&2
    exit 1
    ;;
esac

remaining_count="$(marked_popups_for_parent)"
[ "$remaining_count" = '1' ] || {
  echo "expected malicious duplicate popup to be reconciled down to one marked popup, got: $remaining_count" >&2
  exit 1
}

tmux new-session -d -s rank -c "$work_dir" 'sleep 9999'
rank_parent_id="$(floating_popup_session_id_for_target '=rank')"
[ -n "$rank_parent_id" ] || {
  echo 'test setup failed: could not resolve rank parent session id' >&2
  exit 1
}
tmux new-session -d -s __floating-popup-100 -c "$work_dir" 'sleep 9999'
tmux new-session -d -s __floating-popup-101 -c "$work_dir" 'sleep 9999'
for popup_session in __floating-popup-100 __floating-popup-101; do
  tmux set-option -t "$popup_session" -q "$(floating_popup_session_flag)" 1
  tmux set-option -t "$popup_session" -q "$(floating_popup_owner_session_option)" rank
  tmux set-option -t "$popup_session" -q "$(floating_popup_owner_session_id_option)" "$rank_parent_id"
done
tmux set-option -t __floating-popup-100 -q "$(floating_popup_activated_option)" 0
tmux set-option -t __floating-popup-101 -q "$(floating_popup_activated_option)" 1

floating_popup_reconcile_sessions

if tmux has-session -t =__floating-popup-100 2>/dev/null; then
  echo 'expected inactive lower-id duplicate popup to be removed when an activated duplicate exists' >&2
  exit 1
fi
if ! tmux has-session -t =__floating-popup-101 2>/dev/null; then
  echo 'expected activated duplicate popup to survive reconciliation' >&2
  exit 1
fi

echo 'ok: duplicate marked popups are reconciled without killing non-flagged user sessions'
