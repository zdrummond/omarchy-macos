#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-window-state-saver-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export TMPDIR="$TMP_ROOT/tmp"
SAVER="$TMP_ROOT/window_state_debounced_save.sh"
LOG_FILE="$TMP_ROOT/window_state.log"
STATUS_LOG="$TMP_ROOT/restore_status.log"
SAVE_LOG="$TMP_ROOT/save.log"
STARTUP_GUARD="$TMPDIR/omarchy_window_state_startup_restore_active"

mkdir -p "$HOME/.config/aerospace" "$HOME/.config/sketchybar/plugins" "$TMPDIR"

awk '/cat > "\$WINDOW_STATE_DEBOUNCED_SAVER" << '\''WINDOW_STATE_DEBOUNCED_SAVER_EOF'\''/{in_block=1; next} /^WINDOW_STATE_DEBOUNCED_SAVER_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$SAVER"
chmod +x "$SAVER"

cat > "$HOME/.config/aerospace/window_state.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SAVE_LOG"
EOF
chmod +x "$HOME/.config/aerospace/window_state.sh"

cat > "$HOME/.config/sketchybar/plugins/restore_status.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${1:-refresh}" >> "$STATUS_LOG"
EOF
chmod +x "$HOME/.config/sketchybar/plugins/restore_status.sh"

printf '%s\n' 'pending-window-state-saver' > "$STARTUP_GUARD"

OMARCHY_WINDOW_STATE_LOG="$LOG_FILE" \
  OMARCHY_WINDOW_STATE_DEBOUNCE_SECONDS=0 \
  OMARCHY_STARTUP_RESTORE_PENDING_MAX_SECONDS=0 \
  "$SAVER" window-detected

[[ ! -e "$STARTUP_GUARD" ]]
grep -q 'startup restore pending guard expired; allowing automatic saves' "$LOG_FILE"
[[ "$(cat "$STATUS_LOG")" == "complete" ]]
[[ "$(cat "$SAVE_LOG")" == "save auto window-detected" ]]

/usr/bin/perl -0777 -e '
  my $source = <>;
  die "debounced saver does not clear restore status on pending expiry\n"
    unless $source =~ /cat > "\$WINDOW_STATE_DEBOUNCED_SAVER" << .*?RESTORE_STATUS_HELPER=.*?clear_restore_status\(\).*?startup restore pending guard expired; allowing automatic saves.*?clear_restore_status.*?WINDOW_STATE_DEBOUNCED_SAVER_EOF/s;
  die "periodic saver does not clear restore status on pending expiry\n"
    unless $source =~ /cat > "\$WINDOW_STATE_SAVER" << .*?RESTORE_STATUS_HELPER=.*?clear_restore_status\(\).*?startup restore pending guard expired; allowing automatic saves.*?clear_restore_status.*?WINDOW_STATE_SAVER_EOF/s;
  die "refresh must restart services in refresh mode\n"
    unless $source =~ /cmd_refresh\(\).*?stop_services\n  start_services refresh/s;
  die "refresh-mode service start must create and clean a one-shot saver marker\n"
    unless $source =~ /start_services\(\).*?mode="\$\{1:-normal\}".*?skip-next-startup-guard.*?launchctl load "\$WINDOW_STATE_SAVER_PLIST".*?rm -f "\$WINDOW_STATE_REFRESH_RESTART_MARKER"/s;
  die "periodic saver must consume a fresh refresh marker without seeding a startup guard\n"
    unless $source =~ /cat > "\$WINDOW_STATE_SAVER" << .*?REFRESH_RESTART_MARKER=.*?seed_startup_restore_guard\(\) \{.*?skip-next-startup-guard.*?config refresh restart; startup restore guard not seeded.*?clear_restore_status.*?return 0.*?pending-window-state-saver/s;
' "$ROOT/install.sh"

printf 'window_state_saver_fake.sh: all checks passed\n'
