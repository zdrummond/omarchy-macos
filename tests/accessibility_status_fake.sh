#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-accessibility-status-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export TMPDIR="$TMP_ROOT/tmp"
export XDG_RUNTIME_DIR="$TMP_ROOT/runtime"
export CONFIG_DIR="$HOME/.config/sketchybar"
FAKE_BIN="$TMP_ROOT/bin"
LOG_FILE="$TMP_ROOT/sketchybar.log"
REPORT_HELPER="$HOME/.config/aerospace/accessibility_report.sh"
STATUS_PLUGIN="$CONFIG_DIR/plugins/restore_status.sh"
STARTUP_GUARD="$TMPDIR/omarchy_window_state_startup_restore_active"

mkdir -p "$HOME/.config/aerospace" "$CONFIG_DIR/plugins" "$FAKE_BIN" "$TMPDIR" "$XDG_RUNTIME_DIR"

awk '/cat > "\$ACCESSIBILITY_REPORT_HELPER" << '\''ACCESSIBILITY_REPORT_EOF'\''/{in_block=1; next} /^ACCESSIBILITY_REPORT_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$REPORT_HELPER"
chmod +x "$REPORT_HELPER"

awk '/cat > "\$SKETCHY_DIR\/plugins\/restore_status.sh" << '\''RESTORE_STATUS_PLUGIN_EOF'\''/{in_block=1; next} /^RESTORE_STATUS_PLUGIN_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$STATUS_PLUGIN"
chmod +x "$STATUS_PLUGIN"

/usr/bin/perl -0777 -e '
  my $source = <>;
  die "sketchybarrc should default CONFIG_DIR before sourcing generated files\n"
    unless $source =~ /export CONFIG_DIR="\$\{CONFIG_DIR:-\$HOME\/\.config\/sketchybar\}"/;
  die "should clean up old accessibility status files\n"
    unless $source =~ /rm -f "\$SKETCHY_DIR\/items\/accessibility_status\.sh" "\$SKETCHY_DIR\/plugins\/accessibility_status\.sh"/;
  die "should remove old accessibility status item from running sketchybar\n"
    unless $source =~ /restore_status accessibility_status/;
  die "should not generate separate accessibility status item\n"
    if $source =~ /source "\$CONFIG_DIR\/items\/accessibility_status\.sh"/ ||
       $source =~ /cat > "\$SKETCHY_DIR\/items\/accessibility_status\.sh"/ ||
       $source =~ /cat > "\$SKETCHY_DIR\/plugins\/accessibility_status\.sh"/;
  die "restore status should read accessibility report\n"
    unless $source =~ /ACCESSIBILITY_HELPER/ && $source =~ /show_accessibility/;
  die "missing accessibility command\n"
    unless $source =~ /accessibility\) cmd_accessibility "\$@" ;;/;
' "$ROOT/install.sh"

cat > "$FAKE_BIN/id" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-u" ]; then
  printf '501\n'
else
  /usr/bin/id "$@"
fi
EOF
chmod +x "$FAKE_BIN/id"

cat > "$FAKE_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "print" ]; then
  label="${2##*/}"
  case " ${OMARCHY_FAKE_LOADED_LABELS:-} " in
    *" $label "*) exit 0 ;;
  esac
fi
exit 1
EOF
chmod +x "$FAKE_BIN/launchctl"

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
mode="${OMARCHY_FAKE_AEROSPACE:-windows-ok}"
case "${1:-}" in
  list-windows)
    case "$mode" in
      windows-ok) printf '100\n'; exit 0 ;;
      windows-fail-monitors-ok|down) exit 1 ;;
    esac
    ;;
  list-monitors)
    case "$mode" in
      windows-ok|windows-fail-monitors-ok) printf '1\n'; exit 0 ;;
      down) exit 1 ;;
    esac
    ;;
esac
exit 1
EOF
chmod +x "$FAKE_BIN/aerospace"

