#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-startup-restore-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export TMPDIR="$TMP_ROOT/tmp"
CONFIG_DIR="$HOME/.config/aerospace"
SKETCHY_DIR="$HOME/.config/sketchybar"
FAKE_BIN="$TMP_ROOT/bin"
GUARD_FILE="$TMPDIR/omarchy_window_state_startup_restore_active"
PARTIAL_GUARD_FILE="$TMPDIR/omarchy_window_state_restore_incomplete"
LOG_FILE="$TMP_ROOT/calls.log"
STATE_LOG_FILE="$TMP_ROOT/window_state.log"

mkdir -p "$CONFIG_DIR" "$SKETCHY_DIR/plugins" "$FAKE_BIN" "$TMPDIR"

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/omarchy_space_state.sh"

awk '/cat > "\$AEROSPACE_DIR\/startup_restore.sh" << '\''STARTUP_RESTORE_EOF'\''/{in_block=1; next} /^STARTUP_RESTORE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/startup_restore.sh"
chmod +x "$CONFIG_DIR/startup_restore.sh"

cat > "$CONFIG_DIR/repair_spaces.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]]
if [ "${1:-}" = "--detached-only" ]; then
  printf 'repair-detached\n' >> "$OMARCHY_TEST_LOG"
else
  printf 'repair\n' >> "$OMARCHY_TEST_LOG"
fi
EOF

cat > "$CONFIG_DIR/window_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-missing}" in
  restore)
    [[ -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]]
    printf 'restore\n' >> "$OMARCHY_TEST_LOG"
    printf 'restore-attempts:%s delay:%s\n' "${OMARCHY_WINDOW_RESTORE_ATTEMPTS:-missing}" "${OMARCHY_WINDOW_RESTORE_DELAY:-missing}" >> "$OMARCHY_TEST_LOG"
    if [ "${OMARCHY_FAIL_RESTORE:-0}" = "1" ]; then
      printf 'incomplete\n' > "$TMPDIR/omarchy_window_state_restore_incomplete"
    fi
    ;;
  save)
    [[ ! -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]]
    printf 'save:%s:%s\n' "${2:-missing-mode}" "${3:-missing-reason}" >> "$OMARCHY_TEST_LOG"
    rm -f "$TMPDIR/omarchy_window_state_restore_incomplete"
    ;;
  *)
    printf 'unexpected-window-state-command:%s\n' "${1:-missing}" >> "$OMARCHY_TEST_LOG"
    exit 1
    ;;
esac
EOF

cat > "$CONFIG_DIR/window_state_debounced_save.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]]
printf '%s\n' "${1:-missing-reason}" >> "$OMARCHY_TEST_LOG"
EOF

cat > "$SKETCHY_DIR/plugins/restore_status.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mode="${1:-missing}"
guard=0
partial=0
[[ -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]] && guard=1
[[ -e "$TMPDIR/omarchy_window_state_restore_incomplete" ]] && partial=1
if [[ "${OMARCHY_TEST_HANG_STATUS_MODE:-}" == "$mode" ]]; then
  printf 'status-start:%s:guard=%s:partial=%s\n' "$mode" "$guard" "$partial" >> "$OMARCHY_TEST_LOG"
  sleep 30
fi
printf 'status:%s:guard=%s:partial=%s\n' "$mode" "$guard" "$partial" >> "$OMARCHY_TEST_LOG"
EOF

cat > "$FAKE_BIN/sketchybar" <<'EOF'
#!/usr/bin/env bash
printf 'sketchybar:%s\n' "$*" >> "$OMARCHY_TEST_LOG"
EOF

