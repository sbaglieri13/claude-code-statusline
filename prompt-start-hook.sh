#!/usr/bin/env bash
# Records prompt-start timestamp (ms) for the statusline timer.
# Portable across Linux, macOS, Windows (Git Bash).

TMPDIR="${TMPDIR:-/tmp}"

# Key the timer file by session_id so parallel sessions don't collide.
SID=""
if command -v jq >/dev/null 2>&1; then
    SID=$(cat | jq -r '.session_id // empty' 2>/dev/null)
fi
[ -z "$SID" ] && SID="default"
OUT="${TMPDIR}/claude-prompt-start-${SID}.txt"

# Prune orphan timer files from old/closed sessions (older than 1 day).
find "$TMPDIR" -maxdepth 1 -name 'claude-prompt-start-*.txt' -mtime +0 -delete 2>/dev/null || true

if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d", time*1000' > "$OUT"
elif date +%N 2>/dev/null | grep -q '^[0-9]'; then
    # GNU date (Linux, Git Bash)
    date +%s%3N > "$OUT"
elif [ -n "${EPOCHREALTIME:-}" ]; then
    # bash 5+
    awk -v t="$EPOCHREALTIME" 'BEGIN { printf "%d", t*1000 }' > "$OUT"
else
    # Fallback: seconds → ms
    awk 'BEGIN { printf "%d", systime()*1000 }' > "$OUT"
fi
