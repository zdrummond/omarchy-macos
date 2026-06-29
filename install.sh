#!/usr/bin/env bash
# =============================================================================
# omarchy-macos — Hyprland/Omarchy-style window management for macOS M1
#
# Usage:
#   ./install.sh install   — install and configure everything
#   ./install.sh refresh   — rewrite generated configs without reinstalling brew packages
#   ./install.sh save-window-state — save current window/workspace layout
#   ./install.sh restore-window-state — replay saved window/workspace layout
#   ./install.sh secure-input [--watch] — diagnose macOS Secure Input owner
#   ./install.sh revert    — undo everything, restore previous state
#   ./install.sh status    — show what's installed and running
#
# Tools installed:
#   aerospace    — tiling window manager (i3-style)
#   skhd         — global hotkey daemon for app launchers
#   sketchybar   — scriptable status bar (waybar equivalent)
#   jankyborders — optional colored border on focused window
# =============================================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${BLUE}→${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
error()   { echo -e "${RED}✗${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}$*${RESET}"; }

# ── Paths ─────────────────────────────────────────────────────────────────────
BACKUP_DIR="$HOME/.omarchy-macos-backup"
AEROSPACE_CFG="$HOME/.aerospace.toml"
AEROSPACE_DIR="$HOME/.config/aerospace"
SKHD_DIR="$HOME/.config/skhd"
SKHD_CFG="$SKHD_DIR/skhdrc"
SKETCHY_DIR="$HOME/.config/sketchybar"
BORDERS_DIR="$HOME/.config/borders"
BORDERS_INSTALLED_MARKER="$BACKUP_DIR/.borders-installed"
BORDERS_SERVICE_PLIST="$HOME/Library/LaunchAgents/homebrew.mxcl.borders.plist"

BAR_TOGGLE_LABEL="com.omarchy-macos.bar_toggle"
BAR_TOGGLE_PLIST="$HOME/Library/LaunchAgents/$BAR_TOGGLE_LABEL.plist"

AEROSPACE_START_LABEL="com.omarchy-macos.aerospace_start"
AEROSPACE_START_PLIST="$HOME/Library/LaunchAgents/$AEROSPACE_START_LABEL.plist"

WINDOW_PICKER_SRC="$AEROSPACE_DIR/window_picker.swift"
WINDOW_PICKER_BIN="$AEROSPACE_DIR/window_picker"
SECURE_INPUT_HELPER="$AEROSPACE_DIR/secure_input_report.sh"

CHROME_REHOME_SRC="$SKETCHY_DIR/plugins/chrome_rehome.swift"
CHROME_REHOME_LABEL="com.omarchy-macos.chrome_rehome"
CHROME_REHOME_APP="$HOME/Applications/Omarchy Chrome Rehome.app"
CHROME_REHOME_BIN="$CHROME_REHOME_APP/Contents/MacOS/chrome_rehome"
CHROME_REHOME_PLIST="$HOME/Library/LaunchAgents/$CHROME_REHOME_LABEL.plist"

SHORTCUT_WIDGET_SRC="$AEROSPACE_DIR/shortcut_widget.swift"
SHORTCUT_WIDGET_LABEL="com.omarchy-macos.shortcut_widget"
SHORTCUT_WIDGET_APP="$HOME/Applications/Omarchy Shortcuts Widget.app"
SHORTCUT_WIDGET_BIN="$SHORTCUT_WIDGET_APP/Contents/MacOS/shortcut_widget"
SHORTCUT_WIDGET_PLIST="$HOME/Library/LaunchAgents/$SHORTCUT_WIDGET_LABEL.plist"

WINDOW_STATE_FILE="$AEROSPACE_DIR/omarchy_window_state.json"
WINDOW_STATE_HELPER="$AEROSPACE_DIR/window_state.pl"
WINDOW_STATE_WRAPPER="$AEROSPACE_DIR/window_state.sh"
WINDOW_STATE_LOG="/tmp/omarchy_window_state.log"
WINDOW_STATE_SAVER="$AEROSPACE_DIR/window_state_saver.sh"
WINDOW_STATE_DEBOUNCED_SAVER="$AEROSPACE_DIR/window_state_debounced_save.sh"
WINDOW_STATE_MONITOR_MOVE_HELPER="$AEROSPACE_DIR/move_node_to_monitor_and_save.sh"
RESPONSIVE_LAYOUT_HELPER="$AEROSPACE_DIR/responsive_layout.sh"
MONITOR_FRAME_SRC="$AEROSPACE_DIR/monitor_frame.swift"
MONITOR_FRAME_BIN="$AEROSPACE_DIR/monitor_frame"
WINDOW_STATE_SAVE_INTERVAL_SECONDS=900
WINDOW_STATE_SAVER_LABEL="com.omarchy-macos.window_state_saver"
WINDOW_STATE_SAVER_PLIST="$HOME/Library/LaunchAgents/$WINDOW_STATE_SAVER_LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHORTCUT_IMAGE_SCRIPT="$SCRIPT_DIR/generate_shortcut_image.py"
SHORTCUT_IMAGE_OUTPUT="$HOME/Desktop/omarchy-shortcuts.png"

INSTALLED_MARKER="$BACKUP_DIR/.installed"

# =============================================================================
# INSTALL
# =============================================================================
cmd_install() {
  header "omarchy-macos installer"

  check_prerequisites

  if [[ -f "$INSTALLED_MARKER" ]]; then
    warn "Already installed. Run './install.sh revert' first to reinstall."
    exit 1
  fi

  backup_existing_configs

  header "Installing packages via Homebrew..."
  brew_install "aerospace"    "nikitabobko/tap/aerospace"
  brew_install "skhd"         "koekeishiya/formulae/skhd"
  brew_install "sketchybar"   "FelixKratz/formulae/sketchybar"
  if borders_enabled; then
    brew_install "jankyborders" "FelixKratz/formulae/borders"
    touch "$BORDERS_INSTALLED_MARKER"
  else
    info "Skipping optional jankyborders (set OMARCHY_ENABLE_BORDERS=1 to install)"
  fi

  header "Writing configuration files..."
  write_aerospace_config
  write_space_state_helper
  write_window_state_helper
  write_window_state_saver_agent
  write_goto_space_helper
  write_window_cycle_helper
  write_window_picker_helper
  write_secure_input_helper
  write_aerospace_start_agent
  write_skhd_config
  write_sketchybar_config
  write_borders_config_if_enabled
  write_chrome_rehome_daemon
  write_shortcut_desktop_widget

  header "Tuning macOS for instant window movement..."
  defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
  defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
  success "macOS window animations disabled"

  header "Starting services..."
  start_services

  touch "$INSTALLED_MARKER"

  echo ""
  success "Installation complete!"
  echo ""
  echo -e "  ${BOLD}Modifier key:${RESET} Option (⌥)  ← your new SUPER key"
  echo ""
  echo -e "  ${BOLD}Essential shortcuts:${RESET}"
  echo "  ⌥ + 1-9          switch workspace"
  echo "  ⌥ + h/j/k/l      focus window (vim-style)"
  echo "  ⌥ + shift + h/j/k/l  move window"
  echo "  ⌥ + return        open terminal (Ghostty → WezTerm → Terminal)"
  echo "  ⌥ + space         Raycast launcher"
  echo "  ⌥ + f             fullscreen toggle"
  echo "  ⌥ + shift + q     close focused window"
  echo "  ⌥ + shift + r     reload aerospace config"
  echo ""
  echo -e "  ${BOLD}Edit configs:${RESET}"
  echo "  $AEROSPACE_CFG"
  echo "  $SKHD_CFG"
  echo "  $SKETCHY_DIR/sketchybarrc"
  echo ""
  warn "You may need to grant Accessibility permissions to Aerospace and skhd"
  warn "in System Settings → Privacy & Security → Accessibility"
}

# =============================================================================
# REFRESH GENERATED CONFIG
# =============================================================================
cmd_refresh() {
  header "omarchy-macos config refresh"

  check_prerequisites

  header "Rewriting generated configuration files..."
  write_aerospace_config
  write_space_state_helper
  write_window_state_helper
  write_window_state_saver_agent
  write_goto_space_helper
  write_window_cycle_helper
  write_window_picker_helper
  write_secure_input_helper
  write_aerospace_start_agent
  write_skhd_config
  write_sketchybar_config
  write_borders_config_if_enabled
  write_chrome_rehome_daemon
  write_shortcut_desktop_widget

  header "Restarting services..."
  stop_services
  start_services

  echo ""
  success "Configuration refreshed."
  echo "Run './install.sh repair-spaces' once after AeroSpace is healthy to move windows off detached monitor workspaces."
}

# =============================================================================
# SHORTCUT DESKTOP WIDGET
# =============================================================================
cmd_shortcuts_widget() {
  header "omarchy-macos shortcut widget"
  write_shortcut_desktop_widget
  if [[ -f "$SHORTCUT_WIDGET_PLIST" ]]; then
    launchctl unload "$SHORTCUT_WIDGET_PLIST" 2>/dev/null || true
    launchctl load "$SHORTCUT_WIDGET_PLIST" 2>/dev/null || \
      warn "Could not load shortcut desktop widget LaunchAgent"
  fi
}

# =============================================================================
# REPAIR DETACHED MONITOR WORKSPACES
# =============================================================================
cmd_repair_spaces() {
  header "omarchy-macos repair spaces"

  local helper="$AEROSPACE_DIR/omarchy_space_state.sh"
  if [[ ! -f "$helper" ]]; then
    error "Missing $helper. Run './install.sh refresh' first."
    exit 1
  fi

  # shellcheck source=/dev/null
  source "$helper"

  if ! omarchy_aerospace_available; then
    error "AeroSpace is not reachable; no spaces were changed."
    exit 1
  fi

  omarchy_repair_detached_monitor_workspaces
  success "Detached monitor workspaces repaired."
}

# =============================================================================
# WINDOW STATE SAVE / RESTORE
# =============================================================================
cmd_save_window_state() {
  header "omarchy-macos save window state"
  write_window_state_helper
  "$WINDOW_STATE_WRAPPER" save
}

cmd_restore_window_state() {
  header "omarchy-macos restore window state"
  write_window_state_helper
  "$WINDOW_STATE_WRAPPER" restore
}

cmd_secure_input() {
  header "omarchy-macos secure input"
  write_secure_input_helper >/dev/null
  "$SECURE_INPUT_HELPER" "${@:2}"
}

write_shortcut_desktop_widget() {
  mkdir -p "$AEROSPACE_DIR" "$SHORTCUT_WIDGET_APP/Contents/MacOS" "$HOME/Library/LaunchAgents"

  if [[ ! -f "$SHORTCUT_IMAGE_SCRIPT" ]]; then
    warn "Shortcut widget generator not found at $SHORTCUT_IMAGE_SCRIPT"
    return 0
  fi
  if ! command -v python3 &>/dev/null; then
    warn "python3 not found — could not regenerate $SHORTCUT_IMAGE_OUTPUT"
    return 0
  fi
  if ! python3 -c 'import PIL' >/dev/null 2>&1; then
    warn "Python Pillow is not installed — could not regenerate $SHORTCUT_IMAGE_OUTPUT"
    return 0
  fi

  info "Regenerating shortcut desktop image..."
  python3 "$SHORTCUT_IMAGE_SCRIPT" >/dev/null
  success "Shortcut desktop image written to $SHORTCUT_IMAGE_OUTPUT"

  cat > "$SHORTCUT_WIDGET_SRC" << SHORTCUT_WIDGET_SWIFT_EOF
import AppKit

let imagePath = NSHomeDirectory() + "/Desktop/omarchy-shortcuts.png"
let margin = CGFloat(Double(ProcessInfo.processInfo.environment["OMARCHY_SHORTCUT_WIDGET_MARGIN"] ?? "24") ?? 24)
let bottomOffset = CGFloat(Double(ProcessInfo.processInfo.environment["OMARCHY_SHORTCUT_WIDGET_BOTTOM"] ?? "40") ?? 40)
let maxWidth = CGFloat(Double(ProcessInfo.processInfo.environment["OMARCHY_SHORTCUT_WIDGET_WIDTH"] ?? "560") ?? 560)

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var imageView: NSImageView?
    var lastModified: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        render()
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.renderIfChanged()
        }
    }

    func renderIfChanged() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: imagePath)
        let modified = attrs?[.modificationDate] as? Date
        if modified != lastModified {
            render()
        }
    }

    func render() {
        guard let image = NSImage(contentsOfFile: imagePath),
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            window?.orderOut(nil)
            return
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: imagePath)
        lastModified = attrs?[.modificationDate] as? Date

        let scale = min(1.0, maxWidth / max(image.size.width, 1.0))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.maxX - size.width - margin,
            y: visible.minY + bottomOffset
        )
        let frame = NSRect(origin: origin, size: size)

        if window == nil {
            let win = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

            let view = NSImageView(frame: NSRect(origin: .zero, size: size))
            view.imageScaling = .scaleProportionallyUpOrDown
            view.alphaValue = 0.92
            view.image = image
            win.contentView = view
            imageView = view
            window = win
        } else {
            window?.setFrame(frame, display: true)
            imageView?.frame = NSRect(origin: .zero, size: size)
            imageView?.image = image
        }

        window?.orderFrontRegardless()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
SHORTCUT_WIDGET_SWIFT_EOF

  if ! command -v swiftc &>/dev/null; then
    warn "swiftc not found — shortcut image was generated, but desktop widget app was not built"
    return 0
  fi

  info "Compiling shortcut desktop widget..."
  swiftc -O "$SHORTCUT_WIDGET_SRC" -o "$SHORTCUT_WIDGET_BIN"
  chmod +x "$SHORTCUT_WIDGET_BIN"

  cat > "$SHORTCUT_WIDGET_APP/Contents/Info.plist" << SHORTCUT_WIDGET_INFO_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>shortcut_widget</string>
  <key>CFBundleIdentifier</key>
  <string>$SHORTCUT_WIDGET_LABEL</string>
  <key>CFBundleName</key>
  <string>Omarchy Shortcuts Widget</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
SHORTCUT_WIDGET_INFO_PLIST_EOF

  /usr/bin/codesign --force --sign - --identifier "$SHORTCUT_WIDGET_LABEL" "$SHORTCUT_WIDGET_APP" >/dev/null 2>&1 || \
    warn "Could not ad-hoc sign $SHORTCUT_WIDGET_APP"
  xattr -dr com.apple.quarantine "$SHORTCUT_WIDGET_APP" 2>/dev/null || true
  xattr -dr com.apple.provenance "$SHORTCUT_WIDGET_APP" 2>/dev/null || true

  cat > "$SHORTCUT_WIDGET_PLIST" << SHORTCUT_WIDGET_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$SHORTCUT_WIDGET_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$SHORTCUT_WIDGET_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/omarchy_shortcut_widget.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/omarchy_shortcut_widget.log</string>
</dict>
</plist>
SHORTCUT_WIDGET_PLIST_EOF

  success "Shortcut desktop widget written"
}

# =============================================================================
# REVERT
# =============================================================================
cmd_revert() {
  header "omarchy-macos revert"
  local managed_borders=0

  if [[ ! -f "$INSTALLED_MARKER" ]]; then
    warn "omarchy-macos doesn't appear to be installed (no marker found)."
    read -r -p "Force revert anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 0
  fi
  if [[ -f "$BORDERS_INSTALLED_MARKER" ]] || borders_enabled; then
    managed_borders=1
  elif [[ -f "$BORDERS_DIR/bordersrc" ]] && grep -q "Active border = Catppuccin Mauve" "$BORDERS_DIR/bordersrc"; then
    managed_borders=1
  fi

  header "Stopping services..."
  stop_services revert

  header "Removing configuration files..."
  rm -f "$AEROSPACE_CFG"
  rm -rf "$AEROSPACE_DIR"
  rm -rf "$SKHD_DIR"
  rm -rf "$SKETCHY_DIR"
  rm -rf "$BORDERS_DIR"
  rm -f "$AEROSPACE_START_PLIST"
  rm -f "$WINDOW_STATE_SAVER_PLIST"
  rm -f "$BAR_TOGGLE_PLIST"
  rm -f "$CHROME_REHOME_PLIST"
  rm -f "$SHORTCUT_WIDGET_PLIST"
  rm -rf "$CHROME_REHOME_APP"
  rm -rf "$SHORTCUT_WIDGET_APP"
  success "Config files removed"

  header "Restoring backups..."
  restore_backups

  header "Uninstalling packages..."
  if [[ "$managed_borders" -eq 1 ]]; then
    brew_uninstall "borders" "FelixKratz/formulae/borders"
    rm -f "$BORDERS_INSTALLED_MARKER"
  else
    info "borders optional and unmanaged, skipping uninstall"
  fi
  brew_uninstall "sketchybar" "FelixKratz/formulae/sketchybar"
  brew_uninstall "skhd"       "koekeishiya/formulae/skhd"
  brew_uninstall "aerospace"  "nikitabobko/tap/aerospace"

  rm -f "$INSTALLED_MARKER"

  echo ""
  success "Reverted. Your previous configuration has been restored."
  warn "You may need to log out and back in for all changes to take effect."
}

