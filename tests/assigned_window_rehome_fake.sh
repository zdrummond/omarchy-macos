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

# Assigned apps use the same exact-window broker contract as unassigned apps.
BROKER="$HOME/Applications/Omarchy Dock Launch.app/Contents/MacOS/dock_launch_follow"
mkdir -p "$(dirname "$BROKER")"
cat > "$BROKER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'broker:%s\n' "$*" >> "$OMARCHY_FAKE_COMMANDS"
case "$OMARCHY_FAKE_BROKER" in
  approve) exit 0 ;;
  denied|no-intent|dialog) exit 1 ;;
  timeout-moved)
    printf '11323|06|Gemini|com.google.GeminiMacOS|Gemini\n' > "$OMARCHY_FAKE_WINDOWS"
    exit 1 ;;
  user-moved)
    printf '11323|08|Gemini|com.google.GeminiMacOS|Gemini\n' > "$OMARCHY_FAKE_WINDOWS"
    exit 1 ;;
  vanished) : > "$OMARCHY_FAKE_WINDOWS"; exit 1 ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$BROKER"

for outcome in approve denied no-intent dialog timeout-moved user-moved vanished; do
  export OMARCHY_FAKE_BROKER="$outcome"
  printf '11323|01|Gemini|com.google.GeminiMacOS|Gemini\n' > "$WINDOWS"
  cp "$WINDOWS" "$FOCUSED"
  : > "$COMMANDS"
  "$HELPER" 06 11323
  [[ "$(head -n 1 "$COMMANDS")" == 'broker:--move 11323 01 06 com.google.GeminiMacOS' ]]
  case "$outcome" in
    denied|no-intent|dialog)
      [[ "$(tail -n 1 "$COMMANDS")" == 'move-node-to-workspace --window-id 11323 06' ]]
      [[ "$(wc -l < "$COMMANDS" | tr -d ' ')" == 2 ]] ;;
    *) [[ "$(wc -l < "$COMMANDS" | tr -d ' ')" == 1 ]] ;;
  esac
done
grep -q 'Dock-authorized assigned window moved and followed window=11323 from=01 to=06' "$LOG_FILE"
grep -q 'skipped stale assigned rehome window=11323 source=01 actual=08' "$LOG_FILE"
grep -q 'skipped stale assigned rehome window=11323 source=01 actual=gone' "$LOG_FILE"

# Already-placed windows never request a late follow, even with an active broker.
printf '11323|06|Gemini|com.google.GeminiMacOS|Gemini\n' > "$WINDOWS"
: > "$COMMANDS"
"$HELPER" 06 11323
[[ ! -s "$COMMANDS" ]]
printf 'assigned_window_rehome_fake.sh: all checks passed\n'
