#!/usr/bin/env bash
# =============================================================================
# omarchy-macos — Hyprland/Omarchy-style window management for macOS M1
#
# Usage:
#   ./omarchy.sh install   — install and configure everything
#   ./omarchy.sh refresh   — rewrite generated configs without reinstalling brew packages
#   ./omarchy.sh save-window-state — save current window/workspace layout
#   ./omarchy.sh restore-window-state — replay saved window/workspace layout
#   ./omarchy.sh secure-input [--watch] — diagnose macOS Secure Input owner
#   ./omarchy.sh accessibility — diagnose Accessibility permissions
#   ./omarchy.sh revert    — undo everything, restore previous state
#   ./omarchy.sh status    — show what's installed and running
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

BAR_TOGGLE_LABELS=("com.omarchy-macos.bar_toggle" "com.omarchy.bar-toggle")

AEROSPACE_START_LABEL="com.omarchy-macos.aerospace_start"
AEROSPACE_START_PLIST="$HOME/Library/LaunchAgents/$AEROSPACE_START_LABEL.plist"

WINDOW_PICKER_SRC="$AEROSPACE_DIR/window_picker.swift"
WINDOW_PICKER_BIN="$AEROSPACE_DIR/window_picker"
SECURE_INPUT_HELPER="$AEROSPACE_DIR/secure_input_report.sh"
ACCESSIBILITY_REPORT_HELPER="$AEROSPACE_DIR/accessibility_report.sh"
NATIVE_INPUT_HELPER="$AEROSPACE_DIR/native_input_mode.sh"

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
SHORTCUT_WIDGET_PID_FILE="/tmp/omarchy_shortcut_widget.pid"

WINDOW_STATE_FILE="$AEROSPACE_DIR/omarchy_window_state.json"
WINDOW_STATE_HELPER="$AEROSPACE_DIR/window_state.pl"
WINDOW_STATE_WRAPPER="$AEROSPACE_DIR/window_state.sh"
WINDOW_STATE_LOG="/tmp/omarchy_window_state.log"
WINDOW_STATE_SAVER="$AEROSPACE_DIR/window_state_saver.sh"
WINDOW_STATE_DEBOUNCED_SAVER="$AEROSPACE_DIR/window_state_debounced_save.sh"
WINDOW_STATE_MONITOR_MOVE_HELPER="$AEROSPACE_DIR/move_node_to_monitor_and_save.sh"
RESPONSIVE_LAYOUT_HELPER="$AEROSPACE_DIR/responsive_layout.sh"
ASSIGNED_WINDOW_REHOME_HELPER="$AEROSPACE_DIR/assigned_window_rehome.sh"
WORKSPACE_CHANGE_LOG_HELPER="$AEROSPACE_DIR/workspace_change_log.sh"
REHOMED_WINDOW_CLOSE_WATCHER="$AEROSPACE_DIR/rehomed_window_close_watch.sh"
MONITOR_FRAME_SRC="$AEROSPACE_DIR/monitor_frame.swift"
MONITOR_FRAME_BIN="$AEROSPACE_DIR/monitor_frame"
WINDOW_STATE_SAVE_INTERVAL_SECONDS=900
WINDOW_STATE_SAVER_LABEL="com.omarchy-macos.window_state_saver"
WINDOW_STATE_SAVER_PLIST="$HOME/Library/LaunchAgents/$WINDOW_STATE_SAVER_LABEL.plist"
WINDOW_STATE_REFRESH_RESTART_MARKER="${TMPDIR:-/tmp}/omarchy_window_state_refresh_restart"
SHORTCUT_IMAGE_SRC="$AEROSPACE_DIR/shortcut_image.swift"
SHORTCUT_IMAGE_BIN="$AEROSPACE_DIR/shortcut_image"
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
  write_native_input_helper
  write_window_cycle_helper
  write_window_picker_helper
  write_secure_input_helper
  write_accessibility_report_helper
  write_aerospace_start_agent
  write_skhd_config
  write_sketchybar_config
  write_borders_config_if_enabled
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
  echo -e "  ${BOLD}Modifier key:${RESET} Left Option (⌥) = SUPER; Right Option stays native"
  echo ""
  echo -e "  ${BOLD}Essential shortcuts:${RESET}"
  echo "  Left ⌥ + 1-0          switch workspace"
  echo "  Left ⌥ + arrows       focus window"
  echo "  Left ⌥ + shift + arrows  swap window"
  echo "  Left ⌥ + return       open terminal (Ghostty → WezTerm → Terminal)"
  echo "  Left ⌥ + space        Raycast launcher"
  echo "  Left ⌥ + f            fullscreen toggle"
  echo "  Left ⌥ + w            close focused window"
  echo "  Fn + Escape           toggle Native Input passthrough"
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
  write_native_input_helper
  write_window_cycle_helper
  write_window_picker_helper
  write_secure_input_helper
  write_accessibility_report_helper
  write_aerospace_start_agent
  write_skhd_config
  write_sketchybar_config
  write_borders_config_if_enabled
  write_shortcut_desktop_widget

  header "Restarting services..."
  stop_services
  start_services refresh

  echo ""
  success "Configuration refreshed."
  echo "Run './install.sh repair-spaces' once after AeroSpace is healthy to move windows off detached monitor workspaces."
}

# =============================================================================
# SHORTCUT DESKTOP WIDGET
# =============================================================================
cmd_shortcuts_widget() {
  header "omarchy-macos shortcut widget"
  stop_shortcut_widget
  write_shortcut_desktop_widget
  if [[ -f "$SHORTCUT_WIDGET_PLIST" ]]; then
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
  "$HOME/.config/sketchybar/plugins/restore_status.sh" complete >/dev/null 2>&1 || true
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

cmd_accessibility() {
  header "omarchy-macos accessibility"
  write_accessibility_report_helper >/dev/null
  "$ACCESSIBILITY_REPORT_HELPER" "${@:2}"
}

write_shortcut_desktop_widget() {
  mkdir -p "$AEROSPACE_DIR" "$SHORTCUT_WIDGET_APP/Contents/MacOS" "$HOME/Library/LaunchAgents"

  if ! command -v swiftc &>/dev/null; then
    warn "swiftc not found — shortcut image and desktop widget were not built"
    return 0
  fi

  cat > "$SHORTCUT_IMAGE_SRC" << 'SHORTCUT_IMAGE_SWIFT_EOF'
import AppKit

struct Row {
    let key: String
    let action: String
}

struct Section {
    let title: String
    let color: NSColor
    let rows: [Row]
}

extension NSColor {
    convenience init(rgb r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat = 1.0) {
        self.init(calibratedRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: alpha)
    }
}

let bg       = NSColor(rgb: 30, 30, 46)
let surface  = NSColor(rgb: 49, 50, 68)
let overlay  = NSColor(rgb: 69, 71, 90)
let text     = NSColor(rgb: 205, 214, 244)
let subtext  = NSColor(rgb: 166, 173, 200)
let mauve    = NSColor(rgb: 203, 166, 247)
let blue     = NSColor(rgb: 137, 180, 250)
let green    = NSColor(rgb: 166, 227, 161)
let peach    = NSColor(rgb: 250, 179, 135)
let pink     = NSColor(rgb: 245, 194, 231)
let yellow   = NSColor(rgb: 249, 226, 175)
let teal     = NSColor(rgb: 148, 226, 213)
let lavender = NSColor(rgb: 180, 190, 254)

let fontSm = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
let fontMd = NSFont.monospacedSystemFont(ofSize: 16, weight: .regular)
let fontLg = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
let fontTitle = NSFont.monospacedSystemFont(ofSize: 28, weight: .bold)
let fontKey = NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)

let sections = [
    Section(title: "Workspaces", color: mauve, rows: [
        Row(key: "L⌥ 1-0", action: "Switch workspace"),
        Row(key: "L⌥ ⇧ 1-0", action: "Move and follow"),
        Row(key: "L⌥ ⇧ ⌃ 1-0", action: "Move without follow"),
        Row(key: "L⌥ Tab", action: "Next workspace"),
        Row(key: "L⌥ ⇧ Tab", action: "Previous workspace"),
        Row(key: "L⌥ ⌘ Tab", action: "Former workspace"),
    ]),
    Section(title: "Focus", color: blue, rows: [
        Row(key: "L⌥ Arrows", action: "Focus direction"),
        Row(key: "⌃ Tab", action: "Next local window"),
        Row(key: "⌃ ⇧ Tab", action: "Previous local window"),
        Row(key: "⌘ ⌃ Tab", action: "Next monitor"),
    ]),
    Section(title: "Move", color: green, rows: [
        Row(key: "L⌥ ⇧ Arrows", action: "Swap window"),
        Row(key: "L⌥ ⇧ ⌃ Arrows", action: "Move monitor"),
    ]),
    Section(title: "Resize", color: peach, rows: [
        Row(key: "L⌥ - / =", action: "Width down / up"),
        Row(key: "L⌥ ⇧ - / =", action: "Height down / up"),
    ]),
    Section(title: "Layout", color: pink, rows: [
        Row(key: "L⌥ K", action: "Shortcut reference"),
        Row(key: "L⌥ J", action: "Toggle split direction"),
        Row(key: "L⌥ L", action: "Tiles / accordion"),
        Row(key: "L⌥ T", action: "Float / tile toggle"),
        Row(key: "L⌥ F", action: "Fullscreen"),
        Row(key: "L⌥ W", action: "Close window"),
        Row(key: "auto", action: "Accordion when narrow"),
    ]),
    Section(title: "Apps", color: yellow, rows: [
        Row(key: "L⌥ Return", action: "Terminal"),
        Row(key: "L⌥ ⇧ Return", action: "Browser"),
        Row(key: "L⌥ ⇧ N", action: "Editor"),
        Row(key: "L⌥ ⇧ F", action: "Finder"),
        Row(key: "L⌥ ⇧ M", action: "Music"),
        Row(key: "L⌥ ⇧ G", action: "Chat"),
        Row(key: "L⌥ ⇧ /", action: "Passwords"),
    ]),
    Section(title: "Misc", color: teal, rows: [
        Row(key: "Fn Esc", action: "Toggle Native Input"),
        Row(key: "R⌥ Arrows", action: "Native text movement"),
        Row(key: "L⌥ ⇧ S", action: "Screenshot (region)"),
        Row(key: "L⌥ ⌘ ↑", action: "Mission Control"),
        Row(key: "L⌥ Z", action: "Toggle bar"),
        Row(key: "L⌥ Space", action: "Raycast launcher"),
    ]),
]

let colWidth: CGFloat = 340
let padding: CGFloat = 30
let sectionGap: CGFloat = 18
let rowHeight: CGFloat = 26
let headerHeight: CGFloat = 32
let keyCol: CGFloat = 140

var colHeights = [CGFloat](repeating: 0, count: 2)
var colSections = [[Section]](repeating: [], count: 2)
for section in sections {
    let height = headerHeight + CGFloat(section.rows.count) * rowHeight + sectionGap
    let target = colHeights[0] <= colHeights[1] ? 0 : 1
    colSections[target].append(section)
    colHeights[target] += height
}

let imageWidth = padding * 3 + colWidth * 2
let imageHeight = (colHeights.max() ?? 0) + padding * 2 + 60
let image = NSImage(size: NSSize(width: imageWidth, height: imageHeight))

func attrs(font: NSFont, color: NSColor) -> [NSAttributedString.Key: Any] {
    [.font: font, .foregroundColor: color]
}

func textSize(_ value: String, font: NSFont) -> NSSize {
    (value as NSString).size(withAttributes: attrs(font: font, color: text))
}

func drawText(_ value: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs(font: font, color: color))
}

func fillRounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func fillRect(_ rect: NSRect, color: NSColor) {
    color.setFill()
    NSBezierPath(rect: rect).fill()
}

image.lockFocusFlipped(true)
fillRounded(NSRect(x: 0, y: 0, width: imageWidth, height: imageHeight), radius: 16, color: bg)

let title = "omarchy-macos shortcuts"
let titleSize = textSize(title, font: fontTitle)
drawText(title, x: (imageWidth - titleSize.width) / 2, y: padding - 5, font: fontTitle, color: lavender)

let subtitle = "Omarchy: left ⌥  •  native macOS: right ⌥  •  bypass: Fn Esc"
let subtitleSize = textSize(subtitle, font: fontSm)
drawText(subtitle, x: (imageWidth - subtitleSize.width) / 2, y: padding + 28, font: fontSm, color: subtext)

