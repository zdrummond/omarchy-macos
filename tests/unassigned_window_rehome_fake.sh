#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-unassigned-rehome-test.XXXXXX")"
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
ALIAS_FILE="$SKETCHY_DIR/space_aliases"

mkdir -p "$CONFIG_DIR" "$SKETCHY_DIR" "$FAKE_BIN" "$TMPDIR"

awk '/cat > "\$AEROSPACE_DIR\/omarchy_space_state.sh" << '\''SPACE_STATE_EOF'\''/{in_block=1; next} /^SPACE_STATE_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/omarchy_space_state.sh"

awk '/cat > "\$AEROSPACE_DIR\/unassigned_window_rehome.sh" << '\''UNASSIGNED_WINDOW_REHOME_EOF'\''/{in_block=1; next} /^UNASSIGNED_WINDOW_REHOME_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$CONFIG_DIR/unassigned_window_rehome.sh"

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

format_row() {
  local format="$1" id="$2" workspace="$3" app="$4" bundle="$5"
  local out="$format"
  out="${out//%\{window-id\}/$id}"
  out="${out//%\{workspace\}/$workspace}"
  out="${out//%\{app-name\}/$app}"
  out="${out//%\{app-bundle-id\}/$bundle}"
  printf '%s\n' "$out"
}

case "$cmd" in
  list-monitors)
    if [[ "${1:-}" == "--focused" ]]; then
      printf '1\n'
    else
      printf '1\n'
    fi
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
      while IFS='|' read -r id workspace app bundle; do
        [[ -n "$id" ]] || continue
        format_row "$format" "$id" "$workspace" "$app" "$bundle"
      done < "$OMARCHY_FAKE_FOCUSED"
    else
      while IFS='|' read -r id workspace app bundle; do
        [[ -n "$id" ]] || continue
        format_row "$format" "$id" "$workspace" "$app" "$bundle"
      done < "$OMARCHY_FAKE_WINDOWS"
    fi
    ;;
  move-node-to-workspace)
    [[ "${1:-}" == "--window-id" ]]
    printf 'move:%s:%s\n' "$2" "$3" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  workspace)
    printf 'workspace:%s\n' "${1:-}" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  focus)
    [[ "${1:-}" == "--window-id" ]]
    printf 'focus:%s\n' "${2:-}" >> "$OMARCHY_FAKE_COMMANDS"
    ;;
  *)
    printf 'unexpected fake aerospace command: %s\n' "$cmd" >&2
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
export OMARCHY_REHOME_FOLLOW_DELAY=0

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

run_case() {
  : > "$COMMANDS_FILE"
  : > "$LOG_FILE"
  "$CONFIG_DIR/unassigned_window_rehome.sh" "$1"
}

write_default_aliases
printf '10|04|Bear|net.shinyfrog.bear\n20|08|Todoist|com.todoist.mac.Todoist\n' > "$WINDOWS_FILE"
printf '10|04|Bear|net.shinyfrog.bear\n' > "$FOCUSED_FILE"
run_case 10
expected=$'move:10:07\nsave:unassigned-window-rehome-07\nresponsive:unassigned-window-rehome-07:10\nworkspace:07\nfocus:10'
actual="$(cat "$COMMANDS_FILE")"
[[ "$actual" == "$expected" ]]

printf '11|08|Bear|net.shinyfrog.bear\n20|07|Todoist|com.todoist.mac.Todoist\n' > "$WINDOWS_FILE"
printf '11|08|Bear|net.shinyfrog.bear\n' > "$FOCUSED_FILE"
run_case 11
[[ "$(cat "$COMMANDS_FILE")" == "responsive:window-detected-settled-08:11" ]]

printf '%s\n' \
  '10|04|Bear|net.shinyfrog.bear' \
  '20|07|Todoist|com.todoist.mac.Todoist' \
  '21|08|Weather|com.apple.weather' \
  '22|09|Notes|com.apple.Notes' > "$WINDOWS_FILE"
printf '10|04|Bear|net.shinyfrog.bear\n' > "$FOCUSED_FILE"
run_case 10
expected=$'move:10:00\nsave:unassigned-window-rehome-00\nresponsive:unassigned-window-rehome-00:10\nworkspace:00\nfocus:10'
actual="$(cat "$COMMANDS_FILE")"
[[ "$actual" == "$expected" ]]

cat > "$ALIAS_FILE" <<'EOF'
01=Mail
02=Msg
07=Research
EOF
printf '12|04|Bear|net.shinyfrog.bear\n' > "$WINDOWS_FILE"
printf '12|04|Bear|net.shinyfrog.bear\n' > "$FOCUSED_FILE"
run_case 12
[[ "$(cat "$COMMANDS_FILE")" == "responsive:window-detected-settled-04:12" ]]

printf '13|07|Bear|net.shinyfrog.bear\n' > "$WINDOWS_FILE"
printf '13|07|Bear|net.shinyfrog.bear\n' > "$FOCUSED_FILE"
run_case 13
expected=$'move:13:08\nsave:unassigned-window-rehome-08\nresponsive:unassigned-window-rehome-08:13\nworkspace:08\nfocus:13'
actual="$(cat "$COMMANDS_FILE")"
[[ "$actual" == "$expected" ]]

write_default_aliases
printf '%s\n' \
  '50|03|TV|com.apple.TV' \
  '20|07|Todoist|com.todoist.mac.Todoist' \
  '21|08|Weather|com.apple.weather' \
  '22|09|Notes|com.apple.Notes' > "$WINDOWS_FILE"
printf '50|03|TV|com.apple.TV\n' > "$FOCUSED_FILE"
run_case 50
expected=$'move:50:00\nsave:unassigned-window-rehome-00\nresponsive:unassigned-window-rehome-00:50\nworkspace:00\nfocus:50'
actual="$(cat "$COMMANDS_FILE")"
[[ "$actual" == "$expected" ]]

printf '51|08|TV|com.apple.TV\n' > "$WINDOWS_FILE"
printf '51|08|TV|com.apple.TV\n' > "$FOCUSED_FILE"
run_case 51
[[ "$(cat "$COMMANDS_FILE")" == "responsive:window-detected-settled-08:51" ]]

printf '30|04|iTerm2|com.googlecode.iterm2\n' > "$WINDOWS_FILE"
printf '30|04|iTerm2|com.googlecode.iterm2\n' > "$FOCUSED_FILE"
run_case 30
[[ "$(cat "$COMMANDS_FILE")" == "responsive:assigned-window-settled-04:30" ]]

touch "$GUARD_FILE"
printf '40|04|Bear|net.shinyfrog.bear\n' > "$WINDOWS_FILE"
printf '40|04|Bear|net.shinyfrog.bear\n' > "$FOCUSED_FILE"
run_case 40
[[ ! -s "$COMMANDS_FILE" ]]
rm -f "$GUARD_FILE"

printf 'unassigned_window_rehome_fake.sh: all checks passed\n'
