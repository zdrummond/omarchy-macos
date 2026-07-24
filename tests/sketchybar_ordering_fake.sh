#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-sketchybar-ordering-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export CONFIG_DIR="$HOME/.config/sketchybar"
AEROSPACE_DIR="$HOME/.config/aerospace"
FAKE_BIN="$TMP_ROOT/bin"
ITEMS_FILE="$TMP_ROOT/items.txt"

mkdir -p "$CONFIG_DIR/items" "$CONFIG_DIR/plugins" "$AEROSPACE_DIR" "$FAKE_BIN"
: > "$ITEMS_FILE"

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

cat > "$CONFIG_DIR/space_aliases" <<'EOF'
01=Mail
02=Msg
03=Music
04=Terms
05=Editors
06=Agents
EOF

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$AEROSPACE_DIR/omarchy_space_state.sh"

awk '/cat > "\$SKETCHY_DIR\/items\/spaces.sh" << '\''SPACES_ITEM_EOF'\''/{in_block=1; next} /^SPACES_ITEM_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/items/spaces.sh"

awk '/cat > "\$SKETCHY_DIR\/plugins\/spaces.sh" << '\''SPACES_PLUGIN_EOF'\''/{in_block=1; next} /^SPACES_PLUGIN_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/plugins/spaces.sh"

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true
case "$cmd" in
  list-monitors)
    if [[ "${1:-}" == "--focused" ]]; then
      printf '1\n'
    else
      printf '1\n'
    fi
    ;;
  list-workspaces)
    printf '01\n'
    ;;
  list-windows)
    printf '01|Mail|com.apple.mail\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$FAKE_BIN/aerospace"

cat > "$FAKE_BIN/sketchybar" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

items_file="$OMARCHY_FAKE_SKETCHYBAR_ITEMS"
case "${1:-}" in
  --add)
    name="${3:-}"
    grep -Fxq "$name" "$items_file" 2>/dev/null || printf '%s\n' "$name" >> "$items_file"
    ;;
  --remove)
    name="${2:-}"
    awk -v name="$name" '$0 != name' "$items_file" > "$items_file.next"
    mv "$items_file.next" "$items_file"
    ;;
  --order)
    shift
    : > "$items_file.next"
    for name in "$@"; do
      grep -Fxq "$name" "$items_file" && printf '%s\n' "$name" >> "$items_file.next"
    done
    while IFS= read -r existing; do
      found=0
      for name in "$@"; do
        if [[ "$existing" == "$name" ]]; then
          found=1
          break
        fi
      done
      [[ "$found" == "1" ]] || printf '%s\n' "$existing" >> "$items_file.next"
    done < "$items_file"
    mv "$items_file.next" "$items_file"
    ;;
  --set|--bar|--update|--trigger)
    ;;
  --query)
    grep -Fxq "${2:-}" "$items_file"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$FAKE_BIN/sketchybar"

export PATH="$FAKE_BIN:$PATH"
export OMARCHY_AEROSPACE_BIN="$FAKE_BIN/aerospace"
export OMARCHY_FAKE_SKETCHYBAR_ITEMS="$ITEMS_FILE"

bash "$CONFIG_DIR/items/spaces.sh"
expected=$'space.0.1\nspace.0.2\nspace.0.3\nspace.0.4\nspace.0.5\nspace.0.6\nspace.0.7\nspace.0.8\nspace.0.9\nspace.0.0\nspaces_separator.0'
[[ "$(cat "$ITEMS_FILE")" == "$expected" ]]

sketchybar --remove space.0.9
sketchybar --remove space.0.0
source "$CONFIG_DIR/plugins/spaces.sh"
highlight_space "01"
! grep -Eq '^space\.0\.(9|0)$' "$ITEMS_FILE"

bash "$CONFIG_DIR/items/spaces.sh"
[[ "$(cat "$ITEMS_FILE")" == "$expected" ]]

printf 'sketchybar_ordering_fake.sh: all checks passed\n'
