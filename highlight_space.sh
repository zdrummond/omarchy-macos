#!/usr/bin/env bash
# Manually paint the space highlight on sketchybar. Workspace names follow
# the per-monitor scheme: "${display_id}${key}" (e.g. "03", "23").
#
# Usage:
#   highlight_space.sh <NN>    # highlight workspace NN directly (e.g. 03, 23)
#   highlight_space.sh <N>     # highlight key N on the currently focused monitor
#   highlight_space.sh clear   # clear all highlights

set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage:"
  echo "  highlight_space.sh <NN>    # highlight workspace NN directly (e.g. 03, 23)"
  echo "  highlight_space.sh <N>     # highlight key N on the currently focused monitor"
  echo "  highlight_space.sh clear   # clear all highlights"
  exit 1
fi

export CONFIG_DIR="$HOME/.config/sketchybar"
source "$CONFIG_DIR/plugins/spaces.sh"

arg="$1"
case "$arg" in
  clear)
    highlight_space ""
    ;;
  [0-9][0-9])
    highlight_space "$arg"
    ;;
  [0-9])
    mid=$(aerospace list-monitors --focused --format '%{monitor-id}')
    display=$((mid - 1))
    highlight_space "${display}${arg}"
    ;;
  *)
    echo "highlight_space.sh: invalid arg '$arg' (expected NN, N, or 'clear')" >&2
    exit 1
    ;;
esac
