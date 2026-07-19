#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omarchy-window-state-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

HELPER="$TMP_ROOT/window_state.pl"
FAKE_AEROSPACE="$TMP_ROOT/aerospace"
STATE_FILE="$TMP_ROOT/state.json"
LOG_FILE="$TMP_ROOT/window_state.log"
MONITORS_FILE="$TMP_ROOT/monitors.txt"
WINDOWS_FILE="$TMP_ROOT/windows.txt"
MOVES_FILE="$TMP_ROOT/moves.txt"
GUARD_FILE="$TMP_ROOT/restore-active"
STARTUP_GUARD_FILE="$TMP_ROOT/startup-restore-active"
PARTIAL_GUARD_FILE="$TMP_ROOT/restore-incomplete"

awk '/^#!\/usr\/bin\/env perl$/{in_block=1} in_block{print} /^WINDOW_STATE_PERL_EOF$/{exit}' "$ROOT/install.sh" | sed '$d' > "$HELPER"
chmod +x "$HELPER"

cat > "$FAKE_AEROSPACE" <<'FAKE_AEROSPACE_EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

format_rows() {
  local file="$1"
  local format="$2"
  local line id workspace app bundle title name out
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "$file" == "$OMARCHY_FAKE_MONITORS" ]]; then
      IFS='|' read -r id name <<< "$line"
      out="$format"
      out="${out//%\{monitor-id\}/$id}"
      out="${out//%\{monitor-name\}/$name}"
    else
      IFS='|' read -r id workspace app bundle title <<< "$line"
      out="$format"
      out="${out//%\{window-id\}/$id}"
      out="${out//%\{workspace\}/$workspace}"
      out="${out//%\{app-name\}/$app}"
      out="${out//%\{app-bundle-id\}/$bundle}"
      out="${out//%\{window-title\}/$title}"
    fi
    printf '%s\n' "$out"
  done < "$file"
}

case "$cmd" in
  list-monitors)
    format="%{monitor-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    format_rows "$OMARCHY_FAKE_MONITORS" "$format"
    ;;
  list-windows)
    workspace_filter=""
    format="%{window-id}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --all) shift ;;
        --workspace) workspace_filter="$2"; shift 2 ;;
        --format) format="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ -n "$workspace_filter" ]]; then
      awk -F'|' -v ws="$workspace_filter" '$2 == ws' "$OMARCHY_FAKE_WINDOWS" > "$OMARCHY_FAKE_WINDOWS.filtered"
      format_rows "$OMARCHY_FAKE_WINDOWS.filtered" "$format"
      rm -f "$OMARCHY_FAKE_WINDOWS.filtered"
    else
      format_rows "$OMARCHY_FAKE_WINDOWS" "$format"
    fi
    ;;
  move-node-to-workspace)
    window_id=""
    if [[ "${1:-}" == "--window-id" ]]; then
      window_id="$2"
      shift 2
    fi
    target="${1:?missing target workspace}"
    printf '%s|%s\n' "$window_id" "$target" >> "$OMARCHY_FAKE_MOVES"
    ;;
  workspace)
    ;;
  *)
    printf 'unexpected fake aerospace command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
FAKE_AEROSPACE_EOF
chmod +x "$FAKE_AEROSPACE"

export OMARCHY_AEROSPACE_BIN="$FAKE_AEROSPACE"
export OMARCHY_WINDOW_STATE_FILE="$STATE_FILE"
export OMARCHY_WINDOW_STATE_LOG="$LOG_FILE"
export OMARCHY_WINDOW_RESTORE_ATTEMPTS=1
export OMARCHY_WINDOW_RESTORE_DELAY=0
export OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS=1
export OMARCHY_WINDOW_RESTORE_GUARD="$GUARD_FILE"
export OMARCHY_WINDOW_STARTUP_RESTORE_GUARD="$STARTUP_GUARD_FILE"
export OMARCHY_WINDOW_PARTIAL_RESTORE_GUARD="$PARTIAL_GUARD_FILE"
export OMARCHY_WINDOW_DEBOUNCED_SAVER="$TMP_ROOT/missing-debounced-save"
export OMARCHY_FAKE_MONITORS="$MONITORS_FILE"
export OMARCHY_FAKE_WINDOWS="$WINDOWS_FILE"
export OMARCHY_FAKE_MOVES="$MOVES_FILE"

