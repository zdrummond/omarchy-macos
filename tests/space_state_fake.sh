#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-space-state-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HELPER="$TMP_ROOT/omarchy_space_state.sh"
FAKE_AEROSPACE="$TMP_ROOT/aerospace"
WINDOWS_FILE="$TMP_ROOT/windows.txt"
MOVES_FILE="$TMP_ROOT/moves.txt"

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$HELPER"

cat > "$FAKE_AEROSPACE" <<'FAKE_AEROSPACE_EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "$cmd" in
  list-monitors)
    if [[ "${OMARCHY_FAKE_HANG_MONITORS:-0}" == "1" ]]; then
      sleep 30
      exit 0
    fi
    printf '1|Built-in Retina Display|1\n'
    ;;
  list-windows)
    format="%{window-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all) shift ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    while IFS='|' read -r id workspace app bundle; do
      [[ -n "$id" ]] || continue
      out="$format"
      out="${out//%\{window-id\}/$id}"
      out="${out//%\{workspace\}/$workspace}"
      out="${out//%\{app-name\}/$app}"
      out="${out//%\{app-bundle-id\}/$bundle}"
      printf '%s\n' "$out"
    done < "$OMARCHY_FAKE_WINDOWS"
    ;;
  move-node-to-workspace)
    [[ "${1:-}" == "--window-id" ]]
    window_id="$2"
    target="$3"
    printf '%s|%s\n' "$window_id" "$target" >> "$OMARCHY_FAKE_MOVES"
    ;;
  *)
    printf 'unexpected fake aerospace command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
FAKE_AEROSPACE_EOF
chmod +x "$FAKE_AEROSPACE"

export OMARCHY_AEROSPACE_BIN="$FAKE_AEROSPACE"
export OMARCHY_FAKE_WINDOWS="$WINDOWS_FILE"
export OMARCHY_FAKE_MOVES="$MOVES_FILE"

printf '%s\n' \
  "101|07|Signal|org.whispersystems.signal-desktop" \
  "102|09|Messages|com.apple.MobileSMS" \
  "103|03|Music|com.apple.Music" \
  "104|08|Steam|com.valvesoftware.steam" \
  "105|02|Bear|net.shinyfrog.bear" \
  "106|05|Google Chat|com.google.Chrome.app.google-chat" \
  "107|09|Gmail|com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm" \
  "108|04|TV|com.apple.TV" \
  "109|01|Bear|net.shinyfrog.bear" \
  "110|01|Maps|com.apple.Maps" \
  "111|01|Notes|com.apple.Notes" \
  > "$WINDOWS_FILE"
: > "$MOVES_FILE"

source "$HELPER"
omarchy_repair_app_assigned_workspaces

expected=$'101|02\n102|02\n105|08\n106|02\n107|01\n108|07\n109|09\n110|00\n111|00'
actual="$(cat "$MOVES_FILE")"
if [[ "$actual" != "$expected" ]]; then
  printf 'expected moves:\n%s\nactual moves:\n%s\n' "$expected" "$actual" >&2
  exit 1
fi

started_seconds="$(date +%s)"
if OMARCHY_FAKE_HANG_MONITORS=1 OMARCHY_COMMAND_TIMEOUT_SECONDS=1 \
  omarchy_monitor_rows_by_slot >/dev/null 2>&1; then
  printf 'hung monitor query unexpectedly succeeded\n' >&2
  exit 1
fi
finished_seconds="$(date +%s)"
[[ $((finished_seconds - started_seconds)) -lt 5 ]]

printf 'space_state_fake.sh: all checks passed\n'