cat > "$HOME/.config/aerospace/omarchy_space_state.sh" <<'EOF'
omarchy_monitor_ids_by_slot() {
  printf '1\n'
}

omarchy_sketchybar_display_for_slot() {
  printf '%s\n' "$(( $1 + 1 ))"
}
EOF

cat > "$FAKE_BIN/sketchybar" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "$@" >> "$OMARCHY_SKETCHYBAR_LOG"
printf '<END>\n' >> "$OMARCHY_SKETCHYBAR_LOG"
EOF
chmod +x "$FAKE_BIN/sketchybar"

cat > "$CONFIG_DIR/colors.sh" <<'EOF'
export YELLOW=0xffffff00
export RED=0xffff0000
export ITEM_BG=0xff222222
EOF

export PATH="$FAKE_BIN:$PATH"
export OMARCHY_FAKE_LOADED_LABELS="com.koekeishiya.skhd"
export OMARCHY_RESTORE_STATUS_WATCH_INTERVAL=0

export OMARCHY_FAKE_AEROSPACE="windows-ok"
[[ "$("$REPORT_HELPER" --count)" = "0" ]]
report="$("$REPORT_HELPER")"
[[ "$report" == *"No actionable Accessibility redo detected."* ]]
[[ "$report" == *"AeroSpace - AeroSpace can list windows."* ]]
[[ "$report" == *"skhd - Service is loaded"* ]]

export OMARCHY_FAKE_AEROSPACE="windows-fail-monitors-ok"
[[ "$("$REPORT_HELPER" --count)" = "1" ]]
brief="$("$REPORT_HELPER" --brief || true)"
[[ "$brief" == "AeroSpace" ]]
report="$("$REPORT_HELPER")"
[[ "$report" == *"Needs Accessibility redo:"* ]]
[[ "$report" == *"Re-grant AeroSpace"* ]]

export OMARCHY_ACCESSIBILITY_REPORT_HELPER="$TMP_ROOT/helper_for_bar.sh"
export OMARCHY_SKETCHYBAR_LOG="$LOG_FILE"
cat > "$OMARCHY_ACCESSIBILITY_REPORT_HELPER" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--brief" ]; then
  printf 'AeroSpace\n'
  exit 1
fi
exit 0
EOF
chmod +x "$OMARCHY_ACCESSIBILITY_REPORT_HELPER"

"$STATUS_PLUGIN"
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<--bar>"*"<hidden=off>"* ]]
[[ "$flattened" == *"<--set>"*"<restore_status>"*"<drawing=off>"* ]]
[[ "$flattened" == *"<--set>"*"<restore_status.0>"*"<display=1>"* ]]
[[ "$flattened" == *"<--set>"*"<restore_status.0>"*"<drawing=on>"*"<label=AX: AeroSpace>"* ]]
[[ "$flattened" != *"<--set>"*"<restore_status>"*"<drawing=on>"*"<label=AX: AeroSpace>"* ]]
[[ "$(cat "$XDG_RUNTIME_DIR/omarchy_sketchybar_visible")" = "1" ]]

touch "$STARTUP_GUARD"
: > "$LOG_FILE"
"$STATUS_PLUGIN"
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<label=Restoring windows>"* ]]
[[ "$flattened" != *"<label=AX: AeroSpace>"* ]]
rm -f "$STARTUP_GUARD"

cat > "$OMARCHY_ACCESSIBILITY_REPORT_HELPER" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--brief" ]; then
  exit 0
fi
exit 0
EOF
chmod +x "$OMARCHY_ACCESSIBILITY_REPORT_HELPER"

: > "$LOG_FILE"
"$STATUS_PLUGIN"
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<--set>"*"<restore_status>"*"<drawing=off>"* ]]
[[ "$flattened" == *"<--bar>"*"<hidden=on>"* ]]

printf 'accessibility_status_fake.sh: all checks passed\n'
