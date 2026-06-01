#!/usr/bin/env bash
# Claude Code Statusline — smart cross-platform installer.
# Detects Linux / macOS / Windows (Git Bash, WSL) and merges settings.json
# without overwriting unrelated keys or existing hooks.

set -euo pipefail

# ── ARGS ──────────────────────────────────────────────────────────────────
ACTION="install"
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --uninstall) ACTION="uninstall" ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            cat <<EOF
Usage: ./install.sh [--uninstall] [--dry-run]

  (no args)     Install statusline + prompt hook.
  --uninstall   Remove only entries this script added (marker-based).
  --dry-run     Show what would change without writing.
EOF
            exit 0
            ;;
        *)
            echo "Unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

# ── COLORS ────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_DIM=""; C_BOLD=""; C_RST=""
fi
log() { printf "%s\n" "$*"; }
ok() { printf "%s✓%s %s\n" "$C_OK" "$C_RST" "$*"; }
warn() { printf "%s!%s %s\n" "$C_WARN" "$C_RST" "$*"; }
err() { printf "%s✗%s %s\n" "$C_ERR" "$C_RST" "$*" >&2; }
step() { printf "\n%s%s%s\n" "$C_BOLD" "$*" "$C_RST"; }

# ── OS DETECTION ──────────────────────────────────────────────────────────
UNAME=$(uname -s 2>/dev/null || echo unknown)
case "$UNAME" in
    Linux*) OS="linux" ;;
    Darwin*) OS="macos" ;;
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;; # Git Bash / MSYS2 / Cygwin
    *) OS="unknown" ;;
esac
# WSL is detected as Linux but reports a /proc marker
if [ "$OS" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
    OS="wsl"
fi

# ── DEPS ──────────────────────────────────────────────────────────────────
MISSING=()
for cmd in bash jq git; do
    command -v "$cmd" >/dev/null 2>&1 || MISSING+=("$cmd")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    err "Missing required tools: ${MISSING[*]}"
    case "$OS" in
        linux|wsl) log "  Debian/Ubuntu : sudo apt install ${MISSING[*]}"
                   log "  Fedora : sudo dnf install ${MISSING[*]}"
                   log "  Arch : sudo pacman -S ${MISSING[*]}" ;;
        macos)     log "  Homebrew : brew install ${MISSING[*]}" ;;
        windows)
            # Show specific hint only for jq since bash+git come from Git for Windows
            if printf '%s\n' "${MISSING[@]}" | grep -q '^jq$'; then
                log "  Install jq: winget install jqlang.jq"
                log "  Or see: https://stedolan.github.io/jq/download/"
            fi
            if printf '%s\n' "${MISSING[@]}" | grep -qE '^(bash|git)$'; then
                log "  Install Git for Windows (includes bash + git): https://git-scm.com/download/win"
            fi
            ;;
    esac
    exit 1
fi

# ── PATHS ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE_SRC="$SCRIPT_DIR/statusline.sh"
HOOK_SRC="$SCRIPT_DIR/prompt-start-hook.sh"
STATUSLINE_DST="$CLAUDE_DIR/statusline.sh"
HOOK_DST="$CLAUDE_DIR/prompt-start-hook.sh"

# ── COMMAND STRINGS (resolved at install time, written into settings.json)
# On all platforms we embed the POSIX path — bash (Git Bash / WSL / Linux / macOS)
# always accepts POSIX paths even on Windows. cygpath -w would give backslash paths
# that break when bash re-interprets them as escape sequences.
STATUSLINE_CMD="bash \"$STATUSLINE_DST\""
HOOK_CMD="bash \"$HOOK_DST\""

MARKER="claude-code-statusline"

# ── INFO ──────────────────────────────────────────────────────────────────
step "Detected"
log "  OS              : $OS ($UNAME)"
log "  Claude dir      : $CLAUDE_DIR"
log "  Settings file   : $SETTINGS"
log "  Statusline cmd  : $STATUSLINE_CMD"
log "  Hook cmd        : $HOOK_CMD"
[ "$DRY_RUN" -eq 1 ] && warn "Dry-run mode — no files will be written"

# ── SETTINGS HELPERS ──────────────────────────────────────────────────────
ensure_settings_dir() {
    [ "$DRY_RUN" -eq 1 ] && return
    mkdir -p "$CLAUDE_DIR"
}

read_settings() {
    if [ -f "$SETTINGS" ]; then
        if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
            err "Existing $SETTINGS is not valid JSON. Fix it manually before re-running."
            exit 1
        fi
        cat "$SETTINGS"
    else
        echo '{}'
    fi
}

