# omarchy-macos Keyboard Shortcuts

All shortcuts use **Option (⌥)** as the modifier key, mirroring the SUPER key in Hyprland/Omarchy on Linux.

## Workspaces

Workspace shortcuts resolve against the monitor under the mouse, falling back to
the focused monitor. The built-in display uses slot `0`; external displays use
slots `1`, `2`, and `3` when attached. For example, `⌥+7` targets `07` on the
built-in display and `17` on the first external display.

| Shortcut | Action |
|----------|--------|
| ⌥ + 1–0 | Switch to workspace 1–10 on the current monitor |
| ⌥ + Shift + 1–0 | Move focused window to workspace 1–10 on the current monitor |
| ⌥ + Tab | Toggle back and forth between last workspace |
| ⌥ + Shift + Tab | Move workspace to next monitor |
| ⌥ + Ctrl + Tab | Focus next window across all workspaces |
| ⌥ + Ctrl + Shift + Tab | Focus previous window across all workspaces |

## Window Focus

| Shortcut | Action |
|----------|--------|
| ⌥ + H | Focus window left |
| ⌥ + J | Focus window down |
| ⌥ + K | Focus window up |
| ⌥ + L | Focus window right |

## Window Overview

| Shortcut | Action |
|----------|--------|
| ⌥ + Up | Readable all-window picker |
| ⌥ + Shift + Up | Mission Control / expose |

## Window Movement

| Shortcut | Action |
|----------|--------|
| ⌥ + Shift + H | Move window left |
| ⌥ + Shift + J | Move window down |
| ⌥ + Shift + K | Move window up |
| ⌥ + Shift + L | Move window right |
| ⌥ + Ctrl + Shift + H | Move window to left monitor |
| ⌥ + Ctrl + Shift + L | Move window to right monitor |

## Window Resize

| Shortcut | Action |
|----------|--------|
| ⌥ + Ctrl + H | Shrink width |
| ⌥ + Ctrl + L | Grow width |
| ⌥ + Ctrl + K | Shrink height |
| ⌥ + Ctrl + J | Grow height |

## Layout & Window Management

| Shortcut | Action |
|----------|--------|
| ⌥ + F | Toggle fullscreen |
| ⌥ + E | Toggle split direction (horizontal/vertical) |
| ⌥ + S | Toggle accordion (stacked) layout |
| ⌥ + Shift + Space | Toggle floating/tiling |
| ⌥ + Shift + Q | Close focused window |

Crowded workspaces automatically switch to accordion layout when the estimated
split width falls below 640 points per window.

## App Launchers (skhd)

| Shortcut | Action |
|----------|--------|
| ⌥ + Return | Terminal (Ghostty → WezTerm → Terminal.app) |
| ⌥ + Shift + B | Browser (Safari → Chrome → Firefox) |
| ⌥ + Shift + N | Editor (Cursor → VS Code → TextEdit) |
| ⌥ + Shift + F | File manager (Finder) |
| ⌥ + Shift + M | Music (Spotify → Music.app) |
| ⌥ + Shift + G | Communications (Slack → Messages) |
| ⌥ + Shift + I | AI (ChatGPT → Claude) |
| ⌥ + Shift + / | Passwords (1Password → Keychain Access) |

## Screenshots

| Shortcut | Action |
|----------|--------|
| ⌥ + Shift + S | Region screenshot to clipboard |
| ⌥ + P | Full screenshot to clipboard |

## Config Reload

| Shortcut | Action |
|----------|--------|
| ⌥ + Shift + R | Reload Aerospace config |
| ⌥ + Shift + C | Reload skhd config |

## Diagnostics

Secure Input can prevent AeroSpace and skhd from receiving global keyboard
events. Use a terminal for this diagnostic because a shortcut may not fire while
Secure Input is active.

```sh
./install.sh secure-input
./install.sh secure-input --watch
```

## Bar

| Shortcut | Action |
|----------|--------|
| ⌥ + Z | Toggle SketchyBar |

## Launcher

Set **⌥ + Space** as the Raycast hotkey in Raycast Settings → General → Raycast Hotkey.
