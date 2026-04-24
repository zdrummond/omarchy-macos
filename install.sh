#!/usr/bin/env bash
# =============================================================================
# omarchy-macos — Hyprland/Omarchy-style window management for macOS M1
#
# Usage:
#   ./install.sh install   — install and configure everything
#   ./install.sh revert    — undo everything, restore previous state
#   ./install.sh status    — show what's installed and running
#
# Tools installed:
#   aerospace    — tiling window manager (i3-style)
#   skhd         — global hotkey daemon for app launchers
#   sketchybar   — scriptable status bar (waybar equivalent)
#   jankyborders — colored border on focused window
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

BAR_TOGGLE_BIN="$SKETCHY_DIR/plugins/bar_toggle"
BAR_TOGGLE_SRC="$SKETCHY_DIR/plugins/bar_toggle.swift"
BAR_TOGGLE_LABEL="com.omarchy-macos.bar_toggle"
BAR_TOGGLE_PLIST="$HOME/Library/LaunchAgents/$BAR_TOGGLE_LABEL.plist"

CHROME_REHOME_BIN="$SKETCHY_DIR/plugins/chrome_rehome"
CHROME_REHOME_SRC="$SKETCHY_DIR/plugins/chrome_rehome.swift"
CHROME_REHOME_LABEL="com.omarchy-macos.chrome_rehome"
CHROME_REHOME_PLIST="$HOME/Library/LaunchAgents/$CHROME_REHOME_LABEL.plist"

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
  brew_install "jankyborders" "FelixKratz/formulae/borders"

  header "Writing configuration files..."
  write_aerospace_config
  write_goto_space_helper
  write_skhd_config
  write_sketchybar_config
  write_borders_config
  write_bar_toggle_daemon
  write_chrome_rehome_daemon

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
# REVERT
# =============================================================================
cmd_revert() {
  header "omarchy-macos revert"

  if [[ ! -f "$INSTALLED_MARKER" ]]; then
    warn "omarchy-macos doesn't appear to be installed (no marker found)."
    read -r -p "Force revert anyway? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 0
  fi

  header "Stopping services..."
  stop_services

  header "Removing configuration files..."
  rm -f "$AEROSPACE_CFG"
  rm -rf "$AEROSPACE_DIR"
  rm -rf "$SKHD_DIR"
  rm -rf "$SKETCHY_DIR"
  rm -rf "$BORDERS_DIR"
  rm -f "$BAR_TOGGLE_PLIST"
  rm -f "$CHROME_REHOME_PLIST"
  success "Config files removed"

  header "Restoring backups..."
  restore_backups

  header "Uninstalling packages..."
  brew_uninstall "borders"   "FelixKratz/formulae/borders"
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
  check_tool "jankyborders" "$(brew list FelixKratz/formulae/borders &>/dev/null && echo yes || echo no)"

  echo ""
  check_service "aerospace"
  check_service "skhd"
  check_service "sketchybar"
  check_service "borders"

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
  info "Starting aerospace..."
  brew services start nikitabobko/tap/aerospace 2>/dev/null || \
    brew services start aerospace 2>/dev/null || \
    warn "Could not auto-start aerospace — launch manually from Applications"

  info "Starting skhd..."
  skhd --start-service 2>/dev/null || \
    warn "Could not auto-start skhd — run 'skhd --start-service' manually"

  info "Starting sketchybar..."
  brew services start felixkratz/formulae/sketchybar 2>/dev/null || \
    brew services start sketchybar 2>/dev/null || \
    warn "Could not auto-start sketchybar"

  info "Starting borders..."
  brew services start felixkratz/formulae/borders 2>/dev/null || \
    brew services start borders 2>/dev/null || \
    warn "Could not auto-start borders"

  info "Starting bar_toggle daemon..."
  launchctl unload "$BAR_TOGGLE_PLIST" 2>/dev/null || true
  launchctl load "$BAR_TOGGLE_PLIST" 2>/dev/null || \
    warn "Could not load bar_toggle LaunchAgent"

  info "Starting chrome_rehome daemon..."
  launchctl unload "$CHROME_REHOME_PLIST" 2>/dev/null || true
  launchctl load "$CHROME_REHOME_PLIST" 2>/dev/null || \
    warn "Could not load chrome_rehome LaunchAgent"

  success "Services started"
}

