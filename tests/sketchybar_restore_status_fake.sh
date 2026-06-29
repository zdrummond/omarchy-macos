#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-sketchybar-restore-status-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export TMPDIR="$TMP_ROOT/tmp"
export XDG_RUNTIME_DIR="$TMP_ROOT/runtime"
export CONFIG_DIR="$HOME/.config/sketchybar"
FAKE_BIN="$TMP_ROOT/bin"
LOG_FILE="$TMP_ROOT/sketchybar.log"
VISIBLE_STATE="$XDG_RUNTIME_DIR/omarchy_sketchybar_visible"
PREVIOUS_STATE="$TMPDIR/omarchy_restore_status_previous_bar"
STARTUP_GUARD="$TMPDIR/omarchy_window_state_startup_restore_active"
PARTIAL_GUARD="$TMPDIR/omarchy_window_state_restore_incomplete"

mkdir -p "$CONFIG_DIR/plugins" "$FAKE_BIN" "$TMPDIR" "$XDG_RUNTIME_DIR"

cat > "$CONFIG_DIR/colors.sh" <<'EOF'
export YELLOW=0xffffff00
export RED=0xffff0000
export ITEM_BG=0xff222222
EOF

awk '/cat > "\$SKETCHY_DIR\/plugins\/restore_status.sh" << '\''RESTORE_STATUS_PLUGIN_EOF'\''/{in_block=1; next} /^RESTORE_STATUS_PLUGIN_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/plugins/restore_status.sh"
chmod +x "$CONFIG_DIR/plugins/restore_status.sh"

/usr/bin/perl -0777 -e '
  my $source = <>;
  die "restore status should not poll too aggressively\n" if $source =~ /update_freq=5/;
  die "restore status item should not poll continuously\n"
    unless $source =~ /cat > "\$SKETCHY_DIR\/items\/restore_status\.sh".*?updates=off/s;
  die "monitor restore status items should not each poll independently\n"
    unless $source =~ /name="restore_status\.\$slot".*?updates=off/s;
  die "missing temporary AX warning watcher\n"
    unless $source =~ /start_accessibility_watch/ &&
           $source =~ /OMARCHY_RESTORE_STATUS_WATCH_INTERVAL:-30/;
' "$ROOT/install.sh"

cat > "$FAKE_BIN/sketchybar" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "$@" >> "$OMARCHY_SKETCHYBAR_LOG"
printf '<END>\n' >> "$OMARCHY_SKETCHYBAR_LOG"
EOF
chmod +x "$FAKE_BIN/sketchybar"

export PATH="$FAKE_BIN:$PATH"
export OMARCHY_SKETCHYBAR_LOG="$LOG_FILE"

"$CONFIG_DIR/plugins/restore_status.sh" active
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<--bar>"*"<hidden=off>"* ]]
[[ "$flattened" == *"<--set>"*"<restore_status>"*"<drawing=on>"*"<label=Restoring windows>"* ]]
[[ "$(cat "$VISIBLE_STATE")" == "1" ]]
[[ "$(cat "$PREVIOUS_STATE")" == "0" ]]

: > "$LOG_FILE"
"$CONFIG_DIR/plugins/restore_status.sh" complete
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<--set>"*"<restore_status>"*"<drawing=off>"* ]]
[[ "$flattened" == *"<--bar>"*"<hidden=on>"* ]]
[[ "$(cat "$VISIBLE_STATE")" == "0" ]]
[[ ! -e "$PREVIOUS_STATE" ]]

printf '1' > "$VISIBLE_STATE"
: > "$LOG_FILE"
"$CONFIG_DIR/plugins/restore_status.sh" active
"$CONFIG_DIR/plugins/restore_status.sh" complete
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<--bar>"*"<hidden=off>"* ]]
[[ "$flattened" != *"<hidden=on>"* ]]
[[ "$(cat "$VISIBLE_STATE")" == "1" ]]

rm -f "$PREVIOUS_STATE"
printf '0' > "$VISIBLE_STATE"
touch "$PARTIAL_GUARD"
: > "$LOG_FILE"
"$CONFIG_DIR/plugins/restore_status.sh" refresh
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<--bar>"*"<hidden=off>"* ]]
[[ "$flattened" == *"<--set>"*"<restore_status>"*"<drawing=on>"*"<label=Restore incomplete>"* ]]
[[ "$(cat "$VISIBLE_STATE")" == "1" ]]
[[ "$(cat "$PREVIOUS_STATE")" == "0" ]]

rm -f "$PARTIAL_GUARD" "$PREVIOUS_STATE"
touch "$STARTUP_GUARD"
: > "$LOG_FILE"
"$CONFIG_DIR/plugins/restore_status.sh" refresh
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<label=Restoring windows>"* ]]

printf 'sketchybar_restore_status_fake.sh: all checks passed\n'
