#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-assigned-rehome-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
HELPER="$TMP_ROOT/assigned_window_rehome.sh"
COMMANDS="$TMP_ROOT/commands.log"
LOG_FILE="$TMP_ROOT/window_state.log"
WINDOWS="$TMP_ROOT/windows"
FOCUSED="$TMP_ROOT/focused"

mkdir -p "$HOME/.config/aerospace" "$FAKE_BIN"

awk '/cat > "\$ASSIGNED_WINDOW_REHOME_HELPER" << '\''ASSIGNED_WINDOW_REHOME_EOF'\''/{in_block=1; next} /^ASSIGNED_WINDOW_REHOME_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$HELPER"

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  list-windows)
    if [[ "${2:-}" == "--focused" ]]; then
      cat "$OMARCHY_FAKE_FOCUSED"
    else
      cat "$OMARCHY_FAKE_WINDOWS"
    fi
    ;;
  move-node-to-workspace)
    printf '%s\n' "$*" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  workspace|focus)
    printf 'unexpected focus-changing command: %s\n' "$*" >&2
    exit 99
    ;;
  *)
    printf 'unexpected command: %s\n' "$*" >&2
    exit 98
    ;;
esac
EOF

chmod +x "$HELPER" "$FAKE_BIN/aerospace"
export OMARCHY_AEROSPACE_BIN="$FAKE_BIN/aerospace"
export OMARCHY_WINDOW_STATE_LOG="$LOG_FILE"
export OMARCHY_FAKE_COMMANDS="$COMMANDS"
export OMARCHY_FAKE_WINDOWS="$WINDOWS"
export OMARCHY_FAKE_FOCUSED="$FOCUSED"

printf '42|01|Google Chrome|com.google.Chrome|Reference site\n' > "$FOCUSED"
printf '99|07|Messages|com.apple.MobileSMS|New Message\n' > "$WINDOWS"
: > "$COMMANDS"

"$HELPER" 02 99

[[ "$(cat "$COMMANDS")" == "move-node-to-workspace --window-id 99 02" ]]
grep -q 'assigned window moved window=99 from=07 to=02 app=Messages bundle=com.apple.MobileSMS title=New Message' "$LOG_FILE"
grep -q 'focused_before=42|01|Google Chrome|com.google.Chrome|Reference site' "$LOG_FILE"
grep -q 'focused_after=42|01|Google Chrome|com.google.Chrome|Reference site; no workspace activation' "$LOG_FILE"

printf '99|02|Messages|com.apple.MobileSMS|New Message\n' > "$WINDOWS"
: > "$COMMANDS"
"$HELPER" 02 99
[[ ! -s "$COMMANDS" ]]
grep -q 'already=02.*no workspace activation' "$LOG_FILE"

printf 'assigned_window_rehome_fake.sh: all checks passed\n'
