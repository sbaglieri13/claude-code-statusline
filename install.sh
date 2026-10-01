#!/usr/bin/env bash
# Claude Code Statusline — smart cross-platform installer.
# Merges settings.json without overwriting unrelated keys or hooks.

set -euo pipefail

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
  --uninstall   Remove only entries this script added (matched by exact command, plus the legacy "_managed" marker).
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

UNAME=$(uname -s 2>/dev/null || echo unknown)
case "$UNAME" in
    Linux*) OS="linux" ;;
    Darwin*) OS="macos" ;;
    MINGW*|MSYS*|CYGWIN*) OS="windows" ;;
    *) OS="unknown" ;;
esac
if [ "$OS" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
    OS="wsl"
fi

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE_SRC="$SCRIPT_DIR/statusline.sh"
HOOK_SRC="$SCRIPT_DIR/prompt-start-hook.sh"
STATUSLINE_DST="$CLAUDE_DIR/statusline.sh"
HOOK_DST="$CLAUDE_DIR/prompt-start-hook.sh"

# Embed POSIX paths: bash accepts them on Windows too, backslash paths break.
STATUSLINE_CMD="bash \"$STATUSLINE_DST\""
HOOK_CMD="bash \"$HOOK_DST\""

# Legacy marker: older installs tagged their entries with "_managed". We never write
# it anymore, but still recognise it so those entries can be migrated or removed.
MARKER="claude-code-statusline"
SIG_STATUSLINE="# Claude Code statusline — cross-platform"
SIG_HOOK="Records prompt-start timestamp"

step "Detected"
log "  OS              : $OS ($UNAME)"
log "  Claude dir      : $CLAUDE_DIR"
log "  Settings file   : $SETTINGS"
log "  Statusline cmd  : $STATUSLINE_CMD"
log "  Hook cmd        : $HOOK_CMD"
[ "$DRY_RUN" -eq 1 ] && warn "Dry-run mode — no files will be written"

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

JQ_DEFS='
def sl_cmd: if (.statusLine | type) == "object" then (.statusLine.command // null) else null end;
def sl_mk:  if (.statusLine | type) == "object" then (.statusLine._managed // null) else null end;
def sl_ours: (sl_cmd == $sl) or (sl_mk == $mk);
def sl_foreign: (.statusLine != null) and (sl_ours | not);
# Drop our hooks; remove an entry only if it became empty because of that.
def strip_ours:
    map(
        if (type == "object") and (._managed == $mk) then empty
        elif (type == "object") and ((.hooks | type) == "array") then
            (.hooks) as $h
            | ($h | map(select((.command? // null) != $hk))) as $n
            | if ($n | length) == 0 and ($h | length) > 0 then empty else .hooks = $n end
        else . end
    );
'

statusline_is_foreign() {
    jq -r --arg sl "$STATUSLINE_CMD" --arg mk "$MARKER" \
        "$JQ_DEFS"'if sl_foreign then "yes" else "no" end'
}

merge_install() {
    jq \
        --arg sl "$STATUSLINE_CMD" \
        --arg hk "$HOOK_CMD" \
        --arg mk "$MARKER" \
        "$JQ_DEFS"'
        .statusLine = { type: "command", command: $sl }
        | .hooks //= {}
        | .hooks.UserPromptSubmit = (
            ((.hooks.UserPromptSubmit // []) | if type == "array" then . else [.] end | strip_ours)
            + [ { hooks: [ { type: "command", command: $hk, shell: "bash", async: true } ] } ]
          )
        '
}

merge_uninstall() {
    jq \
        --arg sl "$STATUSLINE_CMD" \
        --arg hk "$HOOK_CMD" \
        --arg mk "$MARKER" \
        "$JQ_DEFS"'
        if sl_ours then del(.statusLine) else . end
        | if (.hooks | type) == "object" and ((.hooks.UserPromptSubmit | type) == "array") then
              .hooks.UserPromptSubmit |= strip_ours
              | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
              | if (.hooks | length) == 0 then del(.hooks) else . end
          else . end
        '
}

is_ours() {
    cmp -s "$1" "$2" || head -n 3 "$2" 2>/dev/null | grep -qF -- "$3"
}

# Refuse to overwrite third-party files. Runs before any backup or copy.
check_destinations() {
    local bad=0
    if [ -e "$STATUSLINE_DST" ] && ! is_ours "$STATUSLINE_SRC" "$STATUSLINE_DST" "$SIG_STATUSLINE"; then
        err "$STATUSLINE_DST exists and was not installed by this script."
        bad=1
    fi
    if [ -e "$HOOK_DST" ] && ! is_ours "$HOOK_SRC" "$HOOK_DST" "$SIG_HOOK"; then
        err "$HOOK_DST exists and was not installed by this script."
        bad=1
    fi
    if [ "$bad" -eq 1 ]; then
        log "  Rename or move the file(s) above, then re-run the installer. Nothing was changed."
        exit 1
    fi
}

do_install() {
    check_destinations

    local current foreign new
    current=$(read_settings)
    foreign=$(printf '%s' "$current" | statusline_is_foreign)

    step "Copying files → $CLAUDE_DIR"
    if [ "$DRY_RUN" -eq 1 ]; then
        warn "Would copy: statusline.sh, prompt-start-hook.sh"
    else
        ensure_settings_dir
        cp "$STATUSLINE_SRC" "$STATUSLINE_DST"; chmod +x "$STATUSLINE_DST"
        cp "$HOOK_SRC" "$HOOK_DST"; chmod +x "$HOOK_DST"
        ok "Copied statusline.sh + prompt-start-hook.sh (executable)"
    fi

    if [ "$foreign" = "yes" ]; then
        step "Settings left untouched"
        warn "Another statusLine is already configured, so settings.json was not modified"
        warn "and the prompt hook was not added. Existing command:"
        log "    $(printf '%s' "$current" | jq -r '(.statusLine.command? // (.statusLine | tojson))')"
        log "  To activate this statusline, set statusLine.command in $SETTINGS to:"
        log "    $STATUSLINE_CMD"
        log "  (and add a UserPromptSubmit hook running: $HOOK_CMD)"
        step "Done"
        warn "The statusline is NOT active."
        return
    fi

    step "Merging $SETTINGS"
    backup_settings
    new=$(printf '%s' "$current" | merge_install | jq '.')
    write_settings "$new"

    step "Done"
    if [ "$DRY_RUN" -eq 0 ]; then
        log "Restart Claude Code to see the statusline."
    fi
}

do_uninstall() {
    step "Removing our entries from $SETTINGS"
    if [ ! -f "$SETTINGS" ]; then
        warn "No settings.json found — nothing to clean."
    else
        backup_settings
        local current new
        current=$(read_settings)
        new=$(printf '%s' "$current" | merge_uninstall | jq '.')
        write_settings "$new"
    fi

    # Files are removed only after settings.json was written successfully (set -e aborts otherwise).
    step "Removing copied files"
    local f src sig
    for f in "$STATUSLINE_DST" "$HOOK_DST"; do
        [ -f "$f" ] || continue
        if [ "$f" = "$STATUSLINE_DST" ]; then src="$STATUSLINE_SRC"; sig="$SIG_STATUSLINE"; else src="$HOOK_SRC"; sig="$SIG_HOOK"; fi
        if ! is_ours "$src" "$f" "$sig"; then
            warn "Skipping $f (not installed by this script)"
        elif [ "$DRY_RUN" -eq 1 ]; then
            warn "Would remove $f"
        else
            rm -f "$f"; ok "Removed $f"
        fi
    done

    step "Done"
}

case "$ACTION" in
    install) do_install ;;
    uninstall) do_uninstall ;;
esac