stop_services() {
  if [[ -f "$BAR_TOGGLE_PLIST" ]]; then
    launchctl unload "$BAR_TOGGLE_PLIST" 2>/dev/null && info "  stopped bar_toggle" || true
  fi
  if [[ -f "$CHROME_REHOME_PLIST" ]]; then
    launchctl unload "$CHROME_REHOME_PLIST" 2>/dev/null && info "  stopped chrome_rehome" || true
  fi
  for svc in borders sketchybar aerospace; do
    if brew services list | grep -q "^$svc"; then
      brew services stop "$svc" 2>/dev/null && info "  stopped $svc" || true
    fi
  done
  skhd --stop-service 2>/dev/null && info "  stopped skhd" || true
  success "Services stopped"
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
write_aerospace_config() {
  info "Writing Aerospace config..."

  cat > "$AEROSPACE_CFG" << 'AEROSPACE_EOF'
# =============================================================================
# Aerospace — Omarchy-style tiling window manager config
# Modifier key: ⌥ (Option/Alt) — your SUPER key
# Docs: https://nikitabobko.github.io/AeroSpace/guide
# =============================================================================

# ── Behavior ──────────────────────────────────────────────────────────────────
after-login-command = []
after-startup-command = []

# Automatically move focus to wherever your mouse is
on-focus-changed = [
  'move-mouse window-lazy-center'
]

# Start Aerospace on login
start-at-login = true

# Remap Option keys so macOS doesn't swallow ⌥+key as special characters
key-mapping.preset = 'qwerty'

# Normalisation: flatten nested containers (keeps tree clean)
enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

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
# Per-monitor spaces: key N on display D resolves to workspace "DN"
# (e.g. monitor 2 + ⌥+3 = workspace "23"). See goto_space.sh.
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
alt-tab       = 'workspace-back-and-forth'
alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'

# ── Move to next/prev monitor ─────────────────────────────────────────────
alt-ctrl-shift-h = 'move-node-to-monitor left'
alt-ctrl-shift-l = 'move-node-to-monitor right'

# ── App → workspace assignments ───────────────────────────────────────────

# App-assignment rules default to monitor 0's spaces ("0N"). If a second
# monitor is attached, move the app to <monitor><N> manually after launch.
[[on-window-detected]]
if.app-name-regex-substring = 'Gmail'
run = ['move-node-to-workspace 01', 'workspace 01']

[[on-window-detected]]
if.app-name-regex-substring = 'Messages'
run = ['move-node-to-workspace 02', 'workspace 02']

[[on-window-detected]]
if.app-name-regex-substring = 'Signal'
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
if.app-name-regex-substring = 'Claude'
run = ['move-node-to-workspace 06', 'workspace 06']

[[on-window-detected]]
if.app-name-regex-substring = 'Steam'
run = ['move-node-to-workspace 09', 'workspace 09']

# [[on-window-detected]]
# if.app-name-regex-substring = 'slack|discord'
# run = 'move-node-to-workspace 8'
AEROSPACE_EOF

  success "Aerospace config written to $AEROSPACE_CFG"
}

# =============================================================================
# GOTO_SPACE HELPER
# Resolves ⌥+N to workspace "${display_id}${N}" so each monitor gets its
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
# <key> is 0-9. Workspace names are `${display_id}${key}` where display_id is
# the 0-based monitor index (aerospace's monitor id minus 1).

set -euo pipefail

KEY="${1:?usage: goto_space.sh <0-9> [--move]}"
ACTION="${2:-focus}"

if ! [[ "$KEY" =~ ^[0-9]$ ]]; then
  echo "goto_space.sh: key must be 0-9 (got: $KEY)" >&2
  exit 1
fi

MONITOR_ID=$(aerospace list-monitors --focused --format '%{monitor-id}')
DISPLAY_ID=$((MONITOR_ID - 1))
TARGET="${DISPLAY_ID}${KEY}"

case "$ACTION" in
  --move)
    aerospace move-node-to-workspace "$TARGET"
    ;;
  focus|*)
    aerospace workspace "$TARGET"
    ;;
