#!/usr/bin/env bash
# .claude/hooks/post-compact.sh
# PostCompact hook — fires after a compact operation completes.
#
# PostCompact stdout is NOT injected into the model's context (only
# UserPromptSubmit, UserPromptExpansion and SessionStart inject stdout) —
# re-injection is handled by compact-restore.sh on SessionStart[compact].
# What PostCompact uniquely receives is the `compact_summary` field: the
# actual summary the compactor generated. This hook archives it so the
# summary of every compaction survives on disk, and records compaction
# metadata in state.json.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# shellcheck source=../../scripts/resolve_state_dir.sh
source "${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}/scripts/resolve_state_dir.sh"

log() { echo "[post-compact] $*" >&2; }

HOOK_INPUT=""
if [ ! -t 0 ]; then HOOK_INPUT=$(cat 2>/dev/null || true); fi
TRIGGER=$(printf '%s' "$HOOK_INPUT" | jq -r '.trigger // "unknown"' 2>/dev/null || echo "unknown")
SUMMARY=$(printf '%s' "$HOOK_INPUT" | jq -r '.compact_summary // ""' 2>/dev/null || echo "")

COMPACT_COUNT=$(jq -r '.compact_count // 0' "$STATE_FILE" 2>/dev/null || echo 0)

# ── Archive the compactor's summary ──────────────────────────────────────────
# /compact-smart and post-mortems can compare what the summary kept against
# what the handover recorded — the delta is what compaction lost.
HISTORY_DIR="$STATE_DIR/compact-history"
if [ -n "$SUMMARY" ]; then
  mkdir -p "$HISTORY_DIR"
  ARCHIVE="$HISTORY_DIR/compact-${COMPACT_COUNT}-$(date -u +%Y%m%dT%H%M%SZ).md"
  {
    echo "# Compaction summary archive"
    echo "_Compaction #$COMPACT_COUNT • trigger: $TRIGGER • ${TIMESTAMP}_"
    echo ""
    printf '%s\n' "$SUMMARY"
  } > "$ARCHIVE" 2>/dev/null && log "Summary archived to $ARCHIVE" \
    || log "WARNING: could not archive summary"
else
  log "No compact_summary in hook input (trigger=$TRIGGER)"
fi

state_write \
  '.last_compact_at = $ts | .last_compact_trigger = $trig' \
  --arg ts "$TIMESTAMP" --arg trig "$TRIGGER" || true

log "Post-compact archival complete (trigger=$TRIGGER)"
exit 0
