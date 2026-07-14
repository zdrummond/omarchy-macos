#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: scripts/check_spec_drift.sh [--cached]

Fails when likely behavior-changing diffs are present without a matching
SPEC.md update. Use --cached to inspect staged changes before commit.
EOF
}

cached=0
case "${1:-}" in
  "")
    ;;
  --cached)
    cached=1
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [ "$cached" -eq 1 ]; then
  changed_files="$(git diff --cached --name-only)"
else
  changed_files="$(git diff --name-only)"
fi
[ -n "$changed_files" ] || exit 0

if grep -qx 'SPEC.md' <<< "$changed_files"; then
  exit 0
fi

behavior_files_regex='^(install\.sh|omarchy\.sh|README\.md|tests/.*\.sh)$'
behavior_terms_regex='(window_state|restore|startup|workspace|aerospace|skhd|sketchybar|LaunchAgent|keybinding|save-window-state|restore-window-state|guard)'

behavior_files="$(grep -E "$behavior_files_regex" <<< "$changed_files" || true)"
[ -n "$behavior_files" ] || exit 0

if [ "$cached" -eq 1 ]; then
  diff_text="$(git diff --cached -- $behavior_files)"
else
  diff_text="$(git diff -- $behavior_files)"
fi
if grep -Eiq "$behavior_terms_regex" <<< "$diff_text"; then
  cat >&2 <<'EOF'
SPEC.md may need an update.

This diff touches restore/save/workspace/keybinding/service behavior, but
SPEC.md is not changed. Review SPEC.md before proceeding. If the spec is still
correct, mention that explicitly in the commit or final response.
EOF
  exit 1
fi