esac
GOTO_SPACE_EOF

  chmod +x "$AEROSPACE_DIR/goto_space.sh"
  success "goto_space helper written to $AEROSPACE_DIR/goto_space.sh"
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
source "$CONFIG_DIR/items/spaces.sh"
source "$CONFIG_DIR/items/front_app.sh"
source "$CONFIG_DIR/items/monitor.sh"

# ── Finalise ──────────────────────────────────────────────────────────────
sketchybar --update
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

  # ── Spaces (workspace indicators) ────────────────────────────────────────
  cat > "$SKETCHY_DIR/items/spaces.sh" << 'SPACES_ITEM_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/colors.sh"

for sid in 1 2 3 4 5 6 7 8 9 0; do
  sketchybar --add item space.$sid left \
    --set space.$sid \
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

sketchybar --add item spaces_separator left \
  --set spaces_separator \
    icon="|" \
    icon.font="SF Pro:Light:14.0" \
    icon.color=$SUBTEXT \
    padding_left=2 \
    padding_right=2 \
    label.drawing=off
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

sketchybar --add item monitor right \
  --set monitor \
    icon.drawing=off \
    label="0" \
    label.font="SF Pro:Semibold:13.0" \
    label.color=$PEACH \
    background.drawing=on \
    background.color=$ITEM_BG \
    background.corner_radius=6 \
    background.height=24 \
    padding_left=6 \
    padding_right=6
MONITOR_ITEM_EOF

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
# Per-monitor spaces: workspace names are "${display_id}${key}" (e.g. "23"
# for monitor 2, key 3). The 10 bar slots (space.0 .. space.9) reflect the
# workspaces for the currently focused monitor; the "monitor" indicator on
# the right shows the 0-based display id.

source "$CONFIG_DIR/colors.sh"

ALIAS_FILE="$HOME/.config/sketchybar/space_aliases"

