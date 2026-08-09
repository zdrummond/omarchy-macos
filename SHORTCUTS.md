# omarchy-macos Keyboard Shortcuts

**Left Option (`L⌥`) is Omarchy Super. Right Option (`R⌥`) remains native
macOS input, including terminal Meta input.** Left Option shortcuts work in
every app, including Ghostty, WezTerm, Warp, iTerm2, and Terminal.

Press **Fn + Escape** to toggle Native Input mode. It temporarily disables all
Omarchy global shortcuts until Fn + Escape is pressed again, making both Option
keys available to the focused terminal or application.

## Workspaces

Workspace shortcuts resolve against the monitor under the mouse, falling back
to the focused monitor. The built-in display uses slot `0`; external displays
use slots `1`, `2`, and `3` when attached.

| Shortcut | Action |
| --- | --- |
| L⌥ + 1–0 | Switch to workspace 1–10 on the current monitor |
| L⌥ + Shift + 1–0 | Move focused window and follow it |
| L⌥ + Shift + Control + 1–0 | Move focused window without following |
| L⌥ + Tab | Next workspace |
| L⌥ + Shift + Tab | Previous workspace |
| L⌥ + Command + Tab | Return to the former workspace |

Standard **Command + Tab** remains the macOS application switcher.

## Text Navigation

| Shortcut | Action |
| --- | --- |
| Control + Left / Right | Move to the previous / next word |
| Control + Shift + Left / Right | Select to the previous / next word |
| Right Option + Arrow | Native macOS text navigation fallback |

The Control-arrow bindings replace macOS's native Mission Control shortcuts for
moving between Spaces. Press Fn + Escape to temporarily pass Control-arrow
through unchanged. The remapper is fail-open and is managed with
`./omarchy.sh control-word-navigation canary|enable|disable|status`.

## Window Focus and Movement

| Shortcut | Action |
| --- | --- |
| L⌥ + Arrow | Focus window in that direction |
| L⌥ + Shift + Arrow | Swap window in that direction |
| L⌥ + Shift + Control + Arrow | Move window to the monitor in that direction |
| Control + Tab | Focus next window on this workspace |
| Control + Shift + Tab | Focus previous window on this workspace |
| Command + Control + Tab | Focus next monitor |
| Command + Control + Shift + Tab | Focus previous monitor |

Use **R⌥ + Arrow** and **R⌥ + Shift + Arrow** for native macOS word/paragraph
movement and text selection. Press Fn + Escape when a terminal workflow needs
both Option keys for native or Meta input.

## Resize, Layout, and Window Management

| Shortcut | Action |
| --- | --- |
| L⌥ + Equal / Minus | Grow / shrink width |
| L⌥ + Shift + Equal / Minus | Grow / shrink height |
| L⌥ + J | Toggle split direction |
| L⌥ + L | Toggle tiles/accordion layout |
| L⌥ + T | Toggle floating/tiling |
| L⌥ + F | Toggle fullscreen |
| L⌥ + W | Close focused window |

Crowded workspaces automatically switch to accordion layout when the estimated
split width falls below 640 points per window.

## App Launchers

| Shortcut | Action |
| --- | --- |
| L⌥ + Return | Terminal (Ghostty → WezTerm → Terminal.app) |
| L⌥ + Shift + Return | Browser (Safari → Chrome → Firefox) |
| L⌥ + Shift + N | Editor (Zed → VS Code → TextEdit) |
| L⌥ + Shift + F | Finder |
| L⌥ + Shift + M | Music (Spotify → Music.app) |
| L⌥ + Shift + G | Communications (Slack → Messages) |
| L⌥ + Shift + / | Passwords (1Password → Keychain Access) |
| L⌥ + Space | Raycast launcher |

Raycast's own global Option-Space shortcut must be disabled so skhd is the only
owner of L⌥ + Space.

## macOS Extensions

| Shortcut | Action |
| --- | --- |
| Fn + Escape | Toggle Native Input passthrough |
| L⌥ + Shift + S | Region screenshot to clipboard |
| L⌥ + Command + Up | Mission Control |
| L⌥ + Z | Toggle SketchyBar |
| L⌥ + Shift + R | Reload AeroSpace config |
| L⌥ + Shift + C | Reload skhd config |

## Diagnostics

Secure Input can prevent AeroSpace and skhd from receiving global keyboard
events. Use a terminal for this diagnostic because a shortcut may not fire
while Secure Input is active.

```sh
./install.sh secure-input
./install.sh secure-input --watch
```
