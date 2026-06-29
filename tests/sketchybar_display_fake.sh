#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-sketchybar-display-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export CONFIG_DIR="$HOME/.config/sketchybar"
AEROSPACE_DIR="$HOME/.config/aerospace"
FAKE_BIN="$TMP_ROOT/bin"
LOG_FILE="$TMP_ROOT/sketchybar.log"

mkdir -p "$CONFIG_DIR/items" "$AEROSPACE_DIR" "$FAKE_BIN"
mkdir -p "$CONFIG_DIR/plugins"

cat > "$CONFIG_DIR/colors.sh" <<'EOF'
export TEXT=0xffffffff
export SUBTEXT=0xff888888
export BLUE=0xff0000ff
export MAUVE=0xffff00ff
export YELLOW=0xffffff00
export PEACH=0xffffaa00
export ITEM_BG=0xff222222
export ITEM_BG_ACTIVE=0xff333333
EOF

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$AEROSPACE_DIR/omarchy_space_state.sh"

awk '/cat > "\$SKETCHY_DIR\/items\/spaces.sh" << '\''SPACES_ITEM_EOF'\''/{in_block=1; next} /^SPACES_ITEM_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/items/spaces.sh"

awk '/cat > "\$SKETCHY_DIR\/items\/monitor.sh" << '\''MONITOR_ITEM_EOF'\''/{in_block=1; next} /^MONITOR_ITEM_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/items/monitor.sh"

awk '/cat > "\$SKETCHY_DIR\/plugins\/spaces.sh" << '\''SPACES_PLUGIN_EOF'\''/{in_block=1; next} /^SPACES_PLUGIN_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/plugins/spaces.sh"

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  list-monitors)
    format="%{monitor-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    for row in \
      "1|Pro Display XDR|2" \
      "2|LEN P32p-20|3" \
      "3|Built-in Retina Display|1"
    do
      IFS='|' read -r id name screen_id <<< "$row"
      out="$format"
      out="${out//%\{monitor-id\}/$id}"
      out="${out//%\{monitor-name\}/$name}"
      out="${out//%\{monitor-appkit-nsscreen-screens-id\}/$screen_id}"
      printf '%s\n' "$out"
    done
    ;;
  list-workspaces)
    monitor=""
    visible=0
    format="%{workspace}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --monitor) monitor="$2"; shift 2 ;;
        --visible) visible=1; shift ;;
        --focused) printf '11\n'; exit 0 ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ "$visible" == "1" ]]
    case "$monitor" in
      1) workspace="11" ;;
      2) workspace="20" ;;
      3) workspace="04" ;;
      *) workspace="" ;;
    esac
    printf '%s\n' "${format//%\{workspace\}/$workspace}"
    ;;
  list-windows)
    format="%{workspace}|%{app-name}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all) shift ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    for row in "11|System Settings" "20|Notes" "04|iTerm2"; do
      workspace="${row%%|*}"
      app="${row#*|}"
      out="$format"
      out="${out//%\{workspace\}/$workspace}"
      out="${out//%\{app-name\}/$app}"
      printf '%s\n' "$out"
    done
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
printf '<%s>\n' "$@" >> "$OMARCHY_SKETCHYBAR_LOG"
printf '<END>\n' >> "$OMARCHY_SKETCHYBAR_LOG"
EOF
chmod +x "$FAKE_BIN/sketchybar"

export PATH="$FAKE_BIN:$PATH"
export OMARCHY_AEROSPACE_BIN="$FAKE_BIN/aerospace"
export OMARCHY_SKETCHYBAR_LOG="$LOG_FILE"

bash "$CONFIG_DIR/items/spaces.sh"
bash "$CONFIG_DIR/items/monitor.sh"

flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<space.0.1>"*"<display=1>"* ]]
[[ "$flattened" == *"<space.1.1>"*"<display=3>"* ]]
[[ "$flattened" == *"<space.2.1>"*"<display=2>"* ]]
[[ "$flattened" == *"<monitor.0>"*"<display=1>"* ]]
[[ "$flattened" == *"<monitor.1>"*"<display=3>"* ]]
[[ "$flattened" == *"<monitor.2>"*"<display=2>"* ]]

: > "$LOG_FILE"
source "$CONFIG_DIR/plugins/spaces.sh"
highlight_space "11"
flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<space.1.1>"*"<display=3>"*"<label=System Settings>"* ]]
[[ "$flattened" == *"<space.2.0>"*"<display=2>"*"<label=Notes>"* ]]
[[ "$flattened" == *"<monitor.1>"*"<display=3>"*"<label=1>"* ]]
[[ "$flattened" == *"<monitor.2>"*"<display=2>"*"<label=2>"* ]]

printf 'sketchybar_display_fake.sh: all checks passed\n'
