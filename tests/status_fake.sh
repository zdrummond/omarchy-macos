#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-status-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

export HOME="$TMP_ROOT/home"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FAKE_BIN" "$HOME/.config/aerospace" "$HOME/.omarchy-macos-backup"

cat > "$FAKE_BIN/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then
  printf '501\n'
else
  /usr/bin/id "$@"
fi
EOF

cat > "$FAKE_BIN/brew" <<'EOF'
#!/usr/bin/env bash
# Reproduce a service installed from a tap that Homebrew no longer trusts:
# binaries and launchd jobs exist, but brew's package/service registry omits it.
if [[ "${1:-}" == "services" && "${2:-}" == "list" ]]; then
  printf 'Name Status User File\nredis started test /tmp/redis.plist\n'
fi
exit 0
EOF

cat > "$FAKE_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "print" ]]; then
  case "${2:-}" in
    gui/501/homebrew.mxcl.sketchybar|gui/501/homebrew.mxcl.borders|gui/501/com.*)
      printf 'state = running\n'
      exit 0
      ;;
  esac
fi
exit 1
EOF

cat > "$FAKE_BIN/aerospace" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "list-monitors" ]]; then
  printf '1\n'
  exit 0
fi
exit 1
EOF

for command_name in skhd sketchybar borders; do
  cat > "$FAKE_BIN/$command_name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
done
chmod +x "$FAKE_BIN"/*

cat > "$HOME/.config/aerospace/accessibility_report.sh" <<'EOF'
#!/usr/bin/env bash
printf 'No actionable Accessibility redo detected.\n'
EOF
cat > "$HOME/.config/aerospace/secure_input_report.sh" <<'EOF'
#!/usr/bin/env bash
printf 'Secure Input: off\n'
EOF
chmod +x "$HOME/.config/aerospace/accessibility_report.sh" \
  "$HOME/.config/aerospace/secure_input_report.sh"

touch "$HOME/.omarchy-macos-backup/.installed"
export PATH="$FAKE_BIN:/usr/bin:/bin"

output="$(bash "$ROOT/install.sh" status)"

[[ "$output" == *"aerospace installed"* ]]
[[ "$output" == *"skhd installed"* ]]
[[ "$output" == *"sketchybar installed"* ]]
[[ "$output" == *"jankyborders (optional) installed"* ]]
[[ "$output" == *"AeroSpace — server reachable"* ]]
[[ "$output" == *"sketchybar — running"* ]]
[[ "$output" == *"borders — running"* ]]
[[ "$output" != *"not installed"* ]]
[[ "$output" != *"not found"* ]]

printf 'status_fake.sh: all checks passed\n'
