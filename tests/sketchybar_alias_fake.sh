#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-sketchybar-alias-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export CONFIG_DIR="$HOME/.config/sketchybar"
AEROSPACE_DIR="$HOME/.config/aerospace"
FAKE_BIN="$TMP_ROOT/bin"
LOG_FILE="$TMP_ROOT/sketchybar.log"

mkdir -p "$CONFIG_DIR/plugins" "$AEROSPACE_DIR" "$FAKE_BIN"

cat > "$CONFIG_DIR/colors.sh" <<'EOF'
export TEXT=0xffffffff
export SUBTEXT=0xff888888
export BLUE=0xff0000ff
export MAUVE=0xffff00ff
export YELLOW=0xffffff00
export ITEM_BG_ACTIVE=0xff222222
EOF

cat > "$CONFIG_DIR/space_aliases" <<'EOF'
01=Mail
02=Msg
03=Music
04=Terms
EOF

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$AEROSPACE_DIR/omarchy_space_state.sh"

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
    focused=0
    mouse=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --focused) focused=1; shift ;;
        --mouse) mouse=1; shift ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$focused" == "1" || "$mouse" == "1" ]]; then
      rows=("1|Built-in Display|1")
    else
      rows=("1|Built-in Display|1" "2|Studio Display|2")
    fi
    for row in "${rows[@]}"; do
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
        --focused) printf '02\n'; exit 0 ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ "$visible" == "1" ]]
    case "$monitor" in
      1) workspace="02" ;;
      2) workspace="12" ;;
      *) workspace="" ;;
    esac
    printf '%s\n' "${format//%\{workspace\}/$workspace}"
    ;;
  list-windows)
    format="%{workspace}|%{app-name}|%{app-bundle-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all) shift ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    for row in \
      "02|Messages|com.apple.MobileSMS" \
      "04|iTerm2|com.googlecode.iterm2" \
      "04|Google Chrome|com.google.Chrome"
    do
      workspace="${row%%|*}"
      rest="${row#*|}"
      app="${rest%%|*}"
      bundle="${rest#*|}"
      out="$format"
      out="${out//%\{workspace\}/$workspace}"
      out="${out//%\{app-name\}/$app}"
      out="${out//%\{app-bundle-id\}/$bundle}"
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

source "$CONFIG_DIR/plugins/spaces.sh"
highlight_space "02"

flattened="$(tr '\n' ' ' < "$LOG_FILE")"
[[ "$flattened" == *"<space.0.2>"*"<label=Msg>"* ]]
[[ "$flattened" == *"<space.0.1>"*"<label=Mail>"* ]]
[[ "$flattened" == *"<space.0.3>"*"<label=Music>"* ]]
[[ "$flattened" == *"<space.0.4>"*"<label=Terms, Google Chrome>"* ]]
[[ "$flattened" != *"<space.0.4>"*"<label=Terms, iTerm2"* ]]
[[ "$flattened" != *"<space.0.2>"*"<label=Messages>"* ]]
[[ "$flattened" == *"<space.1.2>"*"<label=[empty]>"* ]]
[[ "$flattened" != *"<space.1.2>"*"<label=Msg>"* ]]

printf 'sketchybar_alias_fake.sh: all checks passed\n'