highlight_space() {
  local focused="$1"  # full workspace name, e.g. "23", or empty
  local monitor key
  if [[ "$focused" =~ ^[0-9][0-9]$ ]]; then
    monitor="${focused:0:1}"
    key="${focused:1:1}"
  else
    # Fall back to asking aerospace directly.
    local mid
    mid=$(aerospace list-monitors --focused --format '%{monitor-id}' 2>/dev/null)
    monitor=$((mid - 1))
    local ws
    ws=$(aerospace list-workspaces --focused 2>/dev/null | head -1)
    key="${ws:1:1}"
    focused="$ws"
  fi

  # One aerospace call for all windows, grouped by workspace.
  local windows
  windows=$(aerospace list-windows --all --format '%{workspace}|%{app-name}' 2>/dev/null)

  # Build a single batched sketchybar invocation.
  local args=()
  args+=(--set monitor label="$monitor")

  for KEY in 1 2 3 4 5 6 7 8 9 0; do
    local ws_name="${monitor}${KEY}"
    local name="space.$KEY"
    local label alias
    alias=$(grep "^${ws_name}=" "$ALIAS_FILE" 2>/dev/null | cut -d= -f2-)
    if [ -n "$alias" ]; then
      label="$alias"
    else
      label=$(printf '%s\n' "$windows" \
        | awk -F'|' -v s="$ws_name" '$1==s{print $2}' \
        | sort -u | paste -sd "," - | sed 's/,/, /g')
    fi
    local has_label=$( [ -n "$label" ] && echo on || echo off )

    if [ "$KEY" = "$key" ]; then
      args+=(--set "$name"
        icon.font="SF Pro:Bold:12.0"
        icon.color=$BLUE
        label="$label"
        label.drawing=$has_label
        label.font="SF Pro:Bold:12.0"
        label.color=$TEXT
        background.color=$ITEM_BG_ACTIVE
        background.border_color=$BLUE
        background.border_width=2)
    else
      local idle_icon_color=$SUBTEXT
      [ -n "$label" ] && idle_icon_color=$MAUVE
      args+=(--set "$name"
        icon.font="SF Pro:Regular:12.0"
        icon.color=$idle_icon_color
        label="$label"
        label.drawing=$has_label
        label.font="SF Pro:Regular:12.0"
        label.color=$SUBTEXT
        background.color=0x00000000
        background.border_color=0x00000000
        background.border_width=0)
    fi

    # Force redraw: sketchybar doesn't repaint background/border on --set
    # alone. Toggling background.drawing does — batched in the same call.
    args+=(--set "$name" background.drawing=off
           --set "$name" background.drawing=on)
  done

  sketchybar "${args[@]}"
}
SPACES_PLUGIN_EOF

  cat > "$SKETCHY_DIR/plugins/front_app.sh" << 'FRONTAPP_PLUGIN_EOF'
#!/usr/bin/env bash
source "$CONFIG_DIR/plugins/spaces.sh"

APP="${INFO}"
if [ -z "$APP" ]; then
  APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
