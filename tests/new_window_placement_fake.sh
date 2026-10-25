#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-new-window-placement-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
export TMPDIR="$TMP_ROOT/tmp"
CONFIG_DIR="$HOME/.config/aerospace"
SKETCHY_DIR="$HOME/.config/sketchybar"
FAKE_BIN="$TMP_ROOT/bin"
WINDOWS_FILE="$TMP_ROOT/windows.txt"
FOCUSED_FILE="$TMP_ROOT/focused.txt"
COMMANDS_FILE="$TMP_ROOT/commands.txt"
LOG_FILE="$TMP_ROOT/window_state.log"
GUARD_FILE="$TMPDIR/omarchy_window_state_restore_active"
NATIVE_INPUT_FILE="$TMPDIR/omarchy_native_input_active"
LAUNCH_STATE="$TMPDIR/omarchy_last_launch_placement"
LOCK_DIR="$TMPDIR/omarchy_window_placement.lock"
ALIAS_FILE="$SKETCHY_DIR/space_aliases"
HELPER="$CONFIG_DIR/new_window_placement.sh"

mkdir -p "$CONFIG_DIR" "$SKETCHY_DIR" "$FAKE_BIN" "$TMPDIR"

# macOS /bin/bash 3.2 does not exit on a failed [[ ]] under set -e, so every
# [[ ]] assertion here must fail explicitly.
fail() { printf 'assertion failed (line %s)\n' "${BASH_LINENO[0]}" >&2; [[ ! -s "$LOG_FILE" ]] || cat "$LOG_FILE" >&2; exit 1; }

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/omarchy_space_state.sh"
awk '/cat > "\$NEW_WINDOW_PLACEMENT_HELPER" << '\''NEW_WINDOW_PLACEMENT_EOF'\''/{in_block=1; next} /^NEW_WINDOW_PLACEMENT_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$HELPER"
[[ -s "$HELPER" ]] || fail

# Rows: id|workspace|app|bundle|title|layout. The fake applies moves to the
# window list, and a following move also makes the moved window focused.
cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

format_row() {
  local format="$1" id="$2" workspace="$3" app="$4" bundle="$5" title="$6" layout="$7"
  local out="$format"
  out="${out//%\{window-id\}/$id}"
  out="${out//%\{workspace\}/$workspace}"
  out="${out//%\{app-name\}/$app}"
  out="${out//%\{app-bundle-id\}/$bundle}"
  out="${out//%\{window-layout\}/$layout}"
  out="${out//%\{window-title\}/$title}"
  printf '%s\n' "$out"
}

print_rows() {
  local format="$1" file="$2"
  while IFS='|' read -r id workspace app bundle title layout; do
    [[ -n "$id" ]] || continue
    format_row "$format" "$id" "$workspace" "$app" "$bundle" "$title" "${layout:-h_tiles}"
  done < "$file"
}

case "$cmd" in
  list-monitors)
    printf '1\n'
    ;;
  list-windows)
    focused=0
    format="%{window-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --focused) focused=1; shift ;;
        --all) shift ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$focused" == "1" ]]; then
      print_rows "$format" "$OMARCHY_FAKE_FOCUSED"
    else
      print_rows "$format" "$OMARCHY_FAKE_WINDOWS"
    fi
    ;;
  move-node-to-workspace)
    [[ "${1:-}" == "--window-id" ]] || exit 1
    id="$2"
    shift 2
    follow=0
    if [[ "${1:-}" == "--focus-follows-window" ]]; then
      follow=1
      shift
    fi
    target="$1"
    if [[ "$follow" == 1 ]]; then
      printf 'move-follow:%s:%s\n' "$id" "$target" >> "$OMARCHY_FAKE_COMMANDS"
    else
      printf 'move:%s:%s\n' "$id" "$target" >> "$OMARCHY_FAKE_COMMANDS"
    fi
    [[ "${OMARCHY_FAKE_MOVE_FAIL:-0}" == 0 ]] || exit 1
    awk -F'|' -v OFS='|' -v id="$id" -v target="$target" '$1 == id { $2 = target } { print }' \
      "$OMARCHY_FAKE_WINDOWS" > "$OMARCHY_FAKE_WINDOWS.tmp"
    mv "$OMARCHY_FAKE_WINDOWS.tmp" "$OMARCHY_FAKE_WINDOWS"
    if [[ "$follow" == 1 ]]; then
      awk -F'|' -v id="$id" '$1 == id' "$OMARCHY_FAKE_WINDOWS" > "$OMARCHY_FAKE_FOCUSED"
    fi
    ;;
  layout)
    [[ "${1:-}" == "--window-id" ]] || exit 1
    printf 'layout:%s:%s\n' "${2:-}" "${3:-}" >> "$OMARCHY_FAKE_COMMANDS"
    [[ "${OMARCHY_FAKE_LAYOUT_FAIL:-0}" == 0 ]] || exit 1
    ;;
  *)
    # workspace/focus or anything else would be an unrequested focus change.
    printf 'unexpected fake aerospace command: %s %s\n' "$cmd" "$*" >> "$OMARCHY_FAKE_COMMANDS"
    exit 1
    ;;
