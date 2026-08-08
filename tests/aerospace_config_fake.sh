#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

/usr/bin/perl -0777 -e '
  my $source = <>;

  my @move_bindings = map {
    my $key = $_;
    my $workspace_key = $key;
    qr/alt-shift-$key = '\''exec-and-forget ~\/\.config\/aerospace\/goto_space\.sh $workspace_key --move'\''/;
  } qw(1 2 3 4 5 6 7 8 9 0);

  for my $pattern (@move_bindings) {
    die "missing move-window keybinding: $pattern\n" unless $source =~ $pattern;
  }

  my @assignments = (
    ["com.apple.mail", "01"],
    ["com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm", "01"],
    ["Messages", "02"],
    ["Signal", "02"],
    ["Google Chat", "02"],
    ["Spotify|Music", "03"],
    ["Ghostty|WezTerm|Warp|iTerm2", "04"],
    ["Zed|Antigravity", "05"],
    ["com.anthropic.claudefordesktop", "06"],
    ["com.google.GeminiMacOS", "06"],
    ["com.openai.chat", "06"],
    ["ChatGPT", "06"],
  );

  for my $assignment (@assignments) {
    my ($matcher, $workspace) = @$assignment;
    my $quoted = quotemeta($matcher);
    my $app_id = qr/if\.app-id = '\''$quoted'\''\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/assigned_window_rehome\.sh $workspace "(?:\\)?\$AEROSPACE_WINDOW_ID"'\''\ncheck-further-callbacks = true/;
    my $app_name = qr/if\.app-name-regex-substring = '\''$quoted'\''\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/assigned_window_rehome\.sh $workspace "(?:\\)?\$AEROSPACE_WINDOW_ID"'\''\ncheck-further-callbacks = true/;
    die "missing app assignment for $matcher -> $workspace\n"
      unless $source =~ $app_id || $source =~ $app_name;
  }

  die "assigned app detection must not activate its destination workspace\n"
    if $source =~ /run = \['\''move-node-to-workspace \d\d'\'', '\''workspace \d\d'\''\]/;

  die "missing focused-workspace audit callback\n"
    unless $source =~ /exec-on-workspace-change = \['\''\/bin\/bash'\'', '\''-c'\'', '\''~\/\.config\/aerospace\/workspace_change_log\.sh "(?:\\)?\$AEROSPACE_PREV_WORKSPACE" "(?:\\)?\$AEROSPACE_FOCUSED_WORKSPACE"'\''\]/ &&
           $source =~ /workspace focus changed from=%s to=%s focused_window=%s/;

  my ($assigned_helper) = $source =~ /<< '\''ASSIGNED_WINDOW_REHOME_EOF'\''\n(.*?)\nASSIGNED_WINDOW_REHOME_EOF/s;
  die "assigned app helper must log focus context without activating a workspace\n"
    unless defined($assigned_helper) &&
           $assigned_helper =~ /assigned window moved window=.*focused_before=.*focused_after=.*no workspace activation/ &&
           $assigned_helper !~ /\b(?:aerospace|"\$OMARCHY_AEROSPACE_BIN") workspace\b/;

  die "window-detected saver callback must keep checking further callbacks\n"
    unless $source =~ /\[\[on-window-detected\]\]\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/window_state_debounced_save\.sh window-detected'\''\ncheck-further-callbacks = true/;

  die "responsive layout must not run before assignment/rehome settles\n"
    if $source =~ /responsive_layout\.sh window-detected'\''/;

  die "missing final unassigned app launch rehome callback\n"
    unless $source =~ /\[\[on-window-detected\]\]\nif = '\''true'\''\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/unassigned_window_rehome\.sh "(?:\\)?\$AEROSPACE_WINDOW_ID"'\''/;

  die "unassigned rehome must target the detected window instead of current focus\n"
    unless $source =~ /target_window_id="\$\{1:-\$\{AEROSPACE_WINDOW_ID:-\}\}"/ &&
           $source !~ /list-windows --focused --format '\''%\{window-id\}\|%\{workspace\}\|%\{app-name\}\|%\{app-bundle-id\}'\''/;

  die "successful automatic follow must start the close watcher\n"
    unless $source =~ /if follow_rehomed_window "\$target"; then.*?"\$CLOSE_WATCHER" "\$window_id" "\$workspace" "\$target" .*?&/s;

  die "settled responsive layout must target the detected window id\n"
    unless $source =~ /check_responsive_layout\(\).*?responsive_layout\.sh" "\$reason" "\$window_id"/s &&
           $source =~ /layout --window-id "\$TARGET_WINDOW_ID" accordion horizontal vertical/;

  die "Apple TV must stay unassigned and use generic launch rehome\n"
    if $source =~ /if\.app-id = '\''com\.apple\.TV'\''\nrun = \['\''move-node-to-workspace /;

  die "Steam must stay unassigned because key 0 is fallback, not named\n"
    if $source =~ /if\.app-name-regex-substring = '\''Steam'\''\nrun = \['\''move-node-to-workspace /;

  die "unassigned rehome should use named workspace helper, not hard-coded named keys\n"
    unless $source =~ /if ! omarchy_is_named_workspace "\$workspace"; then/;

  die "move helper no longer calls aerospace move-node-to-workspace target\n"
    unless $source =~ /case "\$ACTION" in\n  --move\)\n    aerospace move-node-to-workspace "\$TARGET"/;

  die "move helper no longer records move-window state changes\n"
    unless $source =~ /window_state_debounced_save\.sh" "move-node-to-workspace-\$TARGET"/;

  die "move helper no longer checks responsive layout after moves\n"
    unless $source =~ /responsive_layout\.sh" "move-node-to-workspace-\$TARGET"/;
' "$ROOT/install.sh"

printf 'aerospace_config_fake.sh: all checks passed\n'
