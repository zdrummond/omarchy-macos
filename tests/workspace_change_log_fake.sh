#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-workspace-change-log-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_BIN="$TEST_ROOT/bin"
HELPER="$TEST_ROOT/workspace_change_log.sh"
LOG_FILE="$TEST_ROOT/window_state.log"
STATE_FILE="$TEST_ROOT/workspace_change.state"
mkdir -p "$FAKE_BIN"

awk '/cat > "\$WORKSPACE_CHANGE_LOG_HELPER" << '\''WORKSPACE_CHANGE_LOG_EOF'\''/{in_block=1; next} /^WORKSPACE_CHANGE_LOG_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$HELPER"

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list-windows)
    printf '42|04|iTerm2|com.googlecode.iterm2|shell\n'
    ;;
  list-monitors)
    printf '1\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$FAKE_BIN/aerospace" "$HELPER"

export OMARCHY_AEROSPACE_BIN="$FAKE_BIN/aerospace"
export OMARCHY_WINDOW_STATE_LOG="$LOG_FILE"
export OMARCHY_WORKSPACE_CHANGE_STATE="$STATE_FILE"

"$HELPER" 01 02
"$HELPER" 02 04

first="$(sed -n '1p' "$LOG_FILE")"
second="$(sed -n '2p' "$LOG_FILE")"
[[ "$first" == *'from=01 to=02 rapid=no delta_ms=unknown prior=none focused_monitor=1'* ]]
[[ "$second" == *'from=02 to=04 rapid=yes'* ]]
[[ "$second" == *'prior=01->02 focused_monitor=1'* ]]
[[ "$second" == *'focused_window=42|04|iTerm2|com.googlecode.iterm2|shell'* ]]

printf 'workspace_change_log_fake.sh: all checks passed\n'
