#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-dock-lifecycle.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
export OMARCHY_TEST_ROOT="$TEST_ROOT"
export OMARCHY_DOCK_START_ATTEMPTS=1 OMARCHY_DOCK_START_DELAY=0
mkdir -p "$HOME" "$TEST_ROOT/bin"
sed '/^# USAGE \/ ENTRY POINT/,$d' "$ROOT/install.sh" > "$TEST_ROOT/lib.sh"
source "$TEST_ROOT/lib.sh"
mkdir -p "$(dirname "$DOCK_LAUNCH_BIN")" "$(dirname "$DOCK_LAUNCH_PLIST")" "$BACKUP_DIR"
cat > "$DOCK_LAUNCH_BIN" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --stop) rm -f "$OMARCHY_TEST_ROOT/broker" ;;
  --status)
    if [[ -f "$OMARCHY_TEST_ROOT/broker" ]]; then cat "$OMARCHY_TEST_ROOT/broker";
    else echo 'dock-launch: not running'; fi ;;
esac
EOF
cat > "$TEST_ROOT/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$OMARCHY_TEST_ROOT/calls"
case "$1" in
  disable)
    [[ "${OMARCHY_TEST_FAIL_DISABLE:-0}" != 1 ]] || exit 1
    ;;
  enable) ;;
  print)
    if [[ "$2" == *chrome_rehome ]]; then
      [[ -f "$OMARCHY_TEST_ROOT/legacy" ]] || exit 1
      echo 'state = running'
    else
      [[ -f "$OMARCHY_TEST_ROOT/job" ]] || exit 1
      cat "$OMARCHY_TEST_ROOT/job"
    fi ;;
  bootout)
    if [[ "$2" == *chrome_rehome ]]; then
      [[ "${OMARCHY_TEST_STUCK_LEGACY:-0}" != 1 ]] || exit 1
      rm -f "$OMARCHY_TEST_ROOT/legacy"
    else rm -f "$OMARCHY_TEST_ROOT/job"; fi ;;
  bootstrap)
    case "${OMARCHY_TEST_START:-good}" in
      load-failure) exit 1 ;;
      stopped|crash) printf 'state = exited\npid = 123\n' > "$OMARCHY_TEST_ROOT/job" ;;
      *) printf 'state = running\npid = 123\n' > "$OMARCHY_TEST_ROOT/job" ;;
    esac
    case "${OMARCHY_TEST_START:-good}" in
      good) echo 'dock-launch: running mode=service pid=123' > "$OMARCHY_TEST_ROOT/broker" ;;
      wrong-pid) echo 'dock-launch: running mode=service pid=456' > "$OMARCHY_TEST_ROOT/broker" ;;
      observe) echo 'dock-launch: running mode=observe pid=123' > "$OMARCHY_TEST_ROOT/broker" ;;
      denied|unresponsive|stopped|crash) ;;
    esac ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$DOCK_LAUNCH_BIN" "$TEST_ROOT/bin/launchctl"
export PATH="$TEST_ROOT/bin:$PATH"
: > "$DOCK_LAUNCH_PLIST"
printf 'old-agent\n' > "$CHROME_REHOME_PLIST"
: > "$TEST_ROOT/legacy"
run_dock() { (cmd_dock_launch_follow dock-launch-follow "$@"); }

run_dock enable > "$TEST_ROOT/enable.out"
dock_launch_enabled_valid
dock_launch_service_healthy
[[ ! -f "$CHROME_REHOME_PLIST" && ! -f "$TEST_ROOT/legacy" ]]
grep -rq old-agent "$BACKUP_DIR/retired-launchagents"
grep -Eq 'disable gui/.*/com.omarchy-macos.chrome_rehome' "$TEST_ROOT/calls"
run_dock status | grep -q 'enabled and running persistently'
# A later crash is not reported healthy; explicit start can recover an
# unchanged authorized executable (the refresh/start-services path).
printf 'state = exited\npid = 123\n' > "$TEST_ROOT/job"
rm -f "$TEST_ROOT/broker"
run_dock status | grep -q 'enabled but not healthy'
dock_launch_start >/dev/null
dock_launch_service_healthy
if run_dock observe 1 >/dev/null 2>&1; then exit 1; fi
run_dock stop >/dev/null
[[ ! -e "$DOCK_LAUNCH_ENABLED_MARKER" && ! -e "$TEST_ROOT/job" && ! -e "$TEST_ROOT/broker" ]]
if dock_launch_start >/dev/null 2>&1; then exit 1; fi

for failure in load-failure denied unresponsive stopped crash wrong-pid observe; do
  export OMARCHY_TEST_START="$failure"
  if run_dock enable > "$TEST_ROOT/$failure.out" 2>&1; then
    echo "unexpected startup success: $failure" >&2; exit 1
  fi
  [[ ! -e "$DOCK_LAUNCH_ENABLED_MARKER" && ! -e "$TEST_ROOT/job" && ! -e "$TEST_ROOT/broker" ]]
done
export OMARCHY_TEST_START=good
run_dock enable >/dev/null
printf '\n# replaced\n' >> "$DOCK_LAUNCH_BIN"
if dock_launch_enabled_valid; then exit 1; fi
run_dock status | grep -q 'stale binary authorization'
run_dock disable >/dev/null

# Never start the replacement if retiring the old job fails.
: > "$TEST_ROOT/legacy"
export OMARCHY_TEST_STUCK_LEGACY=1
if run_dock enable >/dev/null 2>&1; then exit 1; fi
[[ ! -e "$DOCK_LAUNCH_ENABLED_MARKER" && ! -e "$TEST_ROOT/job" ]]
unset OMARCHY_TEST_STUCK_LEGACY
export OMARCHY_TEST_FAIL_DISABLE=1
if run_dock enable >/dev/null 2>&1; then exit 1; fi
[[ -e "$TEST_ROOT/legacy" && ! -e "$DOCK_LAUNCH_ENABLED_MARKER" ]]
unset OMARCHY_TEST_FAIL_DISABLE

# A failed move of the old plist is a retirement failure, not a silent success,
# even though callers run retirement in conditional (set -e suppressed) context.
rm -f "$TEST_ROOT/legacy"
printf 'old-agent\n' > "$CHROME_REHOME_PLIST"
rm -rf "$BACKUP_DIR/retired-launchagents"
: > "$BACKUP_DIR/retired-launchagents"
if run_dock enable >/dev/null 2>&1; then exit 1; fi
[[ -f "$CHROME_REHOME_PLIST" && ! -e "$DOCK_LAUNCH_ENABLED_MARKER" && ! -e "$TEST_ROOT/job" ]]
rm -f "$BACKUP_DIR/retired-launchagents"

# Retirement failure during service startup blocks only the Dock broker; the
# remaining services must still start instead of aborting refresh under set -e.
start_body=$(awk '/^start_services\(\) \{/,/^}/' "$ROOT/install.sh")
grep -q 'if retire_legacy_chrome_rehome; then' <<< "$start_body"
! grep -q 'retire_legacy_chrome_rehome || return' <<< "$start_body" || exit 1
grep -q 'Starting shortcut desktop widget' <<< "$start_body"
printf 'dock_launch_lifecycle_fake.sh: all checks passed\n'