for col in 0..<2 {
    let x = padding + CGFloat(col) * (colWidth + padding)
    var y = padding + 60

    for section in colSections[col] {
        fillRounded(NSRect(x: x, y: y, width: colWidth, height: headerHeight - 4), radius: 6, color: surface)
        fillRect(NSRect(x: x, y: y, width: 4, height: headerHeight - 4), color: section.color)
        drawText(section.title, x: x + 14, y: y + 4, font: fontLg, color: section.color)
        y += headerHeight + 2

        for row in section.rows {
            let keyWidth = min(textSize(row.key, font: fontKey).width + 16, keyCol - 8)
            let badgeX = x + 8
            fillRounded(NSRect(x: badgeX, y: y + 2, width: keyWidth, height: rowHeight - 4), radius: 4, color: overlay)
            drawText(row.key, x: badgeX + 8, y: y + 2, font: fontKey, color: text)
            drawText(row.action, x: x + keyCol + 8, y: y + 3, font: fontMd, color: subtext)
            y += rowHeight
        }

        y += sectionGap
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("could not render shortcut image\n", stderr)
    exit(1)
}

let output = NSString(string: NSHomeDirectory()).appendingPathComponent("Desktop/omarchy-shortcuts.png")
do {
    try png.write(to: URL(fileURLWithPath: output), options: .atomic)
} catch {
    fputs("could not write \(output): \(error)\n", stderr)
    exit(1)
}
SHORTCUT_IMAGE_SWIFT_EOF

  info "Regenerating shortcut desktop image..."
  swiftc -O "$SHORTCUT_IMAGE_SRC" -o "$SHORTCUT_IMAGE_BIN"
  "$SHORTCUT_IMAGE_BIN" >/dev/null
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

    func applicationWillTerminate(_ notification: Notification) {
        let pidPath = "/tmp/omarchy_shortcut_widget.pid"
        let current = try? String(contentsOfFile: pidPath, encoding: .utf8)
        if current?.trimmingCharacters(in: .whitespacesAndNewlines) == String(ProcessInfo.processInfo.processIdentifier) {
            try? FileManager.default.removeItem(atPath: pidPath)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        fputs("shortcut widget: application finished launching\n", stderr)
        render()
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.renderIfChanged()
        }
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        fputs("shortcut widget: screen parameters changed\n", stderr)
        render()
    }

    func renderIfChanged() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: imagePath)
        let modified = attrs?[.modificationDate] as? Date
        if modified != lastModified {
            render()
        }
    }

    func render() {
        guard let image = NSImage(contentsOfFile: imagePath) else {
            fputs("shortcut widget: cannot load image at \(imagePath)\n", stderr)
            window?.orderOut(nil)
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            fputs("shortcut widget: no screen available\n", stderr)
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
            win.isReleasedWhenClosed = false
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            // The legacy desktopIconWindow level resolves below the visible
            // wallpaper stack on macOS 26. One level below normal windows keeps
            // this click-through widget visible on the desktop while ordinary
            // application windows remain above it.
            win.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)

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
        fputs("shortcut widget: ordered window frame=\(NSStringFromRect(frame)) level=\(window?.level.rawValue ?? -1)\n", stderr)
    }
}

let app = NSApplication.shared
let policySet = app.setActivationPolicy(.accessory)
fputs("shortcut widget: accessory activation policy=\(policySet)\n", stderr)
try? String(ProcessInfo.processInfo.processIdentifier).write(
    toFile: "/tmp/omarchy_shortcut_widget.pid",
    atomically: true,
    encoding: .utf8
)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
SHORTCUT_WIDGET_SWIFT_EOF

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
    <string>/usr/bin/open</string>
    <string>-W</string>
    <string>-n</string>
    <string>-g</string>
    <string>-o</string>
    <string>/tmp/omarchy_shortcut_widget.log</string>
    <string>--stderr</string>
    <string>/tmp/omarchy_shortcut_widget.log</string>
    <string>-a</string>
    <string>$SHORTCUT_WIDGET_APP</string>
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
  disable_bar_toggle_daemons
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
  if [[ -x "$ACCESSIBILITY_REPORT_HELPER" ]]; then
    "$ACCESSIBILITY_REPORT_HELPER" || true
  else
    warn "Accessibility helper missing — run './install.sh refresh'"
  fi
  echo ""
  if aerospace list-monitors --format '%{monitor-id}' >/dev/null 2>&1; then
    success "AeroSpace server reachable"
  else
    warn "AeroSpace server is not reachable — window restore and workspace moves will fail"
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

disable_bar_toggle_daemons() {
  local label plist

  for label in "${BAR_TOGGLE_LABELS[@]}"; do
    plist="$HOME/Library/LaunchAgents/$label.plist"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || \
      launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist"
  done
}

stop_shortcut_widget() {
  launchctl unload "$SHORTCUT_WIDGET_PLIST" 2>/dev/null || true

  local pid=""
  if [[ -f "$SHORTCUT_WIDGET_PID_FILE" ]]; then
    pid=$(cat "$SHORTCUT_WIDGET_PID_FILE" 2>/dev/null || true)
  fi
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    local command_name
    command_name=$(ps -p "$pid" -o comm= 2>/dev/null | awk -F/ '{print $NF}')
    if [[ "$command_name" == "shortcut_widget" ]]; then
      kill "$pid" 2>/dev/null || true
      for _ in {1..20}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
      done
    fi
  fi
  rm -f "$SHORTCUT_WIDGET_PID_FILE"
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
  local mode="${1:-normal}"

  info "Loading AeroSpace login starter..."
  launchctl unload "$AEROSPACE_START_PLIST" 2>/dev/null || true
  launchctl load "$AEROSPACE_START_PLIST" 2>/dev/null || \
    warn "Could not load AeroSpace login LaunchAgent"

  info "Starting window state saver..."
  if [[ "$mode" == "refresh" ]]; then
    printf '%s\n' 'skip-next-startup-guard' > "$WINDOW_STATE_REFRESH_RESTART_MARKER" 2>/dev/null || true
  fi
  launchctl unload "$WINDOW_STATE_SAVER_PLIST" 2>/dev/null || true
  launchctl load "$WINDOW_STATE_SAVER_PLIST" 2>/dev/null || \
    warn "Could not load window state saver LaunchAgent"
  if [[ "$mode" == "refresh" ]]; then
    # The saver consumes this one-shot marker before seeding its login-only
    # startup guard. Bound the wait and remove leftovers so a failed refresh
    # can never suppress a future real login restore.
    for _ in {1..20}; do
      [[ ! -e "$WINDOW_STATE_REFRESH_RESTART_MARKER" ]] && break
      sleep 0.1
    done
    rm -f "$WINDOW_STATE_REFRESH_RESTART_MARKER"
  fi

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
  if command -v sketchybar >/dev/null 2>&1; then
    CONFIG_DIR="$SKETCHY_DIR" sketchybar --reload >/dev/null 2>&1 || true
    "$SKETCHY_DIR/plugins/restore_status.sh" refresh >/dev/null 2>&1 || true
  fi
  "$NATIVE_INPUT_HELPER" reset >/dev/null 2>&1 || true

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
  disable_bar_toggle_daemons

  info "Disabling legacy chrome_rehome daemon..."
  if [[ -f "$CHROME_REHOME_PLIST" ]]; then
    launchctl unload "$CHROME_REHOME_PLIST" 2>/dev/null || true
  fi

  info "Starting shortcut desktop widget..."
  stop_shortcut_widget
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
  disable_bar_toggle_daemons
  if [[ -f "$CHROME_REHOME_PLIST" ]]; then
    launchctl unload "$CHROME_REHOME_PLIST" 2>/dev/null && info "  stopped chrome_rehome" || true
  fi
  if [[ -f "$SHORTCUT_WIDGET_PLIST" ]]; then
    stop_shortcut_widget
    info "  stopped shortcut widget"
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
    monitor_pattern="${external_ids[$((slot - 1))]:-}"
    [ -n "$monitor_pattern" ] || continue
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
exec-on-workspace-change = ['/bin/bash', '-c', '~/.config/aerospace/workspace_change_log.sh "\$AEROSPACE_PREV_WORKSPACE" "\$AEROSPACE_FOCUSED_WORKSPACE"']

# Start Aerospace on login
start-at-login = true

# Remap Option keys so macOS doesn't swallow ⌥+key as special characters
key-mapping.preset = 'qwerty'

# Normalisation: flatten nested containers (keeps tree clean)
enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

# ── Workspace monitor assignment ──────────────────────────────────────────
# AeroSpace assigns empty workspaces to the main monitor by default. Attached
# external slot assignments make 10-39 native to up to three external displays without
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

# ── Hotkey modes ──────────────────────────────────────────────────────────
# skhd owns all user-facing global bindings so left and right Option can be
# distinguished and terminal apps can receive native Option/Meta input.
# AeroSpace remains the command engine. Native Input mode is intentionally
# empty and is selected by ~/.config/aerospace/native_input_mode.sh.
[mode.main.binding]

[mode.native_input.binding]

# ── App → workspace assignments ───────────────────────────────────────────

[[on-window-detected]]
run = 'exec-and-forget ~/.config/aerospace/window_state_debounced_save.sh window-detected'
check-further-callbacks = true

# App-assignment rules default to monitor 0's spaces ("0N"). If a second
# monitor is attached, move the app to <monitor><N> manually after launch.
[[on-window-detected]]
if.app-id = 'com.apple.mail'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 01 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-id = 'com.google.Chrome.app.fmgjjmmmlfnkbppncabfkddbjimcfncm'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 01 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-name-regex-substring = 'Messages'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 02 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-name-regex-substring = 'Signal'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 02 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-name-regex-substring = 'Google Chat'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 02 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-name-regex-substring = 'Spotify|Music'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 03 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-name-regex-substring = 'Ghostty|WezTerm|Warp|iTerm2'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 04 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-name-regex-substring = 'Zed|Antigravity'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 05 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-id = 'com.anthropic.claudefordesktop'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 06 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-id = 'com.google.GeminiMacOS'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 06 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-id = 'com.openai.chat'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 06 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

[[on-window-detected]]
if.app-name-regex-substring = 'ChatGPT'
run = 'exec-and-forget ~/.config/aerospace/assigned_window_rehome.sh 06 "\$AEROSPACE_WINDOW_ID"'
check-further-callbacks = true

# Keep authentication prompts and password dialogs visible on the current
# workspace. AeroSpace cannot force true "always on top", but floating and
# avoiding fallback rehoming prevents these dialogs from blinking away to 00.
[[on-window-detected]]
if.app-name-regex-substring = '1Password'
run = ['layout floating']

[[on-window-detected]]
if = 'true'
run = 'exec-and-forget ~/.config/aerospace/unassigned_window_rehome.sh "\$AEROSPACE_WINDOW_ID"'

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
OMARCHY_COMMAND_TIMEOUT_SECONDS="${OMARCHY_COMMAND_TIMEOUT_SECONDS:-5}"

omarchy_run_bounded() {
  local timeout_seconds="$1"
  shift
  case "$timeout_seconds" in
    ''|*[!0-9]*) timeout_seconds=5 ;;
  esac
  [ "$timeout_seconds" -gt 0 ] || timeout_seconds=5

  /usr/bin/perl -MPOSIX=:sys_wait_h -e '
    my $timeout = shift @ARGV;
    my $pid = fork();
    exit 127 unless defined $pid;
    if ($pid == 0) {
      setpgrp(0, 0);
      exec @ARGV;
      exit 127;
    }

    local $SIG{ALRM} = sub {
      kill "TERM", -$pid;
      select undef, undef, undef, 0.1;
      kill "KILL", -$pid;
      waitpid($pid, 0);
      exit 124;
    };

    alarm $timeout;
    waitpid($pid, 0);
    alarm 0;
    exit(WIFEXITED($?) ? WEXITSTATUS($?) : 128 + WTERMSIG($?));
  ' "$timeout_seconds" "$@"
}

omarchy_aerospace_available() {
  omarchy_run_bounded "$OMARCHY_COMMAND_TIMEOUT_SECONDS" \
    "$OMARCHY_AEROSPACE_BIN" list-monitors --format '%{monitor-id}' >/dev/null 2>&1
}

omarchy_monitor_rows_by_slot() {
  local rows line monitor_id monitor_name
  rows=$(omarchy_run_bounded "$OMARCHY_COMMAND_TIMEOUT_SECONDS" \
    "$OMARCHY_AEROSPACE_BIN" list-monitors --format '%{monitor-id}|%{monitor-name}|%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null) || return 1

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
    *Mail*|*Gmail*) printf '01\n'; return 0 ;;
    *Messages*|*Signal*|*Google\ Chat*) printf '02\n'; return 0 ;;
    *Spotify*|*Music*) printf '03\n'; return 0 ;;
    *Ghostty*|*WezTerm*|*Warp*|*iTerm2*) printf '04\n'; return 0 ;;
    *Zed*|*Antigravity*) printf '05\n'; return 0 ;;
    *ChatGPT*) printf '06\n'; return 0 ;;
  esac

  case "$bundle_id" in
    com.anthropic.claudefordesktop|com.google.GeminiMacOS|com.openai.chat)
      printf '06\n'
      return 0
      ;;
  esac

  return 1
}