# =============================================================================
# STATUS
# =============================================================================
cmd_status() {
  header "omarchy-macos status"
  echo ""

  check_tool "aerospace"    "$(brew list nikitabobko/tap/aerospace &>/dev/null && echo yes || echo no)"
  check_tool "skhd"         "$(brew list koekeishiya/formulae/skhd &>/dev/null && echo yes || echo no)"
  check_tool "sketchybar"   "$(brew list FelixKratz/formulae/sketchybar &>/dev/null && echo yes || echo no)"
  if brew list FelixKratz/formulae/borders &>/dev/null; then
    check_tool "jankyborders (optional)" "yes"
  else
    echo -e "  ${YELLOW}○${RESET} jankyborders optional — disabled"
  fi

  echo ""
  check_aerospace_app
  check_launch_agent "com.koekeishiya.skhd"
  check_service "sketchybar"
  if borders_enabled || brew list FelixKratz/formulae/borders &>/dev/null; then
    check_service "borders"
  fi
  check_launch_agent "$AEROSPACE_START_LABEL"
  check_launch_agent "$WINDOW_STATE_SAVER_LABEL"
  check_launch_agent "$SHORTCUT_WIDGET_LABEL"

  echo ""
  if aerospace list-monitors --format '%{monitor-id}' >/dev/null 2>&1; then
    success "AeroSpace server reachable"
  else
    warn "AeroSpace server is not reachable — window restore and workspace moves will fail"
  fi
  if [[ -f /tmp/chrome_rehome.log ]] && awk '/AXIsProcessTrusted/ { last=$0 } END { exit(last ~ /false/ ? 0 : 1) }' /tmp/chrome_rehome.log 2>/dev/null; then
    warn "chrome_rehome is not Accessibility-trusted — grant Omarchy Chrome Rehome in Privacy & Security → Accessibility"
  fi
  check_window_state
  if [[ -x "$SECURE_INPUT_HELPER" ]]; then
    echo ""
    "$SECURE_INPUT_HELPER" --brief || true
  fi

  echo ""
  if [[ -f "$INSTALLED_MARKER" ]]; then
    success "Install marker found at $INSTALLED_MARKER"
  else
    warn "No install marker found — run './install.sh install'"
  fi
}

# =============================================================================
# PREREQUISITES
# =============================================================================
check_prerequisites() {
  info "Checking prerequisites..."

  # macOS check
  if [[ "$(uname)" != "Darwin" ]]; then
    error "This script is for macOS only."
    exit 1
  fi

  # Apple Silicon check
  local arch
  arch=$(uname -m)
  if [[ "$arch" != "arm64" ]]; then
    warn "You appear to be on $arch, not arm64 (M1/M2/M3). Proceeding anyway..."
  fi

  # Homebrew check
  if ! command -v brew &>/dev/null; then
    error "Homebrew is required. Install from https://brew.sh"
    exit 1
  fi

  success "Prerequisites OK (macOS $arch, Homebrew $(brew --version | head -1))"

  mkdir -p "$BACKUP_DIR"
}

borders_enabled() {
  [[ "${OMARCHY_ENABLE_BORDERS:-0}" =~ ^(1|true|yes|on)$ ]]
}

# =============================================================================
# BACKUP / RESTORE
# =============================================================================
backup_existing_configs() {
  info "Backing up existing configs to $BACKUP_DIR..."

  [[ -f "$AEROSPACE_CFG" ]]    && cp "$AEROSPACE_CFG" "$BACKUP_DIR/aerospace.toml.bak"     && info "  backed up .aerospace.toml"
  [[ -d "$SKHD_DIR" ]]         && cp -r "$SKHD_DIR" "$BACKUP_DIR/skhd.bak"                && info "  backed up skhd config"
  [[ -d "$SKETCHY_DIR" ]]      && cp -r "$SKETCHY_DIR" "$BACKUP_DIR/sketchybar.bak"        && info "  backed up sketchybar config"
  [[ -d "$BORDERS_DIR" ]]      && cp -r "$BORDERS_DIR" "$BACKUP_DIR/borders.bak"           && info "  backed up borders config"

  success "Backup complete"
}

restore_backups() {
  local restored=0

  if [[ -f "$BACKUP_DIR/aerospace.toml.bak" ]]; then
    cp "$BACKUP_DIR/aerospace.toml.bak" "$AEROSPACE_CFG"
    info "  restored .aerospace.toml"
    restored=1
  fi
  if [[ -d "$BACKUP_DIR/skhd.bak" ]]; then
    mkdir -p "$SKHD_DIR"
    cp -r "$BACKUP_DIR/skhd.bak/." "$SKHD_DIR/"
    info "  restored skhd config"
    restored=1
  fi
  if [[ -d "$BACKUP_DIR/sketchybar.bak" ]]; then
    mkdir -p "$SKETCHY_DIR"
    cp -r "$BACKUP_DIR/sketchybar.bak/." "$SKETCHY_DIR/"
    info "  restored sketchybar config"
    restored=1
  fi
  if [[ -d "$BACKUP_DIR/borders.bak" ]]; then
    mkdir -p "$BORDERS_DIR"
    cp -r "$BACKUP_DIR/borders.bak/." "$BORDERS_DIR/"
    info "  restored borders config"
    restored=1
  fi

  if [[ $restored -eq 0 ]]; then
    info "No backups to restore (nothing was overwritten)"
  else
    success "Backups restored"
  fi
}

