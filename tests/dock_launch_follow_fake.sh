#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-dock-follow-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
export OMARCHY_SOURCE_DIR="$ROOT"
export OMARCHY_WINDOW_STATE_LOG="$TEST_ROOT/window.log"
mkdir -p "$HOME" "$TEST_ROOT/cache"

# Compile and run the actual policy with synthetic evidence, never live windows.
swiftc -module-cache-path "$TEST_ROOT/cache" "$ROOT/helpers/dock_launch_follow.swift" -o "$TEST_ROOT/helper"
"$TEST_ROOT/helper" --self-test
# Invalid command identities fail before any IPC or Accessibility access.
for action in --arm-chrome --cancel-chrome; do
  if "$TEST_ROOT/helper" "$action" invalid; then exit 1; else [[ "$?" == 2 ]]; fi
done
# Persistent startup refuses absent or stale executable authorization before
# touching real Accessibility or creating an input monitor.
mkdir -p "$HOME/.omarchy-macos-backup"
for marker in missing stale; do
  if [[ "$marker" == stale ]]; then
    printf '%064d\n' 0 > "$HOME/.omarchy-macos-backup/dock-launch-follow-enabled.sha256"
  fi
  if "$TEST_ROOT/helper" --service; then exit 1; else [[ "$?" == 6 ]]; fi
done
for seconds in 0 -1 3601 nan; do
  if "$TEST_ROOT/helper" --serve "$seconds"; then
    echo "invalid duration accepted: $seconds" >&2; exit 1
  else
    [[ "$?" == 2 ]]
  fi
done

# Verify generator wiring without compiling into the user's Applications.
sed '/^# USAGE \/ ENTRY POINT/,$d' "$ROOT/install.sh" > "$TEST_ROOT/install_lib.sh"
source "$TEST_ROOT/install_lib.sh"
swiftc() { cp "$TEST_ROOT/helper" "${@: -1}"; }
# Never contact the real user's launchd/IPC from this generator test.
stop_dock_launch_service() { :; }
write_dock_launch_helper >/dev/null
cmp "$ROOT/helpers/dock_launch_follow.swift" "$AEROSPACE_DIR/dock_launch_follow.swift"
"$DOCK_LAUNCH_BIN" --self-test
plutil -lint "$DOCK_LAUNCH_APP/Contents/Info.plist" >/dev/null
/usr/bin/codesign --verify "$DOCK_LAUNCH_APP"
plutil -lint "$DOCK_LAUNCH_PLIST" >/dev/null
! grep -Eq '<key>KeepAlive</key>' "$DOCK_LAUNCH_PLIST" || exit 1
grep -Eq '<string>--service</string>' "$DOCK_LAUNCH_PLIST"
[[ ! -e "$DOCK_LAUNCH_ENABLED_MARKER" ]]
# An unchanged refresh keeps both binary identity and explicit authorization.
mkdir -p "$BACKUP_DIR"
dock_launch_digest > "$DOCK_LAUNCH_ENABLED_MARKER"
write_dock_launch_helper >/dev/null
dock_launch_enabled_valid
# Changed generated source invalidates permission to run persistently.
printf '\n// old generated copy\n' >> "$AEROSPACE_DIR/dock_launch_follow.swift"
write_dock_launch_helper >/dev/null
[[ ! -e "$DOCK_LAUNCH_ENABLED_MARKER" ]]
# A failed rebuild of the opt-in broker warns instead of aborting refresh
# under set -e, revokes authorization, and leaves no partial build behind.
dock_launch_digest > "$DOCK_LAUNCH_ENABLED_MARKER"
printf '\n// stale generated copy\n' >> "$AEROSPACE_DIR/dock_launch_follow.swift"
swiftc() { return 1; }
write_dock_launch_helper > "$TEST_ROOT/build-failure.out" 2>&1
grep -q 'Could not build Dock launch helper' "$TEST_ROOT/build-failure.out"
[[ ! -e "$DOCK_LAUNCH_ENABLED_MARKER" && ! -e "$DOCK_LAUNCH_BIN.build" ]]

# Production source is the tested policy and has only one focus-changing call.
[[ "$(grep -Ec '"--focus-follows-window"' "$ROOT/helpers/dock_launch_follow.swift")" == 1 ]]
! grep -Eq 'CGEvent.post|AXUIElementPerformAction|AXUIElementSetAttributeValue|debug-windows' "$ROOT/helpers/dock_launch_follow.swift" || exit 1
grep -Eq 'if observe .*would-follow.*return "declined"' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'cancel\(allowed \? "consumed"' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'guard serviceAuthorized\(\)' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq '!serviceAuthorized\(\) \|\| !AXIsProcessTrusted\(\)' "$ROOT/helpers/dock_launch_follow.swift"
# The cold-launch policy is used at intake, final validation, and expiry; warm
# apps are identified at mouse-down, and cold binding checks the process date.
[[ "$(grep -Ec 'launchPending\(age:' "$ROOT/helpers/dock_launch_follow.swift")" == 4 ]]
grep -Eq 'runningApplications\(withBundleIdentifier: bundle\).isEmpty' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq '!i.coldLaunch \|\| launched >= i.downDate' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'guard axObserver != nil, observerAttachment\?\.ready == true' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'cancel\("placement-before-observer-ready"\)' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'observerAttachment = nil' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'process.launchDate == i.launched' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'pendingCancellationReason\(candidate\) == nil' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'intent\?\.commandToken == request.token' "$ROOT/helpers/dock_launch_follow.swift"
grep -Eq 'else if message == 1,' "$ROOT/helpers/dock_launch_follow.swift"
printf 'dock_launch_follow_fake.sh: all checks passed\n'
