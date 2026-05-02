#!/usr/bin/env bash
# cua-driver LOCAL installer — install a previously-downloaded + inspected
# build from a local path, or opt in to downloading the latest GitHub release
# before verifying and installing it.
#
# Usage:
#   scripts/install-cua-driver-local.sh <path>
#   scripts/install-cua-driver-local.sh --download-latest
#
# <path> may be either:
#   - a directory containing CuaDriver.app/ at its top level, or
#   - a .tar.gz produced by the upstream release pipeline
#
# Flags (same semantics as upstream install.sh):
#   --bin-dir <path>     install the cua-driver wrapper to <path> instead of
#                        ~/.local/bin
#   --no-modify-path     skip auto-appending an `export PATH=...` line
#   --skip-verify        skip codesign + Gatekeeper re-verification
#                        (NOT recommended — the whole point of the local
#                        flow is to re-check what you inspected)
#   --expected-team-id <id>
#                        require this Apple Developer Team ID. Default:
#                        YCK386LBJ7  (Cua AI, Inc. — observed for v0.1.1)
#   --download-latest    download the latest release tarball from GitHub,
#                        then verify and install it
#
# Env overrides:
#   CUA_DRIVER_BIN_DIR=PATH        same as --bin-dir
#   CUA_DRIVER_NO_MODIFY_PATH=1    same as --no-modify-path
#   CUA_DRIVER_SKIP_VERIFY=1       same as --skip-verify
#   CUA_DRIVER_EXPECTED_TEAM_ID    same as --expected-team-id
#   CUA_DRIVER_DOWNLOAD_LATEST=1   same as --download-latest
set -euo pipefail

REPO="trycua/cua"
APP_NAME="CuaDriver.app"
BINARY_NAME="cua-driver"
TAG_PREFIX="cua-driver-v"
APP_DEST="/Applications/$APP_NAME"
BIN_DIR="${CUA_DRIVER_BIN_DIR:-$HOME/.local/bin}"
NO_MODIFY_PATH="${CUA_DRIVER_NO_MODIFY_PATH:-0}"
SKIP_VERIFY="${CUA_DRIVER_SKIP_VERIFY:-0}"
EXPECTED_TEAM_ID="${CUA_DRIVER_EXPECTED_TEAM_ID:-YCK386LBJ7}"
DOWNLOAD_LATEST="${CUA_DRIVER_DOWNLOAD_LATEST:-0}"
SOURCE_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin-dir) BIN_DIR="$2"; shift 2 ;;
        --bin-dir=*) BIN_DIR="${1#*=}"; shift ;;
        --no-modify-path) NO_MODIFY_PATH=1; shift ;;
        --skip-verify) SKIP_VERIFY=1; shift ;;
        --expected-team-id) EXPECTED_TEAM_ID="$2"; shift 2 ;;
        --expected-team-id=*) EXPECTED_TEAM_ID="${1#*=}"; shift ;;
        --download-latest) DOWNLOAD_LATEST=1; shift ;;
        -h|--help)
            sed -n '2,32p' "$0"; exit 0 ;;
        --) shift; SOURCE_PATH="${1:-}"; shift || true ;;
        -*) echo "error: unknown flag: $1" >&2; exit 2 ;;
        *)
            if [[ -z "$SOURCE_PATH" ]]; then SOURCE_PATH="$1"; else
                echo "error: unexpected extra argument: $1" >&2; exit 2
            fi
            shift ;;
    esac
done

if [[ -n "$SOURCE_PATH" ]] && [[ "$DOWNLOAD_LATEST" == "1" ]]; then
    echo "error: use either <path> or --download-latest, not both" >&2
    exit 2
fi

BIN_LINK="$BIN_DIR/$BINARY_NAME"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

