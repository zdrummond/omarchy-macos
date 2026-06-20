#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-startup-restore-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export TMPDIR="$TMP_ROOT/tmp"
CONFIG_DIR="$HOME/.config/aerospace"
GUARD_FILE="$TMPDIR/omarchy_window_state_startup_restore_active"
LOG_FILE="$TMP_ROOT/calls.log"

mkdir -p "$CONFIG_DIR" "$TMPDIR"

awk '/cat > "\$AEROSPACE_DIR\/startup_restore.sh" << '\''STARTUP_RESTORE_EOF'\''/{in_block=1; next} /^STARTUP_RESTORE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/startup_restore.sh"
chmod +x "$CONFIG_DIR/startup_restore.sh"

cat > "$CONFIG_DIR/repair_spaces.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]]
printf 'repair\n' >> "$OMARCHY_TEST_LOG"
EOF

cat > "$CONFIG_DIR/window_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]]
printf 'restore\n' >> "$OMARCHY_TEST_LOG"
EOF

cat > "$CONFIG_DIR/window_state_debounced_save.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -e "$TMPDIR/omarchy_window_state_startup_restore_active" ]]
printf '%s\n' "${1:-missing-reason}" >> "$OMARCHY_TEST_LOG"
EOF

chmod +x "$CONFIG_DIR"/*.sh
export OMARCHY_TEST_LOG="$LOG_FILE"

"$CONFIG_DIR/startup_restore.sh"

expected=$'repair\nrestore\nrepair\npost-startup-restore'
actual="$(cat "$LOG_FILE")"
[[ "$actual" == "$expected" ]]
[[ ! -e "$GUARD_FILE" ]]

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