write_monitors() {
  : > "$MONITORS_FILE"
  printf '%s\n' "$@" > "$MONITORS_FILE"
}

write_windows() {
  : > "$WINDOWS_FILE"
  printf '%s\n' "$@" > "$WINDOWS_FILE"
  : > "$MOVES_FILE"
}

assert_moves() {
  local expected="$1"
  local actual
  actual="$(cat "$MOVES_FILE" 2>/dev/null || true)"
  if [[ "$actual" != "$expected" ]]; then
    printf 'expected moves:\n%s\nactual moves:\n%s\n' "$expected" "$actual" >&2
    exit 1
  fi
}

run_restore() {
  /usr/bin/perl "$HELPER" restore >/dev/null
}

run_save() {
  /usr/bin/perl "$HELPER" save "$@" >/dev/null
}

write_monitors "1|Built-in Display"
write_windows "101|01|Notes|com.apple.Notes|Scratch"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 1,
  "saved_at": "old",
  "windows": [
    {"window_id":101,"workspace":"17","app_name":"Notes","app_bundle_id":"com.apple.Notes","title":"Scratch"}
  ]
}
JSON
run_restore
assert_moves "101|07"

write_monitors "1|Built-in Display" "2|DELL U2723QE"
write_windows "201|01|Safari|com.apple.Safari|Docs"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "current_topology_key": "0:built-in:Built-in Display||1:external:DELL U2723QE",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display": {
      "format_version": 2,
      "saved_at": "wrong",
      "topology": {"key":"0:built-in:Built-in Display","monitor_count":1,"slot_names":["Built-in Display"],"monitors":[]},
      "windows": [{"window_id":201,"target_workspace":"04","app_name":"Safari","app_bundle_id":"com.apple.Safari","title":"Docs"}]
    },
    "0:built-in:Built-in Display||1:external:DELL U2723QE": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display||1:external:DELL U2723QE","monitor_count":2,"slot_names":["Built-in Display","DELL U2723QE"],"monitors":[]},
      "windows": [{"window_id":201,"target_workspace":"17","app_name":"Safari","app_bundle_id":"com.apple.Safari","title":"Docs"}]
    }
  }
}
JSON
run_restore
assert_moves "201|17"

write_monitors "1|Built-in Display"
write_windows "301|01|Safari|com.apple.Safari|Docs"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display||1:external:DELL U2723QE": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display||1:external:DELL U2723QE","monitor_count":2,"slot_names":["Built-in Display","DELL U2723QE"],"monitors":[]},
      "windows": [{"window_id":301,"target_workspace":"17","app_name":"Safari","app_bundle_id":"com.apple.Safari","title":"Docs"}]
    }
  }
}
JSON
run_restore
assert_moves "301|07"

write_monitors "1|Built-in Display"
write_windows "401|02|Messages|com.apple.MobileSMS|Chat"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display","monitor_count":1,"slot_names":["Built-in Display"],"monitors":[]},
      "windows": [{"window_id":401,"target_workspace":"09","app_name":"Messages","app_bundle_id":"com.apple.MobileSMS","title":"Chat"}]
    }
  }
}
JSON
run_restore
assert_moves ""

write_monitors "1|Built-in Display"
write_windows "411|02|Bear|net.shinyfrog.bear|Bear"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display","monitor_count":1,"slot_names":["Built-in Display"],"monitors":[]},
      "windows": [{"window_id":411,"target_workspace":"02","app_name":"Bear","app_bundle_id":"net.shinyfrog.bear","title":"Bear"}]
    }
  }
}
JSON
run_restore
assert_moves "411|08"

write_monitors "1|Built-in Display"
write_windows "416|07|Bear|net.shinyfrog.bear|Bear"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display","monitor_count":1,"slot_names":["Built-in Display"],"monitors":[]},
      "windows": [{"window_id":416,"workspace":"1","raw_workspace":"1","target_workspace":"1","app_name":"Bear","app_bundle_id":"net.shinyfrog.bear","title":"Bear"}]
    }
  }
}
JSON
run_restore
assert_moves "416|01"