# =============================================================================
# BREW HELPERS
# =============================================================================
brew_install() {
  local name="$1" pkg="$2"
  if brew list "$pkg" &>/dev/null 2>&1; then
    success "$name already installed"
  else
    info "Installing $name..."
    # Add tap if needed
    case "$pkg" in
      nikitabobko/tap/aerospace) brew tap nikitabobko/tap 2>/dev/null || true ;;
      koekeishiya/formulae/skhd) brew tap koekeishiya/formulae 2>/dev/null || true ;;
      FelixKratz/formulae/*) brew tap FelixKratz/formulae 2>/dev/null || true ;;
    esac
    brew install "$pkg"
    success "$name installed"
  fi
}

brew_uninstall() {
  local name="$1" pkg="${2:-$1}"
  if brew list "$pkg" &>/dev/null 2>&1; then
    info "Uninstalling $name..."
    brew uninstall "$pkg" || warn "Could not uninstall $name (may have dependents)"
    success "$name uninstalled"
  else
    info "$name not installed, skipping"
  fi
}

# =============================================================================
# SERVICES
# =============================================================================
start_services() {
  info "Loading AeroSpace login starter..."
  launchctl unload "$AEROSPACE_START_PLIST" 2>/dev/null || true
  launchctl load "$AEROSPACE_START_PLIST" 2>/dev/null || \
    warn "Could not load AeroSpace login LaunchAgent"

  info "Starting window state saver..."
  launchctl unload "$WINDOW_STATE_SAVER_PLIST" 2>/dev/null || true
  launchctl load "$WINDOW_STATE_SAVER_PLIST" 2>/dev/null || \
    warn "Could not load window state saver LaunchAgent"

  info "Starting aerospace..."
  if [[ -d /Applications/AeroSpace.app ]]; then
    open -g /Applications/AeroSpace.app 2>/dev/null || \
      warn "Could not auto-start aerospace — launch /Applications/AeroSpace.app manually"
    for _ in {1..20}; do
      if aerospace list-monitors --format '%{monitor-id}' >/dev/null 2>&1; then
        aerospace reload-config >/dev/null 2>&1 || true
        break
      fi
      sleep 0.2
    done
  else
    warn "Could not find /Applications/AeroSpace.app — reinstall aerospace"
  fi

  info "Starting skhd..."
  skhd --start-service 2>/dev/null || \
    warn "Could not auto-start skhd — run 'skhd --start-service' manually"

  info "Starting sketchybar..."
  brew services start felixkratz/formulae/sketchybar 2>/dev/null || \
    brew services start sketchybar 2>/dev/null || \
    warn "Could not auto-start sketchybar"

  if borders_enabled; then
    info "Starting borders..."
    brew services start felixkratz/formulae/borders 2>/dev/null || \
      brew services start borders 2>/dev/null || \
      warn "Could not auto-start borders"
  else
    info "Skipping optional borders service"
    if [[ -f "$BORDERS_SERVICE_PLIST" ]]; then
      launchctl bootout "gui/$(id -u)" "$BORDERS_SERVICE_PLIST" 2>/dev/null && \
        info "  stopped disabled borders service" || true
    fi
  fi

  info "Disabling bar_toggle daemon..."
  launchctl unload "$BAR_TOGGLE_PLIST" 2>/dev/null || true
  rm -f "$BAR_TOGGLE_PLIST"

  info "Starting chrome_rehome daemon..."
  launchctl unload "$CHROME_REHOME_PLIST" 2>/dev/null || true
  launchctl load "$CHROME_REHOME_PLIST" 2>/dev/null || \
    warn "Could not load chrome_rehome LaunchAgent"

  info "Starting shortcut desktop widget..."
  launchctl unload "$SHORTCUT_WIDGET_PLIST" 2>/dev/null || true
  launchctl load "$SHORTCUT_WIDGET_PLIST" 2>/dev/null || \
    warn "Could not load shortcut desktop widget LaunchAgent"

  success "Services started"
}

stop_services() {
  local mode="${1:-normal}"
  if [[ -f "$AEROSPACE_START_PLIST" ]]; then
    launchctl unload "$AEROSPACE_START_PLIST" 2>/dev/null && info "  stopped AeroSpace login starter" || true
  fi
  if [[ -f "$WINDOW_STATE_SAVER_PLIST" ]]; then
    launchctl unload "$WINDOW_STATE_SAVER_PLIST" 2>/dev/null && info "  stopped window state saver" || true
  fi
  if [[ -f "$BAR_TOGGLE_PLIST" ]]; then
    launchctl unload "$BAR_TOGGLE_PLIST" 2>/dev/null && info "  stopped bar_toggle" || true
  fi
  if [[ -f "$CHROME_REHOME_PLIST" ]]; then
    launchctl unload "$CHROME_REHOME_PLIST" 2>/dev/null && info "  stopped chrome_rehome" || true
  fi
  if [[ -f "$SHORTCUT_WIDGET_PLIST" ]]; then
    launchctl unload "$SHORTCUT_WIDGET_PLIST" 2>/dev/null && info "  stopped shortcut widget" || true
  fi
  if borders_enabled || [[ "$mode" == "revert" ]]; then
    stop_brew_service borders
  elif [[ -f "$BORDERS_SERVICE_PLIST" ]]; then
    launchctl bootout "gui/$(id -u)" "$BORDERS_SERVICE_PLIST" 2>/dev/null && \
      info "  stopped disabled borders service" || true
  fi
  local services=(sketchybar aerospace)
  for svc in "${services[@]}"; do
    stop_brew_service "$svc"
  done
  skhd --stop-service 2>/dev/null && info "  stopped skhd" || true
  success "Services stopped"
}

stop_brew_service() {
  local svc="$1"
  if brew services list | grep -q "^$svc"; then
    brew services stop "$svc" 2>/dev/null && info "  stopped $svc" || true
  fi
}

check_service() {
  local name="$1"
  local status
  status=$(brew services list 2>/dev/null | awk -v n="$name" '$1==n {print $2}')
  if [[ "$status" == "started" ]]; then
    echo -e "  ${GREEN}●${RESET} $name — running"
  elif [[ -n "$status" ]]; then
    echo -e "  ${YELLOW}●${RESET} $name — $status"
  else
    echo -e "  ${RED}○${RESET} $name — not found"
  fi
}

check_launch_agent() {
  local label="$1"
  if launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1; then
    echo -e "  ${GREEN}●${RESET} $label — loaded"
  else
    echo -e "  ${YELLOW}●${RESET} $label — not loaded"
  fi
}

check_aerospace_app() {
  if aerospace list-monitors --format '%{monitor-id}' >/dev/null 2>&1; then
    echo -e "  ${GREEN}●${RESET} AeroSpace — server reachable"
  elif launchctl print "gui/$(id -u)" 2>/dev/null | grep -q "application.bobko.aerospace"; then
    echo -e "  ${YELLOW}●${RESET} AeroSpace — app running, server unreachable"
  else
    echo -e "  ${RED}○${RESET} AeroSpace — not running"
  fi
}

check_window_state() {
  if [[ ! -f "$WINDOW_STATE_FILE" ]]; then
    warn "No saved window state found — run './install.sh save-window-state' or wait for the periodic saver"
    return 0
  fi

  local summary
  summary=$(/usr/bin/perl -MJSON::PP -0777 -e '
    my $data = eval { decode_json(<>); } || {};
    my $count = ref($data->{windows}) eq "ARRAY" ? scalar(@{$data->{windows}}) : 0;
    my $topologies = ref($data->{snapshots}) eq "HASH" ? scalar(keys %{$data->{snapshots}}) : 0;
    my $saved = $data->{saved_at} || "unknown time";
    print "$count windows saved at $saved";
    print " across $topologies topologies" if $topologies;
  ' "$WINDOW_STATE_FILE" 2>/dev/null) || summary="unreadable saved state"
  success "Window state: $summary"
  echo "    $WINDOW_STATE_FILE"
}

check_tool() {
  local name="$1" installed="$2"
  if [[ "$installed" == "yes" ]]; then
    echo -e "  ${GREEN}✓${RESET} $name installed"
  else
    echo -e "  ${RED}✗${RESET} $name not installed"
  fi
}

# =============================================================================
# AEROSPACE CONFIG
# =============================================================================
workspace_force_assignment_toml() {
  local rows line monitor_id monitor_name
  rows=$(aerospace list-monitors --format '%{monitor-id}|%{monitor-name}' 2>/dev/null || true)

  local external_ids=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    monitor_id="${line%%|*}"
    monitor_name="${line#*|}"
    [ -n "$monitor_id" ] || continue
    if [[ ! "$monitor_name" =~ [Bb]uilt.?in ]]; then
      external_ids+=("$monitor_id")
    fi
  done <<< "$rows"

  local slot key monitor_pattern fallback_pattern
  printf '[workspace-to-monitor-force-assignment]\n'
  for slot in 1 2 3; do
    monitor_pattern="${external_ids[$((slot - 1))]:-$((slot + 1))}"
    fallback_pattern="$monitor_pattern"
    [ "$slot" = "1" ] && fallback_pattern="secondary"
    for key in 0 1 2 3 4 5 6 7 8 9; do
      if [ "$fallback_pattern" = "$monitor_pattern" ]; then
        printf '"%s%s" = ["%s", "built-in", "main"]\n' "$slot" "$key" "$monitor_pattern"
      else
        printf '"%s%s" = ["%s", "%s", "built-in", "main"]\n' "$slot" "$key" "$fallback_pattern" "$monitor_pattern"
      fi
    done
  done
}

write_aerospace_config() {
  info "Writing Aerospace config..."

  local workspace_force_assignments
  workspace_force_assignments=$(workspace_force_assignment_toml)

  cat > "$AEROSPACE_CFG" << AEROSPACE_EOF
# =============================================================================
# Aerospace — Omarchy-style tiling window manager config
# Modifier key: ⌥ (Option/Alt) — your SUPER key
# Docs: https://nikitabobko.github.io/AeroSpace/guide
# =============================================================================

# ── Behavior ──────────────────────────────────────────────────────────────────
after-startup-command = ['exec-and-forget ~/.config/aerospace/startup_restore.sh']

# Start Aerospace on login
start-at-login = true

# Remap Option keys so macOS doesn't swallow ⌥+key as special characters
key-mapping.preset = 'qwerty'

# Normalisation: flatten nested containers (keeps tree clean)
enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

# ── Workspace monitor assignment ──────────────────────────────────────────
# AeroSpace assigns empty workspaces to the main monitor by default. External
# slot assignments make 10-39 native to up to three external displays without
# forcing the built-in display back to a default slot-0 workspace.
${workspace_force_assignments}

# ── Appearance ─────────────────────────────────────────────────────────────
[gaps]
inner.horizontal = 8    # gap between tiled windows
inner.vertical   = 8
outer.left       = 8    # gap from screen edge
outer.bottom     = 8
outer.top        = 8    # SketchyBar floats on demand, no reserved space needed
outer.right      = 8

# ── Default layout ─────────────────────────────────────────────────────────
[mode.main.binding]

# ── Workspace switching: ⌥ + 0-9 ─────────────────────────────────────────
# Per-monitor spaces: key N resolves to workspace "<monitor-slot>N".
# The built-in display is slot 0 when present; external displays follow it.
# See goto_space.sh.
alt-1 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 1'
alt-2 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 2'
alt-3 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 3'
alt-4 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 4'
alt-5 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 5'
alt-6 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 6'
alt-7 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 7'
alt-8 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 8'
alt-9 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 9'
alt-0 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 0'

# ── Move window to workspace: ⌥ + Shift + 0-9 ────────────────────────────
alt-shift-1 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 1 --move'
alt-shift-2 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 2 --move'
alt-shift-3 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 3 --move'
alt-shift-4 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 4 --move'
alt-shift-5 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 5 --move'
alt-shift-6 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 6 --move'
alt-shift-7 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 7 --move'
alt-shift-8 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 8 --move'
alt-shift-9 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 9 --move'
alt-shift-0 = 'exec-and-forget ~/.config/aerospace/goto_space.sh 0 --move'

# ── Focus: ⌥ + h/j/k/l ───────────────────────────────────────────────────
# (mirrors Hyprland: SUPER + h/j/k/l)
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'

# ── Window overview: ⌥ + Up ──────────────────────────────────────────────
alt-up = 'exec-and-forget ~/.config/aerospace/window_picker.sh'

# ── Move window: ⌥ + Shift + h/j/k/l ─────────────────────────────────────
# (mirrors Hyprland: SUPER + SHIFT + h/j/k/l)
alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'

# ── Resize: ⌥ + Ctrl + h/j/k/l ───────────────────────────────────────────
# (mirrors Hyprland: SUPER + ALT + h/j/k/l)
alt-ctrl-h = 'resize width -50'
alt-ctrl-l = 'resize width +50'
alt-ctrl-k = 'resize height -50'
alt-ctrl-j = 'resize height +50'

# ── Layout toggles ────────────────────────────────────────────────────────
# ⌥ + e → toggle split direction (horizontal/vertical)
alt-e = 'layout tiles horizontal vertical'

# ⌥ + s → toggle accordion (stacked) layout
alt-s = 'layout accordion horizontal vertical'

# ⌥ + f → fullscreen toggle
# (mirrors Hyprland: SUPER + F)
alt-f = 'fullscreen'

# ⌥ + shift + space → toggle float for focused window
# (mirrors Hyprland: SUPER + V)
alt-shift-space = 'layout floating tiling'

# ── Window management ─────────────────────────────────────────────────────
# ⌥ + shift + q → close focused window
# (mirrors Hyprland: SUPER + Q)
alt-shift-q = 'close'

# ⌥ + shift + r → reload config
alt-shift-r = 'reload-config'

# ── Workspace cycle ───────────────────────────────────────────────────────
# ⌥ + tab → next workspace
# ⌥ + shift + tab → previous workspace
alt-tab       = 'exec-and-forget ~/.config/aerospace/workspace_back_and_forth.sh'
alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'
alt-ctrl-tab = 'exec-and-forget ~/.config/aerospace/window_cycle.sh next'
alt-ctrl-shift-tab = 'exec-and-forget ~/.config/aerospace/window_cycle.sh prev'

# ── Move to next/prev monitor ─────────────────────────────────────────────
alt-ctrl-shift-h = 'exec-and-forget ~/.config/aerospace/move_node_to_monitor_and_save.sh left'
alt-ctrl-shift-l = 'exec-and-forget ~/.config/aerospace/move_node_to_monitor_and_save.sh right'

# ── App → workspace assignments ───────────────────────────────────────────

[[on-window-detected]]
run = [
  'exec-and-forget ~/.config/aerospace/window_state_debounced_save.sh window-detected',
  'exec-and-forget ~/.config/aerospace/responsive_layout.sh window-detected'
]
check-further-callbacks = true

# App-assignment rules default to monitor 0's spaces ("0N"). If a second
# monitor is attached, move the app to <monitor><N> manually after launch.
[[on-window-detected]]
if.app-name-regex-substring = 'Messages'
run = ['move-node-to-workspace 02', 'workspace 02']

[[on-window-detected]]
if.app-name-regex-substring = 'Signal'
run = ['move-node-to-workspace 02', 'workspace 02']

[[on-window-detected]]
if.app-name-regex-substring = 'Google Chat'
run = ['move-node-to-workspace 02', 'workspace 02']

[[on-window-detected]]
if.app-name-regex-substring = 'Spotify|Music'
run = ['move-node-to-workspace 03', 'workspace 03']

[[on-window-detected]]
if.app-name-regex-substring = 'Ghostty|WezTerm|Warp|iTerm2'
run = ['move-node-to-workspace 04', 'workspace 04']

[[on-window-detected]]
if.app-name-regex-substring = 'Zed|Antigravity'
run = ['move-node-to-workspace 05', 'workspace 05']

[[on-window-detected]]
if.app-id = 'com.anthropic.claudefordesktop'
run = ['move-node-to-workspace 06', 'workspace 06']

[[on-window-detected]]
if.app-id = 'com.google.GeminiMacOS'
run = ['move-node-to-workspace 06', 'workspace 06']

[[on-window-detected]]
if.app-id = 'com.openai.chat'
run = ['move-node-to-workspace 06', 'workspace 06']

[[on-window-detected]]
if.app-name-regex-substring = 'ChatGPT'
run = ['move-node-to-workspace 06', 'workspace 06']

[[on-window-detected]]
if.app-name-regex-substring = 'Steam'
run = ['move-node-to-workspace 00', 'workspace 00']

# Keep authentication prompts and password dialogs visible on the current
# workspace. AeroSpace cannot force true "always on top", but floating and
# avoiding fallback rehoming prevents these dialogs from blinking away to 00.
[[on-window-detected]]
if.app-name-regex-substring = '1Password'
run = ['layout floating']

# [[on-window-detected]]
# if.app-name-regex-substring = 'slack|discord'
# run = 'move-node-to-workspace 8'
AEROSPACE_EOF

  success "Aerospace config written to $AEROSPACE_CFG"
}

# =============================================================================
# SPACE STATE HELPER
# Shared workspace/monitor helpers for Aerospace and SketchyBar scripts.
# =============================================================================
write_space_state_helper() {
  info "Writing space state helper..."
  mkdir -p "$AEROSPACE_DIR"

  cat > "$AEROSPACE_DIR/omarchy_space_state.sh" << 'SPACE_STATE_EOF'
#!/usr/bin/env bash
# Shared helpers for monitor-scoped workspace names.
#
# Workspace names are "${slot}${key}" where slot is the focused monitor's
# stable Omarchy slot. The built-in display is slot 0 when present, followed by
# external displays in AeroSpace's order. This deliberately does not use
# "monitor-id - 1": after unplug/replug macOS and AeroSpace may keep assigning
# non-1 monitor ids even when only one physical display remains.

OMARCHY_AEROSPACE_BIN="${OMARCHY_AEROSPACE_BIN:-aerospace}"

omarchy_aerospace_available() {
  "$OMARCHY_AEROSPACE_BIN" list-monitors --format '%{monitor-id}' >/dev/null 2>&1
}

omarchy_monitor_rows_by_slot() {
  local rows line monitor_id monitor_name
  rows=$("$OMARCHY_AEROSPACE_BIN" list-monitors --format '%{monitor-id}|%{monitor-name}|%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null) || return 1

  local built_in_rows=()
  local external_rows=()
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    monitor_id="${line%%|*}"
    line="${line#*|}"
    monitor_name="${line%%|*}"
    [ -n "$monitor_id" ] || continue
    if [[ "$monitor_name" =~ [Bb]uilt.?in ]]; then
      built_in_rows+=("$monitor_id|$line")
    else
      external_rows+=("$monitor_id|$line")
    fi
  done <<< "$rows"

  if ((${#built_in_rows[@]})); then
    printf '%s\n' "${built_in_rows[@]}"
  fi
  if ((${#external_rows[@]})); then
    printf '%s\n' "${external_rows[@]}"
  fi
}

omarchy_monitor_ids_by_slot() {
  local row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    printf '%s\n' "${row%%|*}"
  done < <(omarchy_monitor_rows_by_slot)
}

omarchy_sketchybar_display_for_slot() {
  local target_slot="$1"
  [[ "$target_slot" =~ ^[0-9]+$ ]] || return 1

  local target_monitor_id
  target_monitor_id=$(omarchy_monitor_id_for_slot "$target_slot") || return 1

  # SketchyBar display ids are not AeroSpace monitor ids. On the observed
  # dynamic topology they are the built-in display first, then externals in
  # reverse Omarchy/AeroSpace external order.
  local rows line monitor_id rest monitor_name built_in_count external_count external_index=0
  rows=$(omarchy_monitor_rows_by_slot) || return 1
  built_in_count=$(printf '%s\n' "$rows" | awk -F'|' '$2 ~ /[Bb]uilt.?in/ { count++ } END { print count+0 }')
  external_count=$(printf '%s\n' "$rows" | awk -F'|' '$2 !~ /[Bb]uilt.?in/ { count++ } END { print count+0 }')
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    monitor_id="${line%%|*}"
    rest="${line#*|}"
    monitor_name="${rest%%|*}"
    if [ "$monitor_id" = "$target_monitor_id" ]; then
      if [[ "$monitor_name" =~ [Bb]uilt.?in ]]; then
        printf '1\n'
      else
        printf '%s\n' $((built_in_count + external_count - external_index))
      fi
      return 0
    fi
    if ! [[ "$monitor_name" =~ [Bb]uilt.?in ]]; then
      external_index=$((external_index + 1))
    fi
  done <<< "$rows"

  return 1
}

omarchy_slot_for_monitor_id() {
  local target_id="$1"
  [ -n "$target_id" ] || return 1

  local slot=0 monitor_id
  while IFS= read -r monitor_id; do
    [ -n "$monitor_id" ] || continue
    if [ "$monitor_id" = "$target_id" ]; then
      printf '%s\n' "$slot"
      return 0
    fi
    slot=$((slot + 1))
  done < <(omarchy_monitor_ids_by_slot)

  return 1
}

omarchy_focused_monitor_slot() {
  local focused_id
  focused_id=$("$OMARCHY_AEROSPACE_BIN" list-monitors --focused --format '%{monitor-id}' 2>/dev/null | head -n 1) || return 1
  [ -n "$focused_id" ] || return 1

  omarchy_slot_for_monitor_id "$focused_id"
}

omarchy_mouse_monitor_slot() {
  local mouse_id
  mouse_id=$("$OMARCHY_AEROSPACE_BIN" list-monitors --mouse --format '%{monitor-id}' 2>/dev/null | head -n 1) || return 1
  [ -n "$mouse_id" ] || return 1

  omarchy_slot_for_monitor_id "$mouse_id"
}

omarchy_monitor_id_for_slot() {
  local target_slot="$1"
  [[ "$target_slot" =~ ^[0-9]+$ ]] || return 1

  local slot=0 monitor_id
  while IFS= read -r monitor_id; do
    [ -n "$monitor_id" ] || continue
    if [ "$slot" = "$target_slot" ]; then
      printf '%s\n' "$monitor_id"
      return 0
    fi
    slot=$((slot + 1))
  done < <(omarchy_monitor_ids_by_slot)

  return 1
}

omarchy_normalize_workspace_for_slot() {
  local workspace="$1"
  local slot="$2"
  if [[ "$workspace" =~ ^[0-9][0-9]$ ]]; then
    printf '%s\n' "$workspace"
  elif [[ "$workspace" =~ ^[0-9]$ ]] && [[ "$slot" =~ ^[0-9]+$ ]]; then
    printf '%s%s\n' "$slot" "$workspace"
  else
    return 1
  fi
}

omarchy_normalize_focused_workspace() {
  local workspace="$1"
  local slot
  if [[ "$workspace" =~ ^[0-9][0-9]$ ]]; then
    printf '%s\n' "$workspace"
    return 0
  fi
  [[ "$workspace" =~ ^[0-9]$ ]] || return 1
  slot=$(omarchy_focused_monitor_slot) || return 1
  printf '%s%s\n' "$slot" "$workspace"
}

omarchy_focused_workspace() {
  "$OMARCHY_AEROSPACE_BIN" list-workspaces --focused 2>/dev/null | head -n 1
}

omarchy_workspace_for_key() {
  local key="$1"
  local slot
  slot=$(omarchy_mouse_monitor_slot 2>/dev/null || omarchy_focused_monitor_slot) || return 1
  printf '%s%s\n' "$slot" "$key"
}

omarchy_switch_workspace_on_slot_monitor() {
  local workspace="$1"
  [[ "$workspace" =~ ^[0-9][0-9]$ ]] || return 1

  local slot monitor_id other_monitor visible_workspace
  local restore_workspaces=()
  slot="${workspace:0:1}"
  monitor_id=$(omarchy_monitor_id_for_slot "$slot") || return 1

  if [ "$slot" != "0" ]; then
    while IFS= read -r other_monitor; do
      [ -n "$other_monitor" ] || continue
      [ "$other_monitor" != "$monitor_id" ] || continue
      visible_workspace=$("$OMARCHY_AEROSPACE_BIN" list-workspaces --monitor "$other_monitor" --visible --format '%{workspace}' 2>/dev/null | head -n 1)
      [ -n "$visible_workspace" ] || continue
      [ "$visible_workspace" != "$workspace" ] || continue
      restore_workspaces+=("$visible_workspace")
    done < <(omarchy_monitor_ids_by_slot)
  fi

  "$OMARCHY_AEROSPACE_BIN" workspace "$workspace"

  if ((${#restore_workspaces[@]})); then
    for visible_workspace in "${restore_workspaces[@]}"; do
      "$OMARCHY_AEROSPACE_BIN" workspace "$visible_workspace" >/dev/null 2>&1 || true
    done
  fi

  "$OMARCHY_AEROSPACE_BIN" focus-monitor "$monitor_id" >/dev/null 2>&1 || true
  "$OMARCHY_AEROSPACE_BIN" move-mouse monitor-lazy-center >/dev/null 2>&1 || true
  sleep 0.05
}

omarchy_attached_monitor_count() {
  local count
  count=$("$OMARCHY_AEROSPACE_BIN" list-monitors --format '%{monitor-id}' 2>/dev/null | awk 'NF{count++} END{print count+0}') || return 1
  [ "$count" -gt 0 ] || return 1
  printf '%s\n' "$count"
}

omarchy_is_active_slot() {
  local slot="$1"
  local count
  count=$(omarchy_attached_monitor_count) || return 1
  [[ "$slot" =~ ^[0-9]+$ ]] || return 1
  [ "$slot" -lt "$count" ]
}

omarchy_repair_detached_monitor_workspaces() {
  local count
  count=$(omarchy_attached_monitor_count) || return 1

  local monitor_id legacy_slot visible_workspace legacy_target legacy_windows legacy_window_id visible_slot visible_monitor_id
  legacy_slot=0
  while IFS= read -r monitor_id; do
    [ -n "$monitor_id" ] || continue
    visible_workspace=$("$OMARCHY_AEROSPACE_BIN" list-workspaces --monitor "$monitor_id" --visible --format '%{workspace}' 2>/dev/null | head -n 1) || true
    if [[ "$visible_workspace" =~ ^[0-9]$ ]]; then
      legacy_target="${legacy_slot}${visible_workspace}"
      legacy_windows=$("$OMARCHY_AEROSPACE_BIN" list-windows --workspace "$visible_workspace" --format '%{window-id}' 2>/dev/null) || legacy_windows=""
      while IFS= read -r legacy_window_id; do
        [[ "$legacy_window_id" =~ ^[0-9]+$ ]] || continue
        "$OMARCHY_AEROSPACE_BIN" move-node-to-workspace --window-id "$legacy_window_id" "$legacy_target" >/dev/null 2>&1 || true
      done <<< "$legacy_windows"
      "$OMARCHY_AEROSPACE_BIN" move-workspace-to-monitor --workspace "$legacy_target" "$monitor_id" >/dev/null 2>&1 || true
      "$OMARCHY_AEROSPACE_BIN" focus-monitor "$monitor_id" >/dev/null 2>&1 || true
      "$OMARCHY_AEROSPACE_BIN" workspace "$legacy_target" >/dev/null 2>&1 || true
      "$OMARCHY_AEROSPACE_BIN" focus-monitor "$monitor_id" >/dev/null 2>&1 || true
    elif [[ "$visible_workspace" =~ ^[0-9][0-9]$ ]]; then
      visible_slot="${visible_workspace:0:1}"
      if [ "$visible_slot" != "$legacy_slot" ]; then
        visible_monitor_id=$(omarchy_monitor_id_for_slot "$visible_slot" 2>/dev/null || true)
        if [ -n "$visible_monitor_id" ]; then
          "$OMARCHY_AEROSPACE_BIN" move-workspace-to-monitor --workspace "$visible_workspace" "$visible_monitor_id" >/dev/null 2>&1 || true
        fi
        legacy_target="${legacy_slot}${visible_workspace:1:1}"
        "$OMARCHY_AEROSPACE_BIN" move-workspace-to-monitor --workspace "$legacy_target" "$monitor_id" >/dev/null 2>&1 || true
        "$OMARCHY_AEROSPACE_BIN" focus-monitor "$monitor_id" >/dev/null 2>&1 || true
        "$OMARCHY_AEROSPACE_BIN" workspace "$legacy_target" >/dev/null 2>&1 || true
        "$OMARCHY_AEROSPACE_BIN" focus-monitor "$monitor_id" >/dev/null 2>&1 || true
      fi
    fi
    legacy_slot=$((legacy_slot + 1))
  done < <(omarchy_monitor_ids_by_slot)

  local rows line window_id workspace slot key target
  rows=$("$OMARCHY_AEROSPACE_BIN" list-windows --all --format '%{window-id}|%{workspace}' 2>/dev/null) || return 1
  while IFS= read -r line; do
    IFS='|' read -r window_id workspace <<< "$line"
    [[ "$window_id" =~ ^[0-9]+$ ]] || continue
    [[ "$workspace" =~ ^[0-9][0-9]$ ]] || continue

    slot="${workspace:0:1}"
    key="${workspace:1:1}"
    if [ "$slot" -ge "$count" ]; then
      target="0${key}"
      [ "$target" = "$workspace" ] && continue
      "$OMARCHY_AEROSPACE_BIN" move-node-to-workspace --window-id "$window_id" "$target" >/dev/null 2>&1 || true
    fi
  done <<< "$rows"
}

omarchy_assigned_workspace_for_app() {
  local app_name="$1"
  local bundle_id="$2"

  case "$app_name" in
    *Mail*) printf '01\n'; return 0 ;;
    *Messages*|*Signal*|*Google\ Chat*) printf '02\n'; return 0 ;;
    *Spotify*|*Music*) printf '03\n'; return 0 ;;
    *Ghostty*|*WezTerm*|*Warp*|*iTerm2*) printf '04\n'; return 0 ;;
    *Zed*|*Antigravity*) printf '05\n'; return 0 ;;
    *ChatGPT*) printf '06\n'; return 0 ;;
    *Steam*) printf '00\n'; return 0 ;;
  esac

  case "$bundle_id" in
    com.anthropic.claudefordesktop|com.google.GeminiMacOS|com.openai.chat)
      printf '06\n'
      return 0
      ;;
  esac

  return 1
}

omarchy_repair_app_assigned_workspaces() {
  local rows line window_id workspace app_name bundle_id target
  rows=$("$OMARCHY_AEROSPACE_BIN" list-windows --all --format '%{window-id}|%{workspace}|%{app-name}|%{app-bundle-id}' 2>/dev/null) || return 1
  while IFS= read -r line; do
    IFS='|' read -r window_id workspace app_name bundle_id <<< "$line"
    [[ "$window_id" =~ ^[0-9]+$ ]] || continue
    target=$(omarchy_assigned_workspace_for_app "$app_name" "$bundle_id" 2>/dev/null) || continue
    [ "$workspace" = "$target" ] && continue
    "$OMARCHY_AEROSPACE_BIN" move-node-to-workspace --window-id "$window_id" "$target" >/dev/null 2>&1 || true
  done <<< "$rows"
}
SPACE_STATE_EOF

  chmod +x "$AEROSPACE_DIR/omarchy_space_state.sh"

  cat > "$MONITOR_FRAME_SRC" << 'MONITOR_FRAME_SWIFT_EOF'
import AppKit

guard CommandLine.arguments.count > 1,
      let target = UInt32(CommandLine.arguments[1]) else {
    exit(1)
}

for screen in NSScreen.screens {
    guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        continue
    }
    if number.uint32Value == target {
        let frame = screen.visibleFrame
        print("\(Int(frame.width))|\(Int(frame.height))|\(screen.localizedName)")
        exit(0)
    }
}

exit(1)
MONITOR_FRAME_SWIFT_EOF

  if command -v swiftc &>/dev/null; then
    swiftc -O "$MONITOR_FRAME_SRC" -o "$MONITOR_FRAME_BIN" 2>/dev/null || \
      warn "Could not compile monitor_frame helper; responsive layout will use fallback widths"
    [[ -x "$MONITOR_FRAME_BIN" ]] && chmod +x "$MONITOR_FRAME_BIN"
  else
    warn "swiftc not found — responsive layout will use fallback monitor widths"
  fi

  cat > "$RESPONSIVE_LAYOUT_HELPER" << 'RESPONSIVE_LAYOUT_EOF'
#!/usr/bin/env bash
# Switch crowded narrow workspaces to accordion before split columns become
# too small to use. Intended for laptop displays and narrow external monitors.

set -euo pipefail

source "$HOME/.config/aerospace/omarchy_space_state.sh"

MIN_TILE_WIDTH="${OMARCHY_LAYOUT_MIN_TILE_WIDTH:-640}"
MONITOR_FRAME_BIN="${OMARCHY_MONITOR_FRAME_BIN:-$HOME/.config/aerospace/monitor_frame}"
LAYOUT_GUARD_DELAY="${OMARCHY_LAYOUT_GUARD_DELAY:-0.2}"
REASON="${1:-event}"

sleep "$LAYOUT_GUARD_DELAY" 2>/dev/null || true

focused_monitor_width() {
  local row screen_id monitor_name width fallback_width
  row=$("$OMARCHY_AEROSPACE_BIN" list-monitors --focused --format '%{monitor-appkit-nsscreen-screens-id}|%{monitor-name}' 2>/dev/null | head -n 1) || true
  screen_id="${row%%|*}"
  monitor_name="${row#*|}"

  if [[ -x "$MONITOR_FRAME_BIN" && "$screen_id" =~ ^[0-9]+$ ]]; then
    width=$("$MONITOR_FRAME_BIN" "$screen_id" 2>/dev/null | awk -F'|' 'NR == 1 { print int($1) }') || true
    if [[ "$width" =~ ^[0-9]+$ ]] && [ "$width" -gt 0 ]; then
      printf '%s\n' "$width"
      return 0
    fi
  fi

  fallback_width="${OMARCHY_LAYOUT_FALLBACK_WIDTH:-}"
  if [[ "$fallback_width" =~ ^[0-9]+$ ]] && [ "$fallback_width" -gt 0 ]; then
    printf '%s\n' "$fallback_width"
    return 0
  fi

  if [[ "$monitor_name" =~ [Bb]uilt.?in ]]; then
    printf '1512\n'
  else
    printf '2560\n'
  fi
}

workspace=$(omarchy_focused_workspace 2>/dev/null || true)
[[ -n "$workspace" ]] || exit 0

count=$("$OMARCHY_AEROSPACE_BIN" list-windows --workspace "$workspace" --count 2>/dev/null || true)
count="$(printf '%s' "$count" | tr -cd '0-9')"
[[ "$count" =~ ^[0-9]+$ ]] || exit 0
[ "$count" -gt 1 ] || exit 0

width=$(focused_monitor_width)
[[ "$width" =~ ^[0-9]+$ ]] || exit 0

usable_width=$((width - 16 - ((count - 1) * 8)))
[ "$usable_width" -gt 0 ] || usable_width="$width"
per_window=$((usable_width / count))

if [ "$per_window" -lt "$MIN_TILE_WIDTH" ]; then
  "$OMARCHY_AEROSPACE_BIN" layout accordion horizontal vertical >/dev/null 2>&1 || true
fi

printf '[%s] responsive layout checked (%s): workspace=%s windows=%s width=%s per_window=%s threshold=%s\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$REASON" "$workspace" "$count" "$width" "$per_window" "$MIN_TILE_WIDTH" \
  >> "${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}" 2>/dev/null || true
RESPONSIVE_LAYOUT_EOF

  chmod +x "$RESPONSIVE_LAYOUT_HELPER"

  cat > "$AEROSPACE_DIR/repair_spaces.sh" << 'REPAIR_SPACES_EOF'
#!/usr/bin/env bash
# Move windows from detached monitor-prefixed workspaces back to slot 0.

set -euo pipefail

source "$HOME/.config/aerospace/omarchy_space_state.sh"

for _ in {1..30}; do
  if omarchy_aerospace_available; then
    break
  fi
  sleep 1
done

if ! omarchy_aerospace_available; then
  echo "repair_spaces.sh: AeroSpace is not reachable; no spaces were changed" >&2
  exit 1
fi

for _ in {1..6}; do
  omarchy_repair_detached_monitor_workspaces || true
  omarchy_repair_app_assigned_workspaces || true
  sleep 2
done
REPAIR_SPACES_EOF

  chmod +x "$AEROSPACE_DIR/repair_spaces.sh"
  cat > "$AEROSPACE_DIR/startup_restore.sh" << 'STARTUP_RESTORE_EOF'
#!/usr/bin/env bash
# Login/startup repair pass. Detached-monitor repair runs first so rule-based
# placement is sane, then the saved exact layout is replayed when present.

set -euo pipefail

TMP_ROOT="${TMPDIR:-/tmp}"
STARTUP_RESTORE_GUARD="${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_startup_restore_active}"
DEBOUNCED_SAVER="$HOME/.config/aerospace/window_state_debounced_save.sh"

cleanup() {
  rm -f "$STARTUP_RESTORE_GUARD"
  "$DEBOUNCED_SAVER" "post-startup-restore" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '%s\n' "$$" > "$STARTUP_RESTORE_GUARD"
"$HOME/.config/aerospace/repair_spaces.sh" || true
"$HOME/.config/aerospace/window_state.sh" restore || true
"$HOME/.config/aerospace/repair_spaces.sh" || true
STARTUP_RESTORE_EOF

  chmod +x "$AEROSPACE_DIR/startup_restore.sh"
  success "space state helper written to $AEROSPACE_DIR/omarchy_space_state.sh"
}

# =============================================================================
# WINDOW STATE HELPER
# Saves and restores exact app/window/workspace placement for reboot recovery.
# =============================================================================
write_window_state_helper() {
  info "Writing window state helper..."
  mkdir -p "$AEROSPACE_DIR"

  cat > "$WINDOW_STATE_HELPER" << 'WINDOW_STATE_PERL_EOF'
#!/usr/bin/env perl
use strict;
use warnings;

use Encode qw(decode_utf8);
use File::Path qw(make_path);
use JSON::PP qw(decode_json);
use POSIX qw(strftime);

my $home = $ENV{HOME} || "";
my $state_file = $ENV{OMARCHY_WINDOW_STATE_FILE} || "$home/.config/aerospace/omarchy_window_state.json";
my $log_file = $ENV{OMARCHY_WINDOW_STATE_LOG} || "/tmp/omarchy_window_state.log";
my $restore_attempts = $ENV{OMARCHY_WINDOW_RESTORE_ATTEMPTS} || 120;
my $restore_delay = $ENV{OMARCHY_WINDOW_RESTORE_DELAY} || 2;
my $save_wait_attempts = $ENV{OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS} || 60;
my $skip_empty_save = $ENV{OMARCHY_WINDOW_SKIP_EMPTY_SAVE} || 0;
my $tmp_dir = $ENV{TMPDIR} || "/tmp";
my $restore_guard = $ENV{OMARCHY_WINDOW_RESTORE_GUARD} || "$tmp_dir/omarchy_window_state_restore_active";
my $startup_restore_guard = $ENV{OMARCHY_WINDOW_STARTUP_RESTORE_GUARD} || "$tmp_dir/omarchy_window_state_startup_restore_active";
my $partial_restore_guard = $ENV{OMARCHY_WINDOW_PARTIAL_RESTORE_GUARD} || "$tmp_dir/omarchy_window_state_restore_incomplete";
my $debounced_saver = $ENV{OMARCHY_WINDOW_DEBOUNCED_SAVER} || "$home/.config/aerospace/window_state_debounced_save.sh";
my $history_limit = $ENV{OMARCHY_WINDOW_STATE_HISTORY_LIMIT} || 5;
my $sep = "\x1f";
my $format = join($sep,
    "%{window-id}",
    "%{workspace}",
    "%{app-name}",
    "%{app-bundle-id}",
    "%{window-title}",
);

binmode STDOUT, ":encoding(UTF-8)";
binmode STDERR, ":encoding(UTF-8)";

sub aerospace_bin {
    return $ENV{OMARCHY_AEROSPACE_BIN} if $ENV{OMARCHY_AEROSPACE_BIN};
    for my $candidate ("/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace") {
        return $candidate if -x $candidate;
    }
    return "aerospace";
}

my $aerospace = aerospace_bin();

sub timestamp {
    return strftime("%Y-%m-%dT%H:%M:%S%z", localtime);
}

sub log_msg {
    my ($msg) = @_;
    if (open my $fh, ">>", $log_file) {
        binmode $fh, ":encoding(UTF-8)";
        print {$fh} "[" . timestamp() . "] $msg\n";
        close $fh;
    }
}

sub say_and_log {
    my ($msg) = @_;
    print "$msg\n";
    log_msg($msg);
}

sub aerospace_output {
    my (@args) = @_;
    open my $old_stderr, ">&", \*STDERR;
    open STDERR, ">", "/dev/null";
    my $opened = open my $fh, "-|", $aerospace, @args;
    open STDERR, ">&", $old_stderr;
    close $old_stderr;
    return ("", 0) unless $opened;
    local $/;
    my $out = <$fh>;
    close $fh;
    return ($out // "", $? == 0);
}

sub aerospace_ok {
    my (@args) = @_;
    system($aerospace, @args);
    return $? == 0;
}

sub wait_for_aerospace {
    my ($attempts) = @_;
    $attempts ||= 60;
    for my $attempt (1..$attempts) {
        my ($out, $ok) = aerospace_output("list-monitors", "--format", "%{monitor-id}");
        return 1 if $ok && $out =~ /\S/;
        sleep 1;
    }
    return 0;
}

sub monitor_count {
    my ($topology) = @_;
    return scalar(@{$topology->{monitors} || []}) || 1 if $topology;
    my $current = current_topology();
    return scalar(@{$current->{monitors} || []}) || 1;
}

sub monitor_kind {
    my ($name) = @_;
    return ($name || "") =~ /built.?in/i ? "built-in" : "external";
}

sub current_topology {
    my ($out, $ok) = aerospace_output("list-monitors", "--format", join($sep, "%{monitor-id}", "%{monitor-name}"));
    my @rows;
    if ($ok) {
        for my $line (split /\n/, $out) {
            next unless length $line;
            my ($id, $name) = split /\Q$sep\E/, $line, 2;
            next unless defined($id) && length($id);
            $name = decode_utf8($name // "", 1);
            push @rows, { monitor_id => "$id", monitor_name => $name, kind => monitor_kind($name) };
        }
    }
    if (!@rows) {
        my ($ids, $ids_ok) = aerospace_output("list-monitors", "--format", "%{monitor-id}");
        if ($ids_ok) {
            for my $id (grep { /\S/ } split /\n/, $ids) {
                push @rows, { monitor_id => "$id", monitor_name => "monitor-$id", kind => "external" };
            }
        }
    }

    my @ordered = ((grep { $_->{kind} eq "built-in" } @rows), (grep { $_->{kind} ne "built-in" } @rows));
    my @monitors;
    for my $slot (0..$#ordered) {
        my %monitor = %{$ordered[$slot]};
        $monitor{slot} = $slot;
        push @monitors, \%monitor;
    }
    my @parts = map { $_->{slot} . ":" . $_->{kind} . ":" . ($_->{monitor_name} || "") } @monitors;
    my $key = @parts ? join("||", @parts) : "unknown";
    return {
        key => $key,
        monitors => \@monitors,
        slot_names => [ map { $_->{monitor_name} || "" } @monitors ],
        monitor_count => scalar(@monitors) || 1,
    };
}

sub current_windows {
    my ($required) = @_;
    my ($out, $ok) = aerospace_output("list-windows", "--all", "--format", $format);
    die "AeroSpace list-windows failed\n" if !$ok && $required;
    return () unless $ok;

    my @windows;
    for my $line (split /\n/, $out) {
        next unless length $line;
        my @parts = split /\Q$sep\E/, $line, 5;
        next unless @parts >= 5 && $parts[0] =~ /^\d+$/;
        @parts = map { decode_utf8($_ // "", 1) } @parts;
        push @windows, {
            window_id => 0 + $parts[0],
            workspace => $parts[1] // "",
            raw_workspace => $parts[1] // "",
            app_name => $parts[2] // "",
            app_bundle_id => $parts[3] // "",
            title => $parts[4] // "",
        };
    }
    my %identity_seen;
    for my $idx (0..$#windows) {
        $windows[$idx]->{snapshot_order} = $idx;
        my $identity = identity_key($windows[$idx]);
        $windows[$idx]->{identity_order} = $identity_seen{$identity}++;
    }
    return @windows;
}

sub identity_key {
    my ($window) = @_;
    my $app = length($window->{app_bundle_id} || "") ? $window->{app_bundle_id} : ($window->{app_name} || "");
    return join("\x1e", $app, $window->{title} || "");
}

sub assigned_workspace {
    my ($window) = @_;
    my $app = $window->{app_name} || "";
    my $bundle = $window->{app_bundle_id} || "";

    return "02" if $app =~ /Messages|Signal|Google Chat/i;
    return "03" if $app =~ /Spotify|Music/i;
    return "04" if $app =~ /Ghostty|WezTerm|Warp|iTerm2/i;
    return "05" if $app =~ /Zed|Antigravity/i;
    return "06" if $bundle eq "com.anthropic.claudefordesktop";
    return "06" if $bundle eq "com.google.GeminiMacOS";
    return "06" if $bundle eq "com.openai.chat";
    return "06" if $app =~ /ChatGPT/i;
    return "00" if $app =~ /Steam/i;

    return undef;
}

sub prepare_windows_for_save {
    my (@windows) = @_;
    for my $window (@windows) {
        $window->{raw_workspace} = $window->{workspace} || "";
        my $assigned = assigned_workspace($window);
        $window->{target_workspace} = defined($assigned) ? $assigned : ($window->{raw_workspace} || "");
        if (defined($assigned) && ($window->{raw_workspace} || "") ne $assigned) {
            log_msg("recorded rule target for $window->{app_name} / $window->{app_bundle_id}: $window->{raw_workspace} -> $assigned");
        }
    }
    return @windows;
}

sub state_dir {
    my $dir = $state_file;
    $dir =~ s{/[^/]+$}{};
    return $dir;
}

sub read_state {
    open my $fh, "<", $state_file or return undef;
    local $/;
    my $json = <$fh>;
    close $fh;
    return eval { decode_json($json) };
}

sub write_state {
    my ($state) = @_;
    make_path(state_dir());
    my $json = JSON::PP->new->ascii->pretty->canonical->encode($state);
    my $tmp = "$state_file.tmp.$$";
    open my $fh, ">", $tmp or die "Could not write $tmp: $!\n";
    print {$fh} $json;
    close $fh or die "Could not close $tmp: $!\n";
    rename $tmp, $state_file or die "Could not replace $state_file: $!\n";
}

sub save_state {
    my ($mode, $reason) = @_;
    $mode ||= "manual";
    $reason ||= $mode;
    if (-e $restore_guard || -e $startup_restore_guard) {
        say_and_log("Restore is active; skipped window state save ($mode: $reason)");
        return 0;
    }
    if ($mode eq "auto" && -e $partial_restore_guard) {
        say_and_log("Previous restore is incomplete; skipped automatic window state save ($mode: $reason)");
        return 0;
    }
    unlink $partial_restore_guard if $mode ne "auto";
    wait_for_aerospace($save_wait_attempts) or die "AeroSpace is not reachable; cannot save window state\n";
    my $topology = current_topology();
    my @windows = prepare_windows_for_save(current_windows(1));
    if ($skip_empty_save && !@windows && -f $state_file) {
        say_and_log("No windows found; leaving existing window state at $state_file");
        return 0;
    }

    my $existing = read_state();
    my $snapshots = {};
    if ($existing && ($existing->{format_version} || 1) == 2 && ref($existing->{snapshots}) eq "HASH") {
        $snapshots = $existing->{snapshots};
    }

    my $key = $topology->{key};
    my $previous = $snapshots->{$key};
    my @history = ref($previous->{history}) eq "ARRAY" ? @{$previous->{history}} : ();
    if ($previous && ref($previous->{windows}) eq "ARRAY") {
        unshift @history, {
            saved_at => $previous->{saved_at} || "unknown time",
            windows => $previous->{windows},
        };
        splice @history, $history_limit if @history > $history_limit;
    }

    $snapshots->{$key} = {
        format_version => 2,
        saved_at => timestamp(),
        save_mode => $mode,
        save_reason => $reason,
        topology => $topology,
        windows => \@windows,
        history => \@history,
    };

    my $state = {
        format_version => 2,
        saved_at => $snapshots->{$key}->{saved_at},
        current_topology_key => $key,
        topology => $topology,
        windows => \@windows,
        snapshots => $snapshots,
    };
    write_state($state);

    say_and_log("Saved " . scalar(@windows) . " windows for topology $key to $state_file ($mode: $reason)");
}

sub target_workspace_v1 {
    my ($workspace, $count) = @_;
    return "" unless defined $workspace && length $workspace;
    if ($workspace =~ /^([0-9])([0-9])$/ && $1 >= $count) {
        return "0$2";
    }
    return $workspace;
}

sub remap_workspace {
    my ($workspace, $snapshot_topology, $current_topology) = @_;
    return "" unless defined $workspace && length $workspace;
    return "0$workspace" if $workspace =~ /^[0-9]$/;
    return $workspace unless $workspace =~ /^([0-9])([0-9])$/;

    my ($saved_slot, $key) = ($1, $2);
    my $current_count = monitor_count($current_topology);
    my $saved_names = $snapshot_topology->{slot_names} || [];
    my $current_names = $current_topology->{slot_names} || [];
    my $saved_name = $saved_names->[$saved_slot] // "";
    if (length $saved_name) {
        for my $slot (0..$#$current_names) {
            return "$slot$key" if ($current_names->[$slot] // "") eq $saved_name;
        }
    }
    return $workspace if $saved_slot < $current_count;
    return "0$key";
}

sub target_workspace {
    my ($saved, $snapshot, $current_topology, $exact_topology) = @_;
    my $base = assigned_workspace($saved)
        || $saved->{target_workspace}
        || $saved->{workspace}
        || $saved->{raw_workspace}
        || "";
    return "" unless length $base;
    return $base if defined assigned_workspace($saved);

    if (!$snapshot || !ref($snapshot->{topology}) || (($snapshot->{format_version} || 1) < 2 && !ref($snapshot->{topology}))) {
        return target_workspace_v1($base, monitor_count($current_topology));
    }
    return $base if $exact_topology;
    return remap_workspace($base, $snapshot->{topology}, $current_topology);
}

sub same {
    my ($left, $right) = @_;
    return defined($left) && defined($right) && $left eq $right;
}

sub same_identity {
    my ($window, $saved) = @_;
    if (length($saved->{app_bundle_id} || "")) {
        return same($window->{app_bundle_id}, $saved->{app_bundle_id});
    }
    return same($window->{app_name}, $saved->{app_name});
}

sub find_match {
    my ($saved, $current, $used) = @_;

    for my $window (@{$current}) {
        next if $used->{$window->{window_id}};
        next unless same($window->{window_id}, $saved->{window_id});
        next unless same_identity($window, $saved);
        return $window;
    }

    for my $mode ("bundle-title", "name-title") {
        for my $window (@{$current}) {
            next if $used->{$window->{window_id}};
            next unless same($window->{title}, $saved->{title});
            if ($mode eq "bundle-title") {
                next unless length($saved->{app_bundle_id} || "");
                next unless same($window->{app_bundle_id}, $saved->{app_bundle_id});
            } else {
                next unless same($window->{app_name}, $saved->{app_name});
            }
            return $window;
        }
    }

    if (defined assigned_workspace($saved)) {
        for my $window (@{$current}) {
            next if $used->{$window->{window_id}};
            next unless same_identity($window, $saved);
            return $window;
        }
    }

    my @identity_matches = grep {
        !$used->{$_->{window_id}} && same_identity($_, $saved)
    } @{$current};
    return $identity_matches[0] if @identity_matches == 1;

    return undef;
}

sub ordinary_chrome {
    my ($window) = @_;
    return 0 unless ($window->{app_bundle_id} || "") eq "com.google.Chrome";
    return 0 unless ($window->{app_name} || "") =~ /^Google Chrome$/i;
    return 1;
}

sub topology_score {
    my ($snapshot, $current) = @_;
    return -1 unless $snapshot && ref($snapshot->{topology}) eq "HASH";
    return 10_000 if ($snapshot->{topology}->{key} || "") eq ($current->{key} || "");

    my $score = 0;
    my $snapshot_names = $snapshot->{topology}->{slot_names} || [];
    my $current_names = $current->{slot_names} || [];
    my %current_name = map { ($_ => 1) } grep { length } @$current_names;
    for my $idx (0..$#$snapshot_names) {
        my $name = $snapshot_names->[$idx] // "";
        next unless length $name;
        $score += 10 if $current_name{$name};
        $score += 20 if defined($current_names->[$idx]) && $current_names->[$idx] eq $name;
    }
    $score -= abs(($snapshot->{topology}->{monitor_count} || scalar(@$snapshot_names)) - ($current->{monitor_count} || scalar(@$current_names)));
    return $score;
}

sub selected_snapshot {
    my ($state, $current_topology) = @_;
    if (($state->{format_version} || 1) == 2 && ref($state->{snapshots}) eq "HASH") {
        my $key = $current_topology->{key};
        if (ref($state->{snapshots}{$key}) eq "HASH" && ref($state->{snapshots}{$key}{windows}) eq "ARRAY") {
            my %snapshot = %{$state->{snapshots}{$key}};
            $snapshot{format_version} = 2;
            return (\%snapshot, 1, "exact topology");
        }

        my ($best_key, $best_score);
        for my $candidate_key (keys %{$state->{snapshots}}) {
            my $snapshot = $state->{snapshots}{$candidate_key};
            next unless ref($snapshot) eq "HASH" && ref($snapshot->{windows}) eq "ARRAY";
            my $score = topology_score($snapshot, $current_topology);
            next if defined($best_score) && $score <= $best_score;
            ($best_key, $best_score) = ($candidate_key, $score);
        }
        if (defined $best_key) {
            my %snapshot = %{$state->{snapshots}{$best_key}};
            $snapshot{format_version} = 2;
            return (\%snapshot, 0, "fallback topology $best_key");
        }
    }

    if (ref($state->{windows}) eq "ARRAY") {
        return ({
            format_version => 1,
            saved_at => $state->{saved_at},
            windows => $state->{windows},
        }, 1, "v1/top-level state");
    }

    return (undef, 0, "no usable snapshot");
}

sub schedule_post_restore_save {
    return unless -x $debounced_saver;
    my $pid = fork();
    return unless defined $pid && $pid == 0;
    exec($debounced_saver, "post-restore");
    exit 0;
}

sub restore_state_inner {
    unless (-f $state_file) {
        say_and_log("No saved window state at $state_file; skipping exact restore");
        return 1;
    }
    wait_for_aerospace(60) or die "AeroSpace is not reachable; cannot restore window state\n";

    my $state = read_state();
    die "Could not parse $state_file\n" unless $state;

    my $current_topology = current_topology();
    my ($snapshot, $exact_topology, $selection_reason) = selected_snapshot($state, $current_topology);
    die "No usable window snapshot in $state_file\n" unless $snapshot && ref($snapshot->{windows}) eq "ARRAY";

    my @saved = @{$snapshot->{windows}};
    if (!@saved) {
        say_and_log("Saved window state is empty; nothing to restore");
        return 1;
    }

    my %done;
    my %reported;
    my %claimed_window_ids;
    my $total = scalar(@saved);
    log_msg("restoring $selection_reason with " . $total . " saved windows");

    for my $attempt (1..$restore_attempts) {
        my @current = current_windows();
        my %used = %claimed_window_ids;

        for my $idx (0..$#saved) {
            next if $done{$idx};
            my $saved = $saved[$idx];
            my $target = target_workspace($saved, $snapshot, $current_topology, $exact_topology);
            next unless length $target;

            my $match = find_match($saved, \@current, \%used);
            next unless $match;

            $used{$match->{window_id}} = 1;

            if ($match->{workspace} eq $target) {
                log_msg("window $match->{window_id} already on $target: $saved->{app_name} / $saved->{title}") unless $reported{$idx}++;
                $done{$idx} = 1;
                $claimed_window_ids{$match->{window_id}} = 1;
                next;
            }

            if (aerospace_ok("move-node-to-workspace", "--window-id", "$match->{window_id}", "$target")) {
                log_msg("moved window $match->{window_id} from $match->{workspace} to $target: $saved->{app_name} / $saved->{title}");
                $done{$idx} = 1;
                $claimed_window_ids{$match->{window_id}} = 1;
            } else {
                log_msg("failed moving window $match->{window_id} to $target: $saved->{app_name} / $saved->{title}");
            }
        }

        my @saved_chrome_idx = sort {
            (($saved[$a]->{snapshot_order} // $a) <=> ($saved[$b]->{snapshot_order} // $b))
            || (($saved[$a]->{identity_order} // 0) <=> ($saved[$b]->{identity_order} // 0))
        } grep { !$done{$_} && ordinary_chrome($saved[$_]) } 0..$#saved;
        my @current_chrome = sort {
            (($a->{snapshot_order} // 0) <=> ($b->{snapshot_order} // 0))
            || (($a->{window_id} // 0) <=> ($b->{window_id} // 0))
        } grep { !$used{$_->{window_id}} && ordinary_chrome($_) } @current;

        my $pairs = @saved_chrome_idx < @current_chrome ? scalar(@saved_chrome_idx) : scalar(@current_chrome);
        for my $i (0..$pairs - 1) {
            my $idx = $saved_chrome_idx[$i];
            my $saved = $saved[$idx];
            my $match = $current_chrome[$i];
            my $target = target_workspace($saved, $snapshot, $current_topology, $exact_topology);
            next unless length $target;
            $used{$match->{window_id}} = 1;
            if ($match->{workspace} eq $target) {
                log_msg("Chrome fallback window $match->{window_id} already on $target") unless $reported{$idx}++;
                $done{$idx} = 1;
                $claimed_window_ids{$match->{window_id}} = 1;
            } elsif (aerospace_ok("move-node-to-workspace", "--window-id", "$match->{window_id}", "$target")) {
                log_msg("Chrome fallback moved window $match->{window_id} from $match->{workspace} to $target");
                $done{$idx} = 1;
                $claimed_window_ids{$match->{window_id}} = 1;
            } else {
                log_msg("Chrome fallback failed moving window $match->{window_id} to $target");
            }
        }

        my $remaining = grep { !$done{$_} } 0..$#saved;
        if ($remaining == 0) {
            say_and_log("Restored $total saved windows from $state_file");
            return 1;
        }

        last if $attempt == $restore_attempts;
        sleep $restore_delay;
    }

    my $unmatched = 0;
    for my $idx (0..$#saved) {
        next if $done{$idx};
        my $saved = $saved[$idx];
        my $target = target_workspace($saved, $snapshot, $current_topology, $exact_topology);
        log_msg("unmatched saved window for $target: $saved->{app_name} / $saved->{app_bundle_id} / $saved->{title}");
        $unmatched++;
    }
    say_and_log("Window restore finished with $unmatched unmatched saved windows; see $log_file");
    return 0;
}

sub restore_state {
    make_path(state_dir());
    if (open my $fh, ">", $restore_guard) {
        print {$fh} timestamp() . "\n";
        close $fh;
    }
    my $complete = eval { restore_state_inner() };
    my $err = $@;
    unlink $restore_guard;
    die $err if $err;
    if ($complete) {
        unlink $partial_restore_guard;
        schedule_post_restore_save();
    } else {
        if (open my $fh, ">", $partial_restore_guard) {
            print {$fh} timestamp() . "\n";
            close $fh;
        }
        log_msg("restore incomplete; automatic saves are blocked until a successful restore or manual save");
    }
    return 0;
}

sub status_state {
    unless (-f $state_file) {
        print "No saved window state at $state_file\n";
        return 0;
    }
    my $state = read_state();
    unless ($state) {
        print "Saved window state is unreadable at $state_file\n";
        return 1;
    }
    my $count = ref($state->{windows}) eq "ARRAY" ? scalar(@{$state->{windows}}) : 0;
    my $snapshot_count = ref($state->{snapshots}) eq "HASH" ? scalar(keys %{$state->{snapshots}}) : 0;
    print "$count windows saved at " . ($state->{saved_at} || "unknown time");
    print " across $snapshot_count topologies" if $snapshot_count;
    print "\n";
    print "$state_file\n";
}

my $command = shift(@ARGV) || "status";
if ($command eq "save") {
    my $mode = shift(@ARGV) || "manual";
    my $reason = shift(@ARGV) || $mode;
    save_state($mode, $reason);
} elsif ($command eq "restore") {
    restore_state();
} elsif ($command eq "status") {
    status_state();
} else {
    die "usage: window_state.sh save|restore|status\n";
}
WINDOW_STATE_PERL_EOF

  chmod +x "$WINDOW_STATE_HELPER"
  cat > "$WINDOW_STATE_WRAPPER" << 'WINDOW_STATE_WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

exec /usr/bin/perl "$HOME/.config/aerospace/window_state.pl" "$@"
WINDOW_STATE_WRAPPER_EOF

  chmod +x "$WINDOW_STATE_WRAPPER"
  cat > "$WINDOW_STATE_DEBOUNCED_SAVER" << 'WINDOW_STATE_DEBOUNCED_SAVER_EOF'
#!/usr/bin/env bash
set -u

HELPER="$HOME/.config/aerospace/window_state.sh"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"
DELAY="${OMARCHY_WINDOW_STATE_DEBOUNCE_SECONDS:-2}"
SAVE_WAIT_ATTEMPTS="${OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS:-5}"
TMP_ROOT="${TMPDIR:-/tmp}"
LOCK_DIR="$TMP_ROOT/omarchy_window_state_debounced.lock"
PENDING_FILE="$TMP_ROOT/omarchy_window_state_debounced.pending"
RESTORE_GUARD="${OMARCHY_WINDOW_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_active}"
STARTUP_RESTORE_GUARD="${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_startup_restore_active}"
REASON="${1:-event}"

log_msg() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE"
}

if [[ -e "$RESTORE_GUARD" || -e "$STARTUP_RESTORE_GUARD" ]]; then
  log_msg "restore active; skipped debounced save request ($REASON)"
  exit 0
fi

printf '%s\n' "$REASON" > "$PENDING_FILE" 2>/dev/null || true

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi

cleanup() {
  rm -rf "$LOCK_DIR"
}
trap cleanup EXIT TERM INT HUP

while true; do
  sleep "$DELAY"
  if [[ -e "$RESTORE_GUARD" || -e "$STARTUP_RESTORE_GUARD" ]]; then
    log_msg "restore active; skipped debounced save"
    rm -f "$PENDING_FILE"
    exit 0
  fi

  reason="$(cat "$PENDING_FILE" 2>/dev/null || printf '%s\n' "$REASON")"
  rm -f "$PENDING_FILE"
  if [[ ! -x "$HELPER" ]]; then
    log_msg "window state helper missing at $HELPER"
    exit 0
  fi

  log_msg "debounced save starting ($reason)"
  OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS="$SAVE_WAIT_ATTEMPTS" \
    OMARCHY_WINDOW_SKIP_EMPTY_SAVE=1 \
    "$HELPER" save auto "$reason" >> "$LOG_FILE" 2>&1 || \
    log_msg "debounced save failed ($reason)"

  [[ -f "$PENDING_FILE" ]] || break
done
WINDOW_STATE_DEBOUNCED_SAVER_EOF

  chmod +x "$WINDOW_STATE_DEBOUNCED_SAVER"

  cat > "$WINDOW_STATE_MONITOR_MOVE_HELPER" << 'WINDOW_STATE_MONITOR_MOVE_HELPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

DIRECTION="${1:?usage: move_node_to_monitor_and_save.sh left|right|up|down|next|prev}"

aerospace move-node-to-monitor "$DIRECTION"
"$HOME/.config/aerospace/window_state_debounced_save.sh" "move-node-to-monitor-$DIRECTION" >/dev/null 2>&1 || true
"$HOME/.config/aerospace/responsive_layout.sh" "move-node-to-monitor-$DIRECTION" >/dev/null 2>&1 || true
WINDOW_STATE_MONITOR_MOVE_HELPER_EOF

  chmod +x "$WINDOW_STATE_MONITOR_MOVE_HELPER"
  success "window state helper written to $WINDOW_STATE_WRAPPER"
}

# =============================================================================
# WINDOW STATE SAVER AGENT
# Saves the current AeroSpace window layout every 15 minutes. The long-running
# helper also traps launchd termination during logout/shutdown and performs one
# final best-effort save before exiting.
# =============================================================================
write_window_state_saver_agent() {
  info "Writing window state saver..."
  mkdir -p "$AEROSPACE_DIR" "$HOME/Library/LaunchAgents"

  cat > "$WINDOW_STATE_SAVER" << WINDOW_STATE_SAVER_EOF
#!/usr/bin/env bash
set -u

HELPER="$WINDOW_STATE_WRAPPER"
LOG_FILE="$WINDOW_STATE_LOG"
INTERVAL="\${OMARCHY_WINDOW_STATE_SAVE_INTERVAL:-$WINDOW_STATE_SAVE_INTERVAL_SECONDS}"
SAVE_WAIT_ATTEMPTS="\${OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS:-5}"
RESTORE_GUARD="\${OMARCHY_WINDOW_RESTORE_GUARD:-\${TMPDIR:-/tmp}/omarchy_window_state_restore_active}"
STARTUP_RESTORE_GUARD="\${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-\${TMPDIR:-/tmp}/omarchy_window_state_startup_restore_active}"
sleep_pid=""

log_msg() {
  printf '[%s] %s\n' "\$(date '+%Y-%m-%dT%H:%M:%S%z')" "\$*" >> "\$LOG_FILE"
}

save_now() {
  local reason="\$1"
  if [[ ! -x "\$HELPER" ]]; then
    log_msg "window state helper missing at \$HELPER"
    return 0
  fi
  if [[ -e "\$RESTORE_GUARD" || -e "\$STARTUP_RESTORE_GUARD" ]]; then
    log_msg "restore active; skipped window state save (\$reason)"
    return 0
  fi

  log_msg "saving window state (\$reason)"
  OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS="\$SAVE_WAIT_ATTEMPTS" \
    OMARCHY_WINDOW_SKIP_EMPTY_SAVE=1 \
    "\$HELPER" save auto "\$reason" >> "\$LOG_FILE" 2>&1 || \
    log_msg "window state save failed (\$reason)"
}

shutdown() {
  trap - TERM INT HUP
  if [[ -n "\$sleep_pid" ]]; then
    kill "\$sleep_pid" 2>/dev/null || true
  fi
  save_now "shutdown"
  exit 0
}

trap shutdown TERM INT HUP

log_msg "window state saver started; interval \${INTERVAL}s"

while true; do
  sleep "\$INTERVAL" &
  sleep_pid="\$!"
  wait "\$sleep_pid" || true
  sleep_pid=""
  save_now "periodic"
done
WINDOW_STATE_SAVER_EOF

  chmod +x "$WINDOW_STATE_SAVER"

  cat > "$WINDOW_STATE_SAVER_PLIST" << WINDOW_STATE_SAVER_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$WINDOW_STATE_SAVER_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$WINDOW_STATE_SAVER</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ExitTimeOut</key>
  <integer>30</integer>
  <key>StandardOutPath</key>
  <string>$WINDOW_STATE_LOG</string>
  <key>StandardErrorPath</key>
  <string>$WINDOW_STATE_LOG</string>
</dict>
</plist>
WINDOW_STATE_SAVER_PLIST_EOF

  success "window state saver written"
}

# =============================================================================
# GOTO_SPACE HELPER
# Resolves ⌥+N to workspace "${display_slot}${N}" so each monitor gets its
# own 10 workspaces. Invoked from aerospace bindings via exec-and-forget.
# =============================================================================
write_goto_space_helper() {
  info "Writing goto_space helper..."
  mkdir -p "$AEROSPACE_DIR"

  cat > "$AEROSPACE_DIR/goto_space.sh" << 'GOTO_SPACE_EOF'
#!/usr/bin/env bash
# Resolve a per-monitor workspace target and act on it.
#
# Usage:
#   goto_space.sh <key>          # switch to workspace for current monitor + key
#   goto_space.sh <key> --move   # move focused window to that workspace
#
# <key> is 0-9. Workspace names are `${display_slot}${key}` where display_slot
# is the focused monitor's stable Omarchy slot.

set -euo pipefail

source "$HOME/.config/aerospace/omarchy_space_state.sh"

KEY="${1:?usage: goto_space.sh <0-9> [--move]}"
ACTION="${2:-focus}"

if ! [[ "$KEY" =~ ^[0-9]$ ]]; then
  echo "goto_space.sh: key must be 0-9 (got: $KEY)" >&2
  exit 1
fi

TARGET=$(omarchy_workspace_for_key "$KEY") || {
  echo "goto_space.sh: AeroSpace is not reachable; refusing to switch spaces" >&2
  exit 1
}
TARGET_SLOT="${TARGET:0:1}"
omarchy_monitor_id_for_slot "$TARGET_SLOT" >/dev/null || {
  echo "goto_space.sh: no attached monitor for workspace slot $TARGET_SLOT" >&2
  exit 1
}

omarchy_repair_detached_monitor_workspaces || true

case "$ACTION" in
  --move)
    aerospace move-node-to-workspace "$TARGET"
    "$HOME/.config/aerospace/window_state_debounced_save.sh" "move-node-to-workspace-$TARGET" >/dev/null 2>&1 || true
    "$HOME/.config/aerospace/responsive_layout.sh" "move-node-to-workspace-$TARGET" >/dev/null 2>&1 || true
    ;;
  focus|*)
    omarchy_switch_workspace_on_slot_monitor "$TARGET"
    "$HOME/.config/aerospace/responsive_layout.sh" "workspace-$TARGET" >/dev/null 2>&1 || true
    "$HOME/.config/sketchybar/plugins/hide_bar.sh" >/dev/null 2>&1 || true
    ;;
esac
GOTO_SPACE_EOF

  chmod +x "$AEROSPACE_DIR/goto_space.sh"
  cat > "$AEROSPACE_DIR/workspace_back_and_forth.sh" << 'WORKSPACE_BACK_AND_FORTH_EOF'
#!/usr/bin/env bash
set -euo pipefail

aerospace workspace-back-and-forth
"$HOME/.config/aerospace/responsive_layout.sh" "workspace-back-and-forth" >/dev/null 2>&1 || true
"$HOME/.config/sketchybar/plugins/hide_bar.sh" >/dev/null 2>&1 || true
WORKSPACE_BACK_AND_FORTH_EOF

  chmod +x "$AEROSPACE_DIR/workspace_back_and_forth.sh"
  success "goto_space helper written to $AEROSPACE_DIR/goto_space.sh"
}

# =============================================================================
# WINDOW CYCLE HELPER
# Cycles focus through every AeroSpace-managed window, switching workspaces as
# needed before focusing the target window.
# =============================================================================
write_window_cycle_helper() {
  info "Writing window_cycle helper..."
  mkdir -p "$AEROSPACE_DIR"

  cat > "$AEROSPACE_DIR/window_cycle.sh" << 'WINDOW_CYCLE_EOF'
#!/usr/bin/env bash
set -euo pipefail

DIRECTION="${1:-next}"
case "$DIRECTION" in
  next|prev) ;;
  *)
    echo "window_cycle.sh: usage: window_cycle.sh next|prev" >&2
    exit 1
    ;;
esac

focused_id="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null | head -n 1 || true)"

ids=()
workspaces=()
while IFS='|' read -r window_id workspace; do
  [[ "$window_id" =~ ^[0-9]+$ ]] || continue
  [ -n "$workspace" ] || continue
  ids+=("$window_id")
  workspaces+=("$workspace")
done < <(aerospace list-windows --all --format '%{window-id}|%{workspace}')

count="${#ids[@]}"
[ "$count" -gt 0 ] || exit 0

current=-1
for idx in "${!ids[@]}"; do
  if [ "${ids[$idx]}" = "$focused_id" ]; then
    current="$idx"
    break
  fi
done

if [ "$current" -lt 0 ]; then
  if [ "$DIRECTION" = "prev" ]; then
    target=$((count - 1))
  else
    target=0
  fi
elif [ "$DIRECTION" = "prev" ]; then
  target=$(((current - 1 + count) % count))
else
  target=$(((current + 1) % count))
fi

target_id="${ids[$target]}"
target_workspace="${workspaces[$target]}"

aerospace workspace "$target_workspace" >/dev/null 2>&1 || true
aerospace focus --window-id "$target_id"
"$HOME/.config/aerospace/responsive_layout.sh" "window-cycle-$DIRECTION" >/dev/null 2>&1 || true
"$HOME/.config/sketchybar/plugins/hide_bar.sh" >/dev/null 2>&1 || true
WINDOW_CYCLE_EOF

  chmod +x "$AEROSPACE_DIR/window_cycle.sh"
  success "window_cycle helper written to $AEROSPACE_DIR/window_cycle.sh"
}

# =============================================================================
# WINDOW PICKER HELPER
# Shows a readable list of all AeroSpace-managed windows and focuses the chosen
# one. This is more useful than Mission Control when the thumbnail grid gets too
# small to scan.
# =============================================================================
write_window_picker_helper() {
  info "Writing window_picker helper..."
  mkdir -p "$AEROSPACE_DIR"

  cat > "$AEROSPACE_DIR/window_picker.sh" << 'WINDOW_PICKER_EOF'
#!/usr/bin/env bash
set -euo pipefail

picker_bin="$HOME/.config/aerospace/window_picker"
data_file="${TMPDIR:-/tmp}/omarchy_window_picker.$$.tsv"
trap 'rm -f "$data_file"' EXIT

idx=0
while IFS='|' read -r window_id workspace app title; do
  [[ "$window_id" =~ ^[0-9]+$ ]] || continue
  [ -n "$workspace" ] || workspace="?"
  [ -n "$app" ] || app="Unknown"
  if [ -n "$title" ]; then
    label="[$workspace] $app - $title"
  else
    label="[$workspace] $app"
  fi
  idx=$((idx + 1))
  key="$(printf "%03d" "$idx")"
  label="${label//$'\t'/ }"
  printf "%s\t%s\t%s\t%s  %s\n" "$key" "$window_id" "$workspace" "$key" "$label" >> "$data_file"
done < <(aerospace list-windows --all --format '%{window-id}|%{workspace}|%{app-name}|%{window-title}')

[ -s "$data_file" ] || exit 0
[ -x "$picker_bin" ] || {
  echo "window_picker.sh: missing $picker_bin; run ./install.sh refresh" >&2
  exit 1
}

selected_key="$("$picker_bin" "$data_file")"
[ -n "$selected_key" ] || exit 0

target_id=""
target_workspace=""
while IFS=$'\t' read -r key window_id workspace label; do
  if [ "$key" = "$selected_key" ]; then
    target_id="$window_id"
    target_workspace="$workspace"
    break
  fi
done < "$map_file"

[ -n "$target_id" ] || exit 0

aerospace workspace "$target_workspace" >/dev/null 2>&1 || true
aerospace focus --window-id "$target_id"
"$HOME/.config/aerospace/responsive_layout.sh" "window-picker" >/dev/null 2>&1 || true
"$HOME/.config/sketchybar/plugins/hide_bar.sh" >/dev/null 2>&1 || true
WINDOW_PICKER_EOF

  cat > "$WINDOW_PICKER_SRC" << 'WINDOW_PICKER_SWIFT_EOF'
import AppKit

struct WindowRow {
    let key: String
    let windowId: String
    let workspace: String
    let label: String
}

final class PickerController: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let rows: [WindowRow]
    private let table = NSTableView()
    private let preview = NSImageView()
    private let previewLabel = NSTextField(labelWithString: "Select a window")
    private var selectedKey: String?

    init(rows: [WindowRow]) {
        self.rows = rows
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Windows"
        window.center()
        let container = NSView()
        window.contentView = container

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Jump to window:")
        title.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        title.alignment = .left

        let content = NSStackView()
        content.orientation = .horizontal
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
        column.title = "Window"
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.doubleAction = #selector(focusSelected)
        table.target = self
        scroll.documentView = table

        let previewBox = NSStackView()
        previewBox.orientation = .vertical
        previewBox.spacing = 8
        previewBox.translatesAutoresizingMaskIntoConstraints = false
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        preview.layer?.borderColor = NSColor.separatorColor.cgColor
        preview.layer?.borderWidth = 1
        preview.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.font = NSFont.systemFont(ofSize: 13)
        previewLabel.lineBreakMode = .byTruncatingMiddle
        previewBox.addArrangedSubview(preview)
        previewBox.addArrangedSubview(previewLabel)

        content.addArrangedSubview(scroll)
        content.addArrangedSubview(previewBox)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10
        let spacer = NSView()
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        let focus = NSButton(title: "Focus", target: self, action: #selector(focusSelected))
        focus.keyEquivalent = "\r"
        buttons.addArrangedSubview(spacer)
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(focus)

        root.addArrangedSubview(title)
        root.addArrangedSubview(content)
        root.addArrangedSubview(buttons)
        container.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            root.topAnchor.constraint(equalTo: container.topAnchor),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.56),
            preview.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.38),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 0.62),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 560)
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !rows.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(labelWithString: rows[row].label)
        field.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview()
    }

    private func updatePreview() {
        let rowIndex = table.selectedRow
        guard rowIndex >= 0 && rowIndex < rows.count else { return }
        let row = rows[rowIndex]
        selectedKey = row.key
        previewLabel.stringValue = row.label

        let path = NSTemporaryDirectory() + "omarchy_window_preview_\(row.windowId)_\(ProcessInfo.processInfo.processIdentifier).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l\(row.windowId)", path]
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0, let image = NSImage(contentsOfFile: path) {
                preview.image = image
            } else {
                preview.image = nil
            }
        } catch {
            preview.image = nil
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    @objc private func focusSelected() {
        if selectedKey == nil {
            updatePreview()
        }
        if let key = selectedKey {
            print(key)
            fflush(stdout)
        }
        NSApp.terminate(nil)
    }

    @objc private func cancel() {
        NSApp.terminate(nil)
    }
}

let dataPath = CommandLine.arguments.dropFirst().first ?? ""
let contents = (try? String(contentsOfFile: dataPath, encoding: .utf8)) ?? ""
let rows = contents.split(separator: "\n").compactMap { line -> WindowRow? in
    let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    return WindowRow(key: String(parts[0]), windowId: String(parts[1]), workspace: String(parts[2]), label: String(parts[3]))
}

let app = NSApplication.shared
let delegate = PickerController(rows: rows)
app.delegate = delegate
app.run()
WINDOW_PICKER_SWIFT_EOF

  if ! command -v swiftc &>/dev/null; then
    warn "swiftc not found — install Xcode Command Line Tools (xcode-select --install)"
    return 1
  fi

  info "Compiling window_picker..."
  swiftc -O "$WINDOW_PICKER_SRC" -o "$WINDOW_PICKER_BIN"
  chmod +x "$AEROSPACE_DIR/window_picker.sh" "$WINDOW_PICKER_BIN"
  success "window_picker helper written to $AEROSPACE_DIR/window_picker.sh"
}

# =============================================================================
# SECURE INPUT HELPER
# Reports the current macOS Secure Input owner. Secure Input can block global
# hotkeys, so this intentionally stays terminal-first instead of relying on an
# AeroSpace/skhd binding that may not fire while Secure Input is active.
# =============================================================================
write_secure_input_helper() {
  info "Writing secure input helper..."
  mkdir -p "$AEROSPACE_DIR"

  cat > "$SECURE_INPUT_HELPER" << 'SECURE_INPUT_EOF'
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  secure_input_report.sh           show current Secure Input owner
  secure_input_report.sh --brief   one-line status
  secure_input_report.sh --watch [seconds]
                                  print when the owner changes

Secure Input is a macOS session flag. The PID is best-effort: if the process
exited without clearing Secure Input, the session can retain a stale PID until
the login session is reset.
USAGE
}

secure_input_pid() {
  /usr/sbin/ioreg -r -k IOConsoleUsers -d 1 -l 2>/dev/null |
    /usr/bin/sed -n 's/.*"kCGSSessionSecureInputPID"=\([0-9][0-9]*\).*/\1/p' |
    /usr/bin/head -n 1
}

