#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-chrome-rehome-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

SOURCE="$TMP_ROOT/chrome_rehome.swift"

awk '/cat > "\$source_tmp" << '\''CHROME_REHOME_SWIFT_EOF'\''/{in_block=1; next} /^CHROME_REHOME_SWIFT_EOF$/{exit} in_block{print}' \
  "$ROOT/install.sh" > "$SOURCE"

/usr/bin/perl -0777 -e '
  my $source = <>;
  die "missing AX window-created observer\n"
    unless $source =~ /kAXWindowCreatedNotification/;
  die "missing Accessibility trust check\n"
    unless $source =~ /AXIsProcessTrustedWithOptions/;
  die "missing Chrome workspace scan order\n"
    unless $source =~ /let scanOrder: \[String\] = \["1","2","3","4","5","6","7","8","9","0"\]/;
  die "missing first-empty workspace helper\n"
    unless $source =~ /func firstEmptyOnMonitor\(_ monitor: String, skip currentWs: String\) -> String\?/;
  die "missing same-workspace Chrome sibling guard\n"
    unless $source =~ /already has Chrome here, leaving in place/;
  die "missing rehome move command\n"
    unless $source =~ /sh\(\["move-node-to-workspace", "--window-id", "\\\(wid\)", target\]\)/;
  die "missing target workspace focus\n"
    unless $source =~ /sh\(\["workspace", target\]\)/;
  die "missing post-detection window-state save\n"
    unless $source =~ /scheduleWindowStateSave\("chrome-window-detected"\)/;
  die "queue worker path should not be present\n"
    if $source =~ /omarchy_chrome_rehome|AEROSPACE_WINDOW_ID/;
' "$SOURCE"

printf 'chrome_rehome_source_fake.sh: all checks passed\n'