omarchy_space_alias_lines() {
  local alias_file="${OMARCHY_SPACE_ALIAS_FILE:-$HOME/.config/sketchybar/space_aliases}"
  if [ -f "$alias_file" ]; then
    awk -F= '$1 ~ /^0[0-9]$/ && length($2) { print $0 }' "$alias_file" 2>/dev/null
    return 0
  fi

  printf '%s\n' \
    '01=Mail' \
    '02=Msg' \
    '03=Music' \
    '04=Terms' \
    '05=Editors' \
    '06=Agents'
}

omarchy_named_workspace_keys() {
  omarchy_space_alias_lines |
    awk -F= '$1 ~ /^0[1-9]$/ { print substr($1, 2, 1) }' |
    sort -u
}

omarchy_workspace_key() {
  local workspace="$1"
  if [[ "$workspace" =~ ^[0-9][0-9]$ ]]; then
    printf '%s\n' "${workspace:1:1}"
  elif [[ "$workspace" =~ ^[0-9]$ ]]; then
    printf '%s\n' "$workspace"
  else
    return 1
  fi
}

omarchy_is_named_workspace() {
  local workspace="$1"
  local key named_key
  key=$(omarchy_workspace_key "$workspace") || return 1
  [ "$key" = "0" ] && return 1

  while IFS= read -r named_key; do
    [ "$key" = "$named_key" ] && return 0
  done < <(omarchy_named_workspace_keys)

  return 1
}

omarchy_nearest_empty_unnamed_workspace() {
  local workspace="$1"
  local rows="$2"
  local ignored_window_id="${3:-}"
  local slot launch_key key candidate row_window_id row_workspace
  local occupied distance target="" best_distance=99

  launch_key=$(omarchy_workspace_key "$workspace") || return 1
  if [[ "$workspace" =~ ^([0-9])[0-9]$ ]]; then
    slot="${BASH_REMATCH[1]}"
  else
    slot=$(omarchy_focused_monitor_slot 2>/dev/null || printf '0')
  fi
  [[ "$slot" =~ ^[0-9]+$ ]] || slot=0

  for key in 1 2 3 4 5 6 7 8 9; do
    omarchy_is_named_workspace "0${key}" && continue
    candidate="${slot}${key}"
    occupied=0
    while IFS='|' read -r row_window_id row_workspace _; do
      [[ "$row_window_id" =~ ^[0-9]+$ ]] || continue
      [ -n "$ignored_window_id" ] && [ "$row_window_id" = "$ignored_window_id" ] && continue
      if [ "$row_workspace" = "$candidate" ]; then
        occupied=1
        break
      fi
    done <<< "$rows"
    [ "$occupied" -eq 0 ] || continue

    distance=$((key - launch_key))
    [ "$distance" -lt 0 ] && distance=$((-distance))
    if [ "$distance" -lt "$best_distance" ]; then
      target="$candidate"
      best_distance="$distance"
    fi
  done

  [ -n "$target" ] || target="${slot}0"
  printf '%s\n' "$target"
}

omarchy_repair_app_assigned_workspaces() {
  local rows line window_id workspace app_name bundle_id target
  rows=$("$OMARCHY_AEROSPACE_BIN" list-windows --all --format '%{window-id}|%{workspace}|%{app-name}|%{app-bundle-id}' 2>/dev/null) || return 1
  while IFS= read -r line; do
    IFS='|' read -r window_id workspace app_name bundle_id <<< "$line"
    [[ "$window_id" =~ ^[0-9]+$ ]] || continue
    target=$(omarchy_assigned_workspace_for_app "$app_name" "$bundle_id" 2>/dev/null || true)
    if [ -z "$target" ] && [ "$workspace" = "02" ]; then
      target="08"
    elif [ -z "$target" ] && omarchy_is_named_workspace "$workspace"; then
      target=$(omarchy_nearest_empty_unnamed_workspace "$workspace" "$rows" "$window_id" 2>/dev/null || true)
    fi
    [ -n "$target" ] || continue
    [ "$workspace" = "$target" ] && continue
    if "$OMARCHY_AEROSPACE_BIN" move-node-to-workspace --window-id "$window_id" "$target" >/dev/null 2>&1; then
      rows=$(printf '%s\n' "$rows" | awk -F'|' -v OFS='|' -v id="$window_id" -v target="$target" '$1 == id {$2 = target} {print}')
    fi
  done <<< "$rows"
}
SPACE_STATE_EOF

  chmod +x "$AEROSPACE_DIR/omarchy_space_state.sh"

  cat > "$ASSIGNED_WINDOW_REHOME_HELPER" << 'ASSIGNED_WINDOW_REHOME_EOF'
#!/usr/bin/env bash
set -euo pipefail

target="${1:-}"
window_id="${2:-${AEROSPACE_WINDOW_ID:-}}"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"
OMARCHY_AEROSPACE_BIN="${OMARCHY_AEROSPACE_BIN:-aerospace}"

log_msg() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

[[ "$target" =~ ^[0-9][0-9]$ ]] || exit 0
[[ "$window_id" =~ ^[0-9]+$ ]] || exit 0

detected=$("$OMARCHY_AEROSPACE_BIN" list-windows --all \
  --format '%{window-id}|%{workspace}|%{app-name}|%{app-bundle-id}|%{window-title}' 2>/dev/null |
  awk -F'|' -v id="$window_id" '$1 == id { print; exit }') || true
focused=$("$OMARCHY_AEROSPACE_BIN" list-windows --focused \
  --format '%{window-id}|%{workspace}|%{app-name}|%{app-bundle-id}|%{window-title}' 2>/dev/null |
  head -n 1) || true

if [ -z "$detected" ]; then
  log_msg "assigned window callback could not find window=$window_id target=$target focused=${focused:-none}"
  exit 0
fi

IFS='|' read -r _ source_workspace app_name bundle_id title <<< "$detected"
if [ "$source_workspace" = "$target" ]; then
  log_msg "assigned window detected window=$window_id already=$target app=$app_name bundle=$bundle_id title=$title focused_before=${focused:-none}; no workspace activation"
  exit 0
fi

if "$OMARCHY_AEROSPACE_BIN" move-node-to-workspace --window-id "$window_id" "$target" >/dev/null 2>&1; then
  focused_after=$("$OMARCHY_AEROSPACE_BIN" list-windows --focused \
    --format '%{window-id}|%{workspace}|%{app-name}|%{app-bundle-id}|%{window-title}' 2>/dev/null |
    head -n 1) || true
  log_msg "assigned window moved window=$window_id from=$source_workspace to=$target app=$app_name bundle=$bundle_id title=$title focused_before=${focused:-none} focused_after=${focused_after:-none}; no workspace activation"
else
  log_msg "assigned window move failed window=$window_id from=$source_workspace to=$target app=$app_name bundle=$bundle_id title=$title focused_before=${focused:-none}"
fi
ASSIGNED_WINDOW_REHOME_EOF

  chmod +x "$ASSIGNED_WINDOW_REHOME_HELPER"

  cat > "$WORKSPACE_CHANGE_LOG_HELPER" << 'WORKSPACE_CHANGE_LOG_EOF'
#!/usr/bin/env bash
set -euo pipefail

previous="${1:-unknown}"
focused_workspace="${2:-unknown}"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"
OMARCHY_AEROSPACE_BIN="${OMARCHY_AEROSPACE_BIN:-aerospace}"

focused_window=$("$OMARCHY_AEROSPACE_BIN" list-windows --focused \
  --format '%{window-id}|%{workspace}|%{app-name}|%{app-bundle-id}|%{window-title}' 2>/dev/null |
  head -n 1) || true
printf '[%s] workspace focus changed from=%s to=%s focused_window=%s\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$previous" "$focused_workspace" "${focused_window:-none}" \
  >> "$LOG_FILE" 2>/dev/null || true
WORKSPACE_CHANGE_LOG_EOF

  chmod +x "$WORKSPACE_CHANGE_LOG_HELPER"

  cat > "$REHOMED_WINDOW_CLOSE_WATCHER" << 'REHOMED_WINDOW_CLOSE_WATCH_EOF'
#!/usr/bin/env bash
set -euo pipefail

window_id="${1:-}"
source_workspace="${2:-}"
target_workspace="${3:-}"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"
OMARCHY_AEROSPACE_BIN="${OMARCHY_AEROSPACE_BIN:-aerospace}"
POLL_INTERVAL="${OMARCHY_REHOME_CLOSE_POLL_INTERVAL:-1}"
SETTLE_DELAY="${OMARCHY_REHOME_CLOSE_SETTLE_DELAY:-0.5}"
MAX_SECONDS="${OMARCHY_REHOME_CLOSE_MAX_SECONDS:-21600}"

log_msg() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

[[ "$window_id" =~ ^[0-9]+$ ]] || exit 0
[[ "$source_workspace" =~ ^[0-9][0-9]$ ]] || exit 0
[[ "$target_workspace" =~ ^[0-9][0-9]$ ]] || exit 0
case "$MAX_SECONDS" in ''|*[!0-9]*) MAX_SECONDS=21600 ;; esac

deadline=$((SECONDS + MAX_SECONDS))
while [ "$SECONDS" -lt "$deadline" ]; do
  window_ids=$("$OMARCHY_AEROSPACE_BIN" list-windows --all --format '%{window-id}' 2>/dev/null) || {
    sleep "$POLL_INTERVAL" 2>/dev/null || true
    continue
  }
  if ! grep -qx "$window_id" <<< "$window_ids"; then
    break
  fi
  sleep "$POLL_INTERVAL" 2>/dev/null || true
done

if [ "$SECONDS" -ge "$deadline" ]; then
  log_msg "rehomed window close watch expired window=$window_id source=$source_workspace target=$target_workspace"
  exit 0
fi

# Let macOS activation and AeroSpace window-destruction events settle. The
# observed failure briefly focused the source, then bounced to an empty target
# in the same event burst.
sleep "$SETTLE_DELAY" 2>/dev/null || true

focused_workspace=$("$OMARCHY_AEROSPACE_BIN" list-workspaces --monitor focused --visible \
  --format '%{workspace}' 2>/dev/null | head -n 1) || true
[ "$focused_workspace" = "$target_workspace" ] || exit 0

target_count=$("$OMARCHY_AEROSPACE_BIN" list-windows --workspace "$target_workspace" \
  --format '%{window-id}' 2>/dev/null | awk 'NF { count++ } END { print count + 0 }') || exit 0
[ "$target_count" -eq 0 ] || exit 0

source_count=$("$OMARCHY_AEROSPACE_BIN" list-windows --workspace "$source_workspace" \
  --format '%{window-id}' 2>/dev/null | awk 'NF { count++ } END { print count + 0 }') || exit 0
[ "$source_count" -gt 0 ] || exit 0

if "$OMARCHY_AEROSPACE_BIN" workspace "$source_workspace" >/dev/null 2>&1; then
  log_msg "rehomed window closed; returned from empty workspace=$target_workspace to source=$source_workspace window=$window_id"
else
  log_msg "rehomed window closed; failed returning from empty workspace=$target_workspace to source=$source_workspace window=$window_id"
fi
REHOMED_WINDOW_CLOSE_WATCH_EOF

  chmod +x "$REHOMED_WINDOW_CLOSE_WATCHER"

  cat > "$AEROSPACE_DIR/unassigned_window_rehome.sh" << 'UNASSIGNED_WINDOW_REHOME_EOF'
#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.config/aerospace/omarchy_space_state.sh"

TMP_ROOT="${TMPDIR:-/tmp}"
RESTORE_GUARD="${OMARCHY_WINDOW_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_active}"
STARTUP_RESTORE_GUARD="${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_startup_restore_active}"
PARTIAL_RESTORE_GUARD="${OMARCHY_WINDOW_PARTIAL_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_incomplete}"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"
FOLLOW_DELAY="${OMARCHY_REHOME_FOLLOW_DELAY:-0.5}"
CLOSE_WATCHER="$HOME/.config/aerospace/rehomed_window_close_watch.sh"

log_msg() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

check_responsive_layout() {
  local reason="$1"
  "$HOME/.config/aerospace/responsive_layout.sh" "$reason" "$window_id" >/dev/null 2>&1 || true
}