process_line() {
  local pid="$1"
  /bin/ps -p "$pid" -o pid=,ppid=,stat=,comm=,args= 2>/dev/null || true
}

process_comm() {
  local pid="$1"
  /bin/ps -p "$pid" -o comm= 2>/dev/null | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//' || true
}

parent_chain() {
  local pid="$1" depth=0 line ppid
  while [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] && [ "$depth" -lt 10 ]; do
    line="$(process_line "$pid")"
    [ -n "$line" ] || break
    printf "  %s\n" "$line"
    ppid="$(/bin/ps -p "$pid" -o ppid= 2>/dev/null | /usr/bin/tr -d ' ')"
    [ -n "$ppid" ] || break
    [ "$ppid" = "$pid" ] && break
    pid="$ppid"
    depth=$((depth + 1))
  done
}

aerospace_windows_for_comm() {
  local comm="$1" app_name
  [ -n "$comm" ] || return 0
  app_name="${comm##*/}"
  command -v aerospace >/dev/null 2>&1 || return 0
  aerospace list-windows --all --format '%{workspace}|%{app-name}|%{window-title}' 2>/dev/null |
    /usr/bin/awk -F'|' -v app="$app_name" '
      BEGIN { found = 0 }
      index(tolower($2), tolower(app)) {
        found = 1
        title = $3 == "" ? "(untitled)" : $3
        printf "  [%s] %s - %s\n", $1, $2, title
      }
      END { exit(found ? 0 : 1) }
    '
}

