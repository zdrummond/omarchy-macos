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
    ["Steam", "00"],
  );

  for my $assignment (@assignments) {
    my ($matcher, $workspace) = @$assignment;
    my $quoted = quotemeta($matcher);
    my $app_id = qr/if\.app-id = '\''$quoted'\''\nrun = \['\''move-node-to-workspace $workspace'\'', '\''workspace $workspace'\''\]/;
    my $app_name = qr/if\.app-name-regex-substring = '\''$quoted'\''\nrun = \['\''move-node-to-workspace $workspace'\'', '\''workspace $workspace'\''\]/;
    die "missing app assignment for $matcher -> $workspace\n"
      unless $source =~ $app_id || $source =~ $app_name;
  }

  die "app-assignment saver callback must keep checking further callbacks\n"
    unless $source =~ /\[\[on-window-detected\]\]\nrun = \[\n  '\''exec-and-forget ~\/\.config\/aerospace\/window_state_debounced_save\.sh window-detected'\'',\n  '\''exec-and-forget ~\/\.config\/aerospace\/responsive_layout\.sh window-detected'\''\n\]\ncheck-further-callbacks = true/;

  die "missing final unassigned app launch rehome callback\n"
    unless $source =~ /\[\[on-window-detected\]\]\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/unassigned_window_rehome\.sh'\''/;

  die "Apple TV must stay unassigned and use generic launch rehome\n"
    if $source =~ /if\.app-id = '\''com\.apple\.TV'\''\nrun = \['\''move-node-to-workspace /;

  die "move helper no longer calls aerospace move-node-to-workspace target\n"
    unless $source =~ /case "\$ACTION" in\n  --move\)\n    aerospace move-node-to-workspace "\$TARGET"/;

  die "move helper no longer records move-window state changes\n"
    unless $source =~ /window_state_debounced_save\.sh" "move-node-to-workspace-\$TARGET"/;

  die "move helper no longer checks responsive layout after moves\n"
    unless $source =~ /responsive_layout\.sh" "move-node-to-workspace-\$TARGET"/;
' "$ROOT/install.sh"

printf 'aerospace_config_fake.sh: all checks passed\n'
