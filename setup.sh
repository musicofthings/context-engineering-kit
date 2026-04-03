#!/usr/bin/env bash
# setup.sh — context-engineering-kit initial setup
# Run once after cloning the repo on any machine.
#
# Mac/Linux:   bash setup.sh
# Windows:     bash.exe setup.sh   (in Git Bash terminal)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; }
log()  { echo "   $*"; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  context-engineering-kit — Setup                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ── 1. Make hook scripts executable ──────────────────────────────────────────
echo "1. Setting hook permissions..."
if ls "$PROJECT_DIR/.claude/hooks/"*.sh &>/dev/null; then
  chmod +x "$PROJECT_DIR/.claude/hooks/"*.sh
  ok "Hook scripts are executable"
else
  err "No hook scripts found in .claude/hooks/"
fi

# ── 2. Make other scripts executable ─────────────────────────────────────────
echo ""
echo "2. Setting script permissions..."
chmod +x "$PROJECT_DIR/scripts/"*.sh 2>/dev/null || true
ok "scripts/*.sh are executable"

# ── 3. Create session directory and initial state ────────────────────────────
echo ""
echo "3. Initialising session state..."
mkdir -p "$PROJECT_DIR/.claude/session"

STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
if [ ! -f "$STATE_FILE" ]; then
  HOSTNAME_ID=$(hostname 2>/dev/null || echo "unknown-host")
  cat > "$STATE_FILE" <<EOF
{
  "last_updated": "$TIMESTAMP",
  "initialized_by": "$HOSTNAME_ID",
  "active_task": "initial setup",
  "phase": "Phase 0 — Setup",
  "next_action": "run /context-health in Claude Code",
  "compact_count": 0,
  "changed_files": []
}
EOF
  ok "Session state initialised"
else
  ok "Session state already exists"
fi

# ── 4. Check jq is available (required by hooks) ─────────────────────────────
echo ""
echo "4. Checking dependencies..."
if command -v jq &>/dev/null; then
  ok "jq found: $(jq --version)"
else
  warn "jq not found — hooks use jq for JSON parsing"
  log "Install: brew install jq (Mac) | apt install jq (Linux) | scoop install jq (Windows)"
fi

if command -v python3 &>/dev/null; then
  ok "Python3 found: $(python3 --version)"
else
  warn "Python3 not found — session handover scripts require Python 3.8+"
fi

if command -v git &>/dev/null; then
  ok "Git found: $(git --version)"
else
  err "Git not found — session sync requires git"
fi

# ── 5. Check git repo status ─────────────────────────────────────────────────
echo ""
echo "5. Checking git status..."
cd "$PROJECT_DIR"
if git rev-parse --is-inside-work-tree &>/dev/null; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  ok "Git repo on branch: $BRANCH"
else
  warn "Not a git repo — initialising..."
  git init
  git add .
  git commit -m "feat: initial context-engineering-kit setup [$TIMESTAMP]"
  ok "Git repo initialised and committed"
fi

# ── 6. Windows-specific: check claude.cmd ────────────────────────────────────
echo ""
echo "6. Platform check..."
if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
  warn "Windows detected"
  if command -v claude.cmd &>/dev/null; then
    ok "claude.cmd found — use this instead of 'claude'"
  else
    warn "claude.cmd not found — see docs/windows-no-admin.md for install"
  fi
else
  ok "Platform: $OSTYPE"
fi

# ── 7. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo " Setup complete!"
echo "══════════════════════════════════════════════════════"
echo ""
echo " Next steps:"
echo "  1. Start Claude Code: claude  (or claude.cmd on Windows)"
echo "  2. Run: /context-health       — verify all hooks are wired"
echo "  3. Run: /token-status         — confirm monitoring is active"
echo "  4. Run: /handover             — review initial session state"
echo ""
echo " For bioinformatics projects:"
echo "  Copy examples/bioinformatics-ngs/CLAUDE.md into your project"
echo "  and customise the genomics context section."
echo ""
