# omarchy-macos — Spec

## Goal

Bring the [Omarchy](https://omarchy.org/) / Hyprland Linux tiling workflow to macOS M1/Apple Silicon using only native macOS tooling and Homebrew packages. The result should feel like running Hyprland on Linux, but on a Mac — same keybindings, same visual aesthetic, same muscle memory.

## Design Principles

- **Option (⌥) = SUPER.** Every shortcut mirrors Hyprland's SUPER key with ⌥ as a 1:1 substitute.
- **Vim-style navigation everywhere.** h/j/k/l for focus, movement, and resize.
- **Catppuccin Mocha color scheme.** Matches Omarchy's default theme (mauve accent for active window borders, base for the bar background).
- **Zero visual clutter.** Disable macOS window animations, uniform 8px gaps, no Dock reliance.
- **Single idempotent install script.** `./install.sh install` sets everything up from scratch; `./install.sh revert` fully undoes it and restores prior configs from backup.

## Tool Stack

| macOS Tool | Linux Equivalent | Role |
|---|---|---|
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) | Hyprland | i3-style tiling window manager |
| [skhd](https://github.com/koekeishiya/skhd) | Hyprland `bind` (app launchers) | Global hotkey daemon |
| [SketchyBar](https://github.com/FelixKratz/SketchyBar) | Waybar | Scriptable status bar |
| [JankyBorders](https://github.com/FelixKratz/JankyBorders) | Hyprland border config | Colored border on focused window |
| Raycast | walker/rofi | App launcher (⌥+Space) |

## Workspace Layout

Workspaces 1–9 with automatic app assignment:

| Workspace | App(s) |
|---|---|
| 1 | Gmail (Chrome window) |
| 2 | Messages, Signal |
| 3 | Spotify, Music |
| 4 | Ghostty, WezTerm, Warp, iTerm |
| 5 | Zed, VS Code, Antigravity |
| 6 | Claude desktop |
| 9 | Steam |

## Key Behaviors

- **Focus follows mouse** (lazy center on window focus change)
- **SketchyBar** shows active workspace highlighted in blue with open app names; inactive workspaces with apps shown in mauve; empty workspaces dimmed
- **Front app label** in bar shows `<workspace> <app name>`
- **Right-side bar** has wifi SSID, battery level with color-coded icons, and clock
- **JankyBorders** draws a 3px mauve border on the focused window, surface0 on all others
- **Normalization** flattens nested containers and corrects opposite orientations automatically

## Installer Behavior

- Backs up all existing configs (aerospace, skhd, sketchybar, borders) before writing
- Writes all config files inline from the script (no external dotfiles repo required)
- Disables macOS window animations (`NSAutomaticWindowAnimationsEnabled`, `NSWindowResizeTime`)
- Starts all four services via `brew services`
- Leaves an install marker at `~/.omarchy-macos-backup/.installed` to prevent duplicate installs
- `revert` stops services, removes configs, restores backups, uninstalls packages

## Out of Scope (not implemented)

- Slack/Discord workspace assignment (commented out, intentionally left for user to enable)
- Direct skhd trigger for Raycast (user configures ⌥+Space in Raycast settings instead)
- Multi-monitor workspace movement beyond left/right (`alt-ctrl-shift-h/l`)
