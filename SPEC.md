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

Workspaces 1–10 with automatic app assignment:

| Workspace | App(s) |
|---|---|
| 1 | Gmail (Chrome window) |
| 2 (Msg) | Messages, Signal |
| 3 | Spotify, Music |
| 4 (Terms) | Ghostty, WezTerm, Warp, iTerm |
| 5 (Editors) | Zed, VS Code, Antigravity |
| 6 (Agents) | Claude desktop, Gemini |
| 9 | Steam |

## Key Behaviors

- **Focus follows mouse** (lazy center on window focus change)
- **SketchyBar** shows active workspace highlighted in blue with open app names; inactive workspaces with apps shown in mauve; empty workspaces dimmed
- **Bar visibility is press-to-peek.** SketchyBar starts hidden and only appears while Option (⌥) is held for ≥150ms — mirroring Hyprland's "bar on SUPER" feel and keeping the screen chrome-free the rest of the time.
- **Front app label** in bar shows `<workspace> <app name>`
- **Right-side bar** has wifi SSID, battery level with color-coded icons, and clock
- **JankyBorders** draws a 3px mauve border on the focused window, surface0 on all others
- **Normalization** flattens nested containers and corrects opposite orientations automatically

## Bar Toggle Daemon (`bar_toggle`)

A tiny Swift binary compiled at install time and loaded as a LaunchAgent. It exists to solve two problems that can't be handled in SketchyBar or aerospace config alone:

1. **Press-to-peek visibility.** Neither SketchyBar nor skhd can react to a modifier being held. The daemon polls `CGEventSource.flagsState` every 50ms, and after Option has been held for 150ms it runs `sketchybar --bar hidden=off`. On release it immediately hides the bar again. The 150ms debounce keeps the bar from flashing during quick `⌥+key` combos (e.g. `⌥+1` to switch workspace).
2. **Stale-highlight workaround.** SketchyBar has a known quirk where `--set` against a hidden item updates its data model but never repaints its background/border — so by the time the bar un-hides, the "focused space" highlight is whatever it was the last time the bar was visible. To force a fresh repaint, the daemon fires `sketchybar --trigger front_app_switched` right after un-hiding. The `front_app` plugin re-runs while the bar is actually visible, calls `highlight_space` with the current aerospace workspace, and the drawing-toggle workaround in `spaces.sh` then paints correctly.

The daemon is implemented in Swift (not Python) so it has zero runtime dependencies beyond Xcode Command Line Tools, which are already a Homebrew prerequisite. Source lives at `~/.config/sketchybar/plugins/bar_toggle.swift`; the compiled binary at `~/.config/sketchybar/plugins/bar_toggle`; the LaunchAgent at `~/Library/LaunchAgents/com.omarchy-macos.bar_toggle.plist`.

## Installer Behavior

- Backs up all existing configs (aerospace, skhd, sketchybar, borders) before writing
- Writes all config files inline from the script (no external dotfiles repo required)
- Disables macOS window animations (`NSAutomaticWindowAnimationsEnabled`, `NSWindowResizeTime`)
- Starts all four services via `brew services`
- Compiles the `bar_toggle` Swift daemon via `swiftc` and loads it as a LaunchAgent
- Leaves an install marker at `~/.omarchy-macos-backup/.installed` to prevent duplicate installs
- `revert` stops services, unloads the LaunchAgent, removes configs, restores backups, uninstalls packages

## Out of Scope (not implemented)

- Slack/Discord workspace assignment (commented out, intentionally left for user to enable)
- Direct skhd trigger for Raycast (user configures ⌥+Space in Raycast settings instead)
- Multi-monitor workspace movement beyond left/right (`alt-ctrl-shift-h/l`)
