#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-sketchybar-lifecycle-test.XXXXXX")"
first_pid=""

cleanup() {
  if [[ "$first_pid" =~ ^[0-9]+$ ]]; then
    kill "$first_pid" >/dev/null 2>&1 || true
    wait "$first_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

export HOME="$TMP_ROOT/home"
export TMPDIR="$TMP_ROOT/tmp"
export CONFIG_DIR="$HOME/.config/sketchybar"
export OMARCHY_SKETCHYBAR_CONFIG_LOCK="$TMPDIR/config.lock"
FAKE_BIN="$TMP_ROOT/bin"
LOG_FILE="$TMP_ROOT/sketchybar.log"
STARTED_FILE="$TMP_ROOT/config-started"
RELEASE_FILE="$TMP_ROOT/release-config"
SKETCHYBARRC="$CONFIG_DIR/sketchybarrc"

mkdir -p "$TMPDIR" "$CONFIG_DIR/items" "$FAKE_BIN"
: > "$LOG_FILE"

awk '/cat > "\$SKETCHY_DIR\/sketchybarrc" << '\''SKETCHY_EOF'\''/{in_block=1; next} /^SKETCHY_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$SKETCHYBARRC"
chmod +x "$SKETCHYBARRC"

cat > "$CONFIG_DIR/colors.sh" <<'EOF'
export BAR_COLOR=0xff000000
export BORDER_COLOR=0xff000000
export TEXT=0xffffffff
EOF

cat > "$CONFIG_DIR/items/spaces.sh" <<EOF
touch "$STARTED_FILE"
while [ ! -e "$RELEASE_FILE" ]; do
  sleep 0.05
done
sketchybar --add item space.0.1 left
EOF

for item in front_app monitor display_reload restore_status native_input; do
  : > "$CONFIG_DIR/items/$item.sh"
done

cat > "$FAKE_BIN/sketchybar" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PPID" "$*" >> "$OMARCHY_FAKE_SKETCHYBAR_LOG"
EOF
chmod +x "$FAKE_BIN/sketchybar"

export PATH="$FAKE_BIN:$PATH"
export OMARCHY_FAKE_SKETCHYBAR_LOG="$LOG_FILE"

"$SKETCHYBARRC" &
first_pid=$!

for _ in {1..100}; do
  [ -e "$STARTED_FILE" ] && break
  sleep 0.02
done
[[ -e "$STARTED_FILE" ]]
[[ -f "$OMARCHY_SKETCHYBAR_CONFIG_LOCK/pid" ]]
[[ "$(cat "$OMARCHY_SKETCHYBAR_CONFIG_LOCK/pid")" = "$first_pid" ]]

before_second="$(wc -l < "$LOG_FILE" | tr -d ' ')"
"$SKETCHYBARRC"
after_second="$(wc -l < "$LOG_FILE" | tr -d ' ')"
[[ "$after_second" = "$before_second" ]]

touch "$RELEASE_FILE"
wait "$first_pid"
first_pid=""
[[ ! -e "$OMARCHY_SKETCHYBAR_CONFIG_LOCK" ]]

rm -f "$STARTED_FILE"
mkdir "$OMARCHY_SKETCHYBAR_CONFIG_LOCK"
printf '999999\n' > "$OMARCHY_SKETCHYBAR_CONFIG_LOCK/pid"
touch "$RELEASE_FILE"
"$SKETCHYBARRC"
[[ ! -e "$OMARCHY_SKETCHYBAR_CONFIG_LOCK" ]]
[[ -e "$STARTED_FILE" ]]

printf 'sketchybar_lifecycle_fake.sh: all checks passed\n'
