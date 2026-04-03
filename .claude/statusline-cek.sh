#!/usr/bin/env bash
# ~/.claude/statusline-cek.sh  (or .claude/statusline-cek.sh)
#
# context-engineering-kit statusline — v2.3
# Shows: model | context bar | rate limit | cost | git | lines changed
#
# Install: Add to ~/.claude/settings.json (user) or .claude/settings.json (project):
#   "statusLine": { "type": "command", "command": "~/.claude/statusline-cek.sh" }
#
# Receives JSON from Claude Code via stdin after every assistant message.
# Outputs two lines:
#   Line 1: model | git branch | dir | lines ±
#   Line 2: context bar | rate limit | cost | duration

set -euo pipefail

# ── Read stdin ───────────────────────────────────────────────────────────────
INPUT=$(cat)

# ── Extract all fields ───────────────────────────────────────────────────────
MODEL=$(echo "$INPUT"        | jq -r '.model.display_name        // "unknown"')
CWD=$(echo "$INPUT"          | jq -r '.workspace.current_dir     // .cwd // "?"')
CTX_PCT=$(echo "$INPUT"      | jq -r '.context_window.used_percentage // 0'   | awk '{printf "%.0f", $1}')
CTX_REM=$(echo "$INPUT"      | jq -r '.context_window.remaining_percentage // 100' | awk '{printf "%.0f", $1}')
CTX_SIZE=$(echo "$INPUT"     | jq -r '.context_window.context_window_size // 200000')
COST=$(echo "$INPUT"         | jq -r '.cost.total_cost_usd       // 0'        | awk '{printf "%.4f", $1}')
DUR_MS=$(echo "$INPUT"       | jq -r '.cost.total_duration_ms    // 0'        | awk '{printf "%.0f", $1}')
LINES_ADD=$(echo "$INPUT"    | jq -r '.cost.total_lines_added    // 0')
LINES_DEL=$(echo "$INPUT"    | jq -r '.cost.total_lines_removed  // 0')

# Rate limit fields — the real subscription window data
RL_5H_PCT=$(echo "$INPUT"    | jq -r '.rate_limits.five_hour.used_percentage  // "?"')
RL_7D_PCT=$(echo "$INPUT"    | jq -r '.rate_limits.seven_day.used_percentage  // "?"')
RL_5H_RESET=$(echo "$INPUT"  | jq -r '.rate_limits.five_hour.resets_at        // 0')

# ── Compute derived values ───────────────────────────────────────────────────
DIR="${CWD##*/}"                          # last path component only

# Duration: convert ms to human-readable
DUR_S=$(( DUR_MS / 1000 ))
if   (( DUR_S < 60  )); then DUR_STR="${DUR_S}s"
elif (( DUR_S < 3600 )); then DUR_STR="$(( DUR_S / 60 ))m$(( DUR_S % 60 ))s"
else DUR_STR="$(( DUR_S / 3600 ))h$(( (DUR_S % 3600) / 60 ))m"
fi

# Rate limit reset: time remaining until 5h window resets
RL_RESET_STR=""
if [[ "$RL_5H_RESET" != "0" && "$RL_5H_RESET" != "null" && "$RL_5H_RESET" != "?" ]]; then
  NOW_EPOCH=$(date +%s)
  SECS_LEFT=$(( RL_5H_RESET - NOW_EPOCH ))
  if (( SECS_LEFT > 0 )); then
    MINS_LEFT=$(( SECS_LEFT / 60 ))
    if (( MINS_LEFT < 60 )); then
      RL_RESET_STR=" (resets ${MINS_LEFT}m)"
    else
      RL_RESET_STR=" (resets $(( MINS_LEFT / 60 ))h$(( MINS_LEFT % 60 ))m)"
    fi
  else
    RL_RESET_STR=" (window fresh)"
  fi
fi

# ── Git info ─────────────────────────────────────────────────────────────────
GIT_BRANCH=""
GIT_DIRTY=""
if git -C "$CWD" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  DIRTY_COUNT=$(git -C "$CWD" status --short 2>/dev/null | wc -l | tr -d ' ')
  if (( DIRTY_COUNT > 0 )); then
    GIT_DIRTY="*${DIRTY_COUNT}"
  fi
