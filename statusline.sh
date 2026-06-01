#!/usr/bin/env bash
# Claude Code statusline — cross-platform (Linux, macOS, Windows via Git Bash)
# Reads session JSON from stdin, prints 2 ANSI lines to stdout.

set -u
export LC_ALL=C.UTF-8 2>/dev/null || export LC_ALL=en_US.UTF-8

ESC=$'\033'

# ICONS (UTF-8)
I_ROBOT=$'\xf0\x9f\xa4\x96'      # 🤖
I_FOLDER=$'\xf0\x9f\x93\x81'     # 📁
I_LEAF=$'\xf0\x9f\x8c\xbf'       # 🌿
I_BRAIN=$'\xf0\x9f\xa7\xa0'      # 🧠
I_FUEL=$'\xf0\x9f\x94\x8b'       # 🔋
I_TIMER=$'\xe2\x8f\xb3'          # ⏳
I_BULLET=$'\xe2\x80\xa2'         # •
I_LIGHTNING=$'\xe2\x9a\xa1'      # ⚡
BAR_FULL=$'\xe2\x97\x8f'         # ●
BAR_EMPTY=$'\xe2\x97\x8b'        # ○

# COLORS (truecolor ANSI)
CRAIL="${ESC}[38;2;193;95;60m"
CLOUDY="${ESC}[38;2;177;173;161m"
CYAN="${ESC}[38;2;0;255;255m"
RED="${ESC}[38;2;255;85;85m"
YELLOW="${ESC}[38;2;255;255;128m"
GREEN="${ESC}[38;2;80;250;123m"
WHITE="${ESC}[38;2;244;243;238m"
RESET="${ESC}[0m"

# Thresholds — set your thresholds here
thresh_color() {
    local pct=$1
    if [ "$pct" -lt 60 ]; then echo "$GREEN"
    elif [ "$pct" -lt 80 ]; then echo "$YELLOW"
    else echo "$RED"
    fi
}
# Rate limit color thresholds — set your thresholds here
usage_color() {
    local pct=$1
    if [ "$pct" -lt 70 ]; then echo "$GREEN"
    elif [ "$pct" -lt 95 ]; then echo "$YELLOW"
    else echo "$RED"
    fi
}

fmt_tok() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then
        awk -v n="$n" 'BEGIN { printf "%.1fM", n/1000000 }'
    elif [ "$n" -ge 1000 ]; then
        awk -v n="$n" 'BEGIN { printf "%dk", (n/1000) + 0.5 }'
    else
        printf "%d" "$n"
    fi
}

fmt_reset() {
    local ts=$1
    local now diff
    now=$(date +%s)
    diff=$((ts - now))
    if [ "$diff" -le 0 ]; then echo "now"; return; fi
    if [ "$diff" -lt 86400 ]; then
        date -d "@$ts" +"%-I:%M %p" 2>/dev/null || date -r "$ts" +"%-I:%M %p"
    else
        date -d "@$ts" +"%b %-d, %-I:%M %p" 2>/dev/null || date -r "$ts" +"%b %-d, %-I:%M %p"
    fi
}

# Choose tmp dir (Windows Git Bash uses /tmp too)
TMPDIR="${TMPDIR:-/tmp}"
RL_CACHE="${TMPDIR}/claude-rl-cache.json"   # account-wide, shared across sessions

RAW=$(cat)
if [ -z "$RAW" ]; then RAW='{}'; fi

if ! command -v jq >/dev/null 2>&1; then
    printf "%sjq not installed — statusline unavailable%s" "$RED" "$RESET"
    exit 0
fi

