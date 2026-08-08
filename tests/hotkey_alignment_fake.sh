#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-hotkeys-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export TMPDIR="$TEST_ROOT/tmp"
export XDG_RUNTIME_DIR="$TEST_ROOT/runtime"
mkdir -p "$HOME" "$TMPDIR" "$XDG_RUNTIME_DIR"

# Load generator functions without executing install.sh's command dispatcher.
sed '/^# USAGE \/ ENTRY POINT/,$d' "$ROOT/install.sh" > "$TEST_ROOT/install_lib.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/install_lib.sh" || exit 1
write_skhd_config >/dev/null
write_native_input_helper >/dev/null

SKHD_GENERATED="$HOME/.config/skhd/skhdrc"

required_chords=(
  'lalt - k'
  'lalt - space'
  'lalt - w'
  'lalt - t'
  'lalt - j'
  'lalt - l'
  'lalt - f'
  'lalt - tab'
  'lalt + shift - tab'
  'lalt + cmd - tab'
  'lalt - left'
  'lalt - down'
  'lalt - up'
  'lalt - right'
  'lalt + shift - left'
  'lalt + shift - down'
  'lalt + shift - up'
  'lalt + shift - right'
  'lalt - 0x18'
  'lalt - 0x1B'
  'ctrl - tab'
  'cmd + ctrl - tab'
  'lalt - return'
  'lalt + shift - return'
)

for chord in "${required_chords[@]}"; do
  grep -Fqx "$chord [" "$SKHD_GENERATED" || {
    printf 'missing generated chord: %s\n' "$chord" >&2
    exit 1
  }
done

for key in 1 2 3 4 5 6 7 8 9 0; do
  grep -Fqx "lalt - $key [" "$SKHD_GENERATED"
  grep -Fqx "lalt + shift - $key [" "$SKHD_GENERATED"
  grep -Fqx "lalt + shift + ctrl - $key [" "$SKHD_GENERATED"
done

grep -Fqx 'fn - escape ; native_input' "$SKHD_GENERATED"
grep -Fqx 'native_input < fn - escape ; default' "$SKHD_GENERATED"
grep -Fqx ':: default : ~/.config/aerospace/native_input_mode.sh off' "$SKHD_GENERATED"
grep -Fqx ':: native_input : ~/.config/aerospace/native_input_mode.sh on' "$SKHD_GENERATED"

if grep -Eq '^(alt|ralt)([ +]| -)' "$SKHD_GENERATED"; then
  printf 'only left Option may own Omarchy bindings\n' >&2
  exit 1
fi

# Each generated process-map binding must pass through all configured terminals.
awk '
  /^.+ \[$/ { in_binding=1; block=$0 "\n"; next }
  in_binding { block=block $0 "\n" }
  in_binding && /^]$/ {
    for (i=1; i<=5; i++) {
      terminal=(i==1 ? "Ghostty" : i==2 ? "WezTerm" : i==3 ? "Warp" : i==4 ? "iTerm2" : "Terminal")
      if (index(block, "\"" terminal "\" ~") == 0) {
        print "missing terminal passthrough for " terminal " in " block > "/dev/stderr"
        exit 1
      }
    }
    if (index(block, "* : ") == 0) {
      print "missing fallback command in " block > "/dev/stderr"
      exit 1
    }
    in_binding=0
    block=""
  }
' "$SKHD_GENERATED"

duplicates=$(sed -n 's/ \[$//p' "$SKHD_GENERATED" | sort | uniq -d)
[ -z "$duplicates" ] || {
  printf 'duplicate generated hotkey owners:\n%s\n' "$duplicates" >&2
  exit 1
}

FAKE_BIN="$TEST_ROOT/bin"
CALLS="$TEST_ROOT/calls"
mkdir -p "$FAKE_BIN" "$HOME/.config/sketchybar/plugins"
cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
printf 'aerospace:%s\n' "$*" >> "$OMARCHY_TEST_CALLS"
EOF
cat > "$FAKE_BIN/sketchybar" <<'EOF'
#!/usr/bin/env bash
printf 'sketchybar:%s\n' "$*" >> "$OMARCHY_TEST_CALLS"
EOF
cat > "$HOME/.config/sketchybar/plugins/hide_bar.sh" <<'EOF'
#!/usr/bin/env bash
printf 'hide-bar\n' >> "$OMARCHY_TEST_CALLS"
printf '0' > "${XDG_RUNTIME_DIR:-/tmp}/omarchy_sketchybar_visible"
EOF
chmod +x "$FAKE_BIN"/* "$HOME/.config/sketchybar/plugins/hide_bar.sh"
export PATH="$FAKE_BIN:$PATH"
export OMARCHY_TEST_CALLS="$CALLS"

# Resetting an already-normal session must not alter the user's bar visibility.
printf '1' > "$XDG_RUNTIME_DIR/omarchy_sketchybar_visible"
: > "$CALLS"
"$NATIVE_INPUT_HELPER" reset
! grep -Fqx 'hide-bar' "$CALLS"

printf '0' > "$XDG_RUNTIME_DIR/omarchy_sketchybar_visible"
"$NATIVE_INPUT_HELPER" on
grep -Fqx 'aerospace:mode native_input' "$CALLS"
grep -Fqx 'sketchybar:--set native_input drawing=on label=Native Input' "$CALLS"
[ -e "$TMPDIR/omarchy_native_input_active" ]

: > "$CALLS"
"$NATIVE_INPUT_HELPER" off
grep -Fqx 'aerospace:mode main' "$CALLS"
grep -Fqx 'hide-bar' "$CALLS"
[ ! -e "$TMPDIR/omarchy_native_input_active" ]

# An active restore warning must prevent Native Input from hiding the bar.
printf '0' > "$XDG_RUNTIME_DIR/omarchy_sketchybar_visible"
"$NATIVE_INPUT_HELPER" on
: > "$CALLS"
: > "$TMPDIR/omarchy_window_state_restore_incomplete"
"$NATIVE_INPUT_HELPER" off
! grep -Fqx 'hide-bar' "$CALLS"

printf 'hotkey_alignment_fake.sh: all checks passed\n'