follow_rehomed_window() {
  local target="$1"
  sleep "$FOLLOW_DELAY" 2>/dev/null || true
  "$OMARCHY_AEROSPACE_BIN" workspace "$target" >/dev/null 2>&1 || return 1
  "$OMARCHY_AEROSPACE_BIN" focus --window-id "$window_id" >/dev/null 2>&1 || true
}

if [[ -e "$RESTORE_GUARD" || -e "$STARTUP_RESTORE_GUARD" || -e "$PARTIAL_RESTORE_GUARD" ]]; then
  log_msg "restore active; skipped unassigned launch rehome"
  exit 0
fi

target_window_id="${1:-${AEROSPACE_WINDOW_ID:-}}"
[[ "$target_window_id" =~ ^[0-9]+$ ]] || exit 0

# The callback runs asynchronously. Focus may have changed by the time this
# helper starts, so identify the detected window by the callback's window id
# instead of consulting the currently focused window.
row=$("$OMARCHY_AEROSPACE_BIN" list-windows --all --format '%{window-id}|%{workspace}|%{app-name}|%{app-bundle-id}' 2>/dev/null \
  | awk -F'|' -v id="$target_window_id" '$1 == id { print; exit }') || exit 0
IFS='|' read -r window_id workspace app_name bundle_id <<< "$row"
[[ "$window_id" =~ ^[0-9]+$ ]] || exit 0
[ -n "$workspace" ] || exit 0

assigned=$(omarchy_assigned_workspace_for_app "$app_name" "$bundle_id" 2>/dev/null || true)
if [ -n "$assigned" ]; then
  check_responsive_layout "assigned-window-settled-$assigned"
  exit 0
fi

if ! omarchy_is_named_workspace "$workspace"; then
  check_responsive_layout "window-detected-settled-$workspace"
  exit 0
fi

windows=$("$OMARCHY_AEROSPACE_BIN" list-windows --all --format '%{window-id}|%{workspace}' 2>/dev/null) || exit 0
target=$(omarchy_nearest_empty_unnamed_workspace "$workspace" "$windows" "$window_id" 2>/dev/null || true)
if [ -z "$target" ] || [ "$target" = "$workspace" ]; then
  check_responsive_layout "window-detected-settled-$workspace"
  exit 0
fi

if "$OMARCHY_AEROSPACE_BIN" move-node-to-workspace --window-id "$window_id" "$target" >/dev/null 2>&1; then
  "$HOME/.config/aerospace/window_state_debounced_save.sh" "unassigned-window-rehome-$target" >/dev/null 2>&1 || true
  check_responsive_layout "unassigned-window-rehome-$target"
  if follow_rehomed_window "$target"; then
    log_msg "unassigned launch rehome moved and followed $window_id from $workspace to $target: $app_name / $bundle_id"
    if [ -x "$CLOSE_WATCHER" ]; then
      "$CLOSE_WATCHER" "$window_id" "$workspace" "$target" >/dev/null 2>&1 &
    fi
  else
    log_msg "unassigned launch rehome moved $window_id from $workspace to $target but follow failed: $app_name / $bundle_id"
  fi
else
  check_responsive_layout "window-detected-move-failed-$workspace"
  log_msg "unassigned launch rehome failed moving $window_id from $workspace to $target: $app_name / $bundle_id"
fi
UNASSIGNED_WINDOW_REHOME_EOF

  chmod +x "$AEROSPACE_DIR/unassigned_window_rehome.sh"

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
TARGET_WINDOW_ID="${2:-}"

sleep "$LAYOUT_GUARD_DELAY" 2>/dev/null || true

monitor_width() {
  local monitor_id="$1"
  local row row_monitor_id screen_id monitor_name width fallback_width
  row=$("$OMARCHY_AEROSPACE_BIN" list-monitors --format '%{monitor-id}|%{monitor-appkit-nsscreen-screens-id}|%{monitor-name}' 2>/dev/null |
    awk -F'|' -v id="$monitor_id" '$1 == id { print; exit }') || true
  IFS='|' read -r row_monitor_id screen_id monitor_name <<< "$row"

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

workspace=""
monitor_id=""
if [[ "$TARGET_WINDOW_ID" =~ ^[0-9]+$ ]]; then
  row=$("$OMARCHY_AEROSPACE_BIN" list-windows --all --format '%{window-id}|%{workspace}|%{monitor-id}' 2>/dev/null |
    awk -F'|' -v id="$TARGET_WINDOW_ID" '$1 == id { print; exit }') || true
  IFS='|' read -r row_window_id workspace monitor_id <<< "$row"
  [ "$row_window_id" = "$TARGET_WINDOW_ID" ] || exit 0
else
  workspace=$(omarchy_focused_workspace 2>/dev/null || true)
  monitor_id=$("$OMARCHY_AEROSPACE_BIN" list-monitors --focused --format '%{monitor-id}' 2>/dev/null | head -n 1) || true
fi
[[ -n "$workspace" ]] || exit 0
[[ "$monitor_id" =~ ^[0-9]+$ ]] || exit 0

count=$("$OMARCHY_AEROSPACE_BIN" list-windows --workspace "$workspace" --count 2>/dev/null || true)
count="$(printf '%s' "$count" | tr -cd '0-9')"
[[ "$count" =~ ^[0-9]+$ ]] || exit 0
[ "$count" -gt 1 ] || exit 0

width=$(monitor_width "$monitor_id")
[[ "$width" =~ ^[0-9]+$ ]] || exit 0

usable_width=$((width - 16 - ((count - 1) * 8)))
[ "$usable_width" -gt 0 ] || usable_width="$width"
per_window=$((usable_width / count))

if [ "$per_window" -lt "$MIN_TILE_WIDTH" ]; then
  if [[ "$TARGET_WINDOW_ID" =~ ^[0-9]+$ ]]; then
    "$OMARCHY_AEROSPACE_BIN" layout --window-id "$TARGET_WINDOW_ID" accordion horizontal vertical >/dev/null 2>&1 || true
  else
    "$OMARCHY_AEROSPACE_BIN" layout accordion horizontal vertical >/dev/null 2>&1 || true
  fi
fi

printf '[%s] responsive layout checked (%s): window=%s workspace=%s windows=%s width=%s per_window=%s threshold=%s\n' \
  "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$REASON" "${TARGET_WINDOW_ID:-focused}" "$workspace" "$count" "$width" "$per_window" "$MIN_TILE_WIDTH" \
  >> "${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}" 2>/dev/null || true
RESPONSIVE_LAYOUT_EOF

  chmod +x "$RESPONSIVE_LAYOUT_HELPER"

  cat > "$AEROSPACE_DIR/repair_spaces.sh" << 'REPAIR_SPACES_EOF'
#!/usr/bin/env bash
# Repair workspace placement after monitor topology changes.

set -euo pipefail

source "$HOME/.config/aerospace/omarchy_space_state.sh"

REPAIR_APP_ASSIGNMENTS=1
if [ "${1:-}" = "--detached-only" ]; then
  REPAIR_APP_ASSIGNMENTS=0
fi

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
  if [ "$REPAIR_APP_ASSIGNMENTS" = "1" ]; then
    omarchy_repair_app_assigned_workspaces || true
  fi
  sleep 2
done
REPAIR_SPACES_EOF

  chmod +x "$AEROSPACE_DIR/repair_spaces.sh"
  cat > "$AEROSPACE_DIR/startup_restore.sh" << 'STARTUP_RESTORE_EOF'
#!/usr/bin/env bash
# Login/startup repair pass. Detached-monitor repair runs first so rule-based
# placement is sane, then the saved exact layout is replayed when present.

set -euo pipefail

source "$HOME/.config/aerospace/omarchy_space_state.sh"

TMP_ROOT="${TMPDIR:-/tmp}"
STARTUP_RESTORE_GUARD="${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_startup_restore_active}"
PARTIAL_RESTORE_GUARD="${OMARCHY_WINDOW_PARTIAL_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_incomplete}"
RESTORE_STATUS_HELPER="$HOME/.config/sketchybar/plugins/restore_status.sh"
WINDOW_STATE_HELPER="$HOME/.config/aerospace/window_state.sh"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"
INCOMPLETE_CLEAR_DELAY="${OMARCHY_STARTUP_INCOMPLETE_CLEAR_DELAY:-120}"
INCOMPLETE_CLEAR_ATTEMPTS="${OMARCHY_STARTUP_INCOMPLETE_CLEAR_ATTEMPTS:-6}"
INCOMPLETE_CLEAR_RETRY_DELAY="${OMARCHY_STARTUP_INCOMPLETE_CLEAR_RETRY_DELAY:-5}"
INCOMPLETE_SAVE_WAIT_ATTEMPTS="${OMARCHY_STARTUP_INCOMPLETE_SAVE_WAIT_ATTEMPTS:-6}"
STARTED_AT="${OMARCHY_STARTUP_RESTORE_STARTED_AT:-$(date +%s)}"
RESTORE_RESULT="complete"
RESTORE_STATUS_TIMEOUT="${OMARCHY_RESTORE_STATUS_TIMEOUT_SECONDS:-5}"

log_msg() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE"
}

restore_status() {
  [ -x "$RESTORE_STATUS_HELPER" ] || return 0
  if ! omarchy_run_bounded "$RESTORE_STATUS_TIMEOUT" \
    "$RESTORE_STATUS_HELPER" "$1" >/dev/null 2>&1; then
    log_msg "restore status update timed out or failed: $1"
  fi
}

refresh_space_labels() {
  command -v sketchybar >/dev/null 2>&1 || return 0
  if ! omarchy_run_bounded "$RESTORE_STATUS_TIMEOUT" \
    sketchybar --trigger front_app_switched >/dev/null 2>&1; then
    log_msg "SketchyBar space-label refresh timed out or failed"
  fi
}

schedule_incomplete_clear() {
  case "$INCOMPLETE_CLEAR_DELAY" in
    ''|*[!0-9]*)
      log_msg "invalid startup incomplete clear delay: $INCOMPLETE_CLEAR_DELAY"
      return 0
      ;;
  esac
  [ "$INCOMPLETE_CLEAR_DELAY" -gt 0 ] || return 0
  [ -e "$PARTIAL_RESTORE_GUARD" ] || return 0

  now="$(date +%s)"
  elapsed=0
  if [[ "$STARTED_AT" =~ ^[0-9]+$ ]] && [ "$now" -ge "$STARTED_AT" ]; then
    elapsed=$((now - STARTED_AT))
  fi
  remaining="$INCOMPLETE_CLEAR_DELAY"
  if [ "$elapsed" -lt "$INCOMPLETE_CLEAR_DELAY" ]; then
    remaining=$((INCOMPLETE_CLEAR_DELAY - elapsed))
  else
    remaining=0
  fi
  log_msg "startup restore incomplete; clearing in ${remaining}s (${elapsed}s elapsed of ${INCOMPLETE_CLEAR_DELAY}s grace)"

  (
    [ "$remaining" -gt 0 ] && sleep "$remaining"
    [ -e "$PARTIAL_RESTORE_GUARD" ] || exit 0

    attempts="$INCOMPLETE_CLEAR_ATTEMPTS"
    retry_delay="$INCOMPLETE_CLEAR_RETRY_DELAY"
    save_wait_attempts="$INCOMPLETE_SAVE_WAIT_ATTEMPTS"
    case "$attempts" in ''|*[!0-9]*) attempts=6 ;; esac
    case "$retry_delay" in ''|*[!0-9]*) retry_delay=5 ;; esac
    case "$save_wait_attempts" in ''|*[!0-9]*) save_wait_attempts=6 ;; esac
    [ "$attempts" -gt 0 ] || attempts=1

    log_msg "startup restore incomplete grace period elapsed; saving current layout"
    for ((attempt = 1; attempt <= attempts; attempt++)); do
      if [ -x "$WINDOW_STATE_HELPER" ] && \
        OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS="$save_wait_attempts" \
          "$WINDOW_STATE_HELPER" save manual startup-incomplete-timeout >> "$LOG_FILE" 2>&1; then
        restore_status complete
        refresh_space_labels
        exit 0
      fi
      [ "$attempt" -lt "$attempts" ] || break
      sleep "$retry_delay"
    done

    log_msg "startup restore incomplete clear save failed; clearing stale incomplete marker"
    rm -f "$PARTIAL_RESTORE_GUARD"
    restore_status complete
    refresh_space_labels
  ) >/dev/null 2>&1 &
}