write_monitors "1|Built-in Display"
write_windows "418|03|TV|com.apple.TV|TV"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display","monitor_count":1,"slot_names":["Built-in Display"],"monitors":[]},
      "windows": [{"window_id":418,"target_workspace":"04","app_name":"TV","app_bundle_id":"com.apple.TV","title":"TV"}]
    }
  }
}
JSON
run_restore
assert_moves "418|04"

write_monitors "1|Built-in Display"
write_windows "421|02|Gmail|com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm|"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display","monitor_count":1,"slot_names":["Built-in Display"],"monitors":[]},
      "windows": [{"window_id":421,"target_workspace":"02","app_name":"Gmail","app_bundle_id":"com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm","title":""}]
    }
  }
}
JSON
run_restore
assert_moves "421|01"

write_monitors "1|Built-in Display"
write_windows "451|02|System Settings|com.apple.systempreferences|"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display","monitor_count":1,"slot_names":["Built-in Display"],"monitors":[]},
      "windows": [{"window_id":9000,"target_workspace":"04","app_name":"System Settings","app_bundle_id":"com.apple.systempreferences","title":"Bluetooth"}]
    }
  }
}
JSON
run_restore
assert_moves "451|04"
[[ ! -e "$PARTIAL_GUARD_FILE" ]]

write_monitors "1|Built-in Display" "2|DELL U2723QE"
write_windows "461|04|iTerm2|com.googlecode.iterm2|Project"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display||1:external:DELL U2723QE": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display||1:external:DELL U2723QE","monitor_count":2,"slot_names":["Built-in Display","DELL U2723QE"],"monitors":[]},
      "windows": [{"window_id":461,"workspace":"10","raw_workspace":"10","target_workspace":"04","app_name":"iTerm2","app_bundle_id":"com.googlecode.iterm2","title":"Project"}]
    }
  }
}
JSON
run_restore
assert_moves ""

write_monitors "1|Built-in Display" "2|DELL U2723QE"
write_windows \
  "501|01|Google Chrome|com.google.Chrome|New title 1" \
  "502|01|Google Chrome|com.google.Chrome|New title 2"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display||1:external:DELL U2723QE": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display||1:external:DELL U2723QE","monitor_count":2,"slot_names":["Built-in Display","DELL U2723QE"],"monitors":[]},
      "windows": [
        {"window_id":9001,"target_workspace":"11","app_name":"Google Chrome","app_bundle_id":"com.google.Chrome","title":"Old title A","snapshot_order":0,"identity_order":0},
        {"window_id":9002,"target_workspace":"12","app_name":"Google Chrome","app_bundle_id":"com.google.Chrome","title":"Old title B","snapshot_order":1,"identity_order":0}
      ]
    }
  }
}
JSON
run_restore
assert_moves $'501|11\n502|12'

write_monitors "1|Built-in Display" "2|DELL U2723QE"
write_windows "551|04|Google Chrome|com.google.Chrome|New Tab"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "new",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display||1:external:DELL U2723QE": {
      "format_version": 2,
      "saved_at": "right",
      "topology": {"key":"0:built-in:Built-in Display||1:external:DELL U2723QE","monitor_count":2,"slot_names":["Built-in Display","DELL U2723QE"],"monitors":[]},
      "windows": [
        {"window_id":551,"target_workspace":"04","app_name":"Google Chrome","app_bundle_id":"com.google.Chrome","title":"New Tab","snapshot_order":0,"identity_order":0},
        {"window_id":551,"target_workspace":"11","app_name":"Google Chrome","app_bundle_id":"com.google.Chrome","title":"Docs","snapshot_order":1,"identity_order":0},
        {"window_id":551,"target_workspace":"12","app_name":"Google Chrome","app_bundle_id":"com.google.Chrome","title":"Mail","snapshot_order":2,"identity_order":0}
      ]
    }
  }
}
JSON
run_restore
assert_moves ""
[[ -e "$PARTIAL_GUARD_FILE" ]]
rm -f "$PARTIAL_GUARD_FILE"

