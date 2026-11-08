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

## Task tracking

Track work in GitHub Issues on `zdrummond/omarchy-macos` using the `gh` CLI.
Do not use beads (`bd`), TODO files, or Markdown checklists in the repo. Beads
was retired on 2026-11-08 and its open issues were moved to GitHub.

- At session start, run `gh issue list` to see open work. Read the relevant
  issue with `gh issue view <n>` before starting on it.
- Open an issue before starting non-trivial work, and for any bug or
  follow-up found along the way that is not fixed in the same change. Use the
  `bug` or `enhancement` label. Include the observed behavior, the cause if
  known (with evidence from the diagnostics log), and acceptance criteria.
- Record progress, deployment, and live-verification results as issue
  comments. A fix is not done until its live behavior is verified, so
  record that verification on the issue.
- Reference the issue in commits (`Fixes #<n>` when the commit completes it).
  The issue closes when that commit reaches `main` on GitHub. Close an issue
  by hand with a short reason only when no commit finishes it.
- The repository is public. Keep personal details out of issues: no names,
  message or window titles, email addresses, or account details copied from
  the live window list or logs.
