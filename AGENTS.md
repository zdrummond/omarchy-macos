# Agent Instructions

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

Before committing behavior changes, run:

```bash
scripts/check_spec_drift.sh
```

