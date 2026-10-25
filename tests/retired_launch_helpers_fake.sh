#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-retired-helpers.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" OMARCHY_TEST_ROOT="$TEST_ROOT"
mkdir -p "$HOME" "$TEST_ROOT/bin"

# macOS /bin/bash 3.2 does not exit on a failed [[ ]] under set -e.
fail() { printf 'assertion failed (line %s)\n' "${BASH_LINENO[0]}" >&2; exit 1; }

sed '/^# USAGE \/ ENTRY POINT/,$d' "$ROOT/install.sh" > "$TEST_ROOT/lib.sh"
source "$TEST_ROOT/lib.sh"

# Never contact the live user's launchd or Services registry.
cat > "$TEST_ROOT/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OMARCHY_TEST_ROOT/launchctl"
EOF
chmod +x "$TEST_ROOT/bin/launchctl"
export PATH="$TEST_ROOT/bin:$PATH"
refresh_services_registration() { printf 'registered:%s\n' "$1" >> "$TEST_ROOT/registrations"; }

# Lay out every retired artifact, including a running broker that answers --stop.
mkdir -p "$(dirname "$DOCK_LAUNCH_BIN")" "$CHROME_REHOME_APP/Contents/MacOS" \
  "$(dirname "$DOCK_LAUNCH_PLIST")" "$(dirname "$CHROME_REHOME_SRC")" "$AEROSPACE_DIR" "$BACKUP_DIR"
cat > "$DOCK_LAUNCH_BIN" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> '$TEST_ROOT/broker'
EOF
chmod +x "$DOCK_LAUNCH_BIN"
for file in "$DOCK_LAUNCH_PLIST" "$DOCK_LAUNCH_ENABLED_MARKER" "$CHROME_REHOME_PLIST" \
  "$CHROME_REHOME_SRC" "$AEROSPACE_DIR/dock_launch_follow.swift"; do
  : > "$file"
done

service="$HOME/Library/Services/New Chrome Window.workflow"
workflow="$service/Contents/document.wflow"
backup="$BACKUP_DIR/chrome-window-service.original.wflow"
marker="$BACKUP_DIR/chrome-window-service.managed.sha256"
mkdir -p "$(dirname "$workflow")"
printf 'original workflow\n' > "$backup"
printf 'managed workflow\n' > "$workflow"
/usr/bin/shasum -a 256 "$workflow" | awk '{print $1}' > "$marker"

remove_retired_launch_helpers > "$TEST_ROOT/out" 2>&1
grep -qx -- '--stop' "$TEST_ROOT/broker"
grep -q "bootout gui/.*/$CHROME_REHOME_LABEL" "$TEST_ROOT/launchctl"
grep -q "bootout gui/.*/$DOCK_LAUNCH_LABEL" "$TEST_ROOT/launchctl"
for path in "$DOCK_LAUNCH_APP" "$CHROME_REHOME_APP" "$DOCK_LAUNCH_PLIST" "$DOCK_LAUNCH_ENABLED_MARKER" \
  "$CHROME_REHOME_PLIST" "$CHROME_REHOME_SRC" "$AEROSPACE_DIR/dock_launch_follow.swift" "$marker"; do
  [[ ! -e "$path" ]] || fail
done
# The unchanged managed service gets its original action back; the backup stays.
cmp -s "$workflow" "$backup" || fail
[[ "$(cat "$TEST_ROOT/registrations")" == "registered:$service" ]] || fail

# Running again is a no-op for the restored service.
remove_retired_launch_helpers > "$TEST_ROOT/out" 2>&1
[[ "$(wc -l < "$TEST_ROOT/registrations" | tr -d ' ')" == 1 ]] || fail

# A workflow customized after it was managed is left alone, and the warning
# is shown once rather than on every refresh.
printf 'managed workflow\n' > "$workflow"
/usr/bin/shasum -a 256 "$workflow" | awk '{print $1}' > "$marker"
printf 'user customized\n' > "$workflow"
remove_retired_launch_helpers > "$TEST_ROOT/out" 2>&1
grep -q 'customized; left it unchanged' "$TEST_ROOT/out"
[[ "$(cat "$workflow")" == 'user customized' && ! -e "$marker" && -f "$backup" ]] || fail
[[ "$(wc -l < "$TEST_ROOT/registrations" | tr -d ' ')" == 1 ]] || fail

# Install, refresh, and revert all run the cleanup; nothing rebuilds the broker.
for command in cmd_install cmd_refresh cmd_revert; do
  body=$(awk -v name="$command" '$0 ~ "^" name "\\(\\) \\{" {inside = 1} inside {print} inside && /^}/ {exit}' "$ROOT/install.sh")
  grep -q '^  remove_retired_launch_helpers$' <<< "$body" || fail
done
! grep -Eq 'write_dock_launch_helper|write_chrome_rehome_daemon|dock-launch-follow\)' "$ROOT/install.sh" || fail

printf 'retired_launch_helpers_fake.sh: all checks passed\n'
