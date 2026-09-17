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

# 11) Grok speaks camelCase. Verified against docs.x.ai/build/features/hooks on
# 2026-09-13: the payload is hookEventName / sessionId / toolName / toolInput,
# while the shared core reads the Claude snake_case names. Without the adapter's
# normalisation, guard-dangerous.sh cannot see the command it inspects — so the
# only blocking event Grok has was inert.
GROK_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/cek-phasec-grok.XXXXXX")
git -C "$GROK_SANDBOX" init -q .
git -C "$GROK_SANDBOX" config user.email eval@test
git -C "$GROK_SANDBOX" config user.name eval
printf '# x\n' > "$GROK_SANDBOX/CLAUDE.md"
git -C "$GROK_SANDBOX" add -A >/dev/null 2>&1
git -C "$GROK_SANDBOX" commit -qm init >/dev/null 2>&1

GROK_DANGER=$(python3 -c "
import json
print(json.dumps({'hookEventName':'PreToolUse','sessionId':'g1','toolName':'Bash',
 'toolInput':{'command':'rm'+' -'+'rf'+' '+'/'}}))" 2>/dev/null)
GROK_RC=0
printf '%s' "$GROK_DANGER" | env CLAUDE_PROJECT_DIR="$GROK_SANDBOX" CLAUDE_PLUGIN_ROOT="$PWD" \
  GROK_SESSION_ID=g1 bash .grok/hooks/run.sh hook guard-dangerous.sh >/dev/null 2>&1 || GROK_RC=$?
if [ "$GROK_RC" -eq 2 ]; then
  pass "grok camelCase payload reaches the guard (denies with exit 2)"
else
  fail "grok camelCase payload denied — adapter normalisation missing?"
fi

GROK_RC=0
printf '%s' '{"hookEventName":"PreToolUse","sessionId":"g1","toolName":"Bash","toolInput":{"command":"ls -la"}}' \
  | env CLAUDE_PROJECT_DIR="$GROK_SANDBOX" CLAUDE_PLUGIN_ROOT="$PWD" GROK_SESSION_ID=g1 \
    bash .grok/hooks/run.sh hook guard-dangerous.sh >/dev/null 2>&1 || GROK_RC=$?
if [ "$GROK_RC" -eq 0 ]; then
  pass "grok safe command allowed"
else
  fail "grok safe command should exit 0"
fi
rm -rf "$GROK_SANDBOX"

# 12) Grok's documented schema is matcher/type/command/url/timeout — no async.
if grep -q '"async"' .grok/hooks/cek-hooks.json; then
  fail "grok config emits \"async\", which is not in Grok's documented schema"
else
  pass "grok config emits no undocumented async key"
fi

# 13) Grok reads .cursor/hooks.json too — "including Cursor's camelCase event
# names" (docs.x.ai/build/features/hooks, verified 2026-09-17). The repo used to
# claim the opposite, so a Grok session ran cek-hooks.json AND all eleven Cursor
# adapters: two session-start chains, two stop chains, two snapshot commits.
# Every Cursor adapter must defer when GROK_* is in the environment.
DF_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/cek-df.XXXXXX")
git -C "$DF_SANDBOX" init -q
DF_MISS=""
for f in .cursor/hooks/*.sh; do
  b=$(basename "$f")
  [ "$b" = "_common.sh" ] && continue
  out=$(printf '%s' '{"hookEventName":"sessionStart","session_id":"g1"}' \
        | env GROK_SESSION_ID=g1 CLAUDE_PROJECT_DIR="$DF_SANDBOX" \
          CLAUDE_PLUGIN_ROOT="$PWD" bash "$f" SubagentStart 2>&1)
  case "$out" in *"deferring to .grok"*) ;; *) DF_MISS="$DF_MISS $b" ;; esac
done
if [ -z "$DF_MISS" ]; then
  pass "cursor adapters defer to cek-hooks.json under a Grok session"
else
  fail "cursor adapters double-fire on Grok:$DF_MISS"
fi

# ...and still run normally when Grok is not the runtime.
printf '%s' '{"hookEventName":"sessionStart","session_id":"c1"}' \
  | env CLAUDE_PROJECT_DIR="$DF_SANDBOX" CLAUDE_PLUGIN_ROOT="$PWD" \
    bash .cursor/hooks/on-session-start.sh >/dev/null 2>&1
if [ -d "$DF_SANDBOX/.claude/session" ]; then
  pass "cursor adapters still run under Cursor"
else
  fail "cursor adapters no longer run under Cursor (guard too broad)"
fi
rm -rf "$DF_SANDBOX"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ "$FAIL" -eq 0 ]
