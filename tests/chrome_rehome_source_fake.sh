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
  die "missing general workspace key filter\n"
    unless $source =~ /let generalWorkspaceKeys: \[String\] = \["7","8","9"\]/;
  die "missing existing Chrome workspace preference\n"
    unless $source =~ /func chromeWorkspaceOnMonitor\(_ monitor: String, rows: \[WindowRow\], skip currentWs: String, newWindowId: UInt32\) -> String\?/;
  die "missing reserved-workspace-safe empty fallback\n"
    unless $source =~ /func firstEmptyGeneralWorkspaceOnMonitor\(_ monitor: String, rows: \[WindowRow\], skip currentWs: String\) -> String\?/ &&
           $source =~ /for key in generalWorkspaceKeys/;
  die "missing combined Chrome target selector\n"
    unless $source =~ /func targetWorkspaceForChrome\(monitor: String, rows: \[WindowRow\], currentWs: String, newWindowId: UInt32\) -> String\?/ &&
           $source =~ /chromeWorkspaceOnMonitor\(monitor, rows: rows, skip: currentWs, newWindowId: newWindowId\)/ &&
           $source =~ /firstEmptyGeneralWorkspaceOnMonitor\(monitor, rows: rows, skip: currentWs\)/;
  die "missing same-workspace Chrome sibling guard\n"
    unless $source =~ /already has Chrome here, leaving in place/;
  die "missing external-monitor no-rehome guard\n"
    unless $source =~ /if monitorSlot != 0 \{/ &&
           index($source, q{on external workspace \(ws): leaving in place}) >= 0;
  die "should not keep old all-workspaces first-empty helper\n"
    if $source =~ /func firstEmptyOnMonitor/;
  die "missing rehome move command\n"
    unless $source =~ /sh\(\["move-node-to-workspace", "--window-id", "\\\(wid\)", target\]\)/;
  die "missing target workspace focus\n"
    unless $source =~ /sh\(\["workspace", target\]\)/;
  die "missing post-detection window-state save\n"
    unless $source =~ /scheduleWindowStateSave\("chrome-window-detected"\)/;
  die "missing restore guard paths\n"
    unless $source =~ /restoreGuardPath/ && $source =~ /startupRestoreGuardPath/ && $source =~ /partialRestoreGuardPath/;
  die "missing restore-active rehome guard\n"
    unless $source =~ /restoreActive\(\)/ && $source =~ /restore is active or incomplete; leaving in place/;
  die "queue worker path should not be present\n"
    if $source =~ /omarchy_chrome_rehome|AEROSPACE_WINDOW_ID/;
' "$SOURCE"

printf 'chrome_rehome_source_fake.sh: all checks passed\n'