fi
WS=$(aerospace list-workspaces --focused 2>/dev/null | head -1)
sketchybar --set "$NAME" label="$WS $APP"
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
# BAR TOGGLE DAEMON
#
# Tiny Swift binary that polls the Option modifier and shows the SketchyBar
# while Option is held. On each show it fires `front_app_switched` so the
# space highlight is repainted fresh (workaround for sketchybar's background
# redraw quirk when --set runs against a hidden bar). Loaded as a LaunchAgent.
# =============================================================================
write_bar_toggle_daemon() {
  info "Writing bar_toggle daemon..."
  mkdir -p "$SKETCHY_DIR/plugins"

  cat > "$BAR_TOGGLE_SRC" << 'BAR_TOGGLE_SWIFT_EOF'
import Foundation
import CoreGraphics

let showDelay: TimeInterval = 0.15
let pollInterval: TimeInterval = 0.05
let sketchybarPath = "/opt/homebrew/bin/sketchybar"

func sb(_ args: String...) {
    let p = Process()
    p.launchPath = sketchybarPath
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

func optionPressed() -> Bool {
    let flags = CGEventSource.flagsState(.combinedSessionState)
    return flags.rawValue & CGEventFlags.maskAlternate.rawValue != 0
}

sb("--bar", "hidden=on", "topmost=window")

var visible = false
var holdStart: Date? = nil

while true {
    let pressed = optionPressed()
    if pressed && !visible {
        if holdStart == nil {
            holdStart = Date()
        } else if Date().timeIntervalSince(holdStart!) >= showDelay {
            sb("--bar", "hidden=off")
            sb("--trigger", "front_app_switched")
            visible = true
        }
    } else if !pressed {
        holdStart = nil
        if visible {
            sb("--bar", "hidden=on")
            visible = false
        }
    }
    Thread.sleep(forTimeInterval: pollInterval)
}
BAR_TOGGLE_SWIFT_EOF

  if ! command -v swiftc &>/dev/null; then
    warn "swiftc not found — install Xcode Command Line Tools (xcode-select --install)"
    return 1
  fi

  info "Compiling bar_toggle..."
  swiftc -O "$BAR_TOGGLE_SRC" -o "$BAR_TOGGLE_BIN"
  chmod +x "$BAR_TOGGLE_BIN"

  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$BAR_TOGGLE_PLIST" << BAR_TOGGLE_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$BAR_TOGGLE_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BAR_TOGGLE_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/bar_toggle.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/bar_toggle.log</string>
</dict>
</plist>
BAR_TOGGLE_PLIST_EOF

  success "bar_toggle daemon written"
}

# =============================================================================
# CHROME REHOME DAEMON
#
# Swift binary that subscribes to Chrome's AXWindowCreated events and moves
# each newly-opened window to the first empty workspace on the monitor where
# Chrome created it. If every workspace on that monitor is occupied, the
# window stays put. Aerospace's on-window-detected.run accepts only action
# commands (no shell-out), so this lives out-of-band as a LaunchAgent.
# =============================================================================
write_chrome_rehome_daemon() {
  info "Writing chrome_rehome daemon..."
  mkdir -p "$SKETCHY_DIR/plugins"

  cat > "$CHROME_REHOME_SRC" << 'CHROME_REHOME_SWIFT_EOF'
import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError

let aerospacePath = "/opt/homebrew/bin/aerospace"
let chromeBundleID = "com.google.Chrome"
let scanOrder: [String] = ["1","2","3","4","5","6","7","8","9","0"]

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

func firstEmptyOnMonitor(_ monitor: Character, skip currentWs: String) -> String? {
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
    for attempt in 0..<5 {
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
            if attempt < 4 { Thread.sleep(forTimeInterval: 0.04) }
            continue
        }
        let siblingChromeOnWs = rows.contains {
            $0.ws == ws && $0.id != wid && $0.app == "Google Chrome"
        }
        if siblingChromeOnWs {
            log("Chrome window \(wid) on \(ws): already has Chrome here, leaving in place")
            return
        }
        guard let monitor = ws.first else { return }
        if let target = firstEmptyOnMonitor(monitor, skip: ws) {
            log("Chrome window \(wid) alone on \(ws) -> \(target)")
            sh(["move-node-to-workspace", "--window-id", "\(wid)", target])
            sh(["workspace", target])
        } else {
            log("Chrome window \(wid) alone on \(ws): monitor full, leaving in place")
        }
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

func attachObserver(_ pid: pid_t) {
    detachObserver()
    var observer: AXObserver?
    let createResult = AXObserverCreate(pid, axCallback, &observer)
    guard createResult == .success, let obs = observer else {
        log("AXObserverCreate failed for pid \(pid): \(createResult.rawValue)")
        return
    }
    let app = AXUIElementCreateApplication(pid)
    let addResult = AXObserverAddNotification(obs, app, kAXWindowCreatedNotification as CFString, nil)
    if addResult != .success {
        log("AXObserverAddNotification failed for pid \(pid): \(addResult.rawValue)")
        return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    currentObserver = obs
    currentPid = pid
    log("attached AX observer to Chrome pid \(pid)")
}

let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
log("AXIsProcessTrusted: \(trusted)")

if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == chromeBundleID }) {
    attachObserver(app.processIdentifier)
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: nil
) { notif in
    if let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
       app.bundleIdentifier == chromeBundleID {
        attachObserver(app.processIdentifier)
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

  if ! command -v swiftc &>/dev/null; then
    warn "swiftc not found — install Xcode Command Line Tools (xcode-select --install)"
    return 1
  fi

  info "Compiling chrome_rehome..."
  swiftc -O "$CHROME_REHOME_SRC" -o "$CHROME_REHOME_BIN"
  chmod +x "$CHROME_REHOME_BIN"

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
  echo "  ./install.sh install   install and configure all tools"
  echo "  ./install.sh revert    undo everything, restore previous state"
  echo "  ./install.sh status    show install and service status"
  echo ""
}

case "${1:-}" in
  install) cmd_install ;;
  revert)  cmd_revert  ;;
  status)  cmd_status  ;;
  *)       usage; exit 1 ;;
esac