write_monitors "1|Built-in Display"
write_windows "601|15|Zed|dev.zed.Zed|Project"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "existing",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display||1:external:Studio Display": {
      "format_version": 2,
      "saved_at": "external",
      "topology": {"key":"0:built-in:Built-in Display||1:external:Studio Display","monitor_count":2,"slot_names":["Built-in Display","Studio Display"],"monitors":[]},
      "windows": [{"window_id":1,"target_workspace":"15","app_name":"Safari","app_bundle_id":"com.apple.Safari","title":"External"}]
    }
  }
}
JSON
run_save auto event
/usr/bin/perl -MJSON::PP -0777 -e '
  my $s = decode_json(<>);
  die "missing current topology\n" unless $s->{snapshots}{"0:built-in:Built-in Display"};
  die "overwrote other topology\n" unless $s->{snapshots}{"0:built-in:Built-in Display||1:external:Studio Display"};
  die "expected two topologies\n" unless scalar(keys %{$s->{snapshots}}) == 2;
  my ($z) = grep { $_->{app_bundle_id} eq "dev.zed.Zed" } @{$s->{snapshots}{"0:built-in:Built-in Display"}{windows}};
  die "assigned app save did not preserve actual workspace\n" unless $z && $z->{target_workspace} eq "15";
' "$STATE_FILE"

cp "$STATE_FILE" "$STATE_FILE.before"
touch "$GUARD_FILE"
run_save auto guarded
rm -f "$GUARD_FILE"
cmp -s "$STATE_FILE.before" "$STATE_FILE"

touch "$STARTUP_GUARD_FILE"
run_save auto startup-guarded
rm -f "$STARTUP_GUARD_FILE"
cmp -s "$STATE_FILE.before" "$STATE_FILE"

write_monitors "1|Built-in Display"
write_windows "701|02|Messages|com.apple.MobileSMS|Chat"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "restore-target",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display": {
      "format_version": 2,
      "saved_at": "restore-target",
      "topology": {"key":"0:built-in:Built-in Display","monitor_count":1,"slot_names":["Built-in Display"],"monitors":[]},
      "windows": [
        {"window_id":701,"target_workspace":"02","app_name":"Messages","app_bundle_id":"com.apple.MobileSMS","title":"Chat"},
        {"window_id":702,"target_workspace":"08","app_name":"1Password","app_bundle_id":"com.1password.1password","title":"Lock Screen"}
      ]
    }
  }
}
JSON
run_restore
assert_moves ""
[[ -e "$PARTIAL_GUARD_FILE" ]]

cp "$STATE_FILE" "$STATE_FILE.before"
run_save auto partial-restore
cmp -s "$STATE_FILE.before" "$STATE_FILE"

write_windows \
  "701|02|Messages|com.apple.MobileSMS|Chat" \
  "702|02|1Password|com.1password.1password|Lock Screen"
run_restore
assert_moves "702|08"
[[ ! -e "$PARTIAL_GUARD_FILE" ]]

write_monitors "1|Built-in Display" "2|DELL U2723QE"
write_windows "801|02|Google Chrome|com.google.Chrome|New Tab"
cat > "$STATE_FILE" <<'JSON'
{
  "format_version": 2,
  "saved_at": "stable",
  "current_topology_key": "0:built-in:Built-in Display||1:external:DELL U2723QE",
  "windows": [],
  "snapshots": {
    "0:built-in:Built-in Display||1:external:DELL U2723QE": {
      "format_version": 2,
      "saved_at": "stable",
      "save_mode": "manual",
      "save_reason": "manual",
      "topology": {"key":"0:built-in:Built-in Display||1:external:DELL U2723QE","monitor_count":2,"slot_names":["Built-in Display","DELL U2723QE"],"monitors":[]},
      "windows": [{"window_id":801,"target_workspace":"07","workspace":"07","raw_workspace":"07","app_name":"Google Chrome","app_bundle_id":"com.google.Chrome","title":"New Tab"}]
    }
  }
}
JSON
cp "$STATE_FILE" "$STATE_FILE.before"
touch "$STARTUP_GUARD_FILE"
run_save auto startup-window-detected
rm -f "$STARTUP_GUARD_FILE"
cmp -s "$STATE_FILE.before" "$STATE_FILE"

run_restore
assert_moves "801|07"

/usr/bin/perl -0777 -e '
  my $source = <>;
  die "restore wrapper must repair named workspace ownership after replay\n"
    unless $source =~ /cat > "\$WINDOW_STATE_WRAPPER" << .*?command="\$\{1:-status\}".*?if \[ "\$command" = "restore" \].*?omarchy_repair_app_assigned_workspaces/s;
' "$ROOT/install.sh"

printf 'window_state_fake.sh: all checks passed\n'