esac
EOF

cat > "$CONFIG_DIR/window_state_debounced_save.sh" <<'EOF'
#!/usr/bin/env bash
printf 'save:%s\n' "${1:-}" >> "$OMARCHY_FAKE_COMMANDS"
EOF

cat > "$CONFIG_DIR/responsive_layout.sh" <<'EOF'
#!/usr/bin/env bash
printf 'responsive:%s:%s\n' "${1:-}" "${2:-}" >> "$OMARCHY_FAKE_COMMANDS"
EOF

chmod +x "$CONFIG_DIR"/*.sh "$FAKE_BIN/aerospace"
export PATH="$FAKE_BIN:$PATH"
export OMARCHY_AEROSPACE_BIN="$FAKE_BIN/aerospace"
export OMARCHY_FAKE_WINDOWS="$WINDOWS_FILE"
export OMARCHY_FAKE_FOCUSED="$FOCUSED_FILE"
export OMARCHY_FAKE_COMMANDS="$COMMANDS_FILE"
export OMARCHY_WINDOW_STATE_LOG="$LOG_FILE"
export OMARCHY_SPACE_ALIAS_FILE="$ALIAS_FILE"
# Most cases decide immediately; the late-focus case raises this.
export OMARCHY_FRONT_WAIT_MS=0

write_default_aliases() {
  cat > "$ALIAS_FILE" <<'EOF'
01=Mail
02=Msg
03=Music
04=Terms
05=Editors
06=Agents
EOF
}

# windows <rows...>; the focused file is set separately with `focus_row`.
windows() { printf '%s\n' "$@" > "$WINDOWS_FILE"; }
focus_row() { printf '%s\n' "$1" > "$FOCUSED_FILE"; }

run_case() {
  : > "$COMMANDS_FILE"
  : > "$LOG_FILE"
  rm -f "$LAUNCH_STATE"
  "$HELPER" "$1"
  [[ ! -e "$LOCK_DIR" ]] || fail
  ! grep -q 'unexpected fake aerospace command' "$COMMANDS_FILE" || { cat "$COMMANDS_FILE" >&2; exit 1; }
}

expect() {
  local expected="$1" actual
  actual="$(cat "$COMMANDS_FILE")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

write_default_aliases

# --- Launches move and follow -------------------------------------------------

# The 11:43 incident: Option+Command+= from the Terminal workspace creates a
# Chrome window on 04. Chrome becomes frontmost there, so it moves and follows.
windows '392|04|iTerm2|com.googlecode.iterm2|Shell' '4456|04|Google Chrome|com.google.Chrome|New Tab'
focus_row '4456|04|Google Chrome|com.google.Chrome|New Tab'
run_case 4456
expect $'move-follow:4456:07\nsave:launch-placement-07\nresponsive:launch-placement-07:4456'
grep -Fq 'launch placement moved and followed window=4456 from=04 to=07' "$LOG_FILE"
IFS='|' read -r _ state_bundle state_target < "$LAUNCH_STATE"
[[ "$state_bundle" == com.google.Chrome && "$state_target" == 07 ]] || fail

# Focus that lands shortly after detection still counts as the launch.
windows '392|04|iTerm2|com.googlecode.iterm2|Shell' '63|04|Bear|net.shinyfrog.bear|Notes'
focus_row '392|04|iTerm2|com.googlecode.iterm2|Shell'
( sleep 0.3; printf '63|04|Bear|net.shinyfrog.bear|Notes\n' > "$FOCUSED_FILE" ) &
OMARCHY_FRONT_WAIT_MS=2000 run_case 63
wait
expect $'move-follow:63:07\nsave:launch-placement-07\nresponsive:launch-placement-07:63'

# Assigned apps launch into their workspace and the view follows there.
windows '99|07|Messages|com.apple.MobileSMS|New Message'
focus_row '99|07|Messages|com.apple.MobileSMS|New Message'
run_case 99
expect $'move-follow:99:02\nsave:launch-placement-02\nresponsive:launch-placement-02:99'

# With 07-09 occupied, the fallback is space key 0.
windows '10|04|Bear|net.shinyfrog.bear|' '20|07|Todoist|com.todoist.mac.Todoist|' \
  '21|08|Weather|com.apple.weather|' '22|09|Notes|com.apple.Notes|'
focus_row '10|04|Bear|net.shinyfrog.bear|'
run_case 10
expect $'move-follow:10:00\nsave:launch-placement-00\nresponsive:launch-placement-00:10'

# User-defined names change which workspaces are named.
cat > "$ALIAS_FILE" <<'EOF'
01=Mail
02=Msg
07=Research
EOF
windows '12|04|Bear|net.shinyfrog.bear|'
focus_row '12|04|Bear|net.shinyfrog.bear|'
run_case 12
expect 'responsive:window-detected-settled-04:12'
windows '13|07|Bear|net.shinyfrog.bear|'
focus_row '13|07|Bear|net.shinyfrog.bear|'
run_case 13
# 06 and 08 are equally near 07; the lower key wins.
expect $'move-follow:13:06\nsave:launch-placement-06\nresponsive:launch-placement-06:13'
write_default_aliases

# --- Windows that stay where they were created ---------------------------------

# Cmd-N: the app already has an older window here, so the new one splits.
windows '100|04|Google Chrome|com.google.Chrome|Docs' '101|04|Google Chrome|com.google.Chrome|New Tab'
focus_row '101|04|Google Chrome|com.google.Chrome|New Tab'
run_case 101
expect 'responsive:window-detected-settled-04:101'
grep -Fq 'app already on workspace; window stays window=101' "$LOG_FILE"

# Same rule for assigned apps: a second Gmail window next to a moved one stays.
windows '30|04|Gmail|com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm|Inbox' \
  '31|04|Gmail|com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm|Compose'
focus_row '31|04|Gmail|com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm|Compose'
run_case 31
expect 'responsive:window-detected-settled-04:31'

# Windows created together in one launch do not count as "already here":
# only lower (older) window ids do.
windows '200|04|Google Chrome|com.google.Chrome|Restored 1' '201|04|Google Chrome|com.google.Chrome|Restored 2'
focus_row '200|04|Google Chrome|com.google.Chrome|Restored 1'
run_case 200
expect $'move-follow:200:07\nsave:launch-placement-07\nresponsive:launch-placement-07:200'

# Background app windows stay: the Steam/Gmail incident shape with any app.
windows '62|01|Bear|net.shinyfrog.bear|Notes'
focus_row '1561|01|Gmail|com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm|'
run_case 62
expect 'responsive:window-detected-settled-01:62'
grep -Fq 'app not frontmost on its workspace; window stays window=62' "$LOG_FILE"

# A background assigned app does not move either (the Xfinity Assistant case).
windows '2970|09|Messages|com.apple.MobileSMS|Xfinity Assistant'
focus_row '2636|09|Google Chrome|com.google.Chrome|Search'
run_case 2970
expect 'responsive:window-detected-settled-09:2970'

# The app is frontmost but on another workspace: you are not looking at the
# window's workspace, so it stays.
windows '64|04|Bear|net.shinyfrog.bear|Notes' '65|08|Bear|net.shinyfrog.bear|Old'
focus_row '65|08|Bear|net.shinyfrog.bear|Old'
run_case 64
expect 'responsive:window-detected-settled-04:64'

# Unassigned windows on unnamed workspaces stay, even when frontmost.
windows '11|08|Bear|net.shinyfrog.bear|'
focus_row '11|08|Bear|net.shinyfrog.bear|'
run_case 11
expect 'responsive:window-detected-settled-08:11'

# Assigned windows already home stay.
windows '30|04|iTerm2|com.googlecode.iterm2|'
focus_row '30|04|iTerm2|com.googlecode.iterm2|'
run_case 30
expect 'responsive:assigned-window-settled-04:30'

# AeroSpace-floated dialogs and popups stay with their app.
windows '66|04|Google Chrome|com.google.Chrome|Sign in|floating'
focus_row '66|04|Google Chrome|com.google.Chrome|Sign in|floating'
run_case 66
[[ ! -s "$COMMANDS_FILE" ]] || fail
grep -Fq 'floating window stays window=66' "$LOG_FILE"

# Touch ID prompts float and stay.
windows '60|04|coreautha|com.apple.LocalAuthentication.UIAgent|1Password Touch ID'
focus_row '60|04|coreautha|com.apple.LocalAuthentication.UIAgent|1Password Touch ID'
run_case 60
expect 'layout:60:floating'
grep -Fq 'transient authentication window retained workspace=04 window=60' "$LOG_FILE"

# Steam toasts float and stay, even if floating fails.
windows '52773|01|Steam Helper|com.valvesoftware.steam.helper|notificationtoasts_2545_desktop'
focus_row '52773|01|Steam Helper|com.valvesoftware.steam.helper|notificationtoasts_2545_desktop'
run_case 52773
expect 'layout:52773:floating'
OMARCHY_FAKE_LAYOUT_FAIL=1 run_case 52773
expect 'layout:52773:floating'
grep -Fq 'retained but float failed' "$LOG_FILE"

# Only that exact Steam title family is exempt.
for row in \
  '61|01|Steam Helper|com.valvesoftware.steam.helper|Steam' \
  '61|01|Other|com.example.other|notificationtoasts_2545_desktop'; do
  windows "$row"
  focus_row "$row"
  run_case 61
  expect $'move-follow:61:07\nsave:launch-placement-07\nresponsive:launch-placement-07:61'
done

# Restore and Native Input suppress all placement.
windows '40|04|Bear|net.shinyfrog.bear|'
focus_row '40|04|Bear|net.shinyfrog.bear|'
for guard in "$GUARD_FILE" "$NATIVE_INPUT_FILE"; do
  touch "$guard"
  run_case 40
  [[ ! -s "$COMMANDS_FILE" ]] || fail
  rm -f "$guard"
done

# Invalid or vanished callback ids are harmless.
run_case 99999
[[ ! -s "$COMMANDS_FILE" ]] || fail
run_case invalid
[[ ! -s "$COMMANDS_FILE" ]] || fail

# --- Same launch, failures, and serialization ----------------------------------

# A second window from a launch just placed joins its destination without a
# second follow. Outside the launch window it is judged on its own.
windows '4456|07|Google Chrome|com.google.Chrome|New Tab' '4457|04|Google Chrome|com.google.Chrome|Restored'
focus_row '4456|07|Google Chrome|com.google.Chrome|New Tab'
: > "$COMMANDS_FILE"
: > "$LOG_FILE"
printf '%s|com.google.Chrome|07\n' "$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')" > "$LAUNCH_STATE"
"$HELPER" 4457
expect $'move:4457:07\nsave:launch-group-07\nresponsive:launch-group-07:4457'
grep -Fq 'same-launch window joined window=4457 from=04 to=07' "$LOG_FILE"
windows '4456|07|Google Chrome|com.google.Chrome|New Tab' '4457|04|Google Chrome|com.google.Chrome|Restored'
: > "$COMMANDS_FILE"
printf '1000|com.google.Chrome|07\n' > "$LAUNCH_STATE"
"$HELPER" 4457
expect 'responsive:window-detected-settled-04:4457'
# Another app's launch state never captures this app's window.
windows '4457|04|Google Chrome|com.google.Chrome|Restored'
focus_row '4457|04|Google Chrome|com.google.Chrome|Restored'
: > "$COMMANDS_FILE"
printf '%s|net.shinyfrog.bear|08\n' "$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.0f", time * 1000')" > "$LAUNCH_STATE"
"$HELPER" 4457
expect $'move-follow:4457:07\nsave:launch-placement-07\nresponsive:launch-placement-07:4457'

# A failed move records nothing and never starts a launch group.
windows '70|04|Bear|net.shinyfrog.bear|'
focus_row '70|04|Bear|net.shinyfrog.bear|'
OMARCHY_FAKE_MOVE_FAIL=1 run_case 70
expect $'move-follow:70:07\nresponsive:window-detected-move-failed-04:70'
[[ ! -e "$LAUNCH_STATE" ]] || fail

# A stale lock from a crashed placement is reclaimed rather than blocking.
mkdir "$LOCK_DIR"
windows '71|04|Bear|net.shinyfrog.bear|'
focus_row '71|04|Bear|net.shinyfrog.bear|'
run_case 71
expect $'move-follow:71:07\nsave:launch-placement-07\nresponsive:launch-placement-07:71'

# A placement in progress holds the lock; the next one waits for it and then
# sees its move, so two launches never share a destination.
windows '80|07|Bear|net.shinyfrog.bear|' '81|04|Notes|com.apple.Notes|'
focus_row '81|04|Notes|com.apple.Notes|'
: > "$COMMANDS_FILE"
rm -f "$LAUNCH_STATE"
mkdir "$LOCK_DIR"
"$HELPER" 81 &
waiting=$!
sleep 0.4
[[ ! -s "$COMMANDS_FILE" ]] || fail
rmdir "$LOCK_DIR"
wait "$waiting"
expect $'move-follow:81:08\nsave:launch-placement-08\nresponsive:launch-placement-08:81'
[[ ! -e "$LOCK_DIR" ]] || fail

printf 'new_window_placement_fake.sh: all checks passed\n'
