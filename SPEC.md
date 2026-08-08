# omarchy-macos — Spec

## Goal

Bring the [Omarchy](https://omarchy.org/) / Hyprland Linux tiling workflow to macOS M1/Apple Silicon using only native macOS tooling and Homebrew packages. The result should feel like running Hyprland on Linux, but on a Mac — same keybindings, same visual aesthetic, same muscle memory.

## Design Principles

- **Left Option (⌥) = SUPER.** Left Option mirrors Hyprland's SUPER key;
  right Option remains native macOS input. Configured terminal apps receive
  both Option keys unchanged so Option/Meta input keeps working.
- **Current Omarchy navigation where macOS permits it.** Left Option plus arrow
  keys controls window focus/movement; right Option plus arrow keys retains
  native macOS text navigation and selection.
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
- Generated AeroSpace app-assignment rules and skhd move-window keybindings are
  part of the contract and must have fake/source tests that fail if an assigned
  app stops moving to its canonical workspace or `Left ⌥+Shift+<number>` stops
  invoking the workspace move-and-follow helper.
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
| 01 | Mail workspace; Apple Mail and Gmail Chrome app windows launch here by bundle id; both Mail and Gmail are treated as assigned apps for repair and bar labels |
| 02 (Msg) | Messages, Signal, Google Chat |
| 03 | Spotify, Music |
| 04 (Terms) | Ghostty, WezTerm, Warp, iTerm |
| 05 (Editors) | Zed, VS Code, Antigravity |
| 06 (Agents) | Claude desktop, Gemini, ChatGPT |
| unnamed workspace | Apps without an explicit rule or restored saved location |
| 00 | Unnamed fallback workspace |

Workspace `02` is reserved for messaging. During startup repair and restore,
unassigned windows found on or saved to `02` are moved to `08` so a corrupted
snapshot or login-time app launch cannot crowd the message workspace.

## Key Behaviors

- **Hotkey compatibility profile.** skhd owns the user-facing global hotkeys so
  bindings can distinguish left from right Option and pass through per app.
  Left Option is Omarchy Super in normal GUI apps. Right Option is never claimed
  by Omarchy and retains native macOS text navigation. Ghostty, WezTerm, Warp,
  iTerm2, and Terminal receive both Option keys unchanged, so overlapping
  Omarchy actions do not fire while those apps are focused. Native
  Option-arrow movement and Option-Shift-arrow selection therefore remain
  available everywhere: through right Option in GUI apps and either Option in
  configured terminals. Standard Command-Tab remains the macOS app switcher.
- **Native Input escape hatch.** `Fn+Escape` toggles a cross-daemon Native Input
  mode. While active, skhd claims only the exit chord and AeroSpace uses an
  empty binding mode, so all other shortcuts pass through to macOS and the
  focused app. SketchyBar becomes visible with a `Native Input` indicator and
  restores its previous visibility when the mode exits, except that active or
  incomplete restore warnings keep the bar visible. Login, install/refresh,
  and service restart reset the mode to normal.
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
  unambiguous. Legacy single-digit saved workspaces are normalized back to slot
  `0` two-digit workspaces before replay, so saved workspace `1` restores to
  `01` instead of recreating a legacy `1` workspace. Startup restore refreshes
  SketchyBar space labels after moving windows and does not write a
  post-restore snapshot, so login-time app creation and rule-based placement
  cannot replace the pre-reboot state. The pending startup guard has a bounded
  fail-open expiry so
  automatic saves do not remain disabled forever if AeroSpace never runs the
  startup restore command; when that pending guard expires, stale restore-status
  UI is cleared as well. The default incomplete-restore cleanup grace is 120
  seconds and is measured from the start of `startup_restore.sh`, not from the
  end of all restore and repair retries, so the warning does not linger after a
  long startup pass. Manual saves clear incomplete-restore state after the user
  accepts the current layout.
- **Named workspace ownership overrides saved stale placement.** During restore
  and repair, canonical app assignments win over saved window state. For
  example, a stale or corrupted snapshot must not keep Gmail on `02`; Gmail
  belongs on `01`. Unassigned apps are not allowed to remain in any named
  workspace (`01`-`06` by default), including when legacy workspace `1` is
  normalized to `01`. After restore they move to the nearest empty unnamed
  workspace on the same monitor slot, with ties preferring the lower key and
  key `0` as the fallback. The reserved message workspace `02` keeps its
  explicit `08` fallback. Saved state continues to control unassigned apps in
  unnamed workspaces.
- **Workspace repair** migrates windows from detached monitor-prefixed workspaces back to slot `0`, migrates visible legacy single-digit workspaces like `2` to the active monitor's slot-prefixed workspace like `12`, and repins any visible two-digit workspace that is shown on the wrong monitor.
- **SketchyBar** creates separate space items per monitor slot and scopes them
  to each SketchyBar display. Each bar shows only that monitor's workspace set;
  active workspaces are highlighted in blue, inactive workspaces with apps are
  mauve, and empty workspaces are dimmed. Workspace aliases are display-specific:
  slot `0` gets the named labels (`Mail`, `Msg`, `Music`, `Terms`, `Editors`,
  `Agents`) while external displays use numeric/app labels. If a named workspace
  contains only apps that are not assigned to that workspace, the label shows the
  actual app names instead of the alias so unexpected placement is visible.
  SketchyBar display ids are resolved separately from AeroSpace monitor ids so
  dynamic multi-monitor topologies can be represented correctly. Configuration
  builds are serialized, only the configuration build creates space items, and
  every completed build explicitly restores number-row order (`1` through `0`)
  so login-time highlights and topology reloads cannot rotate the bar.
- **Bar visibility defaults off.** SketchyBar starts hidden and toggles with
  `Left ⌥+Z`; workspace switches hide it again except while Native Input or a
  restore warning requires visible status. Press-to-peek is disabled because
  the modifier polling/repaint path can make SketchyBar unresponsive on
  multi-monitor setups.
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
  report uses component health signals such as AeroSpace's ability to list
  windows; unverifiable components are reported as unknown instead of as false
  failures.
  The alert is normally event-driven; while an Accessibility warning is visible,
  a single temporary watcher checks every 30 seconds and exits once the warning
  clears. Clearing the status must hide all restore-status items, including
  per-monitor items like `restore_status.0`, even when AeroSpace monitor
  discovery is temporarily unavailable, and it must remove or clear stale
  status labels and backgrounds rather than only toggling item drawing off.
  Restore-status and space-label updates are bounded: a hung AeroSpace or
  SketchyBar query may skip that UI update, but it cannot block restore cleanup
  or prevent the incomplete marker's expiry worker from being scheduled.
  Restarting the window-state saver during `refresh` is not a login/startup
  restore: the refresh path suppresses that restart's one-shot pending startup
  guard, so it must not show `Restoring windows` or block automatic saves.
- **Window discovery** includes `Left ⌥+K` for the shortcut reference,
  `Left ⌥+Command+Up` for Mission Control / expose, plus `Ctrl+Tab` and
  `Ctrl+Shift+Tab` to cycle windows on the focused workspace.
- **Launch rehome protects named spaces.** A named workspace is any workspace
  with an explicit category assignment/alias such as Mail, Msg, Music, Terms,
  Editors, or Agents. Space key `0` is unnamed and is reserved as the fallback
  destination. Apps assigned to a named category belong in that category's
  slot-0 workspace and are moved there when they open elsewhere. Unassigned apps
  that open in an unnamed workspace stay where they opened. Unassigned apps that
  open in a named workspace are moved to the nearest empty unnamed workspace on
  the same monitor slot, excluding key `0` from the normal candidate set and
  ignoring the newly launched window itself for emptiness. "Nearest" is measured
  by number-row key distance from the launch workspace key; ties prefer the
  lower key. If no unnamed non-`0` workspace is empty, the app moves to that
  monitor slot's key `0` workspace (`00`, `10`, etc.). Restore/repair guards
  suppress this catch-all so startup restore can replay saved layout without
  being overwritten. After replay, the same named-workspace ownership rule is
  applied once so stale snapshots cannot repopulate named spaces. Apple TV is
  unassigned; it must not be treated as a Music workspace app. After a
  successful launch-time rehome, the save and responsive-layout checks finish,
  then a short bounded settle delay allows launch-time activation events to
  drain before AeroSpace switches to the destination workspace and focuses the
  rehomed window. The newly created window must remain in view rather than
  being pulled back to its source workspace by a late application event. A
  bounded watcher tracks each automatically followed window. If that window
  closes while its destination remains focused and has become empty, and its
  source workspace still contains windows, Omarchy returns to the source
  workspace. It does nothing if the user has navigated elsewhere or another
  window remains at the destination.
- **1Password dialogs** are floated so authentication prompts stay usable on
  the current workspace.
- **Front app label** in bar shows `<workspace> <app name>`
- **Right-side bar** has wifi SSID, battery level with color-coded icons, and clock
- **Optional JankyBorders** draws a 3px mauve border on the focused window, surface0 on all others when `OMARCHY_ENABLE_BORDERS=1` is set during install/refresh
- **Normalization** flattens nested containers and corrects opposite orientations automatically
- **Responsive layout guard** changes a crowded workspace to AeroSpace
  accordion layout when the estimated split width would fall below 640 points
  per window. This keeps laptop-width displays usable once a workspace grows
  beyond two or three tiled windows. For newly detected windows, assignment or
  unassigned-window rehome completes first; the guard then resolves the
  detected window's final workspace and applies layout directly to that window
  id. It must not accordion the temporary source workspace before moving the
  new window away.
- **Unassigned rehome records layout changes.** After launch-time catch-all
  movement, the updated layout is recorded and responsive layout is rechecked.
- **Automatic app placement never steals focus.** Window-detected assignment
  rules move assigned apps to their canonical workspace without activating that
  workspace. Each assigned-window callback records the detected window id,
  source and target workspaces, app identity/title, and focused window before
  and after the move. Every focused-workspace change also records its previous
  and new workspace and the resulting focused window, so an unsolicited focus
  change can be correlated and attributed without reproducing it. Omarchy's
  shared window-state diagnostic log rotates daily and retains only the current
  log plus one previous-day archive; installing this policy drops older legacy
  entries.

## Installer Behavior

- Backs up all existing configs (aerospace, skhd, sketchybar, borders) before writing
- Writes all config files inline from the script (no external dotfiles repo required)
- Disables macOS window animations (`NSAutomaticWindowAnimationsEnabled`, `NSWindowResizeTime`)
- Starts the core services via `brew services`; JankyBorders is installed, configured, and started only when `OMARCHY_ENABLE_BORDERS=1`
- Keeps SketchyBar hidden by default, binds `Left ⌥+Z` to an explicit toggle,
  hides the bar after workspace switches, adds a temporary restore-status item
  for startup restore, and unloads the old `bar_toggle` LaunchAgent if present
- Writes a dependency-light Perl window-state helper using macOS's system Perl and `JSON::PP`; no extra package is required for saved reboot restore
- Regenerates `~/Desktop/omarchy-shortcuts.png` and runs a click-through
  desktop-level shortcut cheatsheet widget during install/refresh and via
  `./omarchy.sh shortcuts-widget`. The widget LaunchAgent starts the app through
  LaunchServices so AppKit can create a window, waits for that app, records its
  child pid for exact cleanup, logs launch/render failures, and redraws after
  display changes.
- Loads a window-state saver LaunchAgent that saves every 15 minutes, traps
  launchd termination for best-effort logout/shutdown saves, and rotates its
  shared diagnostic log daily with one prior-day archive
- Loads an AeroSpace login LaunchAgent. Launch-time rehome is handled by
  AeroSpace window-detected callbacks, not a Chrome-specific Accessibility
  daemon.
- Writes `~/.config/aerospace/accessibility_report.sh` and wires it to a
  SketchyBar warning item for stale Accessibility permissions
- Writes the Native Input mode helper, resets that mode during service startup,
  and generates exactly one owner for each global binding
- Leaves an install marker at `~/.omarchy-macos-backup/.installed` to prevent duplicate installs
- `revert` stops services, unloads the LaunchAgent, removes configs, restores backups, uninstalls packages

## Out of Scope (not implemented)

- Slack/Discord workspace assignment (commented out, intentionally left for user to enable)
