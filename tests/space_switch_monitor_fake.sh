#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-space-switch-monitor-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HELPER="$TMP_ROOT/omarchy_space_state.sh"
FAKE_AEROSPACE="$TMP_ROOT/aerospace"
STATE_DIR="$TMP_ROOT/state"
COMMANDS_FILE="$TMP_ROOT/commands.txt"

mkdir -p "$STATE_DIR"

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$HELPER"

cat > "$FAKE_AEROSPACE" <<'FAKE_AEROSPACE_EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  list-monitors)
    printf '1|Built-in Retina Display|1\n2|Pro Display XDR|2\n3|Studio Display|3\n'
    ;;
  list-workspaces)
    monitor=""
    visible=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --monitor) monitor="$2"; shift 2 ;;
        --visible) visible=1; shift ;;
        --format) shift 2 ;;
        *) shift ;;
      esac
    done
    [[ "$visible" == "1" ]]
    cat "$OMARCHY_FAKE_STATE/visible.$monitor"
    ;;
  focus-monitor)
    printf '%s\n' "$1" > "$OMARCHY_FAKE_STATE/focused"
    printf 'focus-monitor %s\n' "$1" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  move-workspace-to-monitor)
    [[ "${1:-}" == "--workspace" ]]
    workspace="$2"
    monitor="$3"
    printf '%s\n' "$monitor" > "$OMARCHY_FAKE_STATE/assigned.$workspace"
    printf 'move-workspace-to-monitor %s %s\n' "$workspace" "$monitor" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  workspace)
    workspace="$1"
    if [[ -e "$OMARCHY_FAKE_STATE/assigned.$workspace" ]]; then
      monitor="$(cat "$OMARCHY_FAKE_STATE/assigned.$workspace")"
    else
      monitor="$(cat "$OMARCHY_FAKE_STATE/focused")"
      printf '%s\n' "$monitor" > "$OMARCHY_FAKE_STATE/assigned.$workspace"
    fi
    printf '%s\n' "$workspace" > "$OMARCHY_FAKE_STATE/visible.$monitor"
    printf '%s\n' "$monitor" > "$OMARCHY_FAKE_STATE/focused"
    printf 'workspace %s\n' "$workspace" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  move-mouse)
    [[ "${1:-}" == "monitor-lazy-center" ]]
    printf 'move-mouse monitor-lazy-center\n' >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  *)
    printf 'unexpected fake aerospace command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
FAKE_AEROSPACE_EOF
chmod +x "$FAKE_AEROSPACE"

export OMARCHY_AEROSPACE_BIN="$FAKE_AEROSPACE"
export OMARCHY_FAKE_STATE="$STATE_DIR"
export OMARCHY_FAKE_COMMANDS="$COMMANDS_FILE"

# Reproduce a stale post-attach layout: both secondary-slot targets are still
# assigned to the built-in display because the force-assignment table predates
# the external monitors.
printf '1\n' > "$STATE_DIR/focused"
printf '04\n' > "$STATE_DIR/visible.1"
printf '11\n' > "$STATE_DIR/visible.2"
printf '27\n' > "$STATE_DIR/visible.3"
printf '1\n' > "$STATE_DIR/assigned.04"
printf '2\n' > "$STATE_DIR/assigned.11"
printf '3\n' > "$STATE_DIR/assigned.27"
printf '1\n' > "$STATE_DIR/assigned.12"
printf '1\n' > "$STATE_DIR/assigned.23"
: > "$COMMANDS_FILE"

source "$HELPER"

omarchy_switch_workspace_on_slot_monitor 12
[[ "$(cat "$STATE_DIR/visible.1")" == "04" ]]
[[ "$(cat "$STATE_DIR/visible.2")" == "12" ]]
[[ "$(cat "$STATE_DIR/visible.3")" == "27" ]]
[[ "$(cat "$STATE_DIR/assigned.12")" == "2" ]]
[[ "$(cat "$STATE_DIR/focused")" == "2" ]]

omarchy_switch_workspace_on_slot_monitor 23
[[ "$(cat "$STATE_DIR/visible.1")" == "04" ]]
[[ "$(cat "$STATE_DIR/visible.2")" == "12" ]]
[[ "$(cat "$STATE_DIR/visible.3")" == "23" ]]
[[ "$(cat "$STATE_DIR/assigned.23")" == "3" ]]
[[ "$(cat "$STATE_DIR/focused")" == "3" ]]

expected=$'focus-monitor 2\nmove-workspace-to-monitor 12 2\nworkspace 12\nworkspace 04\nworkspace 27\nfocus-monitor 2\nmove-mouse monitor-lazy-center\nfocus-monitor 3\nmove-workspace-to-monitor 23 3\nworkspace 23\nworkspace 04\nworkspace 12\nfocus-monitor 3\nmove-mouse monitor-lazy-center'
actual="$(cat "$COMMANDS_FILE")"
if [[ "$actual" != "$expected" ]]; then
  printf 'expected commands:\n%s\nactual commands:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

printf 'space_switch_monitor_fake.sh: all checks passed\n'
