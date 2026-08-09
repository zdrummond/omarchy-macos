# Omarchy Hotkey Alignment Plan

Status: Phase 1 is implemented in the repository generator and installed on
the Mac. Phases 2–5 remain roadmap items.

Upstream reference reviewed 2026-08-07:
<https://learn.omacom.io/2/the-omarchy-manual/53/hotkeys>

## Goal

Make the macOS bindings use the same physical key patterns and meanings as
current Omarchy wherever the platform allows it. Keep standard macOS
Command-Tab available. Retain non-conflicting macOS-only discovery and
diagnostic shortcuts as secondary aliases.

## Modifier translation

Omarchy uses three distinct Linux modifiers in compound chords, so treating
Option as both Super and Alt cannot produce a faithful map. Use this translation
consistently:

| Omarchy modifier | macOS key |
| --- | --- |
| Super | Left Option (`L⌥`) |
| Alt | Control (`⌃`) |
| Ctrl | Command (`⌘`) |
| Shift | Shift (`⇧`) |

Examples: Omarchy `Super+Alt+Space` becomes `L⌥+⌃+Space`, and
`Super+Ctrl+L` becomes `L⌥+⌘+L`. Right Option remains native and plain macOS
`⌘+Tab` remains untouched.

## Current high-impact mismatches

These explain most of the immediate muscle-memory breakage:

| Action | Current macOS chord | Current Omarchy pattern |
| --- | --- | --- |
| Close window | `⌥+⇧+Q` | `⌥+W` |
| Toggle tile/float | `⌥+⇧+Space` | `⌥+T` |
| Toggle split direction | `⌥+E` | `⌥+J` |
| Toggle layout | `⌥+S` | `⌥+L` |
| Workspace cycling | `⌥+Tab` means “former”; `⌥+⇧+Tab` moves monitors | `⌥+Tab` next; `⌥+⇧+Tab` previous |
| Move window to workspace | `⌥+⇧+number` does not follow | `⌥+⇧+number` moves and follows |
| Directional focus and swap | H/J/K/L | Arrow keys |
| Launch browser | `⌥+⇧+B` | `⌥+⇧+Return` |
| `⌥+P` | Full-screen screenshot | Pseudo-window mode, which has no AeroSpace equivalent |

## Option-key conflict audit

Using Option as Super is workable, but it is not transparent on macOS. A
global AeroSpace or skhd binding consumes the chord before the focused app can
use its normal meaning. The migration must therefore treat the following as
rollout gates rather than incidental conflicts.

| Risk | Severity | Affected planned bindings | Impact and required response |
| --- | --- | --- | --- |
| Native text navigation and selection | **Must preserve** | `⌥+Arrow`, `⌥+⇧+Arrow` | macOS uses Option-Left/Right for word movement, Option-Up/Down for paragraph movement in many editors, and the Shift variants to extend selection. Left Option carries the Omarchy bindings; right Option remains native everywhere. Native Input temporarily releases both sides. |
| VoiceOver modifier | **Accepted on this machine** | Every `⌥+⌃+…` chord, especially no-follow workspace movement and monitor movement | Control-Option is VoiceOver's default `VO` modifier, but VoiceOver is not used on this machine. Record that assumption in the installed profile; it is not a rollout gate here. |
| Terminal Meta/Alt input | **Must preserve** | Existing `⌥+F`, planned `⌥+B/C/L/P/T/V/W`, and any other captured Option-letter chord | Terminal emulators can send Option as Meta/Escape for shells, Emacs, Vim, tmux, and terminal TUIs. Right Option remains available for Meta input by default. `Fn+Escape` releases left Option too when a workflow needs both sides or conflicts with an Omarchy chord. |
| Accents, dead keys, and symbols | **Accepted on this machine** | Option-letter, Option-number, `⌥+=`, and `⌥+-` bindings | Globally claimed chords cannot type their alternate character. Dead-key and Option-symbol entry are not used on this machine, so this is documented but not a rollout gate. |
| App menu shortcuts | **Medium** | Particularly planned `⌥+⌘+…` and `⌥+⇧+⌘+…` chords | macOS apps already use this namespace. Examples include Option-Command-F for search, Option-Command-T for toolbars, Option-Command-C/V for Copy/Paste Style, and Option-Shift-Command-V for Paste and Match Style. A global clipboard or system binding would steal the app command. Inventory the menu bar in the daily-use apps before assigning each chord. |
| Web and document navigation | **Medium** | `⌥+Tab`, `⌥+Arrow`, `⌥+⇧+Arrow` | Safari can use Option-Tab to move through webpage controls, while Option-Arrows scroll in larger increments when focus is not in text. The planned workspace cycle and focus layer would replace those behaviors. |
| Control-arrow word navigation | **Accepted on this machine** | `⌃+Left/Right`, `⌃+⇧+Left/Right` | macOS normally uses these chords to move between native Spaces and move windows between Spaces. AeroSpace replaces that workspace workflow, so install/refresh disables symbolic hotkeys 79–82. A separate tail-position event tap rewrites Control to Option in place after skhd, without synthesizing another event. It must pass a timed canary and exits fail-open on tap failure. Native Input passes the original chords through, and revert restores the saved enabled flags. App-specific Control-arrow actions are intentionally overridden. |
| Multiple global-hotkey owners | **High operational risk** | Any chord shared by AeroSpace, skhd, Raycast, macOS Keyboard Shortcuts, or an app-level global hotkey | The winner can depend on process state, Accessibility permission, and launch order. A chord must have exactly one declared owner. Phase 1's conflict test must include generated AeroSpace and skhd bindings plus a documented manual inventory of Raycast and System Settings shortcuts. |
| Secure Input | **Reliability risk, not a mapping collision** | All global bindings | Password fields and some terminal states can prevent AeroSpace/skhd from observing shortcuts. The existing `./omarchy.sh secure-input` diagnostic remains necessary; switching modifiers does not solve this class of failure. |