cleanup() {
  rm -f "$STARTUP_RESTORE_GUARD"
  if [ "$RESTORE_RESULT" = "incomplete" ] || [ -e "$PARTIAL_RESTORE_GUARD" ]; then
    # Schedule durable state cleanup before touching UI. A wedged status bar
    # must never prevent the incomplete marker from reaching its bounded
    # expiry path.
    schedule_incomplete_clear
    restore_status incomplete
    # The expiry worker may finish while the bounded incomplete update is in
    # flight. Reconcile once more so a late UI write cannot resurrect a stale
    # warning after the marker and saved state are already clean.
    if [ ! -e "$PARTIAL_RESTORE_GUARD" ]; then
      restore_status complete
    fi
  else
    restore_status complete
  fi
  refresh_space_labels
}
trap cleanup EXIT

printf '%s\n' "$$" > "$STARTUP_RESTORE_GUARD"
restore_status active
"$HOME/.config/aerospace/repair_spaces.sh" || true
OMARCHY_WINDOW_RESTORE_ATTEMPTS="${OMARCHY_STARTUP_WINDOW_RESTORE_ATTEMPTS:-30}" \
OMARCHY_WINDOW_RESTORE_DELAY="${OMARCHY_STARTUP_WINDOW_RESTORE_DELAY:-1}" \
  "$HOME/.config/aerospace/window_state.sh" restore || RESTORE_RESULT="incomplete"
"$HOME/.config/aerospace/repair_spaces.sh" --detached-only || true
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

    return "01" if $app =~ /Mail/i;
    return "02" if $app =~ /Messages|Signal|Google Chat/i;
    return "03" if $app =~ /Spotify|Music/i;
    return "04" if $app =~ /Ghostty|WezTerm|Warp|iTerm2/i;
    return "05" if $app =~ /Zed|Antigravity/i;
    return "06" if $bundle eq "com.anthropic.claudefordesktop";
    return "06" if $bundle eq "com.google.GeminiMacOS";
    return "06" if $bundle eq "com.openai.chat";
    return "06" if $app =~ /ChatGPT/i;

    return undef;
}

sub prepare_windows_for_save {
    my (@windows) = @_;
    for my $window (@windows) {
        $window->{raw_workspace} = $window->{workspace} || "";
        $window->{target_workspace} = $window->{raw_workspace} || "";
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
    my $assigned = assigned_workspace($saved);
    return $assigned if defined $assigned;

    my $base = $saved->{raw_workspace}
        || $saved->{workspace}
        || $saved->{target_workspace}
        || "";
    return "" unless length $base;

    my $target;
    if (!$snapshot || !ref($snapshot->{topology}) || (($snapshot->{format_version} || 1) < 2 && !ref($snapshot->{topology}))) {
        $target = target_workspace_v1($base, monitor_count($current_topology));
    } elsif ($exact_topology) {
        $target = $base;
    } else {
        $target = remap_workspace($base, $snapshot->{topology}, $current_topology);
    }
    $target = "0$target" if $target =~ /^[0-9]$/;
    return "08" if $target eq "02" || $target eq "2";
    return $target;
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
    return 0;
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

command="${1:-status}"
/usr/bin/perl "$HOME/.config/aerospace/window_state.pl" "$@"

# Saved placement cannot override named workspace ownership. Run the same
# lightweight assignment repair after both manual and startup restores so an
# old generic workspace like `1` cannot repopulate the Mail workspace `01`.
if [ "$command" = "restore" ] && [ -f "$HOME/.config/aerospace/omarchy_space_state.sh" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.config/aerospace/omarchy_space_state.sh"
  omarchy_repair_app_assigned_workspaces || true
fi
WINDOW_STATE_WRAPPER_EOF

  chmod +x "$WINDOW_STATE_WRAPPER"
  cat > "$WINDOW_STATE_DEBOUNCED_SAVER" << 'WINDOW_STATE_DEBOUNCED_SAVER_EOF'
#!/usr/bin/env bash
set -u

HELPER="$HOME/.config/aerospace/window_state.sh"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"
DELAY="${OMARCHY_WINDOW_STATE_DEBOUNCE_SECONDS:-2}"
SAVE_WAIT_ATTEMPTS="${OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS:-5}"
PENDING_MAX_SECONDS="${OMARCHY_STARTUP_RESTORE_PENDING_MAX_SECONDS:-300}"
TMP_ROOT="${TMPDIR:-/tmp}"
LOCK_DIR="$TMP_ROOT/omarchy_window_state_debounced.lock"
PENDING_FILE="$TMP_ROOT/omarchy_window_state_debounced.pending"
RESTORE_GUARD="${OMARCHY_WINDOW_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_active}"
STARTUP_RESTORE_GUARD="${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_startup_restore_active}"
RESTORE_STATUS_HELPER="$HOME/.config/sketchybar/plugins/restore_status.sh"
REASON="${1:-event}"

log_msg() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >> "$LOG_FILE"
}

clear_restore_status() {
  [ -x "$RESTORE_STATUS_HELPER" ] || return 0
  "$RESTORE_STATUS_HELPER" complete >/dev/null 2>&1 || true
}

startup_restore_active() {
  [[ -e "$STARTUP_RESTORE_GUARD" ]] || return 1
  if grep -q '^pending-window-state-saver$' "$STARTUP_RESTORE_GUARD" 2>/dev/null; then
    case "$PENDING_MAX_SECONDS" in ''|*[!0-9]*) PENDING_MAX_SECONDS=300 ;; esac
    modified="$(stat -f %m "$STARTUP_RESTORE_GUARD" 2>/dev/null || printf '0')"
    now="$(date +%s)"
    if [[ "$modified" =~ ^[0-9]+$ ]] && [ $((now - modified)) -ge "$PENDING_MAX_SECONDS" ]; then
      log_msg "startup restore pending guard expired; allowing automatic saves"
      rm -f "$STARTUP_RESTORE_GUARD"
      clear_restore_status
      return 1
    fi
  fi
  return 0
}

if [[ -e "$RESTORE_GUARD" ]] || startup_restore_active; then
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
  if [[ -e "$RESTORE_GUARD" ]] || startup_restore_active; then
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
LOG_DAY_FILE="\${OMARCHY_WINDOW_STATE_LOG_DAY_FILE:-\${LOG_FILE}.day}"
LOG_ARCHIVE="\${OMARCHY_WINDOW_STATE_LOG_ARCHIVE:-\${LOG_FILE}.1}"
INTERVAL="\${OMARCHY_WINDOW_STATE_SAVE_INTERVAL:-$WINDOW_STATE_SAVE_INTERVAL_SECONDS}"
SAVE_WAIT_ATTEMPTS="\${OMARCHY_WINDOW_SAVE_WAIT_ATTEMPTS:-5}"
PENDING_MAX_SECONDS="\${OMARCHY_STARTUP_RESTORE_PENDING_MAX_SECONDS:-300}"
RESTORE_GUARD="\${OMARCHY_WINDOW_RESTORE_GUARD:-\${TMPDIR:-/tmp}/omarchy_window_state_restore_active}"
STARTUP_RESTORE_GUARD="\${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-\${TMPDIR:-/tmp}/omarchy_window_state_startup_restore_active}"
REFRESH_RESTART_MARKER="\${OMARCHY_WINDOW_REFRESH_RESTART_MARKER:-\${TMPDIR:-/tmp}/omarchy_window_state_refresh_restart}"
RESTORE_STATUS_HELPER="$HOME/.config/sketchybar/plugins/restore_status.sh"
sleep_pid=""

rotate_log_if_needed() {
  local today recorded_day rotate_lock filtered_log
  today="\$(date '+%Y-%m-%d')"
  recorded_day="\$(cat "\$LOG_DAY_FILE" 2>/dev/null || true)"
  [ "\$recorded_day" = "\$today" ] && return 0

  rotate_lock="\${LOG_FILE}.rotate.lock"
  mkdir "\$rotate_lock" 2>/dev/null || return 0
  recorded_day="\$(cat "\$LOG_DAY_FILE" 2>/dev/null || true)"
  if [ "\$recorded_day" != "\$today" ]; then
    if [ -z "\$recorded_day" ]; then
      # First run after this retention policy is installed: discard entries
      # older than today instead of preserving an unbounded legacy log.
      filtered_log="\${LOG_FILE}.today.\$\$"
      awk -v prefix="[\$today" 'index(\$0, prefix) == 1 { print }' "\$LOG_FILE" > "\$filtered_log" 2>/dev/null || true
      cp "\$filtered_log" "\$LOG_FILE" 2>/dev/null || true
      rm -f "\$filtered_log"
    elif [ -s "\$LOG_FILE" ]; then
      cp "\$LOG_FILE" "\$LOG_ARCHIVE" 2>/dev/null || true
      : > "\$LOG_FILE"
    fi
    printf '%s\n' "\$today" > "\$LOG_DAY_FILE" 2>/dev/null || true
  fi
  rmdir "\$rotate_lock" 2>/dev/null || true
}

log_msg() {
  rotate_log_if_needed
  printf '[%s] %s\n' "\$(date '+%Y-%m-%dT%H:%M:%S%z')" "\$*" >> "\$LOG_FILE"
}

clear_restore_status() {
  [ -x "\$RESTORE_STATUS_HELPER" ] || return 0
  "\$RESTORE_STATUS_HELPER" complete >/dev/null 2>&1 || true
}

startup_restore_active() {
  [[ -e "\$STARTUP_RESTORE_GUARD" ]] || return 1
  if grep -q '^pending-window-state-saver$' "\$STARTUP_RESTORE_GUARD" 2>/dev/null; then
    case "\$PENDING_MAX_SECONDS" in ''|*[!0-9]*) PENDING_MAX_SECONDS=300 ;; esac
    modified="\$(stat -f %m "\$STARTUP_RESTORE_GUARD" 2>/dev/null || printf '0')"
    now="\$(date +%s)"
    if [[ "\$modified" =~ ^[0-9]+$ ]] && [ \$((now - modified)) -ge "\$PENDING_MAX_SECONDS" ]; then
      log_msg "startup restore pending guard expired; allowing automatic saves"
      rm -f "\$STARTUP_RESTORE_GUARD"
      clear_restore_status
      return 1
    fi
  fi
  return 0
}

seed_startup_restore_guard() {
  if [[ -e "\$REFRESH_RESTART_MARKER" ]]; then
    marker="\$(cat "\$REFRESH_RESTART_MARKER" 2>/dev/null || true)"
    modified="\$(stat -f %m "\$REFRESH_RESTART_MARKER" 2>/dev/null || printf '0')"
    now="\$(date +%s)"
    rm -f "\$REFRESH_RESTART_MARKER"
    if [[ "\$marker" == "skip-next-startup-guard" && "\$modified" =~ ^[0-9]+$ ]] &&
       [ \$((now - modified)) -ge 0 ] && [ \$((now - modified)) -le 30 ]; then
      log_msg "config refresh restart; startup restore guard not seeded"
      clear_restore_status
      return 0
    fi
  fi
  [[ -e "\$STARTUP_RESTORE_GUARD" ]] && return 0
  printf '%s\n' 'pending-window-state-saver' > "\$STARTUP_RESTORE_GUARD" 2>/dev/null || return 0
  log_msg "startup restore pending; blocking automatic saves"
}

save_now() {
  local reason="\$1"
  if [[ ! -x "\$HELPER" ]]; then
    log_msg "window state helper missing at \$HELPER"
    return 0
  fi
  if [[ -e "\$RESTORE_GUARD" ]] || startup_restore_active; then
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

rotate_log_if_needed
log_msg "window state saver started; interval \${INTERVAL}s"
seed_startup_restore_guard

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
#   goto_space.sh <key> --move-follow # move focused window and follow it
#   goto_space.sh <key> --move        # move focused window without following
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
  --move-follow)
    window_id=$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null | head -n 1 || true)
    aerospace move-node-to-workspace "$TARGET"
    omarchy_switch_workspace_on_slot_monitor "$TARGET"
    if [[ "$window_id" =~ ^[0-9]+$ ]]; then
      aerospace focus --window-id "$window_id" >/dev/null 2>&1 || true
    fi
    "$HOME/.config/aerospace/window_state_debounced_save.sh" "move-node-to-workspace-$TARGET" >/dev/null 2>&1 || true
    "$HOME/.config/aerospace/responsive_layout.sh" "move-node-to-workspace-$TARGET" >/dev/null 2>&1 || true
    "$HOME/.config/sketchybar/plugins/hide_bar.sh" >/dev/null 2>&1 || true
    ;;
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

  cat > "$AEROSPACE_DIR/workspace_cycle.sh" << 'WORKSPACE_CYCLE_EOF'
#!/usr/bin/env bash
set -euo pipefail

DIRECTION="${1:-next}"
case "$DIRECTION" in next|prev) ;; *) exit 2 ;; esac

