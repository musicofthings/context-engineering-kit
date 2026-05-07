#!/usr/bin/env bash
# .claude/hooks/morning-brief-auto.sh
#
# SessionStart hook — fires once per calendar day (UTC).
# Silently generates the morning brief if today's file doesn't exist yet,
# then injects a one-line notice so Claude can inform the user.
# Does nothing if the brief for today already exists.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
BRIEFS_DIR="$PROJECT_DIR/briefs"
TODAY=$(date -u +"%Y-%m-%d")
BRIEF_FILE="$BRIEFS_DIR/${TODAY}.md"
CONFIG_FILE="$PROJECT_DIR/config/morning_brief.json"

# Skip if config doesn't exist — morning-brief not configured for this project
[ -f "$CONFIG_FILE" ] || exit 0

# Skip if today's brief already exists — already generated this session/day
[ -f "$BRIEF_FILE" ] && exit 0

# Check feedparser is available; skip silently if not installed
python3 -c "import feedparser" 2>/dev/null || {
  echo "[morning-brief] feedparser not installed — run: pip install feedparser" >&2
  exit 0
}

# Generate the brief quietly (file only, no terminal output during hook)
mkdir -p "$BRIEFS_DIR"
python3 "$PROJECT_DIR/scripts/morning_brief.py" --quiet 2>/dev/null || {
  echo "[morning-brief] Brief generation failed — run /morning-brief manually" >&2
  exit 0
}

# Brief generated — inject a single notice line into Claude's context
echo ""
echo "📰 Today's morning brief is ready (${TODAY}). Type /morning-brief to read it."
echo ""