References for the native behavior above:

- Apple's [Mac keyboard shortcut reference](https://support.apple.com/en-gb/102650)
  documents Option-arrow word navigation, Option-Shift-arrow selection, and
  common Option-Command application shortcuts.
- Apple's [Terminal keyboard settings](https://support.apple.com/guide/terminal/trmlkbrd/mac)
  explicitly support using Option as the Meta key.
- Apple's [VoiceOver keyboard guide](https://support.apple.com/guide/voiceover/vo2681/mac)
  defines Control-Option as the default VoiceOver modifier.
- The [AeroSpace guide](https://nikitabobko.github.io/AeroSpace/guide#binding-modes)
  exposes `alt` as a modifier and supports temporary binding modes, but its
  binding syntax does not distinguish left Option from right Option.
- The [skhd configuration reference](https://github.com/koekeishiya/skhd#configuration)
  documents hotkey passthrough, application-specific maps, and modal hotkeys;
  its [keyword reference](https://github.com/koekeishiya/skhd/issues/1)
  includes Fn and side-specific modifiers and notes Fn limitations for arrow
  and navigation keys.

### Required policy before implementation

The selected baseline uses side-specific Option ownership rather than
unconditional Option capture:

1. Preserve ordinary `⌘+Tab` and all unclaimed Option chords.
2. Left Option is Omarchy Super in every app, including terminals. Right Option
   is never claimed and retains native word/paragraph navigation and selection.
3. Preserve terminal Option/Meta input through right Option by default. Global
   bindings move out of AeroSpace's unconditional table and into skhd so left
   Option remains Omarchy Super in terminal apps. `Fn+Escape` releases left
   Option too when a terminal workflow needs both sides.
4. Add the cross-daemon Native Input escape hatch specified below before
   expanding the Option-letter layer.
5. Record VoiceOver and dead-key support as consciously unsupported by this
   machine profile, rather than prompting on every refresh.
6. Maintain a machine-readable binding manifest with owner, native/app
   conflict, fallback, and test status. Generate the configuration and shortcut
   reference from it; reject duplicate ownership during fake tests.
7. Smoke-test at least Finder, the configured browser, the configured terminal,
   Zed, Mail, Messages, Raycast, password prompts, and every enabled keyboard
   input source before making a new profile the default.

Modifier-only actions and Option-click are not inherently lost: AeroSpace and
skhd claim complete keyboard chords, not a bare Option press or mouse gesture.
That remains true unless a future low-level remapper is added; such a remapper
needs its own pass-through tests.

### Native Input escape hatch

Implement `Fn+Escape` as a toggle, not Fn as a held modifier:

- First press enters **Native Input**. Switch AeroSpace to a binding mode with
  no Omarchy shortcuts and switch skhd to a mode in which only the exit chord
  is claimed. All other keys pass through to macOS and the focused app.
- The shortcut widget or SketchyBar must show `Native Input` while the bypass
  is active. A second `Fn+Escape` returns both daemons to their normal modes
  and clears the indicator.
- Service restart, refresh, and login reset both daemons to normal mode so a
  stale bypass cannot look like broken hotkeys. The exit chord must work from
  both modes, and fake tests must verify the paired transition and reset.

skhd supports Fn as a modifier, passthrough, application-specific maps, and
modal hotkeys. AeroSpace supports modal binding tables, so skhd can own the
toggle and switch AeroSpace at mode entry/exit. This provides a reliable
one-keystroke escape hatch without a new dependency.

Holding Fn is **not** a reliable transparent bypass with this stack. AeroSpace
only exposes Command, Option, Control, and Shift as binding modifiers, and
macOS changes Fn+Arrow into Home/End/Page Up/Page Down behavior. Consequently,
`Fn+⌥+Arrow` would not reproduce native `⌥+Arrow`. A true momentary hold layer
would require an optional low-level remapper and more invasive event handling;
the toggle is the safer design.

## Phase 1 — Canonical navigation and window management

This is the highest-value muscle-memory pass and should land atomically with
updated generated-config tests, `SHORTCUTS.md`, the desktop cheatsheet, and
`SPEC.md`.

| Omarchy action | Canonical macOS chord | Plan |
| --- | --- | --- |
| Show main bindings | Not bound | AeroSpace has no shortcut-reference UI; use the always-visible desktop widget. |
| Application launcher | `⌥+Space` | Keep Raycast; make installer validation/documentation explicit. |
| Close window | `⌥+W` | Replace current `⌥+⇧+Q`; optionally keep the old chord as a temporary alias. |
| Toggle tile/float | `⌥+T` | Replace current `⌥+⇧+Space`. |
| Toggle split direction | `⌥+J` | Replace current `⌥+E`; directional focus moves to arrows. |
| Toggle tiles/scrolling | `⌥+L` | Map to AeroSpace tiles/accordion. |
| Fullscreen | `⌥+F` | Already aligned. |
| Workspace 1–4 | `⌥+1…4` | Already aligned; retain 5–0 as macOS extensions. |
| Next workspace | `⌥+Tab` | Change from “former workspace” to ordered next workspace. |
| Previous workspace | `⌥+⇧+Tab` | Change from monitor movement to ordered previous workspace. |
| Former workspace | `⌥+⌘+Tab` | Move current back-and-forth behavior here. |
| Move and follow | `⌥+⇧+1…4` | Change current no-follow behavior to follow the destination. |
| Move without following | `⌥+⇧+⌃+1…4` | Add explicit no-follow helper; retain 5–0 extensions. |
| Focus direction | Left `⌥+Arrow` | Use skhd's side-specific modifier support. Right Option remains native; Native Input provides full passthrough. |
| Swap direction | Left `⌥+⇧+Arrow` | Use skhd's side-specific modifier support. Right Option remains native; Native Input provides full passthrough. |
| Resize horizontally | `⌥+=` / `⌥+-` | Map to AeroSpace width resize steps. |
| Resize vertically | `⌥+⇧+=` / `⌥+⇧+-` | Map to AeroSpace height resize steps. |
| Move workspace to monitor | `⌥+⇧+⌃+Arrow` | Extend current left/right helper to all supported directions. |
| Cycle windows on workspace | `⌃+Tab` / `⌃+⇧+Tab` | Add a workspace-local cycle helper. |
| Cycle monitor focus | `⌘+⌃+Tab` / `⌘+⌃+⇧+Tab` | Implement with AeroSpace monitor focus. |

Before activation, add a conflict test that fails when two generated global
bindings claim the same chord and a contract test covering every Phase 1 row.

## Phase 2 — App launchers and everyday controls

Align the upstream launcher layer, using native Mac applications or documented
fallbacks:

- `⌥+Return`: terminal; already aligned.
- `⌥+⌃+Return`: tmux terminal.
- `⌥+⇧+Return`: browser; replaces current `⌥+⇧+B`.
- `⌥+⇧+⌃+B`: private browser.
- `⌥+⇧+F`: Finder; already aligned.
- `⌥+⇧+⌃+F`: Finder at the focused terminal's working directory
  when the terminal exposes it; otherwise open the home directory and report
  the limitation.
- Align music, password manager, calendar, email, AI, messenger, photos,
  Docker, writing, X, and YouTube chords to the manual, with configurable Mac
  app/web-app targets rather than hard-coded Linux applications.
- `⌥+⌘+L`: lock via the supported macOS lock-screen action.
- Add native or terminal-based activity, audio, Bluetooth, Wi-Fi, sharing, and
  capture menus where a reliable Mac equivalent exists.

The app map should be data-driven so users can override application names and
URLs without editing the generated skhd template.

## Phase 3 — Clipboard, capture, toggles, and notices

Implement only after Phase 1 is stable because these bindings interact with
macOS-reserved input and privacy permissions.

- Map `⌥+C/X/V` to universal copy/cut/paste using a reliable event-remapping
  layer; validate terminals, password fields, and Secure Input behavior.
- Map `⌥+⌘+V` to the chosen clipboard manager (Raycast is the default
  candidate).
- Align screenshot, recording, color picker, URL copy, and optional dictation
  chords using native `screencapture`, Shortcuts, or explicitly installed
  helpers.
- Implement sleep prevention, bar visibility, gap toggling, audio-output
  switching, reminders, and time/battery/weather notices with small audited
  helpers.
- Treat brightness/volume fine adjustment, Night Shift, display mirroring, and
  display power as optional hardware-specific features with capability checks.

## Phase 4 — Deliberate approximations

These Omarchy concepts do not exist directly in AeroSpace. Prototype them
behind tests and document that they are approximations:

- Scratchpad: dedicated AeroSpace workspace plus return-to-previous helper;
  it cannot be a true Hyprland overlay.
- Sticky floating: float and move a window to the current workspace on demand;
  it cannot remain compositor-sticky across every AeroSpace workspace.
- Window grouping: use accordion layout and window-cycle helpers; this does not
  reproduce Hyprland group containers or group membership.
- Full width: resize a floating window to the visible screen width or add an
  AeroSpace layout helper; exact Hyprland fullscreen states are unavailable.
- Screen zoom and monitor scaling: invoke macOS Accessibility Zoom or a vetted
  display utility, with per-machine configuration and rollback.

## Phase 5 — Application-level parity

Tmux, Ghostty, file-manager, and Neovim bindings from the manual are not global
window-manager behavior. Keep them in an optional companion dotfiles layer so
installing this project does not overwrite an existing terminal/editor setup.
Where the same application is installed on both systems, reuse upstream-style
configuration and test only the installer/merge behavior here.

## Not faithfully possible on this Mac stack

The following require a Hyprland compositor feature, an unsupported public
macOS API, or an additional input daemon. They must not be presented as exact
parity:

| Omarchy feature | macOS limitation |
| --- | --- |
| Pseudo window style | AeroSpace has no Hyprland pseudo-tiling equivalent. |
| Sticky floating across workspaces | AeroSpace cannot display one managed window simultaneously on all workspaces. |
| Hyprland window groups | AeroSpace has no equivalent group container, group lock, or indexed group members. |
| Scratchpad overlay | A dedicated workspace can imitate the workflow, but not the overlay/sticky compositor behavior. |
| Separate “fullscreen”, “full width”, and “fullscreen inside window” states | AeroSpace/macOS do not expose all three Hyprland states consistently. |
| Super+mouse drag/resize and Super+scroll workspace switching | AeroSpace and skhd do not own mouse-button/wheel gestures; this needs an optional tool such as Hammerspoon, Karabiner-Elements, or BetterTouchTool. |
| Per-window transparency and Hyprland square/pseudo styling | Not supported generically by AeroSpace or public macOS window APIs. |
| Reliable notification dismiss/invoke | macOS has no stable public API for manipulating arbitrary Notification Center items; Accessibility UI automation would be fragile. |
| Exact Linux audio/Wi-Fi/Bluetooth/hardware TUIs | Functional Mac substitutes are possible, but the Linux programs and device model are not portable. |
| Universal CapsLock XCompose sequences | Requires an additional low-level remapper and cannot be delivered reliably by AeroSpace/skhd alone. |
| Arbitrary monitor scaling/display power parity | macOS exposes less control than Hyprland; third-party utilities are hardware-specific and may break across OS updates. |

## Rollout and rollback

1. Capture the current generated bindings as a fixture and add the new
   canonical manifest/tests.
2. Implement and test terminal application pass-through plus the `Fn+Escape`
   Native Input toggle before adding more global Option-letter bindings.
3. Implement Phase 1 behind one generator change; do not mix system-control or
   clipboard dependencies into it.
4. Regenerate `SHORTCUTS.md` and the desktop cheatsheet from the same manifest
   to prevent drift.
5. Run all fake tests and `scripts/check_spec_drift.sh`.
6. Save the pre-refresh generated configs, deploy with `./omarchy.sh refresh`,
   and smoke-test every Phase 1 chord without running restore/repair.
7. Confirm native Option-arrow editing, Option-Shift-arrow selection, and
   Option/Meta terminal input before accepting the new profile.
8. Keep a one-command rollback to the previous generated bindings until the
   new map has been used for several days on both Omarchy and macOS.
