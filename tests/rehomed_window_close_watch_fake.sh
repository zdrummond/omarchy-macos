#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-close-watch-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HELPER="$TMP_ROOT/rehomed_window_close_watch.sh"
FAKE_BIN="$TMP_ROOT/bin"
COMMANDS="$TMP_ROOT/commands"
LOG_FILE="$TMP_ROOT/window_state.log"
FOCUSED_WORKSPACE="$TMP_ROOT/focused_workspace"
ALL_WINDOWS="$TMP_ROOT/all_windows"
SOURCE_WINDOWS="$TMP_ROOT/source_windows"
TARGET_WINDOWS="$TMP_ROOT/target_windows"

mkdir -p "$FAKE_BIN"
awk '/cat > "\$REHOMED_WINDOW_CLOSE_WATCHER" << '\''REHOMED_WINDOW_CLOSE_WATCH_EOF'\''/{in_block=1; next} /^REHOMED_WINDOW_CLOSE_WATCH_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$HELPER"

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list-windows)
    if [[ "${2:-}" == "--all" ]]; then
      cat "$OMARCHY_FAKE_ALL_WINDOWS"
    elif [[ "${2:-}" == "--workspace" && "${3:-}" == "04" ]]; then
      cat "$OMARCHY_FAKE_SOURCE_WINDOWS"
    elif [[ "${2:-}" == "--workspace" && "${3:-}" == "00" ]]; then
      cat "$OMARCHY_FAKE_TARGET_WINDOWS"
    else
      exit 2
    fi
    ;;
  list-workspaces)
    cat "$OMARCHY_FAKE_FOCUSED_WORKSPACE"
    ;;
  workspace)
    printf 'workspace:%s\n' "${2:-}" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  *)
    exit 3
    ;;
esac
EOF

chmod +x "$HELPER" "$FAKE_BIN/aerospace"
export OMARCHY_AEROSPACE_BIN="$FAKE_BIN/aerospace"
export OMARCHY_WINDOW_STATE_LOG="$LOG_FILE"
export OMARCHY_FAKE_COMMANDS="$COMMANDS"
export OMARCHY_FAKE_FOCUSED_WORKSPACE="$FOCUSED_WORKSPACE"
export OMARCHY_FAKE_ALL_WINDOWS="$ALL_WINDOWS"
export OMARCHY_FAKE_SOURCE_WINDOWS="$SOURCE_WINDOWS"
export OMARCHY_FAKE_TARGET_WINDOWS="$TARGET_WINDOWS"
export OMARCHY_REHOME_CLOSE_POLL_INTERVAL=0
export OMARCHY_REHOME_CLOSE_SETTLE_DELAY=0
export OMARCHY_REHOME_CLOSE_MAX_SECONDS=1

run_case() {
  : > "$COMMANDS"
  : > "$LOG_FILE"
  "$HELPER" 99 04 00
}

# The followed window is gone, target 00 is focused and empty, and source 04
# still has a terminal: return to 04.
: > "$ALL_WINDOWS"
printf '00\n' > "$FOCUSED_WORKSPACE"
printf '7441\n' > "$SOURCE_WINDOWS"
: > "$TARGET_WINDOWS"
run_case
[[ "$(cat "$COMMANDS")" == "workspace:04" ]]
grep -q 'returned from empty workspace=00 to source=04 window=99' "$LOG_FILE"

# Respect navigation elsewhere after launch.
printf '05\n' > "$FOCUSED_WORKSPACE"
run_case
[[ ! -s "$COMMANDS" ]]

# Do not leave a destination that still contains another window.
printf '00\n' > "$FOCUSED_WORKSPACE"
printf '123\n' > "$TARGET_WINDOWS"
run_case
[[ ! -s "$COMMANDS" ]]

# Do not switch to an empty source workspace.
: > "$TARGET_WINDOWS"
: > "$SOURCE_WINDOWS"
run_case
[[ ! -s "$COMMANDS" ]]

printf 'rehomed_window_close_watch_fake.sh: all checks passed\n'
