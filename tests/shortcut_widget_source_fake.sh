#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

/usr/bin/perl -0777 -e '
  my $source = <>;

  die "widget activation-policy failure must not terminate the app\n"
    if $source =~ /guard app\.setActivationPolicy\(\.accessory\)/;
  die "widget must log launch and rendered window details\n"
    unless $source =~ /application finished launching/ &&
           $source =~ /ordered window frame=/ &&
           $source =~ /cannot load image at/;
  die "widget must redraw when screen parameters change\n"
    unless $source =~ /applicationDidChangeScreenParameters/;
  die "widget must join fullscreen Spaces where permitted\n"
    unless $source =~ /\.fullScreenAuxiliary/;
  die "widget must stay above the macOS 26 wallpaper stack but below apps\n"
    unless $source =~ /NSWindow\.Level\.normal\.rawValue - 1/ &&
           $source !~ /CGWindowLevelForKey\(\.desktopIconWindow\)/;
  die "LaunchAgent must start the app through LaunchServices and wait for it\n"
    unless $source =~ m{<string>/usr/bin/open</string>.*?<string>-W</string>.*?<string>-n</string>.*?<string>-g</string>.*?<string>-a</string>.*?<string>\$SHORTCUT_WIDGET_APP</string>}s;
  die "widget must publish and clean up a validated pid file\n"
    unless $source =~ /omarchy_shortcut_widget\.pid/ &&
           $source =~ /applicationWillTerminate/ &&
           $source =~ /command_name.*?shortcut_widget/s;
  die "widget rebuild must stop the existing LaunchServices child first\n"
    unless $source =~ /cmd_shortcuts_widget\(\).*?stop_shortcut_widget.*?write_shortcut_desktop_widget/s;
' "$ROOT/install.sh"

printf 'shortcut_widget_source_fake.sh: all checks passed\n'
