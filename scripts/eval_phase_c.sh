#!/usr/bin/env bash
# scripts/eval_phase_c.sh — hypothetical multi-runtime wiring checks (Phase C)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck source=find_python.sh
source "$ROOT/scripts/find_python.sh"

PASS=0
FAIL=0
pass() { echo "  PASS  $*"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

echo "╔════════════════════════════════════════╗"
echo "║  Phase C runtime wiring evals          ║"
echo "╚════════════════════════════════════════╝"

# 1) Generator check
if "$PYTHON" scripts/generate_runtime_hooks.py --check >/dev/null 2>&1; then
  pass "generate_runtime_hooks --check clean"
else
  fail "generate_runtime_hooks --check drift"
fi

# 2) No absolute paths
for f in .codex/hooks.json .grok/hooks/cek-hooks.json; do
  if grep -E 'C:\\\\Users|C:/Users|/Users/[A-Za-z0-9]' "$f" >/dev/null 2>&1; then
    fail "absolute path in $f"
  else
    pass "portable paths in $f"
  fi
done

# 3) Codex event coverage (must include SessionEnd, Stop chain, Subagent*)
for evt in SessionStart SessionEnd UserPromptSubmit PreToolUse Stop SubagentStart SubagentStop PreCompact; do
  if grep -q "\"$evt\"" .codex/hooks.json; then
    pass "codex has $evt"
  else
    fail "codex missing $evt"
  fi
done

# 4) Grok must NOT wire PermissionRequest; MUST wire PermissionDenied
if grep -q "PermissionRequest" .grok/hooks/cek-hooks.json; then
  fail "grok must not wire PermissionRequest"
else
  pass "grok omits PermissionRequest"
fi
if grep -q "PermissionDenied" .grok/hooks/cek-hooks.json && grep -q "permission-denied.sh" .grok/hooks/cek-hooks.json; then
  pass "grok wires PermissionDenied"
else
  fail "grok missing PermissionDenied → permission-denied.sh"
fi
if [ -f .claude/hooks/permission-denied.sh ]; then
  pass "permission-denied.sh present"
else
  fail "missing .claude/hooks/permission-denied.sh"
fi

# 5) Grok has PermissionDenied gap documented — still has Stop/Subagent
for evt in SessionStart SessionEnd UserPromptSubmit Stop SubagentStart SubagentStop; do
  if grep -q "\"$evt\"" .grok/hooks/cek-hooks.json; then
    pass "grok has $evt"
  else
    fail "grok missing $evt"
  fi
done

# 6) run.sh dispatch works (session-start no-ops safely without full state)
export CLAUDE_PROJECT_DIR="$ROOT" CLAUDE_PLUGIN_ROOT="$ROOT"
if bash .codex/hooks/run.sh hook notify.sh </dev/null >/dev/null 2>&1; then
  pass "codex run.sh hook dispatch"
else
  fail "codex run.sh hook dispatch"
fi
if bash .grok/hooks/run.sh hook notify.sh </dev/null >/dev/null 2>&1; then
  pass "grok run.sh hook dispatch"
else
  fail "grok run.sh hook dispatch"
fi

# 7) cek_runtime_supports matrix
# shellcheck source=cek_runtime.sh
source "$ROOT/scripts/cek_runtime.sh"
export CEK_RUNTIME=grok
if cek_runtime_supports PermissionRequest; then
  fail "grok should not support PermissionRequest"
else
  pass "cek_runtime_supports PermissionRequest=false on grok"
fi
export CEK_RUNTIME=claude
if cek_runtime_supports PermissionRequest; then
  pass "claude supports PermissionRequest"
else
  fail "claude should support PermissionRequest"
fi
export CEK_RUNTIME=cursor
if cek_runtime_supports UserPromptSubmit; then
  pass "cursor supports UserPromptSubmit"
else
  fail "cursor should support UserPromptSubmit"
fi

# 8) check_sync
if bash scripts/check_sync.sh >/dev/null 2>&1; then
  pass "check_sync.sh overall"
else
  # skills/subagents drift may fail independently — still report
  if bash scripts/check_sync.sh 2>&1 | grep -q "runtime wiring"; then
    fail "check_sync runtime wiring"
  else
    pass "check_sync runtime portion (other drift may exist)"
  fi
fi

# 9) CLAUDE_PROJECT_DIR fallback in settings
if grep -q '\${CLAUDE_PROJECT_DIR:-.}' .claude/settings.json; then
  pass "settings.json portable PROJECT_DIR fallback"
else
  fail "settings.json missing \${CLAUDE_PROJECT_DIR:-.} fallback"
fi

# 10) capability matrix doc
if [ -f docs/runtime-capability-matrix.md ]; then
  pass "capability matrix doc present"
else
  fail "missing docs/runtime-capability-matrix.md"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ "$FAIL" -eq 0 ]
