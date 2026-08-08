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

Left Option is the Omarchy Super key. Right Option remains native macOS input,
including Option-arrow text navigation and terminal Meta input. Left Option
remains Omarchy Super in terminals. Press `Fn+Escape` to toggle Native Input
mode when an application needs both Option keys or every global shortcut
disabled; SketchyBar displays `Native Input` until it is toggled off.
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

Windows without a saved location or explicit app rule stay where they are
created so browser popups and transient dialogs are not moved out from under the
app that opened them. Ordinary Chrome windows are the exception: if a new Chrome
window opens somewhere that does not already contain Chrome, it should first
join an existing ordinary Chrome workspace on that monitor. If none exists, it
may move to the first empty general-purpose workspace on that monitor. Named or
reserved workspaces such as Mail, Msg, Music, Terms, Editors, Agents, and Steam
are not candidates just because they are empty. Chrome app wrappers such as the
Gmail app are left unmanaged by app-name rules because their click handling is
more sensitive than ordinary Chrome tabs. You can also replay the saved state
manually:

```sh
./omarchy.sh restore-window-state
```

1Password windows are floated so authentication dialogs stay usable on the
current workspace. Use `Left ⌥+K` for the shortcut reference,
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