source "$HOME/.config/aerospace/omarchy_space_state.sh"
current=$(aerospace list-workspaces --monitor focused --visible --format '%{workspace}' 2>/dev/null | head -n 1)
[[ "$current" =~ ^[0-9][0-9]$ ]] || exit 0
slot="${current:0:1}"
key="${current:1:1}"
order=(1 2 3 4 5 6 7 8 9 0)
index=-1
for idx in "${!order[@]}"; do
  if [ "${order[$idx]}" = "$key" ]; then index="$idx"; break; fi
done
[ "$index" -ge 0 ] || exit 0
if [ "$DIRECTION" = "next" ]; then
  index=$(((index + 1) % 10))
else
  index=$(((index + 9) % 10))
fi
target="${slot}${order[$index]}"
omarchy_switch_workspace_on_slot_monitor "$target"
"$HOME/.config/aerospace/responsive_layout.sh" "workspace-cycle-$DIRECTION-$target" >/dev/null 2>&1 || true
"$HOME/.config/sketchybar/plugins/hide_bar.sh" >/dev/null 2>&1 || true
WORKSPACE_CYCLE_EOF

  chmod +x "$AEROSPACE_DIR/workspace_cycle.sh"
  success "goto_space helper written to $AEROSPACE_DIR/goto_space.sh"
}

# =============================================================================
# NATIVE INPUT MODE
# Fn+Escape toggles this through skhd. It disables AeroSpace bindings as a
# second line of defence and makes the otherwise hidden bar show mode state.
# =============================================================================
write_native_input_helper() {
  info "Writing Native Input helper..."
  mkdir -p "$AEROSPACE_DIR"

  cat > "$NATIVE_INPUT_HELPER" << 'NATIVE_INPUT_EOF'
#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-toggle}"
TMP_ROOT="${TMPDIR:-/tmp}"
STATE_FILE="$TMP_ROOT/omarchy_native_input_active"
PREVIOUS_BAR_FILE="$TMP_ROOT/omarchy_native_input_previous_bar"
BAR_STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/omarchy_sketchybar_visible"
RESTORE_GUARD="${OMARCHY_WINDOW_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_active}"
STARTUP_RESTORE_GUARD="${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_startup_restore_active}"
PARTIAL_RESTORE_GUARD="${OMARCHY_WINDOW_PARTIAL_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_incomplete}"

show_native_input() {
  if [ ! -f "$STATE_FILE" ]; then
    previous=$(cat "$BAR_STATE_FILE" 2>/dev/null || printf '0')
    case "$previous" in 0|1) ;; *) previous=0 ;; esac
    printf '%s\n' "$previous" > "$PREVIOUS_BAR_FILE"
  fi
  : > "$STATE_FILE"
  aerospace mode native_input >/dev/null 2>&1 || true
  if command -v sketchybar >/dev/null 2>&1; then
    sketchybar --bar hidden=off topmost=window >/dev/null 2>&1 || true
    sketchybar --set native_input drawing=on label="Native Input" >/dev/null 2>&1 || true
  fi
  printf '1' > "$BAR_STATE_FILE"
}

hide_native_input() {
  was_active=0
  [ -e "$STATE_FILE" ] && was_active=1
  aerospace mode main >/dev/null 2>&1 || true
  rm -f "$STATE_FILE"
  if command -v sketchybar >/dev/null 2>&1; then
    sketchybar --set native_input drawing=off label="" >/dev/null 2>&1 || true
  fi
  previous=$(cat "$PREVIOUS_BAR_FILE" 2>/dev/null || printf '0')
  rm -f "$PREVIOUS_BAR_FILE"
  if [ "$was_active" = "1" ] &&
     [ "$previous" = "0" ] &&
     [ ! -e "$RESTORE_GUARD" ] &&
     [ ! -e "$STARTUP_RESTORE_GUARD" ] &&
     [ ! -e "$PARTIAL_RESTORE_GUARD" ]; then
    "$HOME/.config/sketchybar/plugins/hide_bar.sh" >/dev/null 2>&1 || true
  fi
}

case "$ACTION" in
  on) show_native_input ;;
  off|reset) hide_native_input ;;
  toggle)
    if [ -e "$STATE_FILE" ]; then hide_native_input; else show_native_input; fi
    ;;
  *) echo "native_input_mode.sh: usage: on|off|reset|toggle" >&2; exit 2 ;;
esac
NATIVE_INPUT_EOF

  chmod +x "$NATIVE_INPUT_HELPER"
  success "Native Input helper written to $NATIVE_INPUT_HELPER"
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
# ACCESSIBILITY HELPER
# Reports Omarchy components whose macOS Accessibility permission appears stale.
# macOS does not expose a public API for checking another process's trust
# directly, so this uses each component's observable health signal.
# =============================================================================
write_accessibility_report_helper() {
  info "Writing accessibility helper..."
  mkdir -p "$AEROSPACE_DIR"

  cat > "$ACCESSIBILITY_REPORT_HELPER" << 'ACCESSIBILITY_REPORT_EOF'
#!/usr/bin/env bash
set -euo pipefail

ISSUES=""
OKS=""
UNKNOWNS=""

append_line() {
  local current="$1" line="$2"
  if [ -n "$current" ]; then
    printf '%s\n%s\n' "$current" "$line"
  else
    printf '%s\n' "$line"
  fi
}

add_issue() {
  ISSUES="$(append_line "$ISSUES" "$1|$2")"
}

add_ok() {
  OKS="$(append_line "$OKS" "$1|$2")"
}

add_unknown() {
  UNKNOWNS="$(append_line "$UNKNOWNS" "$1|$2")"
}

launch_agent_loaded() {
  local label="$1"
  launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1
}

check_aerospace() {
  if ! command -v aerospace >/dev/null 2>&1; then
    add_unknown "AeroSpace" "aerospace command is not installed or not on PATH."
    return 0
  fi

  if aerospace list-windows --all --format '%{window-id}' >/dev/null 2>&1; then
    add_ok "AeroSpace" "AeroSpace can list windows."
  elif aerospace list-monitors --format '%{monitor-id}' >/dev/null 2>&1; then
    add_issue "AeroSpace" "AeroSpace is reachable but cannot list windows. Re-grant AeroSpace in Privacy & Security > Accessibility."
  else
    add_unknown "AeroSpace" "AeroSpace server is not reachable, so Accessibility trust cannot be checked."
  fi
}

check_skhd() {
  if launch_agent_loaded "com.koekeishiya.skhd" || launch_agent_loaded "homebrew.mxcl.skhd"; then
    add_unknown "skhd" "Service is loaded; macOS does not expose skhd Accessibility trust to this shell report."
  else
    add_unknown "skhd" "Service is not loaded, so Accessibility trust cannot be checked."
  fi
}

brief_issues() {
  printf '%s\n' "$ISSUES" |
    awk -F'|' 'NF { names = names ? names ", " $1 : $1 } END { print names }'
}

issue_count() {
  printf '%s\n' "$ISSUES" | awk 'NF { count++ } END { print count + 0 }'
}

print_section() {
  local title="$1" rows="$2"
  [ -n "$rows" ] || return 0
  printf '%s\n' "$title"
  printf '%s\n' "$rows" |
    while IFS='|' read -r name detail; do
      [ -n "$name" ] || continue
      printf '  %s - %s\n' "$name" "$detail"
    done
  printf '\n'
}

run_checks() {
  check_aerospace
  check_skhd
}

usage() {
  cat <<'USAGE'
Usage:
  accessibility_report.sh          show Accessibility health report
  accessibility_report.sh --brief  print only actionable components
  accessibility_report.sh --count  print actionable issue count

"Needs redo" means the component has an observable failure consistent with a
stale macOS Accessibility grant. Unknown means macOS or the component does not
provide enough non-interactive signal to call it either healthy or stale.
USAGE
}

run_checks

case "${1:-}" in
  --brief)
    brief_issues
    [ "$(issue_count)" -eq 0 ]
    ;;
  --count)
    issue_count
    ;;
  --help|-h)
    usage
    ;;
  "")
    if [ "$(issue_count)" -gt 0 ]; then
      print_section "Needs Accessibility redo:" "$ISSUES"
    else
      printf 'No actionable Accessibility redo detected.\n\n'
    fi
    print_section "Healthy:" "$OKS"
    print_section "Unknown / manual check:" "$UNKNOWNS"
    ;;
  *)
    echo "accessibility_report.sh: unknown argument '$1'" >&2
    usage >&2
    exit 1
    ;;
esac
ACCESSIBILITY_REPORT_EOF

  chmod +x "$ACCESSIBILITY_REPORT_HELPER"
  success "accessibility helper written to $ACCESSIBILITY_REPORT_HELPER"
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
# Left Option is Omarchy SUPER. Right Option remains native macOS input.
# Terminal process maps pass all configured chords through for Option/Meta use.
# =============================================================================

# Fn+Escape is deliberately available even in terminal apps.
:: default : ~/.config/aerospace/native_input_mode.sh off
:: native_input : ~/.config/aerospace/native_input_mode.sh on
fn - escape ; native_input
native_input < fn - escape ; default
SKHD_EOF

  # Every normal-mode binding uses the same terminal pass-through policy.
  # Repeating the process map in generated skhd syntax keeps Fn+Escape active
  # in terminals, unlike skhd's all-or-nothing application blacklist.
  write_binding() {
    local chord="$1"
    local command="$2"
    {
      printf '%s [\n' "$chord"
      printf '  "Ghostty" ~\n'
      printf '  "WezTerm" ~\n'
      printf '  "Warp" ~\n'
      printf '  "iTerm2" ~\n'
      printf '  "Terminal" ~\n'
      printf '  * : %s\n' "$command"
      printf ']\n\n'
    } >> "$SKHD_CFG"
  }

  # Discovery, launcher, and canonical window actions.
  write_binding 'lalt - k' 'open "$HOME/Applications/Omarchy Shortcuts Widget.app"'
  write_binding 'lalt - space' 'open -a "Raycast"'
  write_binding 'lalt - w' 'aerospace close'
  write_binding 'lalt - t' 'aerospace layout floating tiling'
  write_binding 'lalt - j' 'aerospace layout tiles horizontal vertical'
  write_binding 'lalt - l' 'aerospace layout accordion horizontal vertical'
  write_binding 'lalt - f' 'aerospace fullscreen'

  local key
  for key in 1 2 3 4 5 6 7 8 9 0; do
    write_binding "lalt - $key" "$HOME/.config/aerospace/goto_space.sh $key"
    write_binding "lalt + shift - $key" "$HOME/.config/aerospace/goto_space.sh $key --move-follow"
    write_binding "lalt + shift + ctrl - $key" "$HOME/.config/aerospace/goto_space.sh $key --move"
  done

  write_binding 'lalt - tab' '$HOME/.config/aerospace/workspace_cycle.sh next'
  write_binding 'lalt + shift - tab' '$HOME/.config/aerospace/workspace_cycle.sh prev'
  write_binding 'lalt + cmd - tab' '$HOME/.config/aerospace/workspace_back_and_forth.sh'

  write_binding 'lalt - left' 'aerospace focus left'
  write_binding 'lalt - down' 'aerospace focus down'
  write_binding 'lalt - up' 'aerospace focus up'
  write_binding 'lalt - right' 'aerospace focus right'
  write_binding 'lalt + shift - left' 'aerospace swap left'
  write_binding 'lalt + shift - down' 'aerospace swap down'
  write_binding 'lalt + shift - up' 'aerospace swap up'
  write_binding 'lalt + shift - right' 'aerospace swap right'

  write_binding 'lalt - equal' 'aerospace resize width +50'
  write_binding 'lalt - minus' 'aerospace resize width -50'
  write_binding 'lalt + shift - equal' 'aerospace resize height +50'
  write_binding 'lalt + shift - minus' 'aerospace resize height -50'

  write_binding 'lalt + shift + ctrl - left' '$HOME/.config/aerospace/move_node_to_monitor_and_save.sh left'
  write_binding 'lalt + shift + ctrl - down' '$HOME/.config/aerospace/move_node_to_monitor_and_save.sh down'
  write_binding 'lalt + shift + ctrl - up' '$HOME/.config/aerospace/move_node_to_monitor_and_save.sh up'
  write_binding 'lalt + shift + ctrl - right' '$HOME/.config/aerospace/move_node_to_monitor_and_save.sh right'

  write_binding 'ctrl - tab' 'aerospace focus --boundaries workspace --boundaries-action wrap-around-the-workspace dfs-next'
  write_binding 'ctrl + shift - tab' 'aerospace focus --boundaries workspace --boundaries-action wrap-around-the-workspace dfs-prev'
  write_binding 'cmd + ctrl - tab' 'aerospace focus-monitor --wrap-around next'
  write_binding 'cmd + ctrl + shift - tab' 'aerospace focus-monitor --wrap-around prev'

  # App launchers and retained macOS extensions.
  write_binding 'lalt - return' 'open -a "Ghostty" 2>/dev/null || open -a "WezTerm" 2>/dev/null || open -a "Terminal"'
  write_binding 'lalt + shift - return' 'open -a "Safari" 2>/dev/null || open -a "Google Chrome" 2>/dev/null || open -a "Firefox"'
  write_binding 'lalt + shift - f' 'open ~'
  write_binding 'lalt + shift - n' 'open -a "Zed" 2>/dev/null || open -a "Visual Studio Code" 2>/dev/null || open -a "TextEdit"'
  write_binding 'lalt + shift - m' 'open -a "Spotify" 2>/dev/null || open -a "Music"'
  write_binding 'lalt + shift - 0x2C' 'open -a "1Password" 2>/dev/null || open -a "Keychain Access"'
  write_binding 'lalt + shift - g' 'open -a "Slack" 2>/dev/null || open -a "Messages"'
  write_binding 'lalt + shift - s' 'screencapture -ic'
  write_binding 'lalt + cmd - up' 'open -a "Mission Control"'
  write_binding 'lalt - z' '$HOME/.config/sketchybar/plugins/toggle_bar.sh'
  write_binding 'lalt + shift - r' 'aerospace reload-config'
  write_binding 'lalt + shift - c' 'skhd --reload'

  success "skhd config written to $SKHD_CFG"
}

