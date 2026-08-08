# Omarchy-like Project Context

## Mission

Make this Apple Silicon Mac feel like current Omarchy/Hyprland while preserving
macOS reliability. The priority is transferable muscle memory: Omarchy's
current behavior and hotkeys should be canonical when macOS can support them.
Platform adaptations must be deliberate, documented, and tested.

The project is named `omarchy_like`; its user-facing name is currently
`omarchy-macos` in scripts and documentation.

## Sources of truth

Use these in order:

1. `SPEC.md` — behavioral contract and invariants.
2. Generated behavior in `install.sh`, covered by fake/source tests.
3. `SHORTCUTS.md` — user-facing installed key map.
4. `README.md` — installation, operation, and troubleshooting.
5. `OMARCHY_HOTKEY_ALIGNMENT.md` — migration plan toward current upstream
   Omarchy hotkeys; it is a roadmap, not installed behavior.

For Omarchy compatibility work, compare against the current upstream manual,
not remembered bindings:

- <https://learn.omacom.io/2/the-omarchy-manual/53/hotkeys>
- Markdown representation:
  <https://learn.omacom.io/2/the-omarchy-manual/53/hotkeys.md>

## Architecture

- `omarchy.sh` is the stable command entry point and delegates to `install.sh`.
- `install.sh` generates AeroSpace, skhd, SketchyBar, LaunchAgent, helper,
  widget, and optional border configuration. Edit the generator, never only a
  generated file in the home directory.
- AeroSpace owns tiling, focus, workspace placement, and most window bindings.
- skhd owns global app launchers and macOS commands that AeroSpace does not.
- SketchyBar owns the per-monitor workspace UI and status indicators.
- `SPEC.md` defines workspace naming, assignment, restore/save guards,
  focus/launch behavior, and service lifecycle.
- `tests/*_fake.sh` extract generated scripts/configuration and test them using
  fake binaries and state. They are preferred over destructive live tests.
- `scripts/check_spec_drift.sh` enforces that behavioral diffs update the spec.

## Important invariants

- Option (`⌥`) is the macOS stand-in for Omarchy's Super modifier.
- Workspaces are two digits: `<monitor-slot><key>`. Slot `0` is the built-in
  display; attached external displays use slots `1` through `3`.
- Assigned apps belong in their canonical named workspace, but automatic
  placement must not steal focus.
- Unassigned apps must not pollute named workspaces. Launch-time rehome and its
  follow/return behavior are guarded and logged.
- Startup restore must never allow a partial login layout to overwrite a
  known-good snapshot.
- Focus changes must not warp the pointer.
- The bar is hidden by default and must remain responsive across topology
  changes and restore warnings.
- Preserve standard macOS Command-Tab as an app switcher unless the behavioral
  contract is explicitly changed.

## Safe working workflow

1. Read the relevant contract and inspect `git status --short`.
2. Diagnose with repository sources, rotating logs, and read-only queries.
3. Update `SPEC.md` in the same change when contract behavior changes.
4. Update generated-source tests and user-facing shortcut docs as applicable.
5. Run `bash -n install.sh`, the relevant fake tests, then the full fake suite
   for broad behavior changes.
6. Run `scripts/check_spec_drift.sh` before committing behavior changes.
7. Deploy only when requested or clearly part of the task with
   `./omarchy.sh refresh`; do not run live restore/save/repair casually.

Useful non-mutating diagnostics:

```bash
./omarchy.sh status
./omarchy.sh accessibility
./omarchy.sh secure-input
tail -n 200 /tmp/omarchy_window_state.log
```

Run all fake tests:

```bash
for test_script in tests/*_fake.sh; do bash "$test_script" || exit 1; done
```

## Definition of done

A behavioral change is complete only when the generator, spec, relevant fake
tests, user-facing docs, and deployed configuration (when requested) agree.
Report what was tested, whether live state was touched, and whether the saved
window-state baseline changed.
