#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-goto-space-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
CONFIG_DIR="$HOME/.config/aerospace"
SKETCHY_DIR="$HOME/.config/sketchybar/plugins"
FAKE_BIN="$TMP_ROOT/bin"
LOG_FILE="$TMP_ROOT/calls.log"

mkdir -p "$CONFIG_DIR" "$SKETCHY_DIR" "$FAKE_BIN"

awk '/cat > "\$AEROSPACE_DIR\/goto_space.sh" << '\''GOTO_SPACE_EOF'\''/{in_block=1; next} /^GOTO_SPACE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/goto_space.sh"
chmod +x "$CONFIG_DIR/goto_space.sh"

cat > "$CONFIG_DIR/omarchy_space_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

omarchy_workspace_for_key() {
  printf '0%s\n' "$1"
}

omarchy_monitor_id_for_slot() {
  [ "$1" = "0" ] || return 1
  printf '1\n'
}

omarchy_repair_detached_monitor_workspaces() {
  printf 'repair\n' >> "$OMARCHY_TEST_LOG"
}

omarchy_switch_workspace_on_slot_monitor() {
  printf 'switch:%s\n' "$1" >> "$OMARCHY_TEST_LOG"
}
EOF

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'aerospace:%s\n' "$*" >> "$OMARCHY_TEST_LOG"
EOF
chmod +x "$FAKE_BIN/aerospace"

cat > "$CONFIG_DIR/window_state_debounced_save.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'save:%s\n' "${1:-}" >> "$OMARCHY_TEST_LOG"
EOF

cat > "$CONFIG_DIR/responsive_layout.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'responsive:%s\n' "${1:-}" >> "$OMARCHY_TEST_LOG"
EOF

cat > "$SKETCHY_DIR/hide_bar.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'hide-bar\n' >> "$OMARCHY_TEST_LOG"
EOF

chmod +x "$CONFIG_DIR"/*.sh "$SKETCHY_DIR"/*.sh
export PATH="$FAKE_BIN:$PATH"
export OMARCHY_TEST_LOG="$LOG_FILE"

"$CONFIG_DIR/goto_space.sh" 5 --move
expected=$'repair\naerospace:move-node-to-workspace 05\nsave:move-node-to-workspace-05\nresponsive:move-node-to-workspace-05'
actual="$(cat "$LOG_FILE")"
[[ "$actual" == "$expected" ]]

: > "$LOG_FILE"
"$CONFIG_DIR/goto_space.sh" 3
expected=$'repair\nswitch:03\nresponsive:workspace-03\nhide-bar'
actual="$(cat "$LOG_FILE")"
[[ "$actual" == "$expected" ]]

printf 'goto_space_fake.sh: all checks passed\n'
