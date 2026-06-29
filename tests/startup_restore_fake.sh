#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-startup-restore-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export TMPDIR="$TMP_ROOT/tmp"
CONFIG_DIR="$HOME/.config/aerospace"
SKETCHY_DIR="$HOME/.config/sketchybar"
GUARD_FILE="$TMPDIR/omarchy_window_state_startup_restore_active"
PARTIAL_GUARD_FILE="$TMPDIR/omarchy_window_state_restore_incomplete"
LOG_FILE="$TMP_ROOT/calls.log"

mkdir -p "$CONFIG_DIR" "$SKETCHY_DIR/plugins" "$TMPDIR"

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
[[ -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]]
printf 'restore\n' >> "$OMARCHY_TEST_LOG"
printf 'restore-attempts:%s delay:%s\n' "${OMARCHY_WINDOW_RESTORE_ATTEMPTS:-missing}" "${OMARCHY_WINDOW_RESTORE_DELAY:-missing}" >> "$OMARCHY_TEST_LOG"
if [ "${OMARCHY_FAIL_RESTORE:-0}" = "1" ]; then
  exit 1
fi
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
guard=0
partial=0
[[ -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]] && guard=1
[[ -e "$TMPDIR/omarchy_window_state_restore_incomplete" ]] && partial=1
printf 'status:%s:guard=%s:partial=%s\n' "${1:-missing}" "$guard" "$partial" >> "$OMARCHY_TEST_LOG"
EOF

chmod +x "$CONFIG_DIR"/*.sh
chmod +x "$SKETCHY_DIR/plugins/"*.sh
export OMARCHY_TEST_LOG="$LOG_FILE"

"$CONFIG_DIR/startup_restore.sh"

expected=$'status:active:guard=1:partial=0\nrepair\nrestore\nrestore-attempts:30 delay:1\nrepair-detached\nstatus:complete:guard=0:partial=0'
actual="$(cat "$LOG_FILE")"
[[ "$actual" == "$expected" ]]
[[ ! -e "$GUARD_FILE" ]]

: > "$LOG_FILE"
OMARCHY_FAIL_RESTORE=1 "$CONFIG_DIR/startup_restore.sh"

expected=$'status:active:guard=1:partial=0\nrepair\nrestore\nrestore-attempts:30 delay:1\nrepair-detached\nstatus:incomplete:guard=0:partial=0'
actual="$(cat "$LOG_FILE")"
[[ "$actual" == "$expected" ]]
[[ ! -e "$GUARD_FILE" ]]
[[ ! -e "$PARTIAL_GUARD_FILE" ]]

/usr/bin/perl -0777 -e '
  my $source = <>;
  die "unexpected named-space rehome catch-all\n"
    if $source =~ /\[\[on-window-detected\]\]\nrun = \['\''exec-and-forget ~\/\.config\/aerospace\/named_space_rehome\.sh'\''\]/;
  die "unexpected blind catch-all workspace 00 rule\n"
    if $source =~ /\[\[on-window-detected\]\]\nrun = \['\''move-node-to-workspace 00'\''/s;
  die "unexpected Gmail app-name workspace rule\n"
    if $source =~ /if\.app-name-regex-substring = '\''Gmail'\''/;
  die "unexpected Gmail canonical workspace assignment\n"
    if $source =~ /return "01" if \$app =~ \/Gmail\/i;/;
  die "missing Google Chat window-detected assignment\n"
    unless $source =~ /if\.app-name-regex-substring = '\''Google Chat'\''\nrun = \['\''move-node-to-workspace 02'\'', '\''workspace 02'\''\]/;
  die "missing Google Chat canonical workspace assignment\n"
    unless $source =~ /return "02" if \$app =~ \/Messages\|Signal\|Google Chat\/i;/;
' "$ROOT/install.sh"

printf 'startup_restore_fake.sh: all checks passed\n'
