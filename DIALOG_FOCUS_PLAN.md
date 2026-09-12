# Dialog and focus protection plan

Status: planned; broader dialog protection is not implemented.

Branch: `codex/dialog-focus-protection`.
Baseline: `9127d14` — the existing Touch ID exception, rapid workspace-change
diagnostics, documentation, and regression tests. This plan builds on that
commit. `SPEC.md` remains the contract for currently implemented behavior.

## Problem and evidence

The September 12, 2026 diagnostics show three different situations:

- Touch ID was retained on its launch workspace at 15:09:23. The narrow
  authentication exception is deployed and working for that observation.
- iTerm's Software Update windows were moved from workspace 02 to 04 at
  15:18:14 and 15:18:40. Focus subsequently switched to the relocated dialogs.
  The assignment helper did not explicitly activate their destination, but
  moving an active dialog can still be followed by application activation.
- System Settings was moved and explicitly followed from 04 to 09 at
  15:21:43. Closing it was followed by a 04-to-09 bounce and a failed return.
  This was an ordinary System Settings window, so dialog classification alone
  must not be presented as a complete fix for that sequence.

Other rapid transitions between existing app windows have no recorded move.
The current logs cannot distinguish user shortcuts, application activation,
and every possible focus-changing command. Temporal correlation is evidence
to investigate, not proof of the initiating actor.

## Intended behavior

Automatic assignment and rehome apply only to positively identified ordinary
windows. Dialogs stay where they appear. Native sheets retain their attachment;
standalone dialogs may be floated without moving or activating a workspace.
An ordinary owner window with an active sheet is temporarily protected too.
Explicit user move/focus commands remain available.

Classification has three outcomes: ordinary, protected, and unknown. Missing
permissions, incomplete metadata, ambiguous identity, timeouts, and vanished
windows must not silently become ordinary. For unknown windows, skip automatic
movement and forced layout and record the reason. A bounded retry may classify
a newly initializing window, but it must not cause a surprise delayed move
after the user begins interacting with it. Do not add an indefinite retry loop.

## Implementation sequence

### 1. Prove a read-only classifier and its identity mapping

Build a small metadata adapter with structured results: window identity,
process identity, role, subrole, modal state, owner/sheet relationship,
classification, and reason. Separate metadata acquisition from classification
so synthetic fixtures can test the policy without interacting with the desktop.

Use Accessibility role/subrole and modal/sheet signals, retaining the existing
Touch ID exception. Floating layout, small size, app name, or a dialog-like
title alone is not sufficient evidence. Browser popups sometimes expose the
same role as normal browser windows; describe unsupported cases explicitly.

First establish how the installed AeroSpace version can supply supported
metadata. Its `debug-windows --window-id` output is useful for investigating
examples, but is explicitly not a stable API and must not become a production
parser. If a separate Accessibility helper is required, verify its actual
permission context and a reliable join between AeroSpace window IDs and AX
elements. Do not match by title alone or select an arbitrary same-app window.
Ambiguous joins return unknown. Document any unavoidable private API before
depending on it.

Bound metadata calls and total inspection time. Key any short-lived cache by
window and process lifetime; invalidate on destruction, restart, and metadata
changes. Do not persist decisions keyed only by recyclable window IDs.

Completion: fixtures distinguish ordinary windows, modal windows, sheets,
owners with sheets, and unknowns; read-only sampling on this Mac validates the
adapter and any required permission without moving windows.

### 2. Apply protection at every automatic mutation boundary

Update generators in `install.sh`, not only installed outputs:

- `assigned_window_rehome.sh`: inspect before canonical app assignment.
- `unassigned_window_rehome.sh`: inspect before choosing a destination or
  scheduling move/follow/return behavior.
- `responsive_layout.sh`: do not force protected windows into tiling, and
  exclude dialogs from the count that triggers a layout change.
- `omarchy_repair_app_assigned_workspaces`: preserve the exception during
  post-restore ownership repair.
- Detached-monitor/legacy-workspace repair: inspect all window-moving paths;
  owner-attached UI must travel consistently with its owner when topology
  recovery actually requires movement. Do not strand it off-screen under a
  blanket no-move rule.

Shared policy must run before mutations even when callbacks execute
asynchronously. Revalidate identity immediately before a move. Avoid separate
assignment and generic-rehome workers making conflicting decisions for the
same window. Keep ordinary app assignments and explicit number-row move
commands covered by their existing regression tests.

### 3. Make saved-layout handling dialog-aware

Update generated `window_state.pl` capture, matching, and restore behavior:

