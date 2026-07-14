# omarchy-macos — Spec

## Goal

Bring the [Omarchy](https://omarchy.org/) / Hyprland Linux tiling workflow to macOS M1/Apple Silicon using only native macOS tooling and Homebrew packages. The result should feel like running Hyprland on Linux, but on a Mac — same keybindings, same visual aesthetic, same muscle memory.

## Design Principles

- **Option (⌥) = SUPER.** Every shortcut mirrors Hyprland's SUPER key with ⌥ as a 1:1 substitute.
- **Vim-style navigation everywhere.** h/j/k/l for focus, movement, and resize.
- **Catppuccin Mocha color scheme.** Matches Omarchy's default theme (mauve accent for optional active window borders, base for the bar background).
- **Zero visual clutter.** Disable macOS window animations, uniform 8px gaps, no Dock reliance.
- **Single idempotent command wrapper.** `./omarchy.sh install` sets everything
  up from scratch; `./omarchy.sh revert` fully undoes it and restores prior
  configs from backup. `./install.sh` remains as a compatibility entry point
  and takes no action when run without a subcommand.
- **The spec is the contract.** Changes to workspace assignment, startup
  restore, automatic save behavior, live state files, keybindings, or service
  startup must be checked against this spec before implementation. If behavior
  changes, `SPEC.md` must be updated in the same change.

## Change Discipline

- Review this spec before making fundamental changes to restore/save logic,
  workspace assignment, startup ordering, generated service files, or global
  keybindings.
- Prefer fake tests and generated-script syntax checks for validation. Do not
  run live restore/save/repair commands against the user's current window state
  unless the requested task requires it and the expected state impact is clear.
- Never let a partial startup layout overwrite a known-good saved state. Login
  and app-launch events are treated as unsafe until startup restore has either
  completed or the bounded startup guard has expired.
- Assigned workspaces are authoritative for their assigned apps. Saved window
  state may refine placement for unassigned apps, but it must not move assigned
  apps away from their canonical workspace.
- When a restore/save bug affects live state, report the exact observed cause,
  the commands that were run, the current guard-file state, and whether the
  saved baseline was changed.

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
assignments are generated from the displays attached during install/refresh:
`10`-`19` are pinned to the first external display, `20`-`29` to the second,
and `30`-`39` only when a third external display is actually attached. Missing
external slots are not forced to the built-in display. Slot-0 workspaces are
intentionally left unforced so the built-in display keeps its current visible
workspace while an external display changes spaces. After an external-slot
switch, the helper restores the previously visible workspace on the other
monitors, then returns focus to the target external monitor and centers the
mouse on that monitor so the next number-row shortcut continues resolving
against the same external slot.

Default slot-0 app assignments:

| Workspace | App(s) |
|---|---|
| 01 | Mail workspace; Gmail Chrome app windows |
| 02 (Msg) | Messages, Signal, Google Chat |
| 03 | Spotify, Music |
| 04 (Terms) | Ghostty, WezTerm, Warp, iTerm |
| 05 (Editors) | Zed, VS Code, Antigravity |
| 06 (Agents) | Claude desktop, Gemini, ChatGPT |
| 00 | Steam |
| current workspace | Apps without an explicit rule or restored saved location |

## Key Behaviors

- **Focus changes do not warp the pointer.** Browser links and buttons must
  receive clicks at the user's chosen cursor position.
- **Exact reboot restore** is snapshot-based. `./omarchy.sh save-window-state`
  captures the current AeroSpace window list, including window id, workspace,
  app name, app bundle id, and title, to
  `~/.config/aerospace/omarchy_window_state.json`. A LaunchAgent refreshes that
  single snapshot every 15 minutes and performs one best-effort save when macOS
  logs out or shuts down. On login/startup, the window-state saver creates a
  pending startup guard immediately, before window-detected events can save a
  partial app-launch layout. `startup_restore.sh` then takes over that guard,
  waits for AeroSpace, repairs detached-monitor workspaces, and replays the
  saved layout with a bounded startup retry window. Matching prefers app
  identity and title before falling back to app identity where that is
  unambiguous. Startup restore does not write a post-restore snapshot, so
  login-time app creation and rule-based placement cannot replace the
  pre-reboot state. The pending startup guard has a bounded fail-open expiry so
  automatic saves do not remain disabled forever if AeroSpace never runs the
  startup restore command. Manual saves clear incomplete-restore state after
  the user accepts the current layout.
- **Assigned apps override saved stale placement.** During restore and repair,
  canonical app assignments win over saved window state. For example, a stale
  or corrupted snapshot must not keep Gmail on `02`; Gmail belongs on `01`.
  Saved state still controls unassigned apps and ordinary app windows that do
  not have an explicit workspace contract.
- **Workspace repair** migrates windows from detached monitor-prefixed workspaces back to slot `0`, migrates visible legacy single-digit workspaces like `2` to the active monitor's slot-prefixed workspace like `12`, and repins any visible two-digit workspace that is shown on the wrong monitor.
- **SketchyBar** creates separate space items per monitor slot and scopes them
  to each SketchyBar display. Each bar shows only that monitor's workspace set;
  active workspaces are highlighted in blue, inactive workspaces with apps are
  mauve, and empty workspaces are dimmed. Workspace aliases are display-specific:
  slot `0` gets the named labels (`Mail`, `Msg`, `Music`, `Terms`, `Editors`,
  `Agents`) while external displays use numeric/app labels. SketchyBar display
  ids are resolved separately from AeroSpace monitor ids so dynamic multi-monitor
  topologies can be represented correctly.
- **Bar visibility defaults off.** SketchyBar starts hidden and toggles with `⌥ + Z`; `⌥+1-0` workspace switches and `⌥+Tab` hide it again. Press-to-peek is disabled because the modifier polling/repaint path can make SketchyBar unresponsive on multi-monitor setups.
- **Status alert indicator** temporarily shows SketchyBar with
  `Restoring windows` during startup restore, then hides the indicator and
  restores the previous bar visibility when restore completes. If restore is
  incomplete, the bar remains visible with `Restore incomplete` while automatic
  saves are blocked. After the startup grace period, the current layout is
  saved as the accepted baseline and the incomplete marker is cleared; a manual
  save or a later successful restore also clears it. When no restore is active,
  the same alert item shows `AX: ...` if Omarchy can
  observe that a component's macOS Accessibility grant is stale. The same
  diagnosis is available from `./omarchy.sh accessibility`. Because macOS does
  not expose arbitrary processes' Accessibility trust to shell scripts, the
  report uses component health signals such as Chrome rehome's
  `AXIsProcessTrusted` log and AeroSpace's ability to list windows;
  unverifiable components are reported as unknown instead of as false failures.
  The alert is normally event-driven; while an Accessibility warning is visible,
  a single temporary watcher checks every 30 seconds and exits once the warning
  clears. Clearing the status must hide all restore-status items, including
  per-monitor items like `restore_status.0`, even when AeroSpace monitor
  discovery is temporarily unavailable.
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
- **Chrome new-window rehome** uses an Accessibility-trusted LaunchAgent to
  watch ordinary Chrome window creation on the built-in monitor slot only.
  External monitor slots are left alone because those larger displays commonly
  use mixed-app spaces intentionally. On slot `0`, if the current workspace
  already contains ordinary Chrome, the new window stays there. Otherwise, it
  should move to an existing ordinary Chrome workspace on the built-in monitor
  when one exists. If no Chrome workspace exists on slot `0`, it may move to
  the first empty general-purpose workspace. Reserved/named workspaces are not
  candidates merely because they are empty: Mail/Msg/Music/Terms/Editors/
  Agents/Steam map to `01`, `02`, `03`, `04`, `05`, `06`, and `00`. After any
  decision, the updated layout is recorded.

## Installer Behavior

- Backs up all existing configs (aerospace, skhd, sketchybar, borders) before writing
- Writes all config files inline from the script (no external dotfiles repo required)
- Disables macOS window animations (`NSAutomaticWindowAnimationsEnabled`, `NSWindowResizeTime`)
- Starts the core services via `brew services`; JankyBorders is installed, configured, and started only when `OMARCHY_ENABLE_BORDERS=1`
- Keeps SketchyBar hidden by default, binds `⌥ + Z` to an explicit toggle,
  hides the bar after workspace switches, adds a temporary restore-status item
  for startup restore, and unloads the old `bar_toggle` LaunchAgent if present
- Writes a dependency-light Perl window-state helper using macOS's system Perl and `JSON::PP`; no extra package is required for saved reboot restore
- Regenerates `~/Desktop/omarchy-shortcuts.png` and runs a click-through
  desktop-level shortcut cheatsheet widget during install/refresh and via
  `./omarchy.sh shortcuts-widget`
- Loads a window-state saver LaunchAgent that saves every 15 minutes and traps launchd termination for best-effort logout/shutdown saves
- Loads an AeroSpace login LaunchAgent and the Accessibility-backed Chrome
  rehome LaunchAgent
- Writes `~/.config/aerospace/accessibility_report.sh` and wires it to a
  SketchyBar warning item for stale Accessibility permissions
- Leaves an install marker at `~/.omarchy-macos-backup/.installed` to prevent duplicate installs
- `revert` stops services, unloads the LaunchAgent, removes configs, restores backups, uninstalls packages

## Out of Scope (not implemented)

- Slack/Discord workspace assignment (commented out, intentionally left for user to enable)
- Direct skhd trigger for Raycast (user configures ⌥+Space in Raycast settings instead)
- Multi-monitor workspace movement beyond left/right (`alt-ctrl-shift-h/l`)
