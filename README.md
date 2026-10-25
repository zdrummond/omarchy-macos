# omarchy-macos

Hyprland/Omarchy-style window management for macOS using native tools:
AeroSpace, skhd, and SketchyBar. JankyBorders is optional.

## Install

Run the normal installer:

```sh
./omarchy.sh install
```

Install the optional focused-window border service:

```sh
OMARCHY_ENABLE_BORDERS=1 ./omarchy.sh install
```

Check status:

```sh
./omarchy.sh status
```

Diagnose macOS Secure Input when global hotkeys stop firing:

```sh
./omarchy.sh secure-input
./omarchy.sh secure-input --watch
```

Secure Input is a macOS session-level keyboard privacy mode. When it is stuck,
AeroSpace and skhd shortcuts can appear disabled because macOS stops other
processes from observing global keyboard input. The diagnostic reports the
current owner PID, process details, parent chain, and matching AeroSpace windows
when there are any.

Regenerate and restart the desktop shortcut cheatsheet widget:

```sh
./omarchy.sh shortcuts-widget
```

For a short, read-only Dock launch experiment:

```sh
swift scripts/dock_launch_probe.swift --self-test
swift scripts/dock_launch_probe.swift 60
```

After `listening` appears, click an application's Dock icon normally. The probe
prints Dock app identities and matching activation observations to stdout,
then exits automatically (maximum 120 seconds). It does not record keystrokes
or window titles, move windows, or change focus. Existing Accessibility trust
is required; it never prompts for permission. This diagnostic is not installed
by `refresh` and does not enable launch-follow behavior. A matched click is not
proof that any particular new window is an ordinary window safe to follow.

The guarded follow implementation is a separate opt-in app, built by
`./omarchy.sh refresh` and disabled by default. After verifying Accessibility permission
for `~/Applications/Omarchy Dock Launch.app`, first run an observation session:

```sh
./omarchy.sh dock-launch-follow observe 120
./omarchy.sh dock-launch-follow status
```

Click an app's Dock icon during the session. The broker logs `would-follow` or
rejection diagnostics to `/tmp/omarchy_window_state.log`; observation does not
enable follow. For a subsequent, explicitly requested live trial:

```sh
./omarchy.sh dock-launch-follow trial 120
./omarchy.sh dock-launch-follow stop
```

For everyday use after testing:

```sh
./omarchy.sh dock-launch-follow enable
./omarchy.sh dock-launch-follow status
```

Enablement persists across login and unchanged refreshes. It succeeds only when
launchd is running and the exact service process responds as ready. A rebuilt
binary requires explicit enable again and may require removing/re-adding
`~/Applications/Omarchy Dock Launch.app` in Accessibility. Failed startup rolls
enablement back; permission loss or a crash stops the service without a restart
loop. `disable` or `stop` switches it off persistently. Disable before running a
separate observation/trial session.

Refresh and enable permanently disable the retired Chrome-rehome service and
move its old LaunchAgent to `~/.omarchy-macos-backup/retired-launchagents/` for
recovery, so it cannot return at login and compete with the guarded helper.

The broker allows one new ordinary window per Dock click to move and
follow with no intervening navigation/input. Already-running apps have three
seconds from the Dock click; cold launches have fifteen seconds. The deadline
never extends when the app activates or creates a window.
The helper can retry a not-yet-ready focus observer for up to two seconds,
without extending that launch deadline. If placement arrives before the
observer is ready, it does not follow later.
Missing permission or uncertain window metadata denies follow. Trial sessions
end automatically; persistent mode is explicitly enabled separately. Assigned apps (including
Gemini on `06`) and unassigned apps use the same guarded exception. The existing
macOS **New Chrome Window** service (Option+Command+= on this machine) also
registers explicit intent before creating its window. Refresh connects only
the known Automator action, preserves the existing shortcut, and backs up its
original workflow. Customized services are left alone; revert restores an
unchanged managed service. Other launch methods and dialogs do not gain
permission to follow. Automatic
placement otherwise retains its existing behavior. The helper uses an undocumented macOS window-ID bridge, so
this needs live acceptance testing after OS updates, not just fake tests.

Left Option is the Omarchy Super key. Right Option remains native macOS input,
including Option-arrow text navigation and terminal Meta input. Left Option
remains Omarchy Super in terminals. Press `Fn+Escape` to toggle Native Input
mode when an application needs both Option keys or every global shortcut
disabled; SketchyBar displays `Native Input` until it is toggled off.
Control-Left/Right moves by word and Control-Shift-Left/Right selects by word,
matching Omarchy/Linux behavior. These replace macOS's Control-arrow native
Space shortcuts; `revert` restores their prior enabled state.
The remapper must pass a timed canary before it can be enabled persistently:

```sh
./omarchy.sh control-word-navigation canary 60
./omarchy.sh control-word-navigation enable
```

The canary records a pass only after the helper stays healthy for the full
timeout. That pass is bound to the exact helper executable, so `enable` refuses
to run without it and a changed helper requires another canary. Enablement also
waits for launchd to report the helper as actually running.