hid_clients() {
  /usr/sbin/ioreg -l -w 0 -r -c IOHIDSystem 2>/dev/null |
    /usr/bin/sed -n 's/.*"IOUserClientCreator" = "\(pid [^"]*\)".*/  \1/p' |
    /usr/bin/sort -u
}

report_once() {
  local mode="${1:-full}" pid line comm
  pid="$(secure_input_pid)"
  if [ -z "$pid" ] || [ "$pid" = "0" ]; then
    if [ "$mode" = "brief" ]; then
      echo "Secure Input: off"
    else
      echo "Secure Input is off."
    fi
    return 0
  fi

  line="$(process_line "$pid")"
  if [ "$mode" = "brief" ]; then
    if [ -n "$line" ]; then
      echo "Secure Input: on, owner PID $pid: $line"
    else
      echo "Secure Input: on, owner PID $pid is not in ps output"
    fi
    return 0
  fi

  echo "Secure Input is ON."
  echo "Owner PID from IOConsoleUsers: $pid"
  echo ""

  if [ -n "$line" ]; then
    echo "Owner process:"
    echo "  $line"
    echo ""
    echo "Parent chain:"
    parent_chain "$pid"
    echo ""
    case "$line" in
      *"/loginwindow.app/"*|*" loginwindow "*)
        echo "Interpretation:"
        echo "  Secure Input is held by loginwindow, so there is no normal app window"
        echo "  for AeroSpace to find. Try lock/unlock first; if it remains stuck,"
        echo "  log out or restart to reset the login session."
        ;;
      *)
        echo "Interpretation:"
        echo "  Close password fields, auth dialogs, terminal password prompts, or"
        echo "  credential-provider popovers owned by this process. If it remains stuck,"
        echo "  quitting that app is the cleanest way to make it release Secure Input."
        ;;
    esac
  else
    echo "No live process with PID $pid appears in ps output."
    echo "That usually means the process exited without clearing Secure Input,"
    echo "or the value is stale in the current login session. Lock/unlock may clear"
    echo "it; otherwise log out or restart to reset the session."
  fi

  comm="$(process_comm "$pid")"
  if [ -n "$comm" ]; then
    echo ""
    echo "AeroSpace windows matching the process name, if any:"
    if ! aerospace_windows_for_comm "$comm"; then
      echo "  none"
    fi
  fi

  echo ""
  echo "Current IOHID clients, for context:"
  hid_clients || true
}

