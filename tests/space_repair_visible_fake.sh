#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-space-repair-visible-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HELPER="$TMP_ROOT/omarchy_space_state.sh"
FAKE_AEROSPACE="$TMP_ROOT/aerospace"
COMMANDS_FILE="$TMP_ROOT/commands.txt"

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$HELPER"

cat > "$FAKE_AEROSPACE" <<'FAKE_AEROSPACE_EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  list-monitors)
    focused=0
    mouse=0
    format="%{monitor-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --focused) focused=1; shift ;;
        --mouse) mouse=1; shift ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$focused" == "1" || "$mouse" == "1" ]]; then
      rows=("3|Built-in Retina Display|1")
    else
      rows=("1|Pro Display XDR|2" "2|LEN P32p-20|3" "3|Built-in Retina Display|1")
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
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    [[ "$visible" == "1" ]]
    case "$monitor" in
      1) workspace="1" ;;
      2) workspace="10" ;;
      3) workspace="04" ;;
      *) workspace="" ;;
    esac
    printf '%s\n' "${format//%\{workspace\}/$workspace}"
    ;;
  list-windows)
    workspace=""
    all=0
    format="%{window-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all) all=1; shift ;;
        --workspace) workspace="$2"; shift 2 ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$all" == "1" ]]; then
      printf '900|04\n'
    elif [[ "$workspace" == "1" ]]; then
      printf '101\n'
    fi
    ;;
  move-node-to-workspace)
    [[ "${1:-}" == "--window-id" ]]
    printf 'move-node-to-workspace %s %s\n' "$2" "$3" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  move-workspace-to-monitor)
    [[ "${1:-}" == "--workspace" ]]
    printf 'move-workspace-to-monitor %s %s\n' "$2" "$3" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  workspace)
    printf 'workspace %s\n' "$1" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  focus-monitor)
    printf 'focus-monitor %s\n' "$1" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  *)
    printf 'unexpected fake aerospace command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
FAKE_AEROSPACE_EOF
chmod +x "$FAKE_AEROSPACE"

export OMARCHY_AEROSPACE_BIN="$FAKE_AEROSPACE"
export OMARCHY_FAKE_COMMANDS="$COMMANDS_FILE"
: > "$COMMANDS_FILE"

source "$HELPER"
omarchy_repair_detached_monitor_workspaces

expected=$'move-node-to-workspace 101 11\nmove-workspace-to-monitor 11 1\nfocus-monitor 1\nworkspace 11\nfocus-monitor 1\nmove-workspace-to-monitor 10 1\nmove-workspace-to-monitor 20 2\nfocus-monitor 2\nworkspace 20\nfocus-monitor 2'
actual="$(cat "$COMMANDS_FILE")"
if [[ "$actual" != "$expected" ]]; then
  printf 'expected commands:\n%s\nactual commands:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

printf 'space_repair_visible_fake.sh: all checks passed\n'