# =============================================================================
# SKETCHYBAR CONFIG
# =============================================================================
write_sketchybar_config() {
  info "Writing SketchyBar config..."
  mkdir -p "$SKETCHY_DIR/plugins" "$SKETCHY_DIR/items"
  rm -f "$SKETCHY_DIR/items/accessibility_status.sh" "$SKETCHY_DIR/plugins/accessibility_status.sh"

  # ── Main bar config ──────────────────────────────────────────────────────
  cat > "$SKETCHY_DIR/sketchybarrc" << 'SKETCHY_EOF'
#!/usr/bin/env bash
# =============================================================================
# SketchyBar — Omarchy-style status bar (waybar equivalent)
# Catppuccin Mocha color scheme
# =============================================================================

export CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"

# A topology event can request a reload while the login-time configuration is
# still creating items. Only one config process may own the item lifecycle at a
# time, otherwise different processes can create different portions of the
# number-row sequence.
CONFIG_LOCK_DIR="${OMARCHY_SKETCHYBAR_CONFIG_LOCK:-${TMPDIR:-/tmp}/omarchy_sketchybar_config.lock}"

release_config_lock() {
  rm -rf "$CONFIG_LOCK_DIR"
}

acquire_config_lock() {
  if ! mkdir "$CONFIG_LOCK_DIR" 2>/dev/null; then
    owner_pid=$(cat "$CONFIG_LOCK_DIR/pid" 2>/dev/null || true)
    if [[ "$owner_pid" =~ ^[0-9]+$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
      exit 0
    fi
    rm -rf "$CONFIG_LOCK_DIR"
    mkdir "$CONFIG_LOCK_DIR" 2>/dev/null || exit 0
  fi

  printf '%s\n' "$$" > "$CONFIG_LOCK_DIR/pid"
  trap release_config_lock EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

acquire_config_lock
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
for item in space.1 space.2 space.3 space.4 space.5 space.6 space.7 space.8 space.9 space.0 spaces_separator front_app monitor display_reload restore_status accessibility_status native_input; do
  sketchybar --remove "$item" >/dev/null 2>&1 || true
done
for slot in 0 1 2 3 4 5 6 7 8 9; do
  for key in 1 2 3 4 5 6 7 8 9 0; do
    sketchybar --remove "space.$slot.$key" >/dev/null 2>&1 || true
  done
  sketchybar --remove "spaces_separator.$slot" >/dev/null 2>&1 || true
  sketchybar --remove "monitor.$slot" >/dev/null 2>&1 || true
  sketchybar --remove "restore_status.$slot" >/dev/null 2>&1 || true
done

source "$CONFIG_DIR/items/spaces.sh"
source "$CONFIG_DIR/items/front_app.sh"
source "$CONFIG_DIR/items/monitor.sh"
source "$CONFIG_DIR/items/display_reload.sh"
source "$CONFIG_DIR/items/restore_status.sh"
source "$CONFIG_DIR/items/native_input.sh"

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
space_order=()
while IFS= read -r monitor_id; do
  [ -n "$monitor_id" ] || continue
  [ "$slot" -gt 9 ] && break
  display=$(omarchy_sketchybar_display_for_slot "$slot" 2>/dev/null || printf '%s\n' $((slot + 1)))
  for sid in 1 2 3 4 5 6 7 8 9 0; do
    name="space.$slot.$sid"
    space_order+=("$name")
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

if [ "${#space_order[@]}" -gt 0 ]; then
  sketchybar --order "${space_order[@]}"
fi
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

  cat > "$SKETCHY_DIR/items/restore_status.sh" << 'RESTORE_STATUS_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"
source "$HOME/.config/aerospace/omarchy_space_state.sh"

sketchybar --add item restore_status center \
  --set restore_status \
    drawing=off \
    updates=off \
    icon.drawing=off \
    label.font="SF Pro:Semibold:13.0" \
    label.color=$YELLOW \
    background.drawing=on \
    background.color=$ITEM_BG \
    background.border_color=$YELLOW \
    background.border_width=1 \
    background.corner_radius=6 \
    background.height=24 \
    padding_left=8 \
    padding_right=8 \
    script="$CONFIG_DIR/plugins/restore_status.sh"

monitors=$(omarchy_monitor_ids_by_slot 2>/dev/null || printf '1')
slot=0
while IFS= read -r monitor_id; do
  [ -n "$monitor_id" ] || continue
  [ "$slot" -gt 9 ] && break
  display=$(omarchy_sketchybar_display_for_slot "$slot" 2>/dev/null || printf '%s\n' $((slot + 1)))
  name="restore_status.$slot"
  sketchybar --add item "$name" center \
    --set "$name" \
      display="$display" \
      drawing=off \
      updates=off \
      icon.drawing=off \
      label.font="SF Pro:Semibold:13.0" \
      label.color=$YELLOW \
      background.drawing=on \
      background.color=$ITEM_BG \
      background.border_color=$YELLOW \
      background.border_width=1 \
      background.corner_radius=6 \
      background.height=24 \
      padding_left=8 \
      padding_right=8 \
      script="$CONFIG_DIR/plugins/restore_status.sh"
  slot=$((slot + 1))
done <<< "$monitors"
RESTORE_STATUS_ITEM_EOF

  cat > "$SKETCHY_DIR/items/native_input.sh" << 'NATIVE_INPUT_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

sketchybar --add item native_input center \
  --set native_input \
    drawing=off \
    updates=off \
    icon.drawing=off \
    label.font="SF Pro:Semibold:13.0" \
    label.color=$YELLOW \
    background.drawing=on \
    background.color=$ITEM_BG \
    background.border_color=$YELLOW \
    background.border_width=1 \
    background.corner_radius=6 \
    background.height=24 \
    padding_left=8 \
    padding_right=8
NATIVE_INPUT_ITEM_EOF

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

assigned_apps_for_alias() {
  local workspace="$1"
  local rows="$2"
  local legacy_workspace="${3:-}"

  printf '%s\n' "$rows" |
    while IFS='|' read -r row_workspace app_name bundle_id; do
      [ "$row_workspace" = "$workspace" ] || { [ -n "$legacy_workspace" ] && [ "$row_workspace" = "$legacy_workspace" ]; } || continue
      [ -n "$app_name" ] || continue
      local assigned
      assigned=$(omarchy_assigned_workspace_for_app "$app_name" "$bundle_id" 2>/dev/null || true)
      [ "$assigned" = "$workspace" ] || continue
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

    # Item creation belongs exclusively to the config build. A highlight can
    # overlap a reload, so it must only update items that already exist.
    args+=(--set "monitor.$slot" display="$display" label="$slot"
           --set "spaces_separator.$slot" display="$display" icon="|" label.drawing=off)

    for KEY in 1 2 3 4 5 6 7 8 9 0; do
      local ws_name="${slot}${KEY}"
      local name="space.$slot.$KEY"
      local label legacy_ws apps alias assigned_apps unexpected_apps
      legacy_ws=""
      [ "$visible_ws" = "$KEY" ] && legacy_ws="$KEY"
      apps=$(printf '%s\n' "$windows" \
        | awk -F'|' -v s="$ws_name" -v legacy="$legacy_ws" '$1==s || (legacy != "" && $1==legacy){print $2}' \
        | sort -u | paste -sd "," - | sed 's/,/, /g')
      alias=$(space_alias_label "$ws_name" 2>/dev/null || true)
      if [ -n "$alias" ]; then
        assigned_apps=$(assigned_apps_for_alias "$ws_name" "$windows" "$legacy_ws" 2>/dev/null || true)
        unexpected_apps=$(unexpected_apps_for_alias "$ws_name" "$windows" "$legacy_ws" 2>/dev/null || true)
        if [ -n "$unexpected_apps" ] && [ -z "$assigned_apps" ]; then
          label="$unexpected_apps"
        elif [ -n "$unexpected_apps" ]; then
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
CONFIG_LOCK_DIR="${OMARCHY_SKETCHYBAR_CONFIG_LOCK:-${TMPDIR:-/tmp}/omarchy_sketchybar_config.lock}"
LOG_FILE="${OMARCHY_WINDOW_STATE_LOG:-/tmp/omarchy_window_state.log}"
STATE_FILE="${TMPDIR:-/tmp}/omarchy_sketchybar_display_topology"
MIN_RELOAD_INTERVAL="${OMARCHY_SKETCHYBAR_DISPLAY_RELOAD_INTERVAL:-15}"
CONFIG_WAIT_ATTEMPTS="${OMARCHY_SKETCHYBAR_CONFIG_WAIT_ATTEMPTS:-40}"
CONFIG_WAIT_DELAY="${OMARCHY_SKETCHYBAR_CONFIG_WAIT_DELAY:-0.25}"

topology_signature() {
  if command -v aerospace >/dev/null 2>&1; then
    aerospace list-monitors --format '%{monitor-id}|%{monitor-name}|%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null |
      awk 'NF' |
      sort |
      paste -sd ';' -
  fi
}

now_epoch() {
  date '+%s'
}

wait_for_config_build() {
  local attempt=0
  while [ -d "$CONFIG_LOCK_DIR" ] && [ "$attempt" -lt "$CONFIG_WAIT_ATTEMPTS" ]; do
    sleep "$CONFIG_WAIT_DELAY"
    attempt=$((attempt + 1))
  done
  [ ! -d "$CONFIG_LOCK_DIR" ]
}

current_signature="$(topology_signature)"
[ -n "$current_signature" ] || exit 0

previous_signature=""
previous_epoch=0
if [ -f "$STATE_FILE" ]; then
  IFS='|' read -r previous_epoch previous_signature < "$STATE_FILE" || true
fi

if [ "$current_signature" = "$previous_signature" ]; then
  exit 0
fi

current_epoch="$(now_epoch)"
if [[ "$previous_epoch" =~ ^[0-9]+$ ]] && [ "$previous_epoch" -gt 0 ]; then
  elapsed=$((current_epoch - previous_epoch))
  if [ "$elapsed" -lt "$MIN_RELOAD_INTERVAL" ]; then
    printf '%s|%s\n' "$current_epoch" "$current_signature" > "$STATE_FILE"
    exit 0
  fi
fi

printf '%s|%s\n' "$current_epoch" "$current_signature" > "$STATE_FILE"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi

(
  sleep 1
  if ! wait_for_config_build; then
    printf '[%s] sketchybar config still active; deferring topology reload: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$current_signature" >> "$LOG_FILE" 2>/dev/null || true
    rm -f "$STATE_FILE"
    rm -rf "$LOCK_DIR"
    exit 0
  fi
  printf '[%s] sketchybar display topology changed; reloading: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$current_signature" >> "$LOG_FILE" 2>/dev/null || true
  sketchybar --reload >/dev/null 2>&1 || true
  "$HOME/.config/sketchybar/plugins/restore_status.sh" refresh >/dev/null 2>&1 || true
  rm -rf "$LOCK_DIR"
) >/dev/null 2>&1 &
DISPLAY_RELOAD_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/restore_status.sh" << 'RESTORE_STATUS_PLUGIN_EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
if [ -f "$CONFIG_DIR/colors.sh" ]; then
  source "$CONFIG_DIR/colors.sh"
else
  YELLOW=0xfff9e2af
  RED=0xfff38ba8
  ITEM_BG=0xff313244
fi

TMP_ROOT="${TMPDIR:-/tmp}"
STARTUP_RESTORE_GUARD="${OMARCHY_WINDOW_STARTUP_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_startup_restore_active}"
RESTORE_GUARD="${OMARCHY_WINDOW_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_active}"
PARTIAL_RESTORE_GUARD="${OMARCHY_WINDOW_PARTIAL_RESTORE_GUARD:-$TMP_ROOT/omarchy_window_state_restore_incomplete}"
VISIBLE_STATE="${XDG_RUNTIME_DIR:-/tmp}/omarchy_sketchybar_visible"
PREVIOUS_STATE="${TMP_ROOT}/omarchy_restore_status_previous_bar"
ACCESSIBILITY_HELPER="${OMARCHY_ACCESSIBILITY_REPORT_HELPER:-$HOME/.config/aerospace/accessibility_report.sh}"
ACCESSIBILITY_WATCH_LOCK="${TMP_ROOT}/omarchy_restore_status_accessibility_watch.lock"
ACCESSIBILITY_WATCH_INTERVAL="${OMARCHY_RESTORE_STATUS_WATCH_INTERVAL:-30}"
SPACE_STATE_HELPER="$HOME/.config/aerospace/omarchy_space_state.sh"

if [ -f "$SPACE_STATE_HELPER" ]; then
  # shellcheck source=/dev/null
  source "$SPACE_STATE_HELPER"
fi

current_visible_state() {
  if [ -f "$VISIBLE_STATE" ]; then
    case "$(cat "$VISIBLE_STATE" 2>/dev/null || true)" in
      1) printf '1\n'; return 0 ;;
    esac
  fi
  printf '0\n'
}

remember_bar_state() {
  [ -f "$PREVIOUS_STATE" ] && return 0
  current_visible_state > "$PREVIOUS_STATE" 2>/dev/null || true
}

status_items() {
  local emitted=0
  if command -v omarchy_monitor_ids_by_slot >/dev/null 2>&1 &&
     command -v omarchy_sketchybar_display_for_slot >/dev/null 2>&1; then
    local monitors slot monitor_id display
    monitors=$(omarchy_monitor_ids_by_slot 2>/dev/null || true)
    slot=0
    while IFS= read -r monitor_id; do
      [ -n "$monitor_id" ] || continue
      [ "$slot" -gt 9 ] && break
      display=$(omarchy_sketchybar_display_for_slot "$slot" 2>/dev/null || printf '%s\n' $((slot + 1)))
      printf 'restore_status.%s|%s\n' "$slot" "$display"
      emitted=1
      slot=$((slot + 1))
    done <<< "$monitors"
  fi
  [ "$emitted" -eq 1 ] || printf 'restore_status|\n'
}

ensure_item() {
  sketchybar --add item restore_status center >/dev/null 2>&1 || true
  sketchybar --set restore_status drawing=off >/dev/null 2>&1 || true
  local row name display
  while IFS='|' read -r name display; do
    [ "$name" = "restore_status" ] && continue
    [ -n "$name" ] || continue
    sketchybar --add item "$name" center >/dev/null 2>&1 || true
    if [ -n "$display" ]; then
      sketchybar --set "$name" display="$display" >/dev/null 2>&1 || true
    fi
  done <<< "$(status_items)"
}

set_status_items() {
  local label="$1" color="$2" row name display
  hide_status_items
  while IFS='|' read -r name display; do
    [ -n "$name" ] || continue
    if [ -n "$display" ]; then
      sketchybar --set "$name" display="$display" >/dev/null 2>&1 || true
    fi
    sketchybar --set "$name" \
      drawing=on \
      icon.drawing=off \
      label="$label" \
      label.color=$color \
      background.drawing=on \
      background.color=$ITEM_BG \
      background.border_color=$color \
      background.border_width=1 \
      background.corner_radius=6 \
      background.height=24 >/dev/null 2>&1 || true
  done <<< "$(status_items)"
}

hide_status_items() {
  local name
  sketchybar --set restore_status drawing=off label="" background.drawing=off >/dev/null 2>&1 || true
  for slot in {0..9}; do
    sketchybar --set "restore_status.$slot" drawing=off label="" background.drawing=off >/dev/null 2>&1 || true
  done
}

remove_status_items() {
  sketchybar --remove restore_status >/dev/null 2>&1 || true
  for slot in {0..9}; do
    sketchybar --remove "restore_status.$slot" >/dev/null 2>&1 || true
  done
}

show_active() {
  remember_bar_state
  ensure_item
  sketchybar --bar hidden=off topmost=window >/dev/null 2>&1 || true
  printf '1' > "$VISIBLE_STATE" 2>/dev/null || true
  set_status_items "Restoring windows" "$YELLOW"
}

show_incomplete() {
  remember_bar_state
  ensure_item
  sketchybar --bar hidden=off topmost=window >/dev/null 2>&1 || true
  printf '1' > "$VISIBLE_STATE" 2>/dev/null || true
  set_status_items "Restore incomplete" "$RED"
}

show_accessibility() {
  local issues="$1"
  remember_bar_state
  ensure_item
  sketchybar --bar hidden=off topmost=window >/dev/null 2>&1 || true
  printf '1' > "$VISIBLE_STATE" 2>/dev/null || true
  set_status_items "AX: $issues" "$RED"
}

restore_bar_state() {
  local previous="0"
  if [ -f "$PREVIOUS_STATE" ]; then
    previous="$(cat "$PREVIOUS_STATE" 2>/dev/null || printf '0')"
  fi
  rm -f "$PREVIOUS_STATE"
  if [ "$previous" = "1" ]; then
    sketchybar --bar hidden=off topmost=window >/dev/null 2>&1 || true
    printf '1' > "$VISIBLE_STATE" 2>/dev/null || true
  else
    sketchybar --bar hidden=on >/dev/null 2>&1 || true
    printf '0' > "$VISIBLE_STATE" 2>/dev/null || true
  fi
}

show_complete() {
  ensure_item
  hide_status_items
  remove_status_items
  restore_bar_state
}

accessibility_issues() {
  [ -x "$ACCESSIBILITY_HELPER" ] || return 1
  "$ACCESSIBILITY_HELPER" --brief 2>/dev/null || true
}

restore_guard_active() {
  [ -e "$STARTUP_RESTORE_GUARD" ] || [ -e "$RESTORE_GUARD" ] || [ -e "$PARTIAL_RESTORE_GUARD" ]
}

start_accessibility_watch() {
  case "$ACCESSIBILITY_WATCH_INTERVAL" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ "$ACCESSIBILITY_WATCH_INTERVAL" -gt 0 ] || return 0
  mkdir "$ACCESSIBILITY_WATCH_LOCK" 2>/dev/null || return 0

  local plugin_path="${BASH_SOURCE[0]:-$0}"
  (
    trap 'rmdir "$ACCESSIBILITY_WATCH_LOCK" >/dev/null 2>&1 || true' EXIT
    while sleep "$ACCESSIBILITY_WATCH_INTERVAL"; do
      if restore_guard_active; then
        "$plugin_path" refresh >/dev/null 2>&1 || true
        continue
      fi
      local issues
      issues="$(accessibility_issues)"
      if [ -z "$issues" ]; then
        "$plugin_path" refresh >/dev/null 2>&1 || true
        break
      fi
    done
  ) >/dev/null 2>&1 &
}

mode="${1:-refresh}"
case "$mode" in
  active|start)
    show_active
    ;;
  incomplete|failed)
    show_incomplete
    ;;
  complete|done)
    show_complete
    ;;
  refresh|*)
    if [ -e "$STARTUP_RESTORE_GUARD" ] || [ -e "$RESTORE_GUARD" ]; then
      show_active
    elif [ -e "$PARTIAL_RESTORE_GUARD" ]; then
      show_incomplete
    elif issues="$(accessibility_issues)" && [ -n "$issues" ]; then
      show_accessibility "$issues"
      start_accessibility_watch
    else
      show_complete
    fi
    ;;