watch_report() {
  local interval="${1:-1}" last="" pid stamp line
  echo "Watching Secure Input owner every ${interval}s. Press Ctrl-C to stop."
  while true; do
    pid="$(secure_input_pid)"
    [ -n "$pid" ] || pid="0"
    if [ "$pid" != "$last" ]; then
      stamp="$(/bin/date '+%Y-%m-%d %H:%M:%S')"
      if [ "$pid" = "0" ]; then
        echo "$stamp Secure Input off"
      else
        line="$(process_line "$pid")"
        if [ -n "$line" ]; then
          echo "$stamp Secure Input PID $pid: $line"
        else
          echo "$stamp Secure Input PID $pid: not in ps output"
        fi
      fi
      last="$pid"
    fi
    /bin/sleep "$interval"
  done
}

case "${1:-}" in
  --help|-h)
    usage
    ;;
  --brief)
    report_once brief
    ;;
  --watch)
    watch_report "${2:-1}"
    ;;
  "")
    report_once full
    ;;
  *)
    echo "secure_input_report.sh: unknown argument '$1'" >&2
    usage >&2
    exit 1
    ;;
esac
SECURE_INPUT_EOF

  chmod +x "$SECURE_INPUT_HELPER"
  success "secure input helper written to $SECURE_INPUT_HELPER"
}

