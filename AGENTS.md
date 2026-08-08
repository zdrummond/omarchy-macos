# Agent Instructions

This is a long-lived project. A resumed Codex thread may be about a narrow bug
and is not the project brief. At the start of every Codex session in this repo,
before planning or editing:

1. Read `PROJECT_CONTEXT.md` for the mission, architecture, workflow, and repo
   map.
2. Read `SPEC.md`; it is the behavioral contract and overrides summaries in
   other documentation.
3. Read `SHORTCUTS.md` for any input/keybinding task and `README.md` for any
   user-facing install or operation task.
4. Run `git status --short` and preserve all existing changes. Treat a dirty
   worktree as user-owned unless the current task clearly created the change.
5. Reconcile the current request with the repository and its recent history;
   do not assume the resumed conversation describes the latest implementation.

## Behavioral contract

`SPEC.md` is the behavioral contract for this repository.

Before changing any of the following, read `SPEC.md` first:

- workspace assignment or workspace naming
- startup restore, window-state save/restore, restore guards, or saved-state files
- generated AeroSpace, skhd, SketchyBar, LaunchAgent, or Accessibility helper behavior
- global keybindings
- install/refresh/revert behavior

When a change affects behavior described by the spec, update `SPEC.md` in the
same change. If the implementation changes but the spec does not, explicitly
state why the spec remains correct.

Prefer fake tests and generated-script syntax checks over live restore/save
commands. Do not run live restore/save/repair commands against the user's
current window state unless the requested task requires it and the expected
state impact is clear.

Generated files under `~/.config`, `~/Library/LaunchAgents`, and related live
locations are outputs, not source. Make durable changes in this repository's
generators (primarily `install.sh`), test them here, then use
`./omarchy.sh refresh` only when the task calls for deployment.

When investigating focus, workspace, restore, or launch-placement bugs, inspect
the rotating diagnostics at `/tmp/omarchy_window_state.log` and
`/tmp/omarchy_window_state.log.1` before changing behavior. Prefer read-only
AeroSpace queries and fake tests over manipulating the live window layout.

Before committing behavior changes, run:

```bash
scripts/check_spec_drift.sh
```
