#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-responsive-layout-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
AEROSPACE_DIR="$HOME/.config/aerospace"
mkdir -p "$AEROSPACE_DIR"

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$AEROSPACE_DIR/omarchy_space_state.sh"
awk '/cat > "\$RESPONSIVE_LAYOUT_HELPER" << '\''RESPONSIVE_LAYOUT_EOF'\''/{in_block=1; next} /^RESPONSIVE_LAYOUT_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$AEROSPACE_DIR/responsive_layout.sh"
chmod +x "$AEROSPACE_DIR/"*.sh

FAKE_AEROSPACE="$TMP_ROOT/aerospace"
FAKE_FRAME="$TMP_ROOT/monitor_frame"
MONITOR_FILE="$TMP_ROOT/monitor.txt"
WORKSPACE_FILE="$TMP_ROOT/workspace.txt"
WINDOW_COUNT_FILE="$TMP_ROOT/window_count.txt"
WINDOW_FILE="$TMP_ROOT/windows.txt"
LAYOUT_FILE="$TMP_ROOT/layouts.txt"

cat > "$FAKE_AEROSPACE" <<'FAKE_AEROSPACE_EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  list-monitors)
    format="%{monitor-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --focused) shift ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    IFS='|' read -r id name screen_id < "$OMARCHY_FAKE_MONITOR"
    out="$format"
    out="${out//%\{monitor-id\}/$id}"
    out="${out//%\{monitor-name\}/$name}"
    out="${out//%\{monitor-appkit-nsscreen-screens-id\}/$screen_id}"
    printf '%s\n' "$out"
    ;;
  list-workspaces)
    if [[ "${1:-}" == "--focused" ]]; then
      cat "$OMARCHY_FAKE_WORKSPACE"
    else
      printf 'unexpected list-workspaces args: %s\n' "$*" >&2
      exit 1
    fi
    ;;
  list-windows)
    workspace=""
    count=0
    all=0
    format="%{window-id}|%{workspace}|%{monitor-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all) all=1; shift ;;
        --workspace) workspace="$2"; shift 2 ;;
        --count) count=1; shift ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$all" -eq 1 ]]; then
      while IFS='|' read -r id row_workspace monitor_id; do
        out="$format"
        out="${out//%\{window-id\}/$id}"
        out="${out//%\{workspace\}/$row_workspace}"
        out="${out//%\{monitor-id\}/$monitor_id}"
        printf '%s\n' "$out"
      done < "$OMARCHY_FAKE_WINDOWS"
      exit 0
    fi
    [[ "$workspace" == "$(cat "$OMARCHY_FAKE_WORKSPACE")" && "$count" -eq 1 ]] || exit 1
    cat "$OMARCHY_FAKE_WINDOW_COUNT"
    ;;
  layout)
    printf '%s\n' "$*" >> "$OMARCHY_FAKE_LAYOUTS"
    ;;
  *)
    printf 'unexpected fake aerospace command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
FAKE_AEROSPACE_EOF
chmod +x "$FAKE_AEROSPACE"

cat > "$FAKE_FRAME" <<'FAKE_FRAME_EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|900|Fake Display\n' "$OMARCHY_FAKE_WIDTH"
FAKE_FRAME_EOF
chmod +x "$FAKE_FRAME"

export OMARCHY_AEROSPACE_BIN="$FAKE_AEROSPACE"
export OMARCHY_MONITOR_FRAME_BIN="$FAKE_FRAME"
export OMARCHY_FAKE_MONITOR="$MONITOR_FILE"
export OMARCHY_FAKE_WORKSPACE="$WORKSPACE_FILE"
export OMARCHY_FAKE_WINDOW_COUNT="$WINDOW_COUNT_FILE"
export OMARCHY_FAKE_WINDOWS="$WINDOW_FILE"
export OMARCHY_FAKE_LAYOUTS="$LAYOUT_FILE"
export OMARCHY_WINDOW_STATE_LOG="$TMP_ROOT/layout.log"
export OMARCHY_LAYOUT_GUARD_DELAY=0

run_case() {
  local monitor="$1" width="$2" windows="$3" expected="$4"
  printf '%s\n' "$monitor" > "$MONITOR_FILE"
  printf '04\n' > "$WORKSPACE_FILE"
  printf '99|04|%s\n' "${monitor%%|*}" > "$WINDOW_FILE"
  printf '%s\n' "$windows" > "$WINDOW_COUNT_FILE"
  : > "$LAYOUT_FILE"
  OMARCHY_FAKE_WIDTH="$width" "$AEROSPACE_DIR/responsive_layout.sh" test 99
  actual="$(cat "$LAYOUT_FILE")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'width=%s windows=%s expected layout:\n%s\nactual:\n%s\n' "$width" "$windows" "$expected" "$actual" >&2
    exit 1
  fi
}

run_case "1|Built-in Retina Display|1" 1512 2 ""
run_case "1|Built-in Retina Display|1" 1512 3 "--window-id 99 accordion horizontal vertical"
run_case "2|Studio Display|2" 2560 3 ""
run_case "2|Studio Display|2" 2560 4 "--window-id 99 accordion horizontal vertical"

printf 'responsive_layout_fake.sh: all checks passed\n'