# =============================================================================
# AEROSPACE LOGIN STARTER
# Starts AeroSpace at login without hiding/suspending the app. AeroSpace's own
# start-at-login setting is still enabled, but this gives the generated setup an
# explicit LaunchAgent to diagnose and repair.
# =============================================================================
write_aerospace_start_agent() {
  info "Writing AeroSpace login starter..."
  mkdir -p "$HOME/Library/LaunchAgents"

  cat > "$AEROSPACE_START_PLIST" << AEROSPACE_START_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$AEROSPACE_START_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-g</string>
    <string>/Applications/AeroSpace.app</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/aerospace_start.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/aerospace_start.log</string>
</dict>
</plist>
AEROSPACE_START_PLIST_EOF

  success "AeroSpace login starter written"
}

# =============================================================================
# SKHD CONFIG
# =============================================================================
write_skhd_config() {
  info "Writing skhd config..."
  mkdir -p "$SKHD_DIR"

  cat > "$SKHD_CFG" << 'SKHD_EOF'
# =============================================================================
# skhd — global hotkey daemon
# Handles app-launching shortcuts that Aerospace doesn't cover
# (mirrors Hyprland: SUPER + SHIFT + <key> app launchers)
# =============================================================================

# ── Terminal: ⌥ + Return ──────────────────────────────────────────────────
# Tries Ghostty → WezTerm → Terminal.app in order
alt - return : \
  if open -a "Ghostty" 2>/dev/null; then :; \
  elif open -a "WezTerm" 2>/dev/null; then :; \
  else open -a "Terminal"; fi

# ── App launchers: ⌥ + Shift + <key> ─────────────────────────────────────
# (mirrors Hyprland: SUPER + SHIFT + B/N/M/G etc.)

# Browser (default system browser)
alt + shift - b : open -a "Safari" 2>/dev/null || open -a "Google Chrome" 2>/dev/null || open -a "Firefox"

# File manager
alt + shift - f : open ~

# Editor (Cursor → VS Code → TextEdit)
alt + shift - n : \
  open -a "Cursor" 2>/dev/null || \
  open -a "Visual Studio Code" 2>/dev/null || \
  open -a "TextEdit"

# Music (Spotify → Music.app)
alt + shift - m : open -a "Spotify" 2>/dev/null || open -a "Music"

# Passwords (1Password → Keychain Access)
alt + shift - 0x2C : open -a "1Password" 2>/dev/null || open -a "Keychain Access"

# Communications (Slack → Messages)
alt + shift - g : open -a "Slack" 2>/dev/null || open -a "Messages"

# ── Launcher: ⌥ + Space → Raycast ────────────────────────────────────────
# (mirrors Hyprland: SUPER + ALT + SPACE → walker)
# Note: Raycast is configured separately. Set its activation key to ⌥+Space
# in Raycast Settings → General → Raycast Hotkey
# Uncomment below if you prefer skhd to trigger it directly:
# alt - space : open -a "Raycast"

# ── Screenshot shortcuts ──────────────────────────────────────────────────
# Region screenshot → clipboard (mirrors SUPER + SHIFT + S)
alt + shift - s : screencapture -ic

# Full screenshot → clipboard
alt - p : screencapture -c

# ── Window overview ───────────────────────────────────────────────────────
# Native Mission Control is still available, but the normal all-window picker
# is bound in AeroSpace as ⌥+Up so it follows the same input path as ⌥+h/j/k/l.
alt + shift - up : open -a "Mission Control"

# ── SketchyBar visibility toggle ──────────────────────────────────────────
alt - z : ~/.config/sketchybar/plugins/toggle_bar.sh

# ── Reload skhd config ────────────────────────────────────────────────────
alt + shift - c : skhd --reload
SKHD_EOF

  success "skhd config written to $SKHD_CFG"
}

# =============================================================================
# SKETCHYBAR CONFIG
# =============================================================================
write_sketchybar_config() {
  info "Writing SketchyBar config..."
  mkdir -p "$SKETCHY_DIR/plugins" "$SKETCHY_DIR/items"

  # ── Main bar config ──────────────────────────────────────────────────────
  cat > "$SKETCHY_DIR/sketchybarrc" << 'SKETCHY_EOF'
#!/usr/bin/env bash
# =============================================================================
# SketchyBar — Omarchy-style status bar (waybar equivalent)
# Catppuccin Mocha color scheme
# =============================================================================

source "$CONFIG_DIR/colors.sh"

# ── Bar appearance ────────────────────────────────────────────────────────
sketchybar --bar \
  position=top        \
  height=32           \
  blur_radius=0       \
  color=$BAR_COLOR    \
  border_width=1      \
  border_color=$BORDER_COLOR \
  shadow=off          \
  topmost=window      \
  y_offset=26         \
  sticky=on           \
  padding_left=8      \
  padding_right=8

# ── Default item appearance ───────────────────────────────────────────────
sketchybar --default \
  icon.font="SF Pro:Semibold:13.0"      \
  icon.color=$TEXT                      \
  label.font="SF Pro:Regular:13.0"      \
  label.color=$TEXT                     \
  padding_left=6                        \
  padding_right=6                       \
  background.corner_radius=6           \
  background.height=24                  \
  background.border_width=0

# ── Load items ────────────────────────────────────────────────────────────
for item in space.1 space.2 space.3 space.4 space.5 space.6 space.7 space.8 space.9 space.0 spaces_separator front_app monitor display_reload; do
  sketchybar --remove "$item" >/dev/null 2>&1 || true
done
for slot in 0 1 2 3 4 5 6 7 8 9; do
  for key in 1 2 3 4 5 6 7 8 9 0; do
    sketchybar --remove "space.$slot.$key" >/dev/null 2>&1 || true
  done
  sketchybar --remove "spaces_separator.$slot" >/dev/null 2>&1 || true
  sketchybar --remove "monitor.$slot" >/dev/null 2>&1 || true
done

source "$CONFIG_DIR/items/spaces.sh"
source "$CONFIG_DIR/items/front_app.sh"
source "$CONFIG_DIR/items/monitor.sh"
source "$CONFIG_DIR/items/display_reload.sh"

# ── Finalise ──────────────────────────────────────────────────────────────
sketchybar --update
rm -f "${XDG_RUNTIME_DIR:-/tmp}/omarchy_sketchybar_visible"
sketchybar --bar hidden=on
SKETCHY_EOF

  chmod +x "$SKETCHY_DIR/sketchybarrc"

  # ── Colors (Catppuccin Mocha — same palette as Omarchy) ──────────────────
  cat > "$SKETCHY_DIR/colors.sh" << 'COLORS_EOF'
#!/usr/bin/env bash
# Catppuccin Mocha
export BAR_COLOR=0xff1e1e2e       # base
export BORDER_COLOR=0xff313244    # surface0
export ITEM_BG=0xff313244         # surface0
export ITEM_BG_ACTIVE=0xff45475a  # surface1

export TEXT=0xffcdd6f4            # text
export SUBTEXT=0xff6c7086         # overlay0
export BLUE=0xff89b4fa            # blue
export MAUVE=0xffcba6f7           # mauve
export GREEN=0xffa6e3a1           # green
export YELLOW=0xfff9e2af          # yellow
export RED=0xfff38ba8             # red
export PEACH=0xfffab387           # peach
COLORS_EOF

  # ── Space aliases ───────────────────────────────────────────────────────
  # Labels are display-specific. Only slot 0, the built-in/main display, gets
  # named workspaces by default; external displays keep numeric/app labels.
  cat > "$SKETCHY_DIR/space_aliases" << 'SPACE_ALIASES_EOF'
01=Mail
02=Msg
03=Music
04=Terms
05=Editors
06=Agents
SPACE_ALIASES_EOF

  # ── Spaces (workspace indicators) ────────────────────────────────────────
  cat > "$SKETCHY_DIR/items/spaces.sh" << 'SPACES_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"
source "$HOME/.config/aerospace/omarchy_space_state.sh"

monitors=$(omarchy_monitor_ids_by_slot 2>/dev/null || printf '1')
slot=0
while IFS= read -r monitor_id; do
  [ -n "$monitor_id" ] || continue
  [ "$slot" -gt 9 ] && break
  display=$(omarchy_sketchybar_display_for_slot "$slot" 2>/dev/null || printf '%s\n' $((slot + 1)))
  for sid in 1 2 3 4 5 6 7 8 9 0; do
    name="space.$slot.$sid"
    sketchybar --add item "$name" left \
      --set "$name" \
        display="$display" \
        icon="$sid" \
        icon.font="SF Pro:Regular:12.0" \
        icon.color=$SUBTEXT \
        icon.padding_left=8 \
        icon.padding_right=4 \
        label.drawing=off \
        label.font="SF Pro:Medium:12.0" \
        label.color=$SUBTEXT \
        label.padding_right=8 \
        background.drawing=on \
        background.color=0x00000000 \
        background.border_color=0x00000000 \
        background.border_width=2 \
        background.corner_radius=6 \
        background.height=24 \
        padding_left=2 \
        padding_right=2
  done

  sketchybar --add item "spaces_separator.$slot" left \
    --set "spaces_separator.$slot" \
      display="$display" \
      icon="|" \
      icon.font="SF Pro:Light:14.0" \
      icon.color=$SUBTEXT \
      padding_left=2 \
      padding_right=2 \
      label.drawing=off
  slot=$((slot + 1))
done <<< "$monitors"
SPACES_ITEM_EOF

  # ── Front app ─────────────────────────────────────────────────────────────
  cat > "$SKETCHY_DIR/items/front_app.sh" << 'FRONTAPP_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

sketchybar --add item front_app left \
  --set front_app \
    icon.drawing=off \
    label.font="SF Pro:Semibold:13.0" \
    label.color=$MAUVE \
    script="$CONFIG_DIR/plugins/front_app.sh" \
  --subscribe front_app front_app_switched
FRONTAPP_ITEM_EOF

  # ── Monitor indicator (0-based display id) ─────────────────────────────
  cat > "$SKETCHY_DIR/items/monitor.sh" << 'MONITOR_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"
source "$HOME/.config/aerospace/omarchy_space_state.sh"

monitors=$(omarchy_monitor_ids_by_slot 2>/dev/null || printf '1')
slot=0
while IFS= read -r monitor_id; do
  [ -n "$monitor_id" ] || continue
  [ "$slot" -gt 9 ] && break
  display=$(omarchy_sketchybar_display_for_slot "$slot" 2>/dev/null || printf '%s\n' $((slot + 1)))
  sketchybar --add item "monitor.$slot" right \
    --set "monitor.$slot" \
      display="$display" \
      icon.drawing=off \
      label="$slot" \
      label.font="SF Pro:Semibold:13.0" \
      label.color=$PEACH \
      background.drawing=on \
      background.color=$ITEM_BG \
      background.corner_radius=6 \
      background.height=24 \
      padding_left=6 \
      padding_right=6
  slot=$((slot + 1))
done <<< "$monitors"
MONITOR_ITEM_EOF

  cat > "$SKETCHY_DIR/items/display_reload.sh" << 'DISPLAY_RELOAD_ITEM_EOF'
#!/usr/bin/env bash

sketchybar --add event display_change >/dev/null 2>&1 || true
sketchybar --add item display_reload center \
  --set display_reload \
    drawing=off \
    updates=on \
    script="$CONFIG_DIR/plugins/display_reload.sh" \
  --subscribe display_reload display_change system_woke
DISPLAY_RELOAD_ITEM_EOF

  # ── Right-side items: wifi, battery, clock ─────────────────────────────
  cat > "$SKETCHY_DIR/items/wifi.sh" << 'WIFI_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

sketchybar --add item wifi right \
  --set wifi \
    update_freq=10 \
    icon.font="SF Pro:Regular:14.0" \
    icon.color=$BLUE \
    label.color=$TEXT \
    script="$CONFIG_DIR/plugins/wifi.sh"
WIFI_ITEM_EOF

  cat > "$SKETCHY_DIR/items/battery.sh" << 'BATTERY_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

sketchybar --add item battery right \
  --set battery \
    update_freq=60 \
    icon.font="SF Pro:Regular:14.0" \
    script="$CONFIG_DIR/plugins/battery.sh" \
  --subscribe battery power_source_change system_woke
BATTERY_ITEM_EOF

  cat > "$SKETCHY_DIR/items/clock.sh" << 'CLOCK_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

sketchybar --add item clock right \
  --set clock \
    update_freq=10 \
    icon.drawing=off \
    label.color=$TEXT \
    script="$CONFIG_DIR/plugins/clock.sh"
CLOCK_ITEM_EOF

  # ── Plugins (scripts that SketchyBar calls) ───────────────────────────────

  cat > "$SKETCHY_DIR/plugins/spaces.sh" << 'SPACES_PLUGIN_EOF'
#!/usr/bin/env bash
# Usage: source "$CONFIG_DIR/plugins/spaces.sh" && highlight_space <focused_workspace>
#
# Per-monitor spaces: workspace names are "${display_slot}${key}" (e.g. "13"
# for slot 1, key 3). Each physical bar gets its own item namespace:
# space.<display_slot>.<key>, scoped with SketchyBar's display property.

source "$CONFIG_DIR/colors.sh"
source "$HOME/.config/aerospace/omarchy_space_state.sh"

ALIAS_FILE="$HOME/.config/sketchybar/space_aliases"

space_alias_label() {
  local workspace="$1"
  [ -f "$ALIAS_FILE" ] || return 1
  awk -F= -v key="$workspace" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      print value
      exit
    }
  ' "$ALIAS_FILE"
}

unexpected_apps_for_alias() {
  local workspace="$1"
  local rows="$2"
  local legacy_workspace="${3:-}"

  printf '%s\n' "$rows" |
    while IFS='|' read -r row_workspace app_name bundle_id; do
      [ "$row_workspace" = "$workspace" ] || { [ -n "$legacy_workspace" ] && [ "$row_workspace" = "$legacy_workspace" ]; } || continue
      [ -n "$app_name" ] || continue
      local assigned
      assigned=$(omarchy_assigned_workspace_for_app "$app_name" "$bundle_id" 2>/dev/null || true)
      [ "$assigned" = "$workspace" ] && continue
      printf '%s\n' "$app_name"
    done |
    sort -u |
    paste -sd "," - |
    sed 's/,/, /g'
}

highlight_space() {
  local focused="$1"  # full workspace name, e.g. "23", or empty
  local focused_monitor focused_key
  if [[ "$focused" =~ ^[0-9][0-9]$ ]]; then
    focused_monitor="${focused:0:1}"
    focused_key="${focused:1:1}"
  else
    focused_monitor=$(omarchy_focused_monitor_slot) || {
      sketchybar --set monitor.0 label="AS?" >/dev/null 2>&1 || true
      return 0
    }
    local ws
    ws=$(omarchy_focused_workspace)
    if [[ "$ws" =~ ^[0-9][0-9]$ ]]; then
      focused_key="${ws:1:1}"
    elif [[ "$ws" =~ ^[0-9]$ ]]; then
      focused_key="$ws"
    else
      focused_key=""
    fi
    focused="$ws"
  fi

  if ! [[ "$focused_monitor" =~ ^[0-9]+$ ]] || ! [[ "$focused_key" =~ ^[0-9]$ ]]; then
    sketchybar --set monitor.0 label="AS?" >/dev/null 2>&1 || true
    return 0
  fi

  # One aerospace call for all windows, grouped by workspace.
  local windows
  windows=$(aerospace list-windows --all --format '%{workspace}|%{app-name}|%{app-bundle-id}' 2>/dev/null) || {
    sketchybar --set monitor.0 label="AS?" >/dev/null 2>&1 || true
    return 0
  }

  local monitors
  monitors=$(omarchy_monitor_ids_by_slot) || {
    sketchybar --set monitor.0 label="AS?" >/dev/null 2>&1 || true
    return 0
  }

  # Build a single batched sketchybar invocation.
  local args=()

  local slot=0 monitor_id display visible_ws active_key
  while IFS= read -r monitor_id; do
    [ -n "$monitor_id" ] || continue
    [ "$slot" -gt 9 ] && break
    display=$(omarchy_sketchybar_display_for_slot "$slot" 2>/dev/null || printf '%s\n' $((slot + 1)))

    visible_ws=$("$OMARCHY_AEROSPACE_BIN" list-workspaces --monitor "$monitor_id" --visible --format '%{workspace}' 2>/dev/null | head -n 1)
    active_key=""
    if [[ "$visible_ws" =~ ^[0-9][0-9]$ ]] && [ "${visible_ws:0:1}" = "$slot" ]; then
      active_key="${visible_ws:1:1}"
    elif [[ "$visible_ws" =~ ^[0-9]$ ]]; then
      active_key="$visible_ws"
    elif [ "$slot" = "$focused_monitor" ]; then
      active_key="$focused_key"
    fi

    # Display changes can race with SketchyBar reloads. Make updates
    # idempotently create missing slot items before setting labels.
    sketchybar --add item "monitor.$slot" right >/dev/null 2>&1 || true
    sketchybar --add item "spaces_separator.$slot" left >/dev/null 2>&1 || true
    args+=(--set "monitor.$slot" display="$display" label="$slot"
           --set "spaces_separator.$slot" display="$display" icon="|" label.drawing=off)

    for KEY in 1 2 3 4 5 6 7 8 9 0; do
      local ws_name="${slot}${KEY}"
      local name="space.$slot.$KEY"
      local label legacy_ws apps alias unexpected_apps
      legacy_ws=""
      [ "$visible_ws" = "$KEY" ] && legacy_ws="$KEY"
      apps=$(printf '%s\n' "$windows" \
        | awk -F'|' -v s="$ws_name" -v legacy="$legacy_ws" '$1==s || (legacy != "" && $1==legacy){print $2}' \
        | sort -u | paste -sd "," - | sed 's/,/, /g')
      alias=$(space_alias_label "$ws_name" 2>/dev/null || true)
      if [ -n "$alias" ]; then
        unexpected_apps=$(unexpected_apps_for_alias "$ws_name" "$windows" "$legacy_ws" 2>/dev/null || true)
        if [ -n "$unexpected_apps" ]; then
          label="$alias, $unexpected_apps"
        else
          label="$alias"
        fi
      else
        label="$apps"
      fi
      local has_content="$apps"
      local active_label_color=$TEXT
      local idle_label_color=$SUBTEXT
      sketchybar --add item "$name" left >/dev/null 2>&1 || true
      if [ -z "$has_content" ]; then
        if [ -z "$alias" ]; then
          label="[empty]"
          active_label_color=$YELLOW
          idle_label_color=$YELLOW
        fi
      fi

      if [ "$KEY" = "$active_key" ]; then
        args+=(--set "$name"
          display="$display"
          icon.font="SF Pro:Bold:12.0"
          icon.color=$BLUE
          label="$label"
          label.drawing=on
          label.font="SF Pro:Bold:12.0"
          label.color=$active_label_color
          background.color=$ITEM_BG_ACTIVE
          background.border_color=$BLUE
          background.border_width=2)
      else
        local idle_icon_color=$SUBTEXT
        [ -n "$has_content" ] && idle_icon_color=$MAUVE
        args+=(--set "$name"
          display="$display"
          icon.font="SF Pro:Regular:12.0"
          icon.color=$idle_icon_color
          label="$label"
          label.drawing=on
          label.font="SF Pro:Regular:12.0"
          label.color=$idle_label_color
          background.color=0x00000000
          background.border_color=0x00000000
          background.border_width=0)
      fi

      # Force redraw: sketchybar doesn't repaint background/border on --set
      # alone. Toggling background.drawing does — batched in the same call.
      args+=(--set "$name" background.drawing=off
             --set "$name" background.drawing=on)
    done

    slot=$((slot + 1))
  done <<< "$monitors"

  if [ "${#args[@]}" -eq 0 ]; then
    return 0
  fi

  sketchybar "${args[@]}"
}
SPACES_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/toggle_bar.sh" << 'TOGGLE_BAR_PLUGIN_EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/omarchy_sketchybar_visible"

