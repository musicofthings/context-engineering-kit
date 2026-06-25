#!/usr/bin/env bash
# .claude/hooks/instructions-loaded.sh
# InstructionsLoaded hook — fires when CLAUDE.md or .claude/rules/*.md is loaded.
#
# Why this matters for prompt caching:
# Claude Code sends CLAUDE.md content as part of the system prompt. The Anthropic
# API caches the prefix of the system prompt automatically. To maximise cache hits:
#   1. Keep the top of CLAUDE.md stable (project description, rules, structure).
#   2. Put dynamic content (active task, last commit) at the BOTTOM.
#   3. Avoid prepending timestamps or dynamic banners at the top.
#
# This hook logs every instruction load so you can see cache reload patterns
# in .claude/session/instructions-loaded.jsonl and tune your CLAUDE.md layout.
# load_reason values: session_start, nested_traversal, path_glob_match, include, compact
#
# On "compact" loads: CLAUDE.md is re-injected after compaction. If the file
# changed since the last load the cache prefix breaks and Anthropic re-processes
# the full prompt. Keeping the stable prefix truly stable avoids this cost.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

INPUT=$(cat 2>/dev/null || true)

FILE_PATH=$(printf '%s' "$INPUT"   | jq -r '.file_path   // ""' 2>/dev/null || echo "")
LOAD_REASON=$(printf '%s' "$INPUT" | jq -r '.load_reason // "unknown"' 2>/dev/null || echo "unknown")

# Append to load log (lightweight — one line per load)
LOAD_LOG="$STATE_DIR/instructions-loaded.jsonl"
jq -n \
  --arg ts "$TIMESTAMP" \
  --arg path "$FILE_PATH" \
  --arg reason "$LOAD_REASON" \
  '{"ts":$ts,"file":$path,"reason":$reason}' \
  >> "$LOAD_LOG" 2>/dev/null || true

# On compact reload: increment a counter so the health-check skill can warn
# if CLAUDE.md is being reloaded too often (sign of unstable prefix)
if [ "$LOAD_REASON" = "compact" ]; then
  state_write \
    '.instructions_compact_reloads = ((.instructions_compact_reloads // 0) + 1)' \
    >/dev/null 2>&1 || true
fi

exit 0