chmod +x "$CONFIG_DIR"/*.sh
chmod +x "$SKETCHY_DIR/plugins/"*.sh
chmod +x "$FAKE_BIN/sketchybar"
export OMARCHY_TEST_LOG="$LOG_FILE"
export OMARCHY_WINDOW_STATE_LOG="$STATE_LOG_FILE"
export PATH="$FAKE_BIN:$PATH"

"$CONFIG_DIR/startup_restore.sh"

expected=$'status:active:guard=1:partial=0\nrepair\nrestore\nrestore-attempts:30 delay:1\nrepair-detached\nstatus:complete:guard=0:partial=0'
actual="$(grep -v '^sketchybar:' "$LOG_FILE")"
[[ "$actual" == "$expected" ]]
[[ ! -e "$GUARD_FILE" ]]

: > "$LOG_FILE"
OMARCHY_FAIL_RESTORE=1 OMARCHY_STARTUP_INCOMPLETE_CLEAR_DELAY=0 "$CONFIG_DIR/startup_restore.sh"

expected=$'status:active:guard=1:partial=0\nrepair\nrestore\nrestore-attempts:30 delay:1\nrepair-detached\nstatus:incomplete:guard=0:partial=1'
actual="$(grep -v '^sketchybar:' "$LOG_FILE")"
[[ "$actual" == "$expected" ]]
[[ ! -e "$GUARD_FILE" ]]
[[ -e "$PARTIAL_GUARD_FILE" ]]

: > "$LOG_FILE"
rm -f "$PARTIAL_GUARD_FILE"
OMARCHY_FAIL_RESTORE=1 OMARCHY_STARTUP_INCOMPLETE_CLEAR_DELAY=1 OMARCHY_STARTUP_INCOMPLETE_CLEAR_ATTEMPTS=1 "$CONFIG_DIR/startup_restore.sh"

for _ in {1..30}; do
  if [[ ! -e "$PARTIAL_GUARD_FILE" ]] && grep -q 'status:complete' "$LOG_FILE"; then
    break
  fi
  sleep 0.2
done

[[ ! -e "$GUARD_FILE" ]]
[[ ! -e "$PARTIAL_GUARD_FILE" ]]
grep -q '^status:active:guard=1:partial=0$' "$LOG_FILE"
grep -q '^repair$' "$LOG_FILE"
grep -q '^restore$' "$LOG_FILE"
grep -q '^repair-detached$' "$LOG_FILE"
[[ "$(grep -c '^save:manual:startup-incomplete-timeout$' "$LOG_FILE")" = "1" ]]
[[ "$(grep -c '^status:complete:guard=0:partial=0$' "$LOG_FILE")" = "1" ]]

: > "$LOG_FILE"
rm -f "$PARTIAL_GUARD_FILE"
old_started_at="$(($(date +%s) - 10))"
OMARCHY_FAIL_RESTORE=1 \
  OMARCHY_STARTUP_RESTORE_STARTED_AT="$old_started_at" \
  OMARCHY_STARTUP_INCOMPLETE_CLEAR_DELAY=1 \
  OMARCHY_STARTUP_INCOMPLETE_CLEAR_ATTEMPTS=1 \
  "$CONFIG_DIR/startup_restore.sh"

for _ in {1..30}; do
  if [[ ! -e "$PARTIAL_GUARD_FILE" ]] && grep -q 'status:complete' "$LOG_FILE"; then
    break
  fi
  sleep 0.2
done

actual="$(grep -v '^sketchybar:' "$LOG_FILE")"
[[ ! -e "$GUARD_FILE" ]]
[[ ! -e "$PARTIAL_GUARD_FILE" ]]
grep -q '^status:active:guard=1:partial=0$' <<< "$actual"
grep -q '^repair$' <<< "$actual"
grep -q '^restore$' <<< "$actual"
grep -q '^repair-detached$' <<< "$actual"
[[ "$(grep -c '^save:manual:startup-incomplete-timeout$' <<< "$actual")" = "1" ]]
[[ "$(grep '^status:' <<< "$actual" | tail -n 1)" = "status:complete:guard=0:partial=0" ]]

: > "$LOG_FILE"
rm -f "$PARTIAL_GUARD_FILE"
started_seconds="$(date +%s)"
OMARCHY_FAIL_RESTORE=1 \
  OMARCHY_TEST_HANG_STATUS_MODE=incomplete \
  OMARCHY_RESTORE_STATUS_TIMEOUT_SECONDS=2 \
  OMARCHY_STARTUP_INCOMPLETE_CLEAR_DELAY=1 \
  OMARCHY_STARTUP_INCOMPLETE_CLEAR_ATTEMPTS=1 \
  "$CONFIG_DIR/startup_restore.sh"
finished_seconds="$(date +%s)"

for _ in {1..30}; do
  [[ ! -e "$PARTIAL_GUARD_FILE" ]] && break
  sleep 0.2
done

[[ $((finished_seconds - started_seconds)) -lt 8 ]]
[[ ! -e "$GUARD_FILE" ]]
[[ ! -e "$PARTIAL_GUARD_FILE" ]]
grep -Eq '^status-start:incomplete:guard=0:partial=[01]$' "$LOG_FILE"
grep -q '^save:manual:startup-incomplete-timeout$' "$LOG_FILE"
grep -q 'restore status update timed out or failed: incomplete' "$STATE_LOG_FILE"
[[ "$(grep '^status:' "$LOG_FILE" | tail -n 1)" = "status:complete:guard=0:partial=0" ]]

/usr/bin/perl -0777 -e '
  my $source = <>;
  die "unexpected named-space rehome catch-all\n"
    if $source =~ /\[\[on-window-detected\]\]\nrun = \['\''exec-and-forget ~\/\.config\/aerospace\/named_space_rehome\.sh'\''\]/;
  die "unexpected blind catch-all workspace 00 rule\n"
    if $source =~ /\[\[on-window-detected\]\]\nrun = \['\''move-node-to-workspace 00'\''/s;
  die "unexpected Gmail app-name workspace rule\n"
    if $source =~ /if\.app-name-regex-substring = '\''Gmail'\''/;
  die "missing Apple Mail window-detected assignment\n"
    unless $source =~ /if\.app-id = '\''com\.apple\.mail'\''\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/assigned_window_rehome\.sh 01 "(?:\\)?\$AEROSPACE_WINDOW_ID"'\''/;
  die "missing Gmail window-detected assignment\n"
    unless $source =~ /if\.app-id = '\''com\.google\.Chrome\.app\.fmgjjmmmlfnkbppncabfkddbjimcfncm'\''\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/assigned_window_rehome\.sh 01 "(?:\\)?\$AEROSPACE_WINDOW_ID"'\''/;
  die "missing Gmail shell workspace assignment\n"
    unless $source =~ /\*Mail\*\|\*Gmail\*\) printf '\''01\\n'\''; return 0 ;;/;
  die "missing Google Chat window-detected assignment\n"
    unless $source =~ /if\.app-name-regex-substring = '\''Google Chat'\''\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/assigned_window_rehome\.sh 02 "(?:\\)?\$AEROSPACE_WINDOW_ID"'\''/;
  die "missing Google Chat canonical workspace assignment\n"
    unless $source =~ /return "02" if \$app =~ \/Messages\|Signal\|Google Chat\/i;/;
' "$ROOT/install.sh"

printf 'startup_restore_fake.sh: all checks passed\n'