if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE" 2>/dev/null)" = "1" ]]; then
  "$HOME/.config/sketchybar/plugins/hide_bar.sh"
else
  sketchybar --bar hidden=off topmost=window
  sketchybar --trigger front_app_switched >/dev/null 2>&1 || true
  printf '1' > "$STATE_FILE"
fi
TOGGLE_BAR_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/hide_bar.sh" << 'HIDE_BAR_PLUGIN_EOF'
#!/usr/bin/env bash
set -euo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/omarchy_sketchybar_visible"

sketchybar --bar hidden=on
printf '0' > "$STATE_FILE"
HIDE_BAR_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/display_reload.sh" << 'DISPLAY_RELOAD_PLUGIN_EOF'
#!/usr/bin/env bash
set -euo pipefail

LOCK_DIR="${TMPDIR:-/tmp}/omarchy_sketchybar_display_reload.lock"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi

(
  sleep 1
  printf '[%s] sketchybar display topology changed; reloading\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$LOG_FILE" 2>/dev/null || true
  sketchybar --reload >/dev/null 2>&1 || true
  rm -rf "$LOCK_DIR"
) >/dev/null 2>&1 &
DISPLAY_RELOAD_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/front_app.sh" << 'FRONTAPP_PLUGIN_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/plugins/spaces.sh"

APP="${INFO}"
if [ -z "$APP" ]; then
  APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
fi
WS=$(omarchy_focused_workspace)
DISPLAY_WS=$(omarchy_normalize_focused_workspace "$WS" 2>/dev/null || true)
if [[ "$DISPLAY_WS" =~ ^[0-9][0-9]$ ]]; then
  sketchybar --set "$NAME" label="$DISPLAY_WS $APP"
else
  sketchybar --set "$NAME" label="AS? $APP"
fi
highlight_space "$WS"
FRONTAPP_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/clock.sh" << 'CLOCK_PLUGIN_EOF'
#!/usr/bin/env bash
sketchybar --set "$NAME" label="$(date '+%a %d %b  %H:%M')"
CLOCK_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/battery.sh" << 'BATTERY_PLUGIN_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

PERCENTAGE=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(pmset -g batt | grep 'AC Power')

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

if [[ "$CHARGING" != "" ]]; then
  ICON="⚡"
  COLOR=$GREEN
elif [[ "$PERCENTAGE" -le 20 ]]; then
  ICON="▂"
  COLOR=$RED
elif [[ "$PERCENTAGE" -le 50 ]]; then
  ICON="▄"
  COLOR=$YELLOW
else
  ICON="█"
  COLOR=$GREEN
fi

sketchybar --set "$NAME" icon="$ICON" icon.color=$COLOR label="${PERCENTAGE}%"
BATTERY_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/wifi.sh" << 'WIFI_PLUGIN_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

# Auto-detect wifi interface (en0 on most Macs, but not all)
WIFI_IFACE=$(networksetup -listallhardwareports 2>/dev/null | awk '/Wi-Fi/{found=1} found && /Device:/{print $2; exit}')
WIFI_IFACE="${WIFI_IFACE:-en0}"
SSID=$(networksetup -getairportnetwork "$WIFI_IFACE" 2>/dev/null | awk -F': ' '{print $2}')

if [[ -z "$SSID" || "$SSID" == "You are not associated with an AirPort network." ]]; then
  sketchybar --set "$NAME" icon="◯" icon.color=$RED label="wifi off"
else
  sketchybar --set "$NAME" icon="◉" icon.color=$BLUE label="$SSID"
fi
WIFI_PLUGIN_EOF

  # Make all plugins executable
  chmod +x "$SKETCHY_DIR/plugins/"*.sh
  chmod +x "$SKETCHY_DIR/items/"*.sh

  success "SketchyBar config written to $SKETCHY_DIR"
}

# =============================================================================
# CHROME REHOME DAEMON
#
# Swift binary that subscribes to Chrome's AXWindowCreated events and moves
# each newly-opened ordinary Chrome window to the first empty workspace on the
# monitor where Chrome created it. If every workspace on that monitor is
# occupied, the window stays put. The updated window state is saved after the
# decision so reboot restore learns the final placement.
# =============================================================================
write_chrome_rehome_daemon() {
  info "Writing chrome_rehome daemon..."
  mkdir -p "$SKETCHY_DIR/plugins"
  mkdir -p "$CHROME_REHOME_APP/Contents/MacOS"
  local source_tmp="$CHROME_REHOME_SRC.tmp"
  local source_changed=0

  cat > "$source_tmp" << 'CHROME_REHOME_SWIFT_EOF'
import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError

let aerospacePath = "/opt/homebrew/bin/aerospace"
let debouncedSavePath = NSHomeDirectory() + "/.config/aerospace/window_state_debounced_save.sh"
let chromeBundleID = "com.google.Chrome"
let scanOrder: [String] = ["1","2","3","4","5","6","7","8","9","0"]
let aerospaceStartupAttempts = 60
let windowListingAttempts = 60
let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? "/tmp"
let restoreGuardPath = ProcessInfo.processInfo.environment["OMARCHY_WINDOW_RESTORE_GUARD"] ?? "\(tmpDir)/omarchy_window_state_restore_active"
let startupRestoreGuardPath = ProcessInfo.processInfo.environment["OMARCHY_WINDOW_STARTUP_RESTORE_GUARD"] ?? "\(tmpDir)/omarchy_window_state_startup_restore_active"
let partialRestoreGuardPath = ProcessInfo.processInfo.environment["OMARCHY_WINDOW_PARTIAL_RESTORE_GUARD"] ?? "\(tmpDir)/omarchy_window_state_restore_incomplete"

func log(_ msg: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardOutput.write(Data("[\(stamp)] \(msg)\n".utf8))
}

@discardableResult
func sh(_ args: [String]) -> String {
    let p = Process()
    p.launchPath = aerospacePath
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch {
        log("aerospace launch failed: \(error)")
        return ""
    }
    p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func aerospaceAvailable() -> Bool {
    !sh(["list-monitors", "--format", "%{monitor-id}"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
}

func scheduleWindowStateSave(_ reason: String) {
    guard FileManager.default.isExecutableFile(atPath: debouncedSavePath) else { return }
    let p = Process()
    p.launchPath = debouncedSavePath
    p.arguments = [reason]
    do {
        try p.run()
    } catch {
        log("could not schedule window state save: \(error)")
    }
}

func waitForAerospace() -> Bool {
    for attempt in 0..<aerospaceStartupAttempts {
        if aerospaceAvailable() {
            if attempt > 0 {
                log("AeroSpace became reachable after \(attempt) seconds")
            }
            return true
        }
        Thread.sleep(forTimeInterval: 1.0)
    }
    return false
}

func restoreActive() -> Bool {
    let fm = FileManager.default
    return fm.fileExists(atPath: restoreGuardPath)
        || fm.fileExists(atPath: startupRestoreGuardPath)
        || fm.fileExists(atPath: partialRestoreGuardPath)
}

func activeMonitorSlotCount() -> Int {
    let out = sh(["list-monitors", "--format", "%{monitor-id}"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return out.split(separator: "\n").count
}

func firstEmptyOnMonitor(_ monitor: String, skip currentWs: String) -> String? {
    for key in scanOrder {
        let ws = "\(monitor)\(key)"
        if ws == currentWs { continue }
        let out = sh(["list-windows", "--workspace", ws, "--format", "%{window-id}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty { return ws }
    }
    return nil
}

func handleNewWindow(_ wid: CGWindowID) {
    guard waitForAerospace() else {
        log("Chrome window \(wid): AeroSpace was not reachable; leaving in place")
        return
    }
    if restoreActive() {
        log("Chrome window \(wid): restore is active or incomplete; leaving in place")
        return
    }

    for attempt in 0..<windowListingAttempts {
        let listing = sh(["list-windows", "--all", "--format", "%{window-id}|%{workspace}|%{app-name}"])
        var currentWs: String? = nil
        struct Row { let id: UInt32; let ws: String; let app: String }
        var rows: [Row] = []
        for line in listing.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3, let id = UInt32(parts[0]) else { continue }
            let row = Row(id: id, ws: String(parts[1]), app: String(parts[2]))
            rows.append(row)
            if id == wid { currentWs = row.ws }
        }
        guard let ws = currentWs else {
            if attempt < windowListingAttempts - 1 { Thread.sleep(forTimeInterval: 0.5) }
            continue
        }
        let siblingChromeOnWs = rows.contains {
            $0.ws == ws && $0.id != wid && $0.app == "Google Chrome"
        }
        if siblingChromeOnWs {
            log("Chrome window \(wid) on \(ws): already has Chrome here, leaving in place")
            scheduleWindowStateSave("chrome-window-detected")
            return
        }
        guard let monitor = ws.first else {
            scheduleWindowStateSave("chrome-window-detected")
            return
        }
        let monitorSlot = Int(String(monitor)) ?? 0
        let activeSlotCount = activeMonitorSlotCount()
        let targetMonitor = monitorSlot < activeSlotCount ? String(monitor) : "0"
        if let target = firstEmptyOnMonitor(targetMonitor, skip: ws) {
            log("Chrome window \(wid) alone on \(ws) -> \(target)")
            sh(["move-node-to-workspace", "--window-id", "\(wid)", target])
            sh(["workspace", target])
        } else {
            log("Chrome window \(wid) alone on \(ws): monitor \(targetMonitor) full, leaving in place")
        }
        scheduleWindowStateSave("chrome-window-detected")
        return
    }
    log("Chrome window \(wid) never appeared in aerospace listing")
}

let axCallback: AXObserverCallback = { _, element, _, _ in
    var wid: CGWindowID = 0
    if _AXUIElementGetWindow(element, &wid) == .success {
        DispatchQueue.global().async { handleNewWindow(wid) }
    }
}

var currentObserver: AXObserver?
var currentPid: pid_t = 0

func detachObserver() {
    if let obs = currentObserver {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }
    currentObserver = nil
    currentPid = 0
}

@discardableResult
func attachObserver(_ pid: pid_t) -> Bool {
    detachObserver()
    var observer: AXObserver?
    let createResult = AXObserverCreate(pid, axCallback, &observer)
    guard createResult == .success, let obs = observer else {
        log("AXObserverCreate failed for pid \(pid): \(createResult.rawValue)")
        return false
    }
    let app = AXUIElementCreateApplication(pid)
    let addResult = AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, nil)
    if addResult != .success {
        log("AXObserverAddNotification failed for pid \(pid): \(addResult.rawValue)")
        return false
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    currentObserver = obs
    currentPid = pid
    log("attached AX observer to Chrome pid \(pid)")
    return true
}

func chromeApp() -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == chromeBundleID }
}

func trustedForAX(prompt: Bool = false) -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([promptKey: prompt] as CFDictionary)
}

func attachChromeIfPossible(prompt: Bool = false) {
    guard currentObserver == nil else { return }
    let trusted = trustedForAX(prompt: prompt)
    log("AXIsProcessTrusted: \(trusted)")
    guard trusted else { return }
    guard let app = chromeApp() else { return }
    _ = attachObserver(app.processIdentifier)
}

attachChromeIfPossible(prompt: true)

Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
    attachChromeIfPossible()
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil
) { notif in
    if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
       app.bundleIdentifier == chromeBundleID {
        if trustedForAX(prompt: true) {
            _ = attachObserver(app.processIdentifier)
        } else {
            log("Chrome launched, but chrome_rehome is not Accessibility-trusted")
        }
    }
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil
) { notif in
    if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
       app.processIdentifier == currentPid {
        log("Chrome terminated, detaching observer")
        detachObserver()
    }
}

log("chrome_rehome started")
RunLoop.main.run()
CHROME_REHOME_SWIFT_EOF

  if [[ -f "$CHROME_REHOME_SRC" ]] && cmp -s "$source_tmp" "$CHROME_REHOME_SRC"; then
    rm -f "$source_tmp"
  else
    mv "$source_tmp" "$CHROME_REHOME_SRC"
    source_changed=1
  fi

  if ! command -v swiftc &>/dev/null; then
    warn "swiftc not found — install Xcode Command Line Tools (xcode-select --install)"
    return 1
  fi

  if [[ "$source_changed" -eq 1 || ! -x "$CHROME_REHOME_BIN" ]]; then
    info "Compiling chrome_rehome..."
    swiftc -O "$CHROME_REHOME_SRC" -o "$CHROME_REHOME_BIN"
    chmod +x "$CHROME_REHOME_BIN"
  else
    info "chrome_rehome source unchanged; keeping existing binary for Accessibility trust"
  fi
  cat > "$CHROME_REHOME_APP/Contents/Info.plist" << CHROME_REHOME_INFO_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>chrome_rehome</string>
  <key>CFBundleIdentifier</key>
  <string>$CHROME_REHOME_LABEL</string>
  <key>CFBundleName</key>
  <string>Omarchy Chrome Rehome</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSBackgroundOnly</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
CHROME_REHOME_INFO_PLIST_EOF

  if [[ "$source_changed" -eq 1 ]] || ! /usr/bin/codesign --verify "$CHROME_REHOME_APP" >/dev/null 2>&1; then
    /usr/bin/codesign --force --sign - --identifier "$CHROME_REHOME_LABEL" "$CHROME_REHOME_APP" >/dev/null 2>&1 || \
      warn "Could not ad-hoc sign $CHROME_REHOME_APP"
  fi
  xattr -dr com.apple.quarantine "$CHROME_REHOME_APP" 2>/dev/null || true
  xattr -dr com.apple.provenance "$CHROME_REHOME_APP" 2>/dev/null || true

  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$CHROME_REHOME_PLIST" << CHROME_REHOME_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$CHROME_REHOME_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$CHROME_REHOME_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/chrome_rehome.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/chrome_rehome.log</string>
</dict>
</plist>
CHROME_REHOME_PLIST_EOF

  success "chrome_rehome daemon written"
}

# =============================================================================
# JANKYBORDERS CONFIG
# =============================================================================
write_borders_config_if_enabled() {
  if borders_enabled; then
    write_borders_config
  else
    info "Skipping optional JankyBorders config"
  fi
}

write_borders_config() {
  info "Writing JankyBorders config..."
  mkdir -p "$BORDERS_DIR"

  cat > "$BORDERS_DIR/bordersrc" << 'BORDERS_EOF'
#!/usr/bin/env bash
# =============================================================================
# JankyBorders — colored border on focused window
# Active border = Catppuccin Mauve (purple), matches Omarchy accent
# =============================================================================

options=(
  style=round                    # round corners
  width=3.0                      # border thickness
  hidpi=on                       # retina-aware
  active_color=0xffcba6f7        # mauve (Catppuccin) — focused window
  inactive_color=0xff313244      # surface0 — all other windows
  background_color=0x00000000    # transparent bg
)

borders "${options[@]}"
BORDERS_EOF

  chmod +x "$BORDERS_DIR/bordersrc"
  success "JankyBorders config written to $BORDERS_DIR/bordersrc"
}

# =============================================================================
# USAGE / ENTRY POINT
# =============================================================================
usage() {
  echo ""
  echo -e "${BOLD}omarchy-macos${RESET} — Hyprland-style window management for macOS M1"
  echo ""
  echo "  ./install.sh install   install and configure core tools"
  echo "                         set OMARCHY_ENABLE_BORDERS=1 to include JankyBorders"
  echo "  ./install.sh refresh   rewrite generated configs without reinstalling packages"
  echo "  ./install.sh repair-spaces"
  echo "                         move windows off detached monitor workspaces"
  echo "  ./install.sh save-window-state"
  echo "                         save current window/workspace layout for reboot restore"
  echo "  ./install.sh restore-window-state"
  echo "                         restore the saved window/workspace layout now"
  echo "  ./install.sh shortcuts-widget"
  echo "                         regenerate the desktop shortcut image"
  echo "  ./install.sh secure-input [--watch [seconds]]"
  echo "                         show the macOS Secure Input owner"
  echo "  ./install.sh revert    undo everything, restore previous state"
  echo "  ./install.sh status    show install and service status"
  echo ""
}

case "${1:-}" in
  install)       cmd_install       ;;
  refresh)       cmd_refresh       ;;
  repair-spaces) cmd_repair_spaces ;;
  save-window-state) cmd_save_window_state ;;
  restore-window-state) cmd_restore_window_state ;;
  shortcuts-widget) cmd_shortcuts_widget ;;
  secure-input)  cmd_secure_input  "$@" ;;
  revert)        cmd_revert        ;;
  status)        cmd_status        ;;
  *)             usage; exit 1     ;;
esac
