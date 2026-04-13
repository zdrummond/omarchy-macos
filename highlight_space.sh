#!/usr/bin/env bash
# Usage:
#   highlight_space.sh <1-9>   # highlight that space
#   highlight_space.sh clear   # clear all highlights
#   highlight_space.sh         # (no arg) clear all highlights
export CONFIG_DIR="$HOME/.config/sketchybar"
source "$CONFIG_DIR/plugins/spaces.sh"

arg="${1:-clear}"
if [ "$arg" = "clear" ]; then
  highlight_space ""
else
  highlight_space "$arg"
fi
