# omarchy-macos — Spec

## Goal

Bring the [Omarchy](https://omarchy.org/) / Hyprland Linux tiling workflow to macOS M1/Apple Silicon using only native macOS tooling and Homebrew packages. The result should feel like running Hyprland on Linux, but on a Mac — same keybindings, same visual aesthetic, same muscle memory.

## Design Principles

- **Option (⌥) = SUPER.** Every shortcut mirrors Hyprland's SUPER key with ⌥ as a 1:1 substitute.
- **Vim-style navigation everywhere.** h/j/k/l for focus, movement, and resize.
- **Catppuccin Mocha color scheme.** Matches Omarchy's default theme (mauve accent for optional active window borders, base for the bar background).
- **Zero visual clutter.** Disable macOS window animations, uniform 8px gaps, no Dock reliance.
- **Single idempotent install script.** `./install.sh install` sets everything up from scratch; `./install.sh revert` fully undoes it and restores prior configs from backup.

## Tool Stack

| macOS Tool | Linux Equivalent | Role |
|---|---|---|
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) | Hyprland | i3-style tiling window manager |
| [skhd](https://github.com/koekeishiya/skhd) | Hyprland `bind` (app launchers) | Global hotkey daemon |
| [SketchyBar](https://github.com/FelixKratz/SketchyBar) | Waybar | Scriptable status bar |
| [JankyBorders](https://github.com/FelixKratz/JankyBorders) | Hyprland border config | Optional colored border on focused window |
| Raycast | walker/rofi | App launcher (⌥+Space) |

## Workspace Layout

Workspaces are monitor-scoped. Workspace names are two digits: `<monitor-slot><key>`.
The built-in display is slot `0` when present; external displays follow in AeroSpace's
monitor order. The number-row shortcuts resolve against the monitor under the
mouse, falling back to AeroSpace's focused monitor only when the mouse monitor
cannot be read. So `⌥+3` with the pointer on the built-in display goes to `03`,
while `⌥+3` with the pointer on the first external display goes to `13`. The `0`
key is the tenth workspace, so it maps to `00`, `10`, etc. AeroSpace force
assignments pin `10`-`39` to up to three external displays, so external-display
workspaces follow the attached monitor slots instead of depending on specific
monitor names. Slot-0 workspaces are intentionally left unforced so the built-in
display keeps its current visible workspace while an external display changes
spaces. After an external-slot switch, the helper restores the previously visible
workspace on the other monitors, then returns focus to the target external
monitor and centers the mouse on that monitor so the next number-row shortcut
continues resolving against the same external slot.

Default slot-0 app assignments:

| Workspace | App(s) |
|---|---|
| 01 | Mail workspace; Gmail Chrome app windows are not force-managed |
| 02 (Msg) | Messages, Signal |
| 03 | Spotify, Music |
| 04 (Terms) | Ghostty, WezTerm, Warp, iTerm |
| 05 (Editors) | Zed, VS Code, Antigravity |
| 06 (Agents) | Claude desktop, Gemini, ChatGPT |
| 00 | Steam |
| current workspace | Apps without an explicit rule or restored saved location |

## Key Behaviors

- **Focus changes do not warp the pointer.** Browser links and buttons must
  receive clicks at the user's chosen cursor position.
- **Exact reboot restore** is snapshot-based. `./install.sh save-window-state` captures the current AeroSpace window list, including window id, workspace, app name, app bundle id, and title, to `~/.config/aerospace/omarchy_window_state.json`. A LaunchAgent refreshes that snapshot every 15 minutes and performs one best-effort save when macOS logs out or shuts down. App-assigned windows are canonicalized to their declared workspaces before save/restore so temporary drift cannot become reboot state. On login/startup, `startup_restore.sh` blocks autosaves before its first repair pass, waits for AeroSpace, repairs detached-monitor workspaces, then retries matching restored windows by window id + app identity, app bundle id + title, app name + title, and app identity for canonical app-assigned windows before moving them back to their saved workspaces. Autosaves resume after startup restore finishes.
- **Workspace repair** migrates windows from detached monitor-prefixed workspaces back to slot `0`, migrates visible legacy single-digit workspaces like `2` to the active monitor's slot-prefixed workspace like `12`, and repins any visible two-digit workspace that is shown on the wrong monitor.
- **SketchyBar** creates separate space items per monitor slot and scopes them to each SketchyBar display. Each bar shows only that monitor's workspace set; active workspaces are highlighted in blue, inactive workspaces with apps are mauve, and empty workspaces are dimmed.
- **Bar visibility defaults off.** SketchyBar starts hidden and toggles with `⌥ + Z`; `⌥+1-0` workspace switches and `⌥+Tab` hide it again. Press-to-peek is disabled because the modifier polling/repaint path can make SketchyBar unresponsive on multi-monitor setups.
- **Window discovery** includes `⌥+Up` for a readable all-window picker,
  `⌥+Shift+Up` for Mission Control / expose, plus `⌥+Ctrl+Tab` and
  `⌥+Ctrl+Shift+Tab` to cycle through every AeroSpace-managed window across
  workspaces.
- **Unassigned windows stay where they open** so browser popups, compose
  windows, and transient dialogs are not moved by a global catch-all rule.
- **1Password dialogs** are floated so authentication prompts stay usable on
  the current workspace.
- **Front app label** in bar shows `<workspace> <app name>`
- **Right-side bar** has wifi SSID, battery level with color-coded icons, and clock
- **Optional JankyBorders** draws a 3px mauve border on the focused window, surface0 on all others when `OMARCHY_ENABLE_BORDERS=1` is set during install/refresh
- **Normalization** flattens nested containers and corrects opposite orientations automatically
- **Responsive layout guard** changes a crowded focused workspace to AeroSpace
  accordion layout when the estimated split width would fall below 640 points
  per window. This keeps laptop-width displays usable once a workspace grows
  beyond two or three tiled windows.
- **Chrome new-window state save** watches Chrome window creation and records
  the updated layout without moving the window.

## Installer Behavior

- Backs up all existing configs (aerospace, skhd, sketchybar, borders) before writing
- Writes all config files inline from the script (no external dotfiles repo required)
- Disables macOS window animations (`NSAutomaticWindowAnimationsEnabled`, `NSWindowResizeTime`)
- Starts the core services via `brew services`; JankyBorders is installed, configured, and started only when `OMARCHY_ENABLE_BORDERS=1`
- Keeps SketchyBar hidden by default, binds `⌥ + Z` to an explicit toggle, hides the bar after workspace switches, and unloads the old `bar_toggle` LaunchAgent if present
- Writes a dependency-light Perl window-state helper using macOS's system Perl and `JSON::PP`; no extra package is required for saved reboot restore
- Regenerates `~/Desktop/omarchy-shortcuts.png` and runs a click-through
  desktop-level shortcut cheatsheet widget during install/refresh and via
  `./install.sh shortcuts-widget`
- Loads a window-state saver LaunchAgent that saves every 15 minutes and traps launchd termination for best-effort logout/shutdown saves
- Loads an AeroSpace login LaunchAgent and a Chrome rehome LaunchAgent
- Leaves an install marker at `~/.omarchy-macos-backup/.installed` to prevent duplicate installs
- `revert` stops services, unloads the LaunchAgent, removes configs, restores backups, uninstalls packages

## Out of Scope (not implemented)

- Slack/Discord workspace assignment (commented out, intentionally left for user to enable)
- Direct skhd trigger for Raycast (user configures ⌥+Space in Raycast settings instead)
- Multi-monitor workspace movement beyond left/right (`alt-ctrl-shift-h/l`)
