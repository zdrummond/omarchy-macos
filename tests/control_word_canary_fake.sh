#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-control-word-canary-test.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export TMPDIR="$TEST_ROOT/tmp"
FAKE_BIN="$TEST_ROOT/bin"
CALLS="$TEST_ROOT/calls"
mkdir -p "$HOME" "$TMPDIR" "$FAKE_BIN"

# Load generator and command functions without executing the dispatcher.
sed '/^# USAGE \/ ENTRY POINT/,$d' "$ROOT/install.sh" > "$TEST_ROOT/install_lib.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/install_lib.sh"

mkdir -p "$(dirname "$CONTROL_WORD_BIN")" "$(dirname "$CONTROL_WORD_PLIST")" "$BACKUP_DIR"
cat > "$CONTROL_WORD_BIN" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$CONTROL_WORD_BIN"
: > "$CONTROL_WORD_PLIST"

cat > "$FAKE_BIN/id" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-u" ]]; then
  printf '501\n'
else
  /usr/bin/id "$@"
fi
EOF

cat > "$FAKE_BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
printf 'launchctl:%s\n' "$*" >> "$OMARCHY_TEST_CALLS"
case "${1:-}" in
  print)
    case "${OMARCHY_FAKE_LAUNCHD_STATE:-missing}" in
      missing) exit 1 ;;
      *) printf 'state = %s\n' "$OMARCHY_FAKE_LAUNCHD_STATE"; exit 0 ;;
    esac
    ;;
  load)
    if [[ "${OMARCHY_FAKE_LAUNCHD_STATE:-missing}" == "load-failure" ]]; then
      exit 1
    fi
    exit 0
    ;;
  unload)
    exit 0
    ;;
esac
exit 1
EOF

cat > "$FAKE_BIN/open" <<'EOF'
#!/usr/bin/env bash
success_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--canary-success-file" ]]; then
    success_file="$2"
    shift 2
  else
    shift
  fi
done

case "${OMARCHY_FAKE_CANARY_RESULT:-crash}" in
  pass)
    printf 'passed\n' > "$success_file"
    ;;
  changed-during-canary)
    printf 'passed\n' > "$success_file"
    printf '# changed during canary\n' >> "$OMARCHY_TEST_CONTROL_WORD_BIN"
    ;;
  permission-denied|tap-failure|crash)
    # These failures exit without the helper's timeout callback writing a token.
    ;;
  launch-failure)
    exit 1
    ;;
  *)
    printf 'unexpected fake canary result\n' >&2
    exit 2
    ;;
esac
EOF