log() { printf '==> %s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

# --- Sanity checks ------------------------------------------------------

if [[ "$(uname -s)" != "Darwin" ]]; then
    err "cua-driver is macOS-only; uname reports $(uname -s)"
    exit 1
fi

if [[ -z "$SOURCE_PATH" ]] && [[ "$DOWNLOAD_LATEST" != "1" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "No local CuaDriver path provided. Download latest release from GitHub? [y/N] " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            DOWNLOAD_LATEST=1
        fi
    fi

    if [[ "$DOWNLOAD_LATEST" != "1" ]]; then
        err "missing <path> argument (directory containing CuaDriver.app, or .tar.gz)"
        err "run with --help for usage, or use --download-latest"
        exit 2
    fi
fi

# --- Resolve source -> $SRC_APP (path to CuaDriver.app to install) ------

if [[ "$DOWNLOAD_LATEST" == "1" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
        err "curl not found on PATH"
        exit 1
    fi
    if ! command -v tar >/dev/null 2>&1; then
        err "tar not found on PATH"
        exit 1
    fi

    log "resolving latest $TAG_PREFIX* release via GitHub API"
    TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=40" \
        | grep -Eo '"tag_name":[[:space:]]*"'"${TAG_PREFIX}"'[^"]+"' \
        | sed -E 's/.*"'"${TAG_PREFIX}"'([0-9]+[.][0-9]+[.][0-9]+)"/\1/' \
        | sort -t. -k1,1nr -k2,2nr -k3,3nr \
        | head -n 1 \
        | sed -E 's/^/'"${TAG_PREFIX}"'/' \
        || true)
    if [[ -z "$TAG" ]]; then
        err "no release matching ${TAG_PREFIX}* found on $REPO"
        exit 1
    fi
    log "latest release: $TAG"

    ARCH=$(uname -m)
    VERSION="${TAG#${TAG_PREFIX}}"
    TARBALL="cua-driver-${VERSION}-darwin-${ARCH}.tar.gz"
    URL="https://github.com/$REPO/releases/download/$TAG/$TARBALL"

    log "downloading $URL"
    if ! curl -fsSL -o "$TMP_DIR/$TARBALL" "$URL"; then
        err "download failed"
        exit 1
    fi

    log "extracting $TARBALL"
    tar -xzf "$TMP_DIR/$TARBALL" -C "$TMP_DIR"
    if [[ ! -d "$TMP_DIR/$APP_NAME" ]]; then
        err "$APP_NAME not found inside $TARBALL"
        exit 1
    fi
    SRC_APP="$TMP_DIR/$APP_NAME"
elif [[ -d "$SOURCE_PATH" ]]; then
    if [[ -d "$SOURCE_PATH/$APP_NAME" ]]; then
        SRC_APP="$SOURCE_PATH/$APP_NAME"
    elif [[ "$(basename "$SOURCE_PATH")" == "$APP_NAME" ]]; then
        SRC_APP="$SOURCE_PATH"
    else
        err "$SOURCE_PATH is a directory but contains no $APP_NAME"
        exit 1
    fi
    log "using local app bundle at $SRC_APP"
elif [[ -f "$SOURCE_PATH" ]]; then
    case "$SOURCE_PATH" in
        *.tar.gz|*.tgz)
            if ! command -v tar >/dev/null 2>&1; then
                err "tar not found on PATH"
                exit 1
            fi
            log "extracting $SOURCE_PATH"
            tar -xzf "$SOURCE_PATH" -C "$TMP_DIR"
            if [[ ! -d "$TMP_DIR/$APP_NAME" ]]; then
                err "$APP_NAME not found inside $SOURCE_PATH"
                exit 1
            fi
            SRC_APP="$TMP_DIR/$APP_NAME"
            ;;
        *)
            err "$SOURCE_PATH: only .tar.gz / .tgz files are supported"
            exit 1
            ;;
    esac
else
    err "$SOURCE_PATH: not a file or directory"
    exit 1
fi

# --- Re-verify code signature ------------------------------------------
#
# This is the point of the local-install flow. The upstream installer does
# zero verification before `ditto`-ing into /Applications; here we re-run
# the same checks we did during inspection, and bail loudly on mismatch.

if [[ "$SKIP_VERIFY" != "1" ]]; then
    log "verifying code signature on $SRC_APP"
    if ! codesign --verify --strict --deep "$SRC_APP" 2>/dev/null; then
        err "codesign --verify --strict --deep FAILED on $SRC_APP"
        exit 1
    fi

    SIG_INFO=$(codesign -dv --verbose=4 "$SRC_APP" 2>&1)
    GOT_TEAM_ID=$(printf '%s\n' "$SIG_INFO" \
        | sed -nE 's/^TeamIdentifier=([A-Z0-9]+).*/\1/p' \
        | head -n 1)
    # Older codesign output puts the team id only inside the Authority line;
    # parse that as a fallback.
    if [[ -z "$GOT_TEAM_ID" ]]; then
        GOT_TEAM_ID=$(printf '%s\n' "$SIG_INFO" \
            | sed -nE 's/^Authority=Developer ID Application:.*\(([A-Z0-9]+)\).*/\1/p' \
            | head -n 1)
    fi

    if [[ -z "$GOT_TEAM_ID" ]]; then
        err "could not extract Team ID from codesign output"
        printf '%s\n' "$SIG_INFO" >&2
        exit 1
    fi
    if [[ "$GOT_TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
        err "Team ID mismatch: got '$GOT_TEAM_ID', expected '$EXPECTED_TEAM_ID'"
        err "refusing to install. Override with --expected-team-id if you know what you're doing."
        exit 1
    fi
    log "codesign team id: $GOT_TEAM_ID (matches expected)"

    # Notarization / Gatekeeper. Don't hard-fail on assess (corp policies can
    # disable spctl), but warn loudly.
    if ASSESS_OUT=$(spctl --assess --type execute --verbose=4 "$SRC_APP" 2>&1); then
        log "Gatekeeper: $(printf '%s\n' "$ASSESS_OUT" | tail -n 1)"
    else
        err "WARNING: spctl --assess did not accept the bundle:"
        printf '%s\n' "$ASSESS_OUT" >&2
        err "continuing (use --skip-verify to silence). Inspect manually before launching."
    fi
else
    log "WARNING: skipping codesign / Gatekeeper verification (--skip-verify)"
fi

# --- Clean up legacy bits from <= v0.0.5 --------------------------------

LEGACY_UPDATER_PLIST="$HOME/Library/LaunchAgents/com.trycua.cua_driver_updater.plist"
LEGACY_UPDATE_SCRIPT="/usr/local/bin/cua-driver-update"

if [[ -f "$LEGACY_UPDATER_PLIST" ]]; then
    launchctl unload "$LEGACY_UPDATER_PLIST" 2>/dev/null || true
    rm -f "$LEGACY_UPDATER_PLIST"
    log "removed legacy LaunchAgent $LEGACY_UPDATER_PLIST"
fi
if [[ -f "$LEGACY_UPDATE_SCRIPT" ]]; then
    log "legacy $LEGACY_UPDATE_SCRIPT still present (run \`cua-driver doctor\` to remove — needs sudo)"
fi

# --- Install .app bundle ------------------------------------------------

if [[ -e "$APP_DEST" ]]; then
    log "removing existing $APP_DEST"
    rm -rf "$APP_DEST"
fi

log "installing $APP_DEST"
ditto "$SRC_APP" "$APP_DEST"

# --- Wrapper / symlink for CLI ------------------------------------------

APP_BINARY="$APP_DEST/Contents/MacOS/$BINARY_NAME"
if [[ ! -x "$APP_BINARY" ]]; then
    err "binary missing at $APP_BINARY (refusing to create broken symlink)"
    exit 1
fi

mkdir -p "$BIN_DIR"
if [[ ! -w "$BIN_DIR" ]]; then
    err "$BIN_DIR is not writable. Pick a user-writable --bin-dir, or pre-create the dir with sudo."
    exit 1
fi
ln -sf "$APP_BINARY" "$BIN_LINK"
log "symlinked $BIN_LINK -> $APP_BINARY"

LEGACY_BIN_LINK="/usr/local/bin/$BINARY_NAME"
if [[ "$BIN_LINK" != "$LEGACY_BIN_LINK" ]] && [[ -L "$LEGACY_BIN_LINK" ]]; then
    log "kept legacy $LEGACY_BIN_LINK in place for backwards compatibility"
fi

# --- Install agent skill pack -------------------------------------------

SKILL_TARGET="$APP_DEST/Contents/Resources/Skills/cua-driver"

link_skill_into() {
    local parent_dir="$1"
    local label="$2"
    local link_path="$parent_dir/cua-driver"

    if [[ ! -d "$parent_dir" ]]; then
        return 0
    fi
    if [[ -e "$link_path" ]] || [[ -L "$link_path" ]]; then
        log "$label skill link already exists at $link_path (skipping)"
        return 0
    fi
    if [[ ! -d "$SKILL_TARGET" ]]; then
        log "skill pack missing at $SKILL_TARGET (skipping; older release?)"
        return 0
    fi
    ln -s "$SKILL_TARGET" "$link_path"
    log "symlinked $label skill at $link_path"
}

link_skill_into "$HOME/.claude/skills" "Claude Code"

if [[ -d "$HOME/.codex" ]] && [[ ! -d "$HOME/.agents/skills" ]]; then
    mkdir -p "$HOME/.agents/skills"
fi
link_skill_into "$HOME/.agents/skills" "Codex"

if [[ -d "$HOME/.openclaw" ]] && [[ ! -d "$HOME/.openclaw/skills" ]]; then
    mkdir -p "$HOME/.openclaw/skills"
fi
link_skill_into "$HOME/.openclaw/skills" "OpenClaw"

if [[ -d "$HOME/.config/opencode" ]] && [[ ! -d "$HOME/.config/opencode/skills" ]]; then
    mkdir -p "$HOME/.config/opencode/skills"
fi
link_skill_into "$HOME/.config/opencode/skills" "OpenCode"

# --- PATH setup ---------------------------------------------------------

PATH_NEEDS_FIX=1
case ":$PATH:" in
    *":$BIN_DIR:"*) PATH_NEEDS_FIX=0 ;;
esac

if [[ "$PATH_NEEDS_FIX" == "1" ]]; then
    if [[ "$NO_MODIFY_PATH" == "1" ]]; then
        log "$BIN_DIR is not on PATH (skipping rc edit; --no-modify-path set)"
    else
        SHELL_NAME="$(basename "${SHELL:-/bin/zsh}")"
        case "$SHELL_NAME" in
            zsh)  RC_FILE="$HOME/.zshrc" ;;
            bash) RC_FILE="$HOME/.bash_profile" ;;
            fish) RC_FILE="$HOME/.config/fish/config.fish" ;;
            *)    RC_FILE="" ;;
        esac

        if [[ -n "$RC_FILE" ]]; then
            mkdir -p "$(dirname "$RC_FILE")"
            # Use the actual chosen BIN_DIR (upstream hardcoded ~/.local/bin
            # here even when --bin-dir overrode it — fixed).
            EXPORT_LINE="export PATH=\"$BIN_DIR:\$PATH\""
            [[ "$SHELL_NAME" == "fish" ]] && EXPORT_LINE="set -gx PATH $BIN_DIR \$PATH"

            if [[ -f "$RC_FILE" ]] && grep -qF "$BIN_DIR" "$RC_FILE"; then
                log "$BIN_DIR already referenced in $RC_FILE (skipping rc edit)"
            else
                {
                    printf '\n# Added by cua-driver local installer\n'
                    printf '%s\n' "$EXPORT_LINE"
                } >> "$RC_FILE"
                log "appended PATH entry to $RC_FILE — restart your shell or run: source $RC_FILE"
            fi
        else
            log "unrecognised shell '$SHELL_NAME' — add $BIN_DIR to PATH manually"
        fi
    fi
fi

# --- Done ---------------------------------------------------------------

INSTALLED_VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_DEST/Contents/Info.plist" 2>/dev/null || echo "?")
log "cua-driver $INSTALLED_VERSION installed from local source"
cat <<FINALEOF

Next steps:

  1. Grant macOS permissions (required either way):
       open -n -g -a CuaDriver --args serve
       cua-driver check_permissions
     macOS raises the Accessibility + Screen Recording dialogs.
     Grant both, then re-run check_permissions to confirm.

  2. Pick how you want to use cua-driver — pick ONE, both, or switch later:

     A. As a CLI from the shell (no extra config needed):
          cua-driver list_apps
          cua-driver --help

     B. As an MCP server — run the one matching your client. Each is also
        available via 'cua-driver mcp-config --client <name>':

        • Claude Code (global/user scope):
            claude mcp add --scope user --transport stdio cua-driver -- $BIN_LINK mcp

          Claude Code computer-use compatibility mode:
            claude mcp add --scope user --transport stdio cua-computer-use -- $BIN_LINK mcp --claude-code-computer-use-compat
          Use this when you want Claude Code's vision/computer-use-style flow
          to ground on CuaDriver window screenshots. It keeps the normal
          CuaDriver tools and changes only the screenshot tool.
          Use MCP for this path; CLI screenshots do not expose the
          mcp__cua-computer-use__screenshot tool name cue.

        • Gemini CLI (global/user scope):
            gemini mcp add --scope user --transport stdio cua-driver $BIN_LINK mcp

        • Codex (OpenAI):
            codex mcp add cua-driver -- $BIN_LINK mcp

        • OpenClaw:
            cua-driver mcp-config --client openclaw

        • GitHub Copilot CLI (paste into ~/.copilot/mcp-config.json):
            {
              "mcpServers": {
                "cua-driver": {
                  "type": "local",
                  "command": "$BIN_LINK",
                  "args": ["mcp"],
                  "tools": ["*"]
                }
              }
            }
            Or inside gh copilot chat: /mcp add → type=STDIO, command=$BIN_LINK, args=mcp

        • Cursor / OpenCode / Hermes (no add CLI — paste config):
            cua-driver mcp-config --client cursor     # JSON for ~/.cursor/mcp.json
            cua-driver mcp-config --client opencode   # JSON for opencode.json
            cua-driver mcp-config --client hermes     # YAML for ~/.hermes/config.yaml

        For other clients accepting the generic mcpServers shape:
            cua-driver mcp-config

Docs: https://github.com/trycua/cua/tree/main/libs/cua-driver
FINALEOF