fi

# ── ANSI colours ─────────────────────────────────────────────────────────────
# Context window colour
CTX_NUM=${CTX_PCT//[^0-9]/}
CTX_NUM=${CTX_NUM:-0}
if   (( CTX_NUM >= 85 )); then CTX_COLOUR="\033[31m"   # red
elif (( CTX_NUM >= 70 )); then CTX_COLOUR="\033[33m"   # amber
elif (( CTX_NUM >= 50 )); then CTX_COLOUR="\033[36m"   # cyan
else                           CTX_COLOUR="\033[32m"   # green
fi

# Rate limit colour
RL_NUM=$(echo "$RL_5H_PCT" | grep -oE '[0-9]+' | head -1 || echo "0")
RL_NUM=${RL_NUM:-0}
if   (( RL_NUM >= 90 )); then RL_COLOUR="\033[31m"
elif (( RL_NUM >= 70 )); then RL_COLOUR="\033[33m"
else                          RL_COLOUR="\033[32m"
fi

RESET="\033[0m"
DIM="\033[2m"
BOLD="\033[1m"
CYAN="\033[36m"
YELLOW="\033[33m"
GREEN="\033[32m"

# ── Context progress bar (20 chars) ──────────────────────────────────────────
BAR_WIDTH=20
FILLED=$(( (CTX_NUM * BAR_WIDTH) / 100 ))
FILLED=$(( FILLED > BAR_WIDTH ? BAR_WIDTH : FILLED ))
EMPTY=$(( BAR_WIDTH - FILLED ))
BAR_FILLED=$(printf '%0.s█' $(seq 1 $FILLED 2>/dev/null) || printf '%*s' $FILLED '' | tr ' ' '█')
BAR_EMPTY=$(printf '%0.s░' $(seq 1 $EMPTY 2>/dev/null) || printf '%*s' $EMPTY '' | tr ' ' '░')
CTX_BAR="${BAR_FILLED}${BAR_EMPTY}"

# ── Context size label (200K / 1M) ──────────────────────────────────────────
if (( CTX_SIZE >= 900000 )); then CTX_LABEL="1M"
else                               CTX_LABEL="200K"
fi

# ── Lines changed ─────────────────────────────────────────────────────────────
if (( LINES_ADD > 0 || LINES_DEL > 0 )); then
  LINES_STR="${GREEN}+${LINES_ADD}${RESET}/${DIM}-${LINES_DEL}${RESET}"
else
  LINES_STR="${DIM}no changes${RESET}"
fi

# ── Output: Line 1 — session info ────────────────────────────────────────────
LINE1=""
LINE1+="${BOLD}${CYAN}${MODEL}${RESET}"
if [[ -n "$GIT_BRANCH" ]]; then
  LINE1+="  ${DIM}⎇${RESET} ${YELLOW}${GIT_BRANCH}${GIT_DIRTY}${RESET}"
fi
LINE1+="  ${DIM}📁${RESET} ${DIR}"
LINE1+="  ${LINES_STR}"

# ── Output: Line 2 — context + rate limit + cost ─────────────────────────────
LINE2=""
LINE2+="${CTX_COLOUR}${CTX_BAR}${RESET}"
LINE2+=" ${CTX_COLOUR}${CTX_PCT}%${RESET}${DIM}/${CTX_LABEL}${RESET}"

# Rate limit (5h window)
if [[ "$RL_5H_PCT" != "?" && "$RL_5H_PCT" != "null" ]]; then
  LINE2+="  ${DIM}5h:${RESET}${RL_COLOUR}${RL_5H_PCT}%${RESET}${DIM}${RL_RESET_STR}${RESET}"
fi

# 7-day rate limit if available
if [[ "$RL_7D_PCT" != "?" && "$RL_7D_PCT" != "null" && "$RL_7D_PCT" != "0" ]]; then
  LINE2+="  ${DIM}7d:${RESET}${RL_7D_PCT}%"
fi

LINE2+="  ${DIM}\$${COST}${RESET}"
LINE2+="  ${DIM}⏱${DUR_STR}${RESET}"

# ── Print ─────────────────────────────────────────────────────────────────────
echo -e "$LINE1"
echo -e "$LINE2"
