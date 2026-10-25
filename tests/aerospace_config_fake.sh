#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

/usr/bin/perl -0777 -e '
  my $source = <>;

  die "AeroSpace must not own Option hotkeys; skhd needs side/app awareness\n"
    if $source =~ /^alt(?:-|\+)/m;

  die "missing skhd move-and-follow generation\n"
    unless $source =~ /write_binding "lalt \+ shift - \$key" "\$HOME\/\.config\/aerospace\/goto_space\.sh \$key --move-follow"/;

  die "missing skhd no-follow generation\n"
    unless $source =~ /write_binding "lalt \+ shift \+ ctrl - \$key" "\$HOME\/\.config\/aerospace\/goto_space\.sh \$key --move"/;

  # App assignments live in one shell table used by new-window placement.
  my @assignments = (
    [q{*Mail*|*Gmail*}, "01"],
    [q{*Messages*|*Signal*|*Google\ Chat*}, "02"],
    [q{*Spotify*|*Music*}, "03"],
    [q{*Ghostty*|*WezTerm*|*Warp*|*iTerm2*}, "04"],
    [q{*Zed*|*Antigravity*}, "05"],
    [q{*ChatGPT*}, "06"],
  );
  for my $assignment (@assignments) {
    my ($pattern, $workspace) = @$assignment;
    my $quoted = quotemeta($pattern);
    die "missing app assignment for $pattern -> $workspace\n"
      unless $source =~ /$quoted\) printf '\''$workspace\\n'\''; return 0 ;;/;
  }
  die "missing bundle assignments for agent apps\n"
    unless $source =~ /com\.anthropic\.claudefordesktop\|com\.google\.GeminiMacOS\|com\.openai\.chat\)\n\s*printf '\''06\\n'\''/;

  die "per-app window-detected rules must not run their own placement\n"
    if $source =~ /run = '\''exec-and-forget [^'\'']*(?:assigned_window_rehome|unassigned_window_rehome)/ ||
       $source =~ /run = \['\''move-node-to-workspace \d\d'\''/;

  die "missing focused-workspace audit callback\n"
    unless $source =~ /exec-on-workspace-change = \['\''\/bin\/bash'\'', '\''-c'\'', '\''~\/\.config\/aerospace\/workspace_change_log\.sh "(?:\\)?\$AEROSPACE_PREV_WORKSPACE" "(?:\\)?\$AEROSPACE_FOCUSED_WORKSPACE"'\''\]/ &&
           $source =~ /workspace focus changed from=%s to=%s rapid=%s delta_ms=%s prior=%s focused_monitor=%s focused_window=%s/;

  die "window-detected saver callback must keep checking further callbacks\n"
    unless $source =~ /\[\[on-window-detected\]\]\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/window_state_debounced_save\.sh window-detected'\''\ncheck-further-callbacks = true/;

  die "responsive layout must not run before placement settles\n"
    if $source =~ /responsive_layout\.sh window-detected'\''/;

  my @placement_callbacks = $source =~ /new_window_placement\.sh "(?:\\)?\$AEROSPACE_WINDOW_ID"/g;
  die "exactly one catch-all new-window placement callback expected\n"
    unless @placement_callbacks == 1 &&
           $source =~ /\[\[on-window-detected\]\]\nif\.during-aerospace-startup = false\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/new_window_placement\.sh "(?:\\)?\$AEROSPACE_WINDOW_ID"'\''/;

  die "missing floating Local Authentication callback before generic placement\n"
    unless $source =~ /if\.app-id = '\''com\.apple\.LocalAuthentication\.UIAgent'\''\nrun = \['\''layout floating'\''\]\ncheck-further-callbacks = true.*?if\.during-aerospace-startup = false\nrun = '\''exec-and-forget ~\/\.config\/aerospace\/new_window_placement/s;

  my ($placement) = $source =~ /<< '\''NEW_WINDOW_PLACEMENT_EOF'\''\n(.*?)\nNEW_WINDOW_PLACEMENT_EOF/s;
  die "missing new-window placement helper\n" unless defined $placement;

  die "transient authentication UI can still enter launch placement\n"
    unless $placement =~ /bundle_id" == "com\.apple\.LocalAuthentication\.UIAgent".*?transient authentication window retained.*?no rehome or follow.*?exit 0/s;

  die "placement must target the detected window instead of current focus\n"
    unless $placement =~ /target_window_id="\$\{1:-\$\{AEROSPACE_WINDOW_ID:-\}\}"/;

  # The only focus change is the launch move itself, in one AeroSpace command.
  my @follows = $placement =~ /--focus-follows-window/g;
  die "launch placement must follow with exactly one move-and-follow command\n"
    unless @follows == 1 &&
           $placement =~ /move-node-to-workspace --window-id "\$window_id" --focus-follows-window "\$target"/;
  die "placement must not issue separate workspace or focus commands\n"
    if $placement =~ /"\$OMARCHY_AEROSPACE_BIN" (?:workspace|focus)\b/;

  die "placement must leave floating dialogs and background apps in place\n"
    unless $placement =~ /if \[ "\$layout" = "floating" \]; then/ &&
           $placement =~ /\[ "\$front" != "\$bundle_id\|\$workspace" \]/;

  die "settled responsive layout must target the detected window id\n"
    unless $placement =~ /check_responsive_layout\(\) \{\n\s*"\$HOME\/\.config\/aerospace\/responsive_layout\.sh" "\$1" "\$window_id"/ &&
           $source =~ /layout --window-id "\$TARGET_WINDOW_ID" accordion horizontal vertical/;

  die "Apple TV must stay unassigned and use generic launch placement\n"
    if $source =~ /if\.app-id = '\''com\.apple\.TV'\''\nrun = \['\''move-node-to-workspace /;

  die "Steam must stay unassigned because key 0 is fallback, not named\n"
    if $source =~ /if\.app-name-regex-substring = '\''Steam'\''\nrun = \['\''move-node-to-workspace /;

  die "unassigned placement should use named workspace helper, not hard-coded named keys\n"
    unless $placement =~ /elif ! omarchy_is_named_workspace "\$workspace"; then/;

  die "move helper no longer calls aerospace move-node-to-workspace target\n"
    unless $source =~ /case "\$ACTION" in.*?--move-follow\).*?aerospace move-node-to-workspace "\$TARGET".*?--move\).*?aerospace move-node-to-workspace "\$TARGET"/s;

  die "move helper no longer records move-window state changes\n"
    unless $source =~ /window_state_debounced_save\.sh" "move-node-to-workspace-\$TARGET"/;

  die "move helper no longer checks responsive layout after moves\n"
    unless $source =~ /responsive_layout\.sh" "move-node-to-workspace-\$TARGET"/;
' "$ROOT/install.sh"

printf 'aerospace_config_fake.sh: all checks passed\n'
