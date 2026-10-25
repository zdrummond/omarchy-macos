# Dialog and focus protection plan

> **Superseded 2026-10-25.** The Dock launch broker, Chrome service
> integration, and legacy Chrome rehome helper described below were removed.
> New-window follow is now the single launch-placement rule in `SPEC.md`
> ("Launch placement protects named spaces and follows launches"). This file
> is kept as the incident and investigation history.

Status: broader dialog protection is planned, not implemented. The October 9
incident fix exempts known Steam toasts at detection and removes all automatic
rehome follow/close-return commands. General classification remains pending.
The guarded Dock exception supports bounded observe/trial sessions and explicit
persistent enablement. Chrome's cold-launch happy path was accepted
on October 18; assigned-app and live cancellation coverage remain pending.
On October 11 the read-only
probe captured a Chrome Dock click followed by matching activation after 0.17s;
that establishes click detection, not the full follow acceptance test.
The October 17 Gemini event confirmed assigned placement moved its focused
window from `01` to `06` without following. The bounded broker now covers both
assigned and unassigned placement; this still requires installed-app permission
and live acceptance. It does not yet implement general dialog stay-in-place.

October 17 deployment: all 26 fake scripts passed; the final startup-diagnostic
change also passed the helper compile/policy/generator test. `refresh` deployed
both placement integrations and the dormant app. Installed observation exited
with `Accessibility permission missing`; no live follow trial has run. The user
must grant Accessibility to `~/Applications/Omarchy Dock Launch.app` before
observation and live acceptance. Surviving window IDs retained their workspaces
across refresh; restore/startup/incomplete guards were absent. Service shutdown
saved the current layout; the prior snapshot is backed up at
`/tmp/omarchy-dock-deploy.I2HFQI/window_state.before.json` (temporary, not durable).

Subsequent observation: removing and re-adding the Accessibility entry allowed
the installed broker to start. The 11:31 Chrome test captured the Dock click at
11:31:27, expired at 11:31:30, and recorded placement at 11:31:35. System logs
show Chrome's new process starting at 11:31:28 and AppKit window restoration at
11:31:33–34, supporting cold startup as a substantial part of the delay. This
does not measure the exact callback queue delay. The broker now allows fifteen
seconds only for cold launches, while keeping three seconds for already-running
apps and preserving every cancellation/identity/dialog gate. New timing logs
separate process binding, focused-window observation, and placement requests.
The helper's 35 policy checks and both placement integration tests pass. The
11:38 refresh deployed this version; the installed source matches and its policy
self-test passes. Observation again reports missing Accessibility permission
after the rebuild, so the app must be removed/re-added before another test. No
live follow trial has run. Surviving windows retained their workspaces, all
restore guards remained absent, and Control-arrow stayed enabled and running.
Refresh saved the current layout on shutdown; the preceding snapshot is backed
up at `/tmp/omarchy-cold-launch-deploy.Y3ilwR/window_state.before.json`.

October 18 observer-readiness fix: the October 17 11:47 Chrome observation
cancelled observer attachment after 0.28 seconds, before placement at 11:47:08.
The helper now pins process identity before attachment and retries selected AX
startup failures for at most two seconds/20 attempts, without extending the
launch deadline. Every attempt checks cancellation conditions. An arriving
placement request still declines and discards intent if the observer is not
ready; there is no queued follow. Diagnostics distinguish creation from
notification-registration errors and report the actual AX error code.
All 26 fake scripts pass, including 37 follow-policy and 47 attachment checks.
The compiler reports Swift 6 language-mode concurrency compatibility warnings;
the current build succeeds, but strict Swift 6 compatibility is not established.
Live observer-recovery and follow acceptance remain pending.
The October 18 12:37 refresh deployed the retry build. Installed source and
signature verification pass, and the installed binary passes all 84 checks.
The startup check again reports missing Accessibility permission after the
rebuild; the user must re-add the app before observation. Surviving window IDs
kept their workspaces, restore/startup/incomplete guards were absent, and the
Control-arrow helper remained enabled and running. The saver wrote a shutdown
snapshot; the previous snapshot is backed up at
`/tmp/omarchy-observer-retry-deploy.TIhYMh/window_state.before.json`.

