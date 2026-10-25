#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-chrome-service.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" OMARCHY_SOURCE_DIR="$ROOT"
mkdir -p "$HOME"
sed '/^# USAGE \/ ENTRY POINT/,$d' "$ROOT/install.sh" > "$TEST_ROOT/lib.sh"
source "$TEST_ROOT/lib.sh"
# Do not update the live user's Services registry from an isolated test.
refresh_chrome_service_registration() { printf 'updated\n' >> "$TEST_ROOT/registrations"; }
workflow="$HOME/Library/Services/New Chrome Window.workflow/Contents/document.wflow"
backup="$BACKUP_DIR/chrome-window-service.original.wflow"
marker="$BACKUP_DIR/chrome-window-service.managed.sha256"
update_chrome_window_service install
[[ ! -e "$workflow" ]]
mkdir -p "$(dirname "$workflow")"
/usr/bin/python3 - "$workflow" <<'PY'
import plistlib,sys
source='''on run {input, parameters}
tell application "System Events"
tell application "Google Chrome"
make new window
activate
end tell
end tell
return input
end run'''
plistlib.dump({'actions':[{'action':{'ActionParameters':{'source':source}}}],
              'workflowMetaData':{'sentinel':'unchanged'}},open(sys.argv[1],'wb'))
PY
cp "$workflow" "$TEST_ROOT/original"
update_chrome_window_service install
cmp "$backup" "$TEST_ROOT/original"
[[ "$(wc -l < "$TEST_ROOT/registrations" | tr -d ' ')" == 1 ]]
plutil -extract actions.0.action.ActionParameters.source raw -o "$TEST_ROOT/installed" "$workflow"
[[ "$(cat "$ROOT/helpers/new_chrome_window.applescript")" == "$(cat "$TEST_ROOT/installed")" ]]
[[ "$(plutil -extract workflowMetaData.sentinel raw -o - "$workflow")" == unchanged ]]
cp "$workflow" "$TEST_ROOT/managed"
update_chrome_window_service install
cmp "$workflow" "$TEST_ROOT/managed"
[[ "$(wc -l < "$TEST_ROOT/registrations" | tr -d ' ')" == 1 ]]
cmp "$backup" "$TEST_ROOT/original"
update_chrome_window_service revert
cmp "$workflow" "$TEST_ROOT/original"
[[ "$(wc -l < "$TEST_ROOT/registrations" | tr -d ' ')" == 2 ]]
[[ ! -f "$marker" ]]
update_chrome_window_service install
plutil -replace actions.0.action.ActionParameters.source -string 'return "custom"' "$workflow"
cp "$workflow" "$TEST_ROOT/custom"
update_chrome_window_service install
update_chrome_window_service revert
cmp "$workflow" "$TEST_ROOT/custom"
cmp "$backup" "$TEST_ROOT/original"
# Even the known source must be left alone if the workflow has extra actions.
cp "$TEST_ROOT/original" "$workflow"
plutil -insert actions.1 -xml '<dict><key>custom</key><true/></dict>' "$workflow"
cp "$workflow" "$TEST_ROOT/extra"
update_chrome_window_service install
cmp "$workflow" "$TEST_ROOT/extra"
# Callers run install in conditional context (set -e suppressed). A failed
# backup must report failure and never replace the workflow unbacked.
cp "$TEST_ROOT/original" "$workflow"
mv "$BACKUP_DIR" "$TEST_ROOT/backup-dir"
: > "$BACKUP_DIR"
if update_chrome_window_service install 2>/dev/null; then exit 1; fi
cmp "$workflow" "$TEST_ROOT/original"
rm -f "$BACKUP_DIR"
mv "$TEST_ROOT/backup-dir" "$BACKUP_DIR"

# Execute the actual service's control flow with a fake broker and a fake
# Chrome block. No live Apple Events or real IPC, including when arming fails.
cat > "$TEST_ROOT/broker" <<EOF
#!/bin/bash
echo "\$1 \$2" >> '$TEST_ROOT/events'
[[ "\$1" != --arm-chrome || ! -f '$TEST_ROOT/deny' ]]
EOF
chmod +x "$TEST_ROOT/broker"
/usr/bin/python3 - "$ROOT/helpers/new_chrome_window.applescript" "$TEST_ROOT" <<'PY'
import sys,pathlib,re
root=pathlib.Path(sys.argv[2]); text=pathlib.Path(sys.argv[1]).read_text()
text=text.replace('/tmp/omarchy_window_state.log',str(root/'diagnostics'))
text=re.sub(r'    set broker to .*',f'    set broker to "{root}/broker"',text)
pattern=r'^        tell application "System Events".*?^        end tell$'
fake=f'        do shell script "echo created >> {root}/events"'
for name,block in [('success',fake),('failure',fake+'\n        error "synthetic creation failure" number 42')]:
 result,n=re.subn(pattern,block,text,flags=re.S|re.M)
 assert n==1 and 'tell application' not in result
 (root/(name+'.applescript')).write_text(result)
PY
for scenario in success denied failure; do
  rm -f "$TEST_ROOT/events" "$TEST_ROOT/deny" "$TEST_ROOT/diagnostics"
  script=success
  [[ "$scenario" != denied ]] || touch "$TEST_ROOT/deny"
  [[ "$scenario" != failure ]] || script=failure
  if osascript "$TEST_ROOT/$script.applescript" '' '' > "$TEST_ROOT/result" 2>&1; then
    [[ "$scenario" != failure ]]
  else
    [[ "$scenario" == failure ]] || { cat "$TEST_ROOT/result" >&2; exit 1; }
    grep -Eq 'synthetic creation failure' "$TEST_ROOT/result"
  fi
  /usr/bin/python3 - "$TEST_ROOT/events" "$scenario" <<'PY'
import sys,uuid
events=open(sys.argv[1]).read().splitlines()
arm,token=events[0].split(); assert arm=='--arm-chrome'; uuid.UUID(token)
assert events[1]=='created'
if sys.argv[2]=='failure': assert events[2:]==['--cancel-chrome '+token]
else: assert len(events)==2
PY
  grep -Eq 'chrome-service: invoked' "$TEST_ROOT/diagnostics"
  if [[ "$scenario" == denied ]]; then
    grep -Eq 'chrome-service: arm-failed code=1' "$TEST_ROOT/diagnostics"
  else
    grep -Eq 'chrome-service: arm-accepted' "$TEST_ROOT/diagnostics"
  fi
  if [[ "$scenario" == failure ]]; then
    grep -Eq 'chrome-service: creation-failed code=42' "$TEST_ROOT/diagnostics"
  else
    grep -Eq 'chrome-service: creation-returned' "$TEST_ROOT/diagnostics"
  fi
  ! grep -Eq 'synthetic creation failure' "$TEST_ROOT/diagnostics" || exit 1
done
printf 'chrome_window_service_fake.sh: all checks passed\n'