# Per-session timer file (keyed by session_id so parallel sessions don't collide)
SID=$(printf '%s' "$RAW" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && SID="default"
TIMER_FILE="${TMPDIR}/claude-prompt-start-${SID}.txt"

# MODEL
M_NAME=$(printf '%s' "$RAW" | jq -r '
    (.model.display_name // .model.id // (.model | strings) // "Claude")
    | sub("^claude-"; "")
' 2>/dev/null)
[ -z "$M_NAME" ] && M_NAME="Claude"

# CONTEXT
TOTAL_TOK=$(printf '%s' "$RAW" | jq -r '
    (.context_window.context_window_size // .context_window.total_tokens // 200000)
    | tonumber
' 2>/dev/null)
[ -z "$TOTAL_TOK" ] || [ "$TOTAL_TOK" = "null" ] && TOTAL_TOK=200000

USED_TOK=$(printf '%s' "$RAW" | jq -r '
    if .context_window.total_input_tokens != null then
        (.context_window.total_input_tokens + (.context_window.total_output_tokens // 0))
    elif .context_window.used_tokens != null then
        .context_window.used_tokens
    else
        empty
    end
' 2>/dev/null)

USED_PCT=$(printf '%s' "$RAW" | jq -r '
    if .context_window.used_percentage != null then
        .context_window.used_percentage
    else
        empty
    end
' 2>/dev/null)

if [ -z "$USED_PCT" ] && [ -n "$USED_TOK" ] && [ "$TOTAL_TOK" -gt 0 ]; then
    USED_PCT=$(awk -v u="$USED_TOK" -v t="$TOTAL_TOK" 'BEGIN { printf "%.2f", (u*100.0)/t }')
fi
[ -z "$USED_PCT" ] && USED_PCT=0

# Rate limits raw
RL=$(printf '%s' "$RAW" | jq -c '.rate_limits // empty' 2>/dev/null)

# FALLBACK from transcript JSONL
TRANSCRIPT=$(printf '%s' "$RAW" | jq -r '.transcript_path // empty' 2>/dev/null)
PCT_INT=$(awk -v p="$USED_PCT" 'BEGIN { x=p+0; if(x>100)x=100; printf "%d", x+0.5 }')

if { [ "$PCT_INT" -eq 0 ] || [ -z "$RL" ]; } && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    NEED_CTX=1; NEED_RL=1
    [ "$PCT_INT" -ne 0 ] && NEED_CTX=0
    [ -n "$RL" ] && NEED_RL=0
    # Read last 30 lines in reverse (newest first)
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        if [ "$NEED_CTX" -eq 1 ]; then
            EP=$(printf '%s' "$line" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
            if [ -n "$EP" ] && awk -v x="$EP" 'BEGIN { exit !(x+0>0) }'; then
                USED_PCT=$EP
                if [ -z "$USED_TOK" ]; then
                    NEW_USED=$(printf '%s' "$line" | jq -r '
                        if .context_window.total_input_tokens != null then
                            (.context_window.total_input_tokens + (.context_window.total_output_tokens // 0))
                        else empty end' 2>/dev/null)
                    [ -n "$NEW_USED" ] && USED_TOK=$NEW_USED
                fi
                NEED_CTX=0
            fi
        fi
        if [ "$NEED_RL" -eq 1 ]; then
            ER=$(printf '%s' "$line" | jq -c '.rate_limits // empty' 2>/dev/null)
            if [ -n "$ER" ]; then RL=$ER; NEED_RL=0; fi
        fi
        [ "$NEED_CTX" -eq 0 ] && [ "$NEED_RL" -eq 0 ] && break
    done < <(tail -n 30 "$TRANSCRIPT" 2>/dev/null | tac 2>/dev/null || tail -n 30 "$TRANSCRIPT" 2>/dev/null | awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}')
    PCT_INT=$(awk -v p="$USED_PCT" 'BEGIN { x=p+0; if(x>100)x=100; printf "%d", x+0.5 }')
fi

TOK_TOTAL_STR=$([ -n "$USED_TOK" ] && fmt_tok "$USED_TOK" || echo "0")
TOK_LIMIT_STR=$(fmt_tok "$TOTAL_TOK")

# PROGRESS BAR
BAR_COLOR=$(thresh_color "$PCT_INT")
BAR_WIDTH=10
FILLED=$(awk -v p="$PCT_INT" -v w="$BAR_WIDTH" 'BEGIN { x=int(p/(100.0/w)); if(x>w)x=w; if(x<0)x=0; printf "%d", x }')
EMPTY=$((BAR_WIDTH - FILLED))

BAR="${BAR_COLOR}"
i=0; while [ "$i" -lt "$FILLED" ]; do BAR="${BAR}${BAR_FULL}"; i=$((i+1)); done
BAR="${BAR}${CLOUDY}"
i=0; while [ "$i" -lt "$EMPTY" ]; do BAR="${BAR}${BAR_EMPTY}"; i=$((i+1)); done

# RATE LIMITS — fallback from cache
if [ -z "$RL" ] && [ -f "$RL_CACHE" ]; then
    RL=$(cat "$RL_CACHE" 2>/dev/null)
fi

USAGE_STR=""; RESET_STR=""
if [ -n "$RL" ]; then
    printf '%s' "$RL" > "$RL_CACHE" 2>/dev/null || true

    U_PARTS=""; R_PARTS=""
    # Daily (five_hour)
    FH_PCT=$(printf '%s' "$RL" | jq -r '.five_hour.used_percentage // empty' 2>/dev/null)
    FH_RST=$(printf '%s' "$RL" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
    if [ -n "$FH_PCT" ]; then
        P=$(awk -v x="$FH_PCT" 'BEGIN { printf "%d", x+0 }')
        UC=$(usage_color "$P")
        SEP=""; [ -n "$U_PARTS" ] && SEP=" ${CLOUDY}${I_BULLET} "
        U_PARTS="${U_PARTS}${SEP}${UC}${P}%${RESET} ${CLOUDY}(Daily)"
        if [ -n "$FH_RST" ]; then
            SEP=""; [ -n "$R_PARTS" ] && SEP=" ${CLOUDY}${I_BULLET} "
            R_PARTS="${R_PARTS}${SEP}${WHITE}$(fmt_reset "$FH_RST") ${CLOUDY}(Daily)"
        fi
    fi
    # Weekly (seven_day)
    SD_PCT=$(printf '%s' "$RL" | jq -r '.seven_day.used_percentage // empty' 2>/dev/null)
    SD_RST=$(printf '%s' "$RL" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
    if [ -n "$SD_PCT" ]; then
        P=$(awk -v x="$SD_PCT" 'BEGIN { printf "%d", x+0 }')
        UC=$(usage_color "$P")
        SEP=""; [ -n "$U_PARTS" ] && SEP=" ${CLOUDY}${I_BULLET} "
        U_PARTS="${U_PARTS}${SEP}${UC}${P}%${RESET} ${CLOUDY}(Weekly)"
        if [ -n "$SD_RST" ]; then
            SEP=""; [ -n "$R_PARTS" ] && SEP=" ${CLOUDY}${I_BULLET} "
            R_PARTS="${R_PARTS}${SEP}${WHITE}$(fmt_reset "$SD_RST") ${CLOUDY}(Weekly)"
        fi
    fi

    [ -n "$U_PARTS" ] && USAGE_STR="${CLOUDY}${I_FUEL} ${U_PARTS}${RESET}"
    [ -n "$R_PARTS" ] && RESET_STR="${CLOUDY}${I_TIMER} Reset: ${R_PARTS}${RESET}"
fi

# FOLDER
RAW_CWD=$(printf '%s' "$RAW" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$RAW_CWD" ] && RAW_CWD=$(pwd)
FOLDER=$(basename "$RAW_CWD")

# GIT
GIT_STATUS=""
if [ -d "$RAW_CWD/.git" ] || git -C "$RAW_CWD" rev-parse --git-dir >/dev/null 2>&1; then
    BRANCH=$(git -C "$RAW_CWD" branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        DIRTY=$(git -C "$RAW_CWD" status --short 2>/dev/null)
        if [ -n "$DIRTY" ]; then GIT_COLOR=$YELLOW; else GIT_COLOR=$GREEN; fi
        GIT_STATUS=" ${CLOUDY}| ${GIT_COLOR}${I_LEAF} ${BRANCH}${RESET}"
    fi
fi

# TIMER
TIMER_STR=""
if [ -f "$TIMER_FILE" ]; then
    START_MS=$(cat "$TIMER_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$START_MS" ]; then
        NOW_MS=$(awk 'BEGIN { srand(); printf "%d", systime()*1000 }')
        # Prefer higher-precision now
        if command -v perl >/dev/null 2>&1; then
            NOW_MS=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
        elif date +%N 2>/dev/null | grep -q '^[0-9]'; then
            NOW_MS=$(date +%s%3N)
        fi
        DELTA=$((NOW_MS - START_MS))
        if [ "$DELTA" -gt 500 ] && [ "$DELTA" -lt 600000 ]; then
            SECS=$(awk -v d="$DELTA" 'BEGIN { printf "%.1f", d/1000.0 }')
            TIMER_STR=" ${CLOUDY}| ${I_LIGHTNING} ${SECS}s${RESET}"
        fi
    fi
fi

# CONTEXT section
if [ "$PCT_INT" -eq 0 ] && { [ -z "$USED_TOK" ] || [ "$USED_TOK" = "0" ]; }; then
    EMPTY_BAR=""
    i=0; while [ "$i" -lt "$BAR_WIDTH" ]; do EMPTY_BAR="${EMPTY_BAR}${BAR_EMPTY}"; i=$((i+1)); done
    CTX_SECTION="${CLOUDY}${I_BRAIN} Context ${EMPTY_BAR} --${RESET}"
else
    CTX_SECTION="${BAR_COLOR}${I_BRAIN} Context ${BAR}${BAR_COLOR} ${PCT_INT}%${RESET} ${CLOUDY}(${TOK_TOTAL_STR}/${TOK_LIMIT_STR})${RESET}"
fi

LINE1="${CYAN}${I_ROBOT} ${M_NAME}${RESET} ${CLOUDY}| ${YELLOW}${I_FOLDER} ${FOLDER}${RESET}${GIT_STATUS}${TIMER_STR}"
LINE2="$CTX_SECTION"
[ -n "$USAGE_STR" ] && LINE2="${LINE2} ${CLOUDY}| ${USAGE_STR}"
[ -n "$RESET_STR" ] && LINE2="${LINE2} ${CLOUDY}| ${RESET_STR}"

printf "%s\n%s" "$LINE1" "$LINE2"