October 18 acceptance: after permission was re-added, the 12:45 observation
recovered registration on attempt 6 (about 1.2 seconds) and logged `would-follow`
for Chrome window 62400 from `04` to `00`. The user then approved a live trial.
At 12:47, registration recovered on attempt 8 (about 1.2 seconds), and the
broker consumed intent and successfully moved/followed Chrome window 62440
from `04` to `00`. The user confirmed that it worked. A second window's request
had no remaining intent. The trial was stopped and status confirmed not running.
This verifies the Chrome cold-launch happy path, not all apps, dialog types,
or live cancellation scenarios. Persistent enablement remains unimplemented.

October 18 12:51 cancellation trial: Chrome intent was cancelled with
`different-or-existing-window` about 1.27 seconds after the Dock click. Both
subsequent placement requests had `pending=false`; no broker follow was issued.
Workspace diagnostics show the switch to `02` at 12:51:07 and no subsequent
workspace change until 12:54:48. The trial expired and status was not running.
This confirms the no-follow outcome, but does not independently validate the
navigation-cancellation branch: a window/focus check cancelled intent first.

October 24: diagnosis of another Chrome launch found the new broker stopped
(only short trials had been run) and the legacy Chrome LaunchAgent running
again. Its log moved window 2606 from `08` to `09` at 14:08:24; workspace
diagnostics then returned to `08`. The legacy plist still had RunAtLoad and
KeepAlive: unloading it during refresh had not retired login startup.
The user approved permanent legacy retirement and opt-in persistent operation
of the guarded replacement. The implementation disables/boots out the old label
and moves its plist into recoverable backup storage outside LaunchAgents.
The new service is executable-authorized, has no KeepAlive, verifies actual
launchd state plus exact-PID IPC readiness, and rolls failed enablement back.
Unchanged refreshes preserve authorization/signature; changed builds need
explicit enable and may need a fresh Accessibility grant. `stop` is now an alias
for persistent `disable`. Lifecycle fake tests cover startup failures,
permission denial, crashes, stale binaries, mismatched readiness, and failed
legacy retirement. All 27 fake scripts passed (with the previously noted Swift
concurrency compatibility warnings). The 14:22 refresh deployed the new build.
The legacy label is confirmed disabled and unloaded; its plist was moved to
`~/.omarchy-macos-backup/retired-launchagents/chrome_rehome.KZkVZm`.
The installed source, signature, plist, and 84 helper checks verify. The explicit
enable attempt at 14:23 failed with `Accessibility permission missing` and
rolled back: authorization removed, job unloaded, and new label disabled.
Persistent activation now requires the user to re-add the rebuilt app's
Accessibility entry, followed by `dock-launch-follow enable` and readiness
verification. Control-arrow remains enabled/running; restore guards are absent.
Refresh saved the current layout on shutdown; the prior snapshot is at
`/tmp/omarchy-persistent-deploy.LfYn09/window_state.before.json`. Placement
comparison found Todoist 2682 changing `09` to `00`; logs show an explicit
`move-node-to-workspace-00` save at 14:22:34, before persistent startup was tried.
No restore/repair was run. Changes remain uncommitted.

October 24 14:27 activation: after the user renewed Accessibility permission,
`dock-launch-follow enable` succeeded. Both launchd (`state = running`, PID
19471) and the exact-PID IPC readiness check report persistent service mode.
The legacy Chrome label remains disabled and its job unloaded. The new label
is enabled for login; no layout restore/save/repair was invoked during this
activation. Login survival and Gemini-specific live acceptance are not yet
verified. `dock-launch-follow disable` is the persistent off switch.

October 25 shortcut diagnosis: Option-Command-Equal is owned by the existing
`~/Library/Services/New Chrome Window.workflow`, confirmed by its macOS Services
key equivalent `@~=`. Its AppleScript creates a Chrome window and activates the
app without Dock intent. The integration now registers one-use Chrome intent
before that existing action, with the same exact-window/focus/navigation gates.
Creation failures cancel only their matching request token; an absent or
declining broker leaves ordinary creation/no-follow placement available. No
new hotkey owner is installed. Refresh backs up and adapts only the known
single-action workflow; guarded revert preserves subsequent custom edits.
All 28 fake scripts, shell syntax, spec drift, and whitespace checks pass.
The helper has 90 policy/attachment/command-freshness checks. The new Automator
test executes the real action control flow with fake Chrome/broker operations,
including arming failure and creation failure. It needs macOS scripting
additions outside the sandbox. Existing Swift 6 compatibility warnings remain.
The 10:31 refresh deployed the helper and adapted the workflow; the installed
source, signature, action source, and unchanged `@~=` shortcut verify. The
original workflow is backed up at
`~/.omarchy-macos-backup/chrome-window-service.original.wflow`. Explicit enable
failed at 10:31:10 with `Accessibility permission missing` and rolled back;
the broker is currently disabled/not running. The user must renew the rebuilt
app's Accessibility entry before enable and real shortcut acceptance. No live
shortcut was invoked by the agent. Surviving windows kept their workspaces,
restore/startup/incomplete guards were absent, and Control-arrow remained
enabled/running. Refresh saved 15 windows on shutdown; the previous baseline
is at `/tmp/omarchy-chrome-service-deploy.1hGRD2/window_state.before.json`.
No restore or repair command was run. Real shortcut acceptance remains pending.