esac
RESTORE_STATUS_PLUGIN_EOF

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
# each newly-opened ordinary Chrome window on the built-in monitor to an
# existing Chrome workspace, or to the first empty general-purpose workspace.
# External monitor slots are left alone. Reserved app workspaces are not empty
# fallback targets. The updated window state is saved after the decision so
# reboot restore learns the final placement.
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
let generalWorkspaceKeys: [String] = ["7","8","9"]
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

struct WindowRow {
    let id: UInt32
    let ws: String
    let app: String
}

func chromeWorkspaceOnMonitor(_ monitor: String, rows: [WindowRow], skip currentWs: String, newWindowId: UInt32) -> String? {
    for key in scanOrder {
        let ws = "\(monitor)\(key)"
        if ws == currentWs { continue }
        let hasChrome = rows.contains {
            $0.ws == ws && $0.id != newWindowId && $0.app == "Google Chrome"
        }
        if hasChrome { return ws }
    }
    return nil
}

func firstEmptyGeneralWorkspaceOnMonitor(_ monitor: String, rows: [WindowRow], skip currentWs: String) -> String? {
    for key in generalWorkspaceKeys {
        let ws = "\(monitor)\(key)"
        if ws == currentWs { continue }
        let occupied = rows.contains { $0.ws == ws }
        if !occupied { return ws }
    }
    return nil
}

func targetWorkspaceForChrome(monitor: String, rows: [WindowRow], currentWs: String, newWindowId: UInt32) -> String? {
    if let chromeWs = chromeWorkspaceOnMonitor(monitor, rows: rows, skip: currentWs, newWindowId: newWindowId) {
        return chromeWs
    }
    return firstEmptyGeneralWorkspaceOnMonitor(monitor, rows: rows, skip: currentWs)
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
        var rows: [WindowRow] = []
        for line in listing.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3, let id = UInt32(parts[0]) else { continue }
            let row = WindowRow(id: id, ws: String(parts[1]), app: String(parts[2]))
            rows.append(row)
            if id == wid { currentWs = row.ws }
        }
        guard let ws = currentWs else {
            if attempt < windowListingAttempts - 1 { Thread.sleep(forTimeInterval: 0.5) }
            continue
        }
        guard let monitor = ws.first else {
            scheduleWindowStateSave("chrome-window-detected")
            return
        }
        let monitorSlot = Int(String(monitor)) ?? 0
        if monitorSlot != 0 {
            log("Chrome window \(wid) on external workspace \(ws): leaving in place")
            scheduleWindowStateSave("chrome-window-detected")
            return
        }
        let siblingChromeOnWs = rows.contains {
            $0.ws == ws && $0.id != wid && $0.app == "Google Chrome"
        }
        if siblingChromeOnWs {
            log("Chrome window \(wid) on \(ws): already has Chrome here, leaving in place")
            scheduleWindowStateSave("chrome-window-detected")
            return
        }
        let activeSlotCount = activeMonitorSlotCount()
        let targetMonitor = monitorSlot < activeSlotCount ? String(monitor) : "0"
        if let target = targetWorkspaceForChrome(monitor: targetMonitor, rows: rows, currentWs: ws, newWindowId: wid) {
            log("Chrome window \(wid) alone on \(ws) -> \(target)")
            sh(["move-node-to-workspace", "--window-id", "\(wid)", target])
            sh(["workspace", target])
        } else {
            log("Chrome window \(wid) alone on \(ws): no Chrome/general workspace available on monitor \(targetMonitor), leaving in place")
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
  echo "No action is taken unless you pass one of these commands:"
  echo ""
  echo "  ./omarchy.sh install   install and configure core tools"
  echo "                         set OMARCHY_ENABLE_BORDERS=1 to include JankyBorders"
  echo "  ./omarchy.sh refresh   rewrite generated configs without reinstalling packages"
  echo "  ./omarchy.sh repair-spaces"
  echo "                         move windows off detached monitor workspaces"
  echo "  ./omarchy.sh save-window-state"
  echo "                         save current window/workspace layout for reboot restore"
  echo "  ./omarchy.sh restore-window-state"
  echo "                         restore the saved window/workspace layout now"
  echo "  ./omarchy.sh shortcuts-widget"
  echo "                         rebuild the desktop shortcut widget"
  echo "  ./omarchy.sh secure-input [--watch [seconds]]"
  echo "                         show the macOS Secure Input owner"
  echo "  ./omarchy.sh accessibility"
  echo "                         show Accessibility permissions that need to be redone"
  echo "  ./omarchy.sh revert    undo everything, restore previous state"
  echo "  ./omarchy.sh status    show install and service status"
  echo ""
  echo "Compatibility: ./install.sh still accepts the same commands."
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
  accessibility) cmd_accessibility "$@" ;;
  revert)        cmd_revert        ;;
  status)        cmd_status        ;;
  "")            usage; exit 0     ;;
  *)             usage; exit 1     ;;
esac