Disable it immediately with `./omarchy.sh control-word-navigation disable`.
The helper rewrites events in place, exits if macOS disables its event tap, and
is not automatically restarted after a fault.
See [SHORTCUTS.md](SHORTCUTS.md) for the complete map.

The exact AeroSpace window/workspace layout is saved automatically every 15
minutes and once more on a best-effort basis when macOS logs out or shuts down.
You can also save it manually after arranging windows the way you want them to
come back after reboot:

```sh
./omarchy.sh save-window-state
```

The saved state is restored automatically at login/startup. Startup autosaves
are held until restore finishes, and startup restore itself does not write a
post-restore snapshot, so login events cannot replace the pre-reboot snapshot.
SketchyBar temporarily shows `Restoring windows` while this is running. If some
saved windows never appear, the bar stays visible with `Restore incomplete`;
arrange the windows as desired and run `./omarchy.sh save-window-state` to
accept that layout and clear the warning.

Assigned apps move to their category workspace (for example, Gmail to Mail).
Unassigned windows, including ordinary Chrome windows, stay where created on
unnamed workspaces. On a named workspace, they move to the nearest empty
unnamed workspace on that monitor, falling back to space key `0`.
By default, automatic placement does not switch to that workspace or focus the moved
window, and closing it does not trigger an automatic return. Switch to it
yourself when wanted; explicit move-and-follow shortcuts are unchanged.
The optional guarded Dock broker above is the narrowly scoped exception.
You can also replay the saved state manually:

```sh
./omarchy.sh restore-window-state
```

1Password windows and macOS Touch ID prompts are floated and kept on the
workspace where they appear, so approving a fingerprint prompt does not move
or strand you on another workspace. Known Steam notification toasts also stay
floating where they appear instead of triggering launch-time rehome. General
dialog protection is not yet implemented, and applications/macOS can still
activate their own windows. Rapid workspace changes and retained
authentication prompts are recorded in `/tmp/omarchy_window_state.log` for
diagnosis. The shortcut reference remains visible on the desktop; use
`Left ⌥+Command+Up` for Mission Control, `Control+Tab` to cycle windows on the
focused workspace, and `Command+Control+Tab` to cycle monitor focus.

Workspace shortcuts are monitor-scoped. The built-in display uses slot `0`, and
attached external displays use slots `1`, `2`, and `3` in AeroSpace monitor
order. SketchyBar shows a separate workspace set per display; named workspace
aliases are used only for the built-in slot, while external displays show
numeric/app labels.

Revert the install:

```sh
./omarchy.sh revert
```

The normal installer does not install CuaDriver.

## Optional: Local CuaDriver Install

This repo includes an optional local CuaDriver installer at:

```sh
scripts/install-cua-driver-local.sh
```

It is not run by `./omarchy.sh install`. Run it manually only if you want
CuaDriver installed as an optional computer-use driver.

The script can either install a previously downloaded CuaDriver release from a
local path or download the latest release itself. In both cases, it verifies the
app signature and expected Apple Developer Team ID before copying the app into
`/Applications`.

Download, verify, and install the latest release:

```sh
scripts/install-cua-driver-local.sh --download-latest
```

If you run the script without a path in an interactive shell, it will offer to
download the latest release for you.

To download the release yourself first:

```sh
mkdir -p /tmp/cua-driver

TAG=$(curl -fsSL "https://api.github.com/repos/trycua/cua/releases?per_page=40" \
  | grep -Eo '"tag_name":[[:space:]]*"cua-driver-v[^"]+"' \
  | sed -E 's/.*"cua-driver-v([0-9]+[.][0-9]+[.][0-9]+)"/\1/' \
  | sort -t. -k1,1nr -k2,2nr -k3,3nr \
  | head -n 1 \
  | sed -E 's/^/cua-driver-v/')

VERSION="${TAG#cua-driver-v}"
ARCH="$(uname -m)"
TARBALL="cua-driver-${VERSION}-darwin-${ARCH}.tar.gz"

curl -fL \
  "https://github.com/trycua/cua/releases/download/${TAG}/${TARBALL}" \
  -o "/tmp/cua-driver/${TARBALL}"
```

Then install the downloaded tarball:

```sh
scripts/install-cua-driver-local.sh "/tmp/cua-driver/${TARBALL}"
```

You can also install from an already extracted app bundle:

```sh
scripts/install-cua-driver-local.sh /path/to/CuaDriver.app
```

By default it installs:

- `/Applications/CuaDriver.app`
- `~/.local/bin/cua-driver`, as a symlink to the app binary
- supported agent skill links, if the relevant agent directories already exist

It may also append `~/.local/bin` to your shell rc file if that directory is
not already on `PATH`. Use `--no-modify-path` to skip that edit.

Common flags:

```sh
scripts/install-cua-driver-local.sh --no-modify-path /path/to/CuaDriver.app
scripts/install-cua-driver-local.sh --bin-dir "$HOME/bin" /path/to/CuaDriver.app
```

Verification can be skipped with `--skip-verify`, but that is not recommended.

See [SPEC.md](SPEC.md) for the project design and installed window-management
behavior.