October 25 10:32 activation: after the user renewed Accessibility permission,
enable succeeded. Launchd reports `state = running`, PID 91405, and exact-PID
broker readiness confirms persistent service mode. The log records
`listening mode=service duration=persistent`. No window action or manual
save/restore/repair was invoked during activation. Option-Command-Equal live
acceptance remains pending.

October 25 10:43 shortcut failure: Chrome window 4186 was placed `04` to `00`
with `pending=false`, while the persistent broker was healthy. There was no
recorded command intent. Both direct AppleScript and temporary read-only
Automator workflows successfully registered/cancelled intent without creating
windows. Services registration points to the expected workflow, but its outer
bundle timestamp had remained in 2022 despite the inner plist update. A stale
action is a hypothesis, not a confirmed cause; the shortcut's actual execution
path still needs acceptance. The user does not recall its setup and doubts it
is Raycast.

The service now logs invocation, arm result, and creation result (numeric error
codes only) to the shared rotating log. Workflow updates/revert touch the
bundle and update Services registration without flushing preferences. Fake
service tests cover diagnostic success/failure and registration calls without
touching the live registry; they pass, as do shell syntax, drift, and whitespace
checks. The 10:49 refresh deployed these changes. The helper binary digest was
unchanged and its enabled service resumed successfully, preserving AX trust.
Surviving windows kept their workspaces across refresh; the shutdown saver
updated the baseline, backed up beforehand at
`/tmp/omarchy-service-diagnostics-deploy.xwuvRA/window_state.before.json`.

At 10:50, one direct execution of the installed workflow through `automator`
passed live: command intent was armed, Chrome observer attached, new window
4242 validated, and one move-and-follow succeeded `04` to `00` at 0.75 seconds.
Read-only AeroSpace query confirmed focused window `4242|00|com.google.Chrome`.
The test window was left open, and normal rehome autosave recorded it. The
earlier `NSPerformService` probe returned accepted but produced no observed
workflow log or new window. Broker status remains healthy; restore guards are
absent. No restore/repair or manual save was run. Direct workflow acceptance
passes; physical Option-Command-Equal routing remains unverified.

Branch: `codex/dialog-focus-protection`.
Baseline: `9127d14` — the existing Touch ID exception, rapid workspace-change
diagnostics, documentation, and regression tests. This plan builds on that
commit. `SPEC.md` remains the contract for currently implemented behavior.

## Problem and evidence

On October 9 at 13:07:35, the catch-all moved Steam Helper window 52773
(`notificationtoasts_2545_desktop`) from Gmail's workspace 01 to 00 and
explicitly followed it. That initiating action is confirmed by the move and
focus logs. The subsequent 00-to-04 transition is not attributed.

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
  scheduling movement; keep automatic follow/return disabled.
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

Superseded by the October 9 no-automatic-follow policy in `SPEC.md`: window
detection cannot reliably establish user intent, so rehome never issues focus
or workspace activation commands by default. The optional bounded Dock trial
brokers explicit click intent, exact new ordinary-window identity, navigation
cancellation, and one-shot consumption (see `SPEC.md`). Close-return remains
disabled. Do not restore general automatic follow
merely based on the current focus or a settle delay. Explicit
user move-and-follow remains separate. Future delayed movement/classification
work still needs cancellation on intervening navigation and window destruction.

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
- No automatic follow or close-return on any detection path, including
  background windows, failed moves, and legacy watcher invocation. For future
  delayed classification, navigation changes must cancel stale movement.
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
normal user navigation works, automatic follow/return stays disabled, and remaining
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