- Exclude positively identified transient dialogs from new snapshots.
- Exclude live protected windows from all restore candidates, including
  app-identity and Chrome fallback matching.
- Never infer dialog status for an old saved record from its title alone.
  Old records lacking classification need an explicit migration/unmatched
  policy; they must not consume an unrelated ordinary window as a fallback.
- If classification fails for otherwise saveable windows, report incomplete
  capture and retain the existing baseline instead of replacing it with an
  empty or silently reduced snapshot. Manual acceptance must be explicit.
- Preserve startup guards and incomplete-restore semantics. Unknown metadata
  must neither corrupt a baseline nor create endless restore retries.

Specify schema compatibility and the legacy-record policy in `SPEC.md` with
the implementation. Exercise these changes only against fake saved states
during development.

### 4. Cancel stale automatic focus actions

An automatic follow is eligible only for an ordinary window that was active
when the event was observed and still has a valid interaction context. A
background window appearing must not pull the user away.

Capture window identity, workspace, and a focus/navigation generation when
scheduling work. Invalidate pending work on intervening user navigation,
focus changes within the same workspace, window destruction, or new dialog
activity. Checking only the final workspace misses leave-and-return cases.
Recognize the helper's own expected transition so it does not invalidate its
own successful action. Recheck immediately before issuing a focus command.

For close-return behavior, preserve the existing empty-target/nonempty-source
conditions and require uninterrupted eligibility since the follow. A watcher
must retire after navigation elsewhere even if the user later revisits that
workspace. If already back at the source, treat that as completion. Log actual
command errors and observed post-command state; avoid forced repeated returns
that would create another focus fight.

### 5. Record requested and observed focus separately

Extend the existing rotated diagnostic log with:

- Classification decisions and reasons, correlated by window/process identity.
- Automatic move/follow/return requests, results, and cancellation reasons.
- Known shortcut command requests from generated skhd/workspace helpers.
- Window focus changes within a workspace as well as workspace changes.
- Frontmost-app activation observations if AeroSpace events alone are
  insufficient; observing activation does not prove who requested it.

Use timestamps and correlation IDs. Keep callbacks quick and non-mutating;
logging failure must not block navigation. Avoid keystroke contents and full
Accessibility trees in persistent logs. Provide a focused incident-report
command that extracts recent events, with optional capture of a problematic
window's metadata. Unattributed events must remain labeled unknown.

### 6. Verify, deploy, and reproduce

Required regression coverage:

- Touch ID, standalone modal dialogs, sheets, owners with sheets, and a
  manually floated ordinary window.
- Assigned and unassigned dialogs on named and unnamed workspaces.
- Permission denial, missing metadata, ambiguous identity, timeout, destroyed
  windows, and recycled IDs.
- Snapshot filtering, legacy records, restore fallback matching, and baseline
  preservation on incomplete classification.
- Focus changing during a delayed follow, leaving and returning before close,
  same-workspace focus changes, already-returned state, and command failure.
- Normal launch placement, explicit move/follow shortcuts, and monitor repair.

Run focused fake tests, generated syntax/compile checks, the full fake suite,
and `scripts/check_spec_drift.sh`. Update the spec and user-facing docs in the
same behavioral commits. Keep classifier, integration, and focus attribution
changes reviewable as separate commits above the baseline.

Deploy through `./omarchy.sh refresh` when ready for the live trial. Record
baseline/guard state before and after, because restarting the saver can write
a shutdown snapshot. Verify helper permission/capability after deployment.

Manually test approving and dismissing Touch ID, iTerm update prompts, native
open/save sheets, and browser authentication popups. Also repeat the ordinary
System Settings open/close case. Navigate elsewhere during pending operations
to verify cancellation. Do not call the work complete based only on a dialog
appearing successfully: verify typing focus and workspace after dismissal.

Success means supported dialogs produce no automatic workspace movement,
normal user navigation works, stale follow/return actions cancel, and remaining
unexplained activation events have usable incident traces. Universal prevention
of application-driven focus changes is not promised.

## Reference constraints

- [AeroSpace debug-windows contract](https://nikitabobko.github.io/AeroSpace/commands#debug-windows)
  explicitly warns against relying on its output as an API.
- [AeroSpace dialog heuristics](https://nikitabobko.github.io/AeroSpace/guide#dialog-heuristics)
  describes the limitations of application-provided dialog metadata.
- Apple documents [modal state](https://developer.apple.com/documentation/applicationservices/kaxmodalattribute)
  and [sheet roles](https://developer.apple.com/documentation/applicationservices/kaxsheetrole).
  Their availability still needs validation against the actual target windows.