chmod +x "$FAKE_BIN"/*
export PATH="$FAKE_BIN:/usr/bin:/bin"
export OMARCHY_OPEN_BIN="$FAKE_BIN/open"
export OMARCHY_TEST_CALLS="$CALLS"
export OMARCHY_TEST_CONTROL_WORD_BIN="$CONTROL_WORD_BIN"
export OMARCHY_CONTROL_WORD_START_ATTEMPTS=1
export OMARCHY_CONTROL_WORD_START_DELAY=0

run_control_word() {
  (cmd_control_word_navigation control-word-navigation "$@")
}

# Persistent enablement is impossible without a canary for this executable.
rm -f "$CONTROL_WORD_CANARY_MARKER" "$CONTROL_WORD_ENABLED_MARKER"
if run_control_word enable >"$TEST_ROOT/direct-enable.out" 2>&1; then
  printf 'enable unexpectedly succeeded without a canary\n' >&2
  exit 1
fi
grep -Fq 'successful canary for the current helper is required' "$TEST_ROOT/direct-enable.out"
[[ ! -e "$CONTROL_WORD_ENABLED_MARKER" ]]

# Permission denial, event-tap creation failure, and an early crash all return
# without a timeout token and therefore cannot create an attestation.
for failure in permission-denied tap-failure crash; do
  record_control_word_canary
  touch "$CONTROL_WORD_ENABLED_MARKER"
  export OMARCHY_FAKE_CANARY_RESULT="$failure"
  if run_control_word canary 1 >"$TEST_ROOT/$failure.out" 2>&1; then
    printf '%s canary unexpectedly succeeded\n' "$failure" >&2
    exit 1
  fi
  grep -Fq 'canary failed; persistent enablement remains blocked' "$TEST_ROOT/$failure.out"
  [[ ! -e "$CONTROL_WORD_CANARY_MARKER" ]]
  [[ ! -e "$CONTROL_WORD_ENABLED_MARKER" ]]
done

# A launch failure also fails closed and leaves no stale attestation.
export OMARCHY_FAKE_CANARY_RESULT=launch-failure
if run_control_word canary 1 >"$TEST_ROOT/launch-failure.out" 2>&1; then
  printf 'canary launch failure unexpectedly succeeded\n' >&2
  exit 1
fi
grep -Fq 'canary could not be launched' "$TEST_ROOT/launch-failure.out"
[[ ! -e "$CONTROL_WORD_CANARY_MARKER" ]]

# Even a timeout token is rejected if the executable changed during the trial.
export OMARCHY_FAKE_CANARY_RESULT=changed-during-canary
if run_control_word canary 1 >"$TEST_ROOT/changed-during-canary.out" 2>&1; then
  printf 'canary unexpectedly attested to an executable changed during the trial\n' >&2
  exit 1
fi
[[ ! -e "$CONTROL_WORD_CANARY_MARKER" ]]

# Only a full fake timeout writes the success token and records the executable
# digest; it still leaves persistent mode disabled until explicitly enabled.
export OMARCHY_FAKE_CANARY_RESULT=pass
export OMARCHY_FAKE_LAUNCHD_STATE=missing
run_control_word canary 1 >"$TEST_ROOT/pass.out" 2>&1
control_word_canary_valid
[[ ! -e "$CONTROL_WORD_ENABLED_MARKER" ]]
[[ "$(run_control_word status)" == *'canary passed; persistent mode disabled'* ]]

# A loaded job is not accepted until launchd reports state = running.
export OMARCHY_FAKE_LAUNCHD_STATE=exited
if run_control_word enable >"$TEST_ROOT/not-running.out" 2>&1; then
  printf 'enable unexpectedly accepted a non-running launchd job\n' >&2
  exit 1
fi
grep -Fq 'did not reach state = running (state: exited)' "$TEST_ROOT/not-running.out" || {
  cat "$TEST_ROOT/not-running.out" >&2
  exit 1
}
[[ ! -e "$CONTROL_WORD_ENABLED_MARKER" ]]
control_word_canary_valid

# Status distinguishes a persistently enabled job that subsequently stopped.
touch "$CONTROL_WORD_ENABLED_MARKER"
[[ "$(run_control_word status)" == *'enabled but not running (launchd state: exited)'* ]]
rm -f "$CONTROL_WORD_ENABLED_MARKER"

# A healthy launchd state completes enablement.
export OMARCHY_FAKE_LAUNCHD_STATE=running
run_control_word enable >"$TEST_ROOT/enable.out" 2>&1
[[ -e "$CONTROL_WORD_ENABLED_MARKER" ]]
[[ "$(run_control_word status)" == *'enabled and running'* ]]

# Any executable change invalidates both the attestation and enable marker.
previous_digest="$(control_word_binary_digest)"
printf '# changed\n' >> "$CONTROL_WORD_BIN"
[[ "$(run_control_word status)" == *'running with invalid canary attestation'* ]]
invalidate_control_word_canary_if_binary_changed "$previous_digest"
[[ ! -e "$CONTROL_WORD_CANARY_MARKER" ]]
[[ ! -e "$CONTROL_WORD_ENABLED_MARKER" ]]
if run_control_word enable >"$TEST_ROOT/changed-enable.out" 2>&1; then
  printf 'enable unexpectedly accepted a stale binary attestation\n' >&2
  exit 1
fi

printf 'control_word_canary_fake.sh: all checks passed\n'
