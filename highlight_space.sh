#!/usr/bin/env bash
# Usage:
#   highlight_space.sh <0-9>   # highlight that space
#   highlight_space.sh clear   # clear all highlights

if [ -z "$1" ]; then
  echo "Usage:"
  echo "  highlight_space.sh <0-9>   # highlight that space"
  echo "  highlight_space.sh clear   # clear all highlights"
  exit 1
fi

export CONFIG_DIR="$HOME/.config/sketchybar"
source "$CONFIG_DIR/plugins/spaces.sh"

arg="$1"
if [ "$arg" = "clear" ]; then
  highlight_space ""
else
  highlight_space "$arg"
fi
