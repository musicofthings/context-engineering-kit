#!/usr/bin/env bash
# .claude/statusline.sh
# context-engineering-kit statusline — pure bash + jq
# Works on Windows (Git Bash), macOS, and Linux.
# Claude Code pipes JSON via stdin after every assistant response.

input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
CTX=$(echo "$input"  | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DMS=$(echo "$input"  | jq -r '.cost.total_duration_ms // 0' | cut -d. -f1)
LADD=$(echo "$input" | jq -r '.cost.total_lines_added // 0' | cut -d. -f1)
LDEL=$(echo "$input" | jq -r '.cost.total_lines_removed // 0' | cut -d. -f1)
RL5=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage // empty' | cut -d. -f1)
RL7=$(echo "$input"  | jq -r '.rate_limits.seven_day.used_percentage // empty' | cut -d. -f1)
RST=$(echo "$input"  | jq -r '.rate_limits.five_hour.resets_at // 0' | cut -d. -f1)
DIR=$(echo "$input"  | jq -r '.workspace.current_dir // "."')
DIR="${DIR##*/}"

# Duration
DUR_S=$(( DMS / 1000 ))
if   (( DUR_S < 60   )); then DUR="${DUR_S}s"
elif (( DUR_S < 3600 )); then DUR="$(( DUR_S/60 ))m$(( DUR_S%60 ))s"
else                          DUR="$(( DUR_S/3600 ))h$(( (DUR_S%3600)/60 ))m"
fi

# Context bar (20 chars)
FILLED=$(( CTX * 20 / 100 ))
(( FILLED > 20 )) && FILLED=20
EMPTY=$(( 20 - FILLED ))
printf -v BAR "%${FILLED}s" && BAR="${BAR// /█}"
printf -v PAD "%${EMPTY}s"  && BAR="${BAR}${PAD// /░}"

# Status icon
if   (( CTX >= 85 )); then ICON="🔴"
elif (( CTX >= 70 )); then ICON="🟠"
elif (( CTX >= 50 )); then ICON="🟡"
else                       ICON="🟢"
fi

# Rate limit reset time
RST_STR=""
if [[ -n "$RST" && "$RST" != "0" ]]; then
  NOW=$(date +%s)
  LEFT=$(( RST - NOW ))
  if (( LEFT > 0 )); then
    ML=$(( LEFT / 60 ))
    if (( ML < 60 )); then RST_STR=" rst:${ML}m"
    else RST_STR=" rst:$(( ML/60 ))h$(( ML%60 ))m"
    fi
  fi
fi

# Git branch
BRANCH=""
PROJ=$(echo "$input" | jq -r '.workspace.project_dir // "."')
if git -C "$PROJ" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  BRANCH=$(git -C "$PROJ" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  DC=$(git -C "$PROJ" status --short 2>/dev/null | wc -l | tr -d ' ')
  (( DC > 0 )) && BRANCH="${BRANCH}*${DC}"
fi

# Cost string
COST_STR=$(printf '$%.4f' "$COST")

# Line 1: model | branch | dir | lines changed
LN1="[${MODEL}]"
[[ -n "$BRANCH" ]] && LN1+="  ⎇ ${BRANCH}"
LN1+="  📁 ${DIR}"
(( LADD > 0 || LDEL > 0 )) && LN1+="  +${LADD}/-${LDEL}"

# Line 2: context bar | rate limits | cost | duration
LN2="${ICON} ${BAR} ${CTX}%/200K"
[[ -n "$RL5" ]] && LN2+="  5h:${RL5}%${RST_STR}"
[[ -n "$RL7" ]] && LN2+="  7d:${RL7}%"
LN2+="  ${COST_STR}  ⏱${DUR}"

echo "$LN1"
echo "$LN2"