backup_settings() {
    [ -f "$SETTINGS" ] || return 0
    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    local bak="${SETTINGS}.bak.${stamp}"
    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Would back up settings → $bak"
    else
        cp "$SETTINGS" "$bak"
        ok "Backed up existing settings → $bak"
    fi
}

write_settings() {
    local new_json="$1"
    if [ "$DRY_RUN" -eq 1 ]; then
        log ""
        log "${C_DIM}── settings.json (preview) ──${C_RST}"
        printf '%s\n' "$new_json"
        log "${C_DIM}─────────────────────────────${C_RST}"
        return
    fi
    printf '%s\n' "$new_json" > "$SETTINGS"
    ok "Wrote $SETTINGS"
}

# Merge: set statusLine (with marker) and append our hook entry if not already present.
merge_install() {
    jq \
        --arg sl "$STATUSLINE_CMD" \
        --arg hk "$HOOK_CMD" \
        --arg mk "$MARKER" \
        '
        # statusLine: replace only if absent OR already marked as ours (preserve user-customized one)
        if (.statusLine == null) or (.statusLine._managed == $mk) then
            .statusLine = { type: "command", command: $sl, _managed: $mk }
        else
            .
        end
        |
        # hooks.UserPromptSubmit: ensure shape, then append our entry only if no entry with our marker exists
        .hooks //= {}
        | .hooks.UserPromptSubmit //= []
        | if any(.hooks.UserPromptSubmit[]?; ._managed == $mk) then
              # Update existing managed entry in place (in case command path changed)
              .hooks.UserPromptSubmit |= map(
                  if ._managed == $mk then
                      { _managed: $mk, hooks: [ { type: "command", command: $hk, shell: "bash", async: true } ] }
                  else . end
              )
          else
              .hooks.UserPromptSubmit += [
                  { _managed: $mk, hooks: [ { type: "command", command: $hk, shell: "bash", async: true } ] }
              ]
          end
        '
}

# Uninstall: drop our statusLine if marked, drop hook entries with our marker, prune empty containers.
merge_uninstall() {
    jq \
        --arg mk "$MARKER" \
        '
        # statusLine
        if (.statusLine? // {} | ._managed) == $mk then
            del(.statusLine)
        else . end
        |
        # hook entries
        if (.hooks?.UserPromptSubmit?) then
            .hooks.UserPromptSubmit |= map(select(._managed != $mk))
            | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
            | if (.hooks | length) == 0 then del(.hooks) else . end
        else . end
        '
}

# ── INSTALL ───────────────────────────────────────────────────────────────
do_install() {
    step "Copying files → $CLAUDE_DIR"
    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Would copy: statusline.sh, prompt-start-hook.sh"
    else
        ensure_settings_dir
        cp "$STATUSLINE_SRC" "$STATUSLINE_DST"; chmod +x "$STATUSLINE_DST"
        cp "$HOOK_SRC" "$HOOK_DST"; chmod +x "$HOOK_DST"
        ok "Copied statusline.sh + prompt-start-hook.sh (executable)"
    fi

    step "Merging $SETTINGS"
    backup_settings
    local current new
    current=$(read_settings)
    new=$(printf '%s' "$current" | merge_install)
    # Pretty-print
    new=$(printf '%s' "$new" | jq '.')
    write_settings "$new"

    step "Done"
    if [ "$DRY_RUN" -eq 0 ]; then
        log "Restart Claude Code to see the statusline."
    fi
}

# ── UNINSTALL ─────────────────────────────────────────────────────────────
do_uninstall() {
    step "Removing managed entries from $SETTINGS"
    if [ ! -f "$SETTINGS" ]; then
        warn "No settings.json found — nothing to clean."
    else
        backup_settings
        local current new
        current=$(read_settings)
        new=$(printf '%s' "$current" | merge_uninstall | jq '.')
        write_settings "$new"
    fi

    step "Removing copied files"
    for f in "$STATUSLINE_DST" "$HOOK_DST"; do
        if [ -f "$f" ]; then
            if [ "$DRY_RUN" -eq 1 ]; then
                warn "Would remove $f"
            else
                rm -f "$f"; ok "Removed $f"
            fi
        fi
    done

    step "Done"
}

# ── MAIN ──────────────────────────────────────────────────────────────────
case "$ACTION" in
    install) do_install ;;
    uninstall) do_uninstall ;;
esac
