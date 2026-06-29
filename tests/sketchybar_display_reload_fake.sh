#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-sketchybar-display-reload-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export TMPDIR="$TMP_ROOT/tmp"
export HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
PLUGIN="$TMP_ROOT/display_reload.sh"
LOG_FILE="$TMP_ROOT/window_state.log"
SKETCHYBAR_LOG="$TMP_ROOT/sketchybar.log"
RESTORE_STATUS_LOG="$TMP_ROOT/restore_status.log"
TOPOLOGY_FILE="$TMP_ROOT/topology.txt"

mkdir -p "$TMPDIR" "$FAKE_BIN" "$HOME/.config/sketchybar/plugins"
: > "$LOG_FILE"
: > "$SKETCHYBAR_LOG"
: > "$RESTORE_STATUS_LOG"

awk '/cat > "\$SKETCHY_DIR\/plugins\/display_reload.sh" << '\''DISPLAY_RELOAD_PLUGIN_EOF'\''/{in_block=1; next} /^DISPLAY_RELOAD_PLUGIN_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$PLUGIN"
chmod +x "$PLUGIN"

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  list-monitors)
    format="%{monitor-id}|%{monitor-name}|%{monitor-appkit-nsscreen-screens-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    while IFS='|' read -r id name screen_id; do
      [ -n "$id" ] || continue
      out="$format"
      out="${out//%\{monitor-id\}/$id}"
      out="${out//%\{monitor-name\}/$name}"
      out="${out//%\{monitor-appkit-nsscreen-screens-id\}/$screen_id}"
      printf '%s\n' "$out"
    done < "$OMARCHY_FAKE_TOPOLOGY"
    ;;
  *)
    printf 'unexpected fake aerospace command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$FAKE_BIN/aerospace"

cat > "$FAKE_BIN/sketchybar" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OMARCHY_FAKE_SKETCHYBAR_LOG"
EOF
chmod +x "$FAKE_BIN/sketchybar"

cat > "$HOME/.config/sketchybar/plugins/restore_status.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${1:-missing}" >> "$OMARCHY_FAKE_RESTORE_STATUS_LOG"
EOF
chmod +x "$HOME/.config/sketchybar/plugins/restore_status.sh"

run_plugin() {
  OMARCHY_WINDOW_STATE_LOG="$LOG_FILE" \
  OMARCHY_FAKE_SKETCHYBAR_LOG="$SKETCHYBAR_LOG" \
  OMARCHY_FAKE_RESTORE_STATUS_LOG="$RESTORE_STATUS_LOG" \
  OMARCHY_FAKE_TOPOLOGY="$TOPOLOGY_FILE" \
  PATH="$FAKE_BIN:$PATH" \
  "$PLUGIN"
  sleep 1.2
}

printf '%s\n' \
  "1|Built-in Retina Display|1" \
  "2|Studio Display|2" \
  > "$TOPOLOGY_FILE"

run_plugin
first_count="$(grep -c -- '--reload' "$SKETCHYBAR_LOG" || true)"
[[ "$first_count" = "1" ]]
first_refresh_count="$(grep -c '^refresh$' "$RESTORE_STATUS_LOG" || true)"
[[ "$first_refresh_count" = "1" ]]

run_plugin
same_count="$(grep -c -- '--reload' "$SKETCHYBAR_LOG" || true)"
[[ "$same_count" = "1" ]]
same_refresh_count="$(grep -c '^refresh$' "$RESTORE_STATUS_LOG" || true)"
[[ "$same_refresh_count" = "1" ]]

printf '%s\n' \
  "1|Built-in Retina Display|1" \
  "2|Studio Display|2" \
  "3|Pro Display XDR|3" \
  > "$TOPOLOGY_FILE"

OMARCHY_SKETCHYBAR_DISPLAY_RELOAD_INTERVAL=0 run_plugin
changed_count="$(grep -c -- '--reload' "$SKETCHYBAR_LOG" || true)"
[[ "$changed_count" = "2" ]]
changed_refresh_count="$(grep -c '^refresh$' "$RESTORE_STATUS_LOG" || true)"
[[ "$changed_refresh_count" = "2" ]]

printf 'sketchybar_display_reload_fake.sh: all checks passed\n'
