#!/usr/bin/env bash
# scripts/eval_antigravity_install.sh
#
# Exercise an Antigravity plugin/workspace install end to end:
#   1. Package with package_plugin.py --runtime antigravity
#   2. Unpack into an external plugin directory
#   3. Verify required files are packaged (.agents/hooks/run.sh, .agents/hooks.json, etc.)
#   4. Execute hooks from an unrelated working directory and nested subdirectory
#   5. Verify PreToolUse dangerous command denial and safe command allowance (JSON contracts)
#   6. Verify PreInvocation banner synthesis
#   7. Verify Stop handler cleanly returns {}
#   8. Verify state isolation: all state written into host project, not plugin root
#
# Usage: bash scripts/eval_antigravity_install.sh

set -uo pipefail

KIT="${KIT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cek-antigravity-install.XXXXXX")
PLUGIN_ROOT="$WORK/plugins/context-engineering-kit"
PROJECT="$WORK/someones-project"

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s — %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
head_() { printf '\n▶ %s\n' "$1"; }

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Antigravity plugin install evals                        ║"
echo "╚══════════════════════════════════════════════════════════╝"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

# ── 1. Package and install ───────────────────────────────────────────────────
head_ "Package and install"
PYTHON="${PYTHON:-python3}"
if ! "$PYTHON" "$KIT/scripts/package_plugin.py" --runtime antigravity --out "$WORK/plugin.zip" >"$WORK/pack.log" 2>&1; then
  bad "package_plugin.py builds antigravity bundle" "$(tail -3 "$WORK/pack.log")"
  echo "Results: $pass passed, $((fail+1)) failed"; exit 1
fi
ok "package_plugin.py builds antigravity bundle"

mkdir -p "$PLUGIN_ROOT"
"$PYTHON" -c "
import zipfile, sys
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
" "$WORK/plugin.zip" "$PLUGIN_ROOT" || { bad "unpack" "extract failed"; exit 1; }
ok "package unpacks to an antigravity plugin root"

for f in .agents/hooks/run.sh .agents/hooks.json scripts/cek_runtime.sh \
         .claude/hooks/guard-dangerous.sh skills/handover/SKILL.md; do
  [ -f "$PLUGIN_ROOT/$f" ] && ok "packaged: $f" || bad "packaged: $f" "missing from the zip"
done

# Ensure hook runner is executable
chmod +x "$PLUGIN_ROOT/.agents/hooks/run.sh" "$PLUGIN_ROOT/.claude/hooks/"*.sh "$PLUGIN_ROOT/scripts/"*.sh

# ── 2. Sandbox project setup ─────────────────────────────────────────────────
head_ "Sandbox project setup"
mkdir -p "$PROJECT/nested/sub/dir"
(
  cd "$PROJECT"
  git init -q
  git config user.name "Eval User"
  git config user.email "eval@example.com"
  echo "# Test Project" > README.md
  git add README.md
  git commit -q -m "initial commit"
)
ok "created test git project with nested subdirectory"

# ── 3. Hook execution from nested cwd ────────────────────────────────────────
head_ "Hook execution from nested cwd via CLAUDE_PLUGIN_ROOT"

# Test 3a: PreToolUse blocks dangerous command
DANGEROUS_PAYLOAD=$("$PYTHON" -c "
import json
print(json.dumps({
  'conversationId': 'eval-conv-installed',
  'workspacePaths': ['$PROJECT'],
  'toolCall': {
    'name': 'run_command',
    'args': {'CommandLine': 'rm -rf /'}
  }
}))")

DENY_OUT=$(printf '%s' "$DANGEROUS_PAYLOAD" | (
  cd "$PROJECT/nested/sub/dir"
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/.agents/hooks/run.sh" hook guard-dangerous.sh 2>/dev/null
))

if echo "$DENY_OUT" | grep -q '"decision": "deny"'; then
  ok "installed hook blocks destructive command (JSON deny)"
else
  bad "installed hook failed to block destructive command" "output: $DENY_OUT"
fi

# Test 3b: PreToolUse allows safe command
SAFE_PAYLOAD=$("$PYTHON" -c "
import json
print(json.dumps({
  'conversationId': 'eval-conv-installed',
  'workspacePaths': ['$PROJECT'],
  'toolCall': {
    'name': 'run_command',
    'args': {'CommandLine': 'git status'}
  }
}))")

ALLOW_OUT=$(printf '%s' "$SAFE_PAYLOAD" | (
  cd "$PROJECT/nested/sub/dir"
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/.agents/hooks/run.sh" hook guard-dangerous.sh 2>/dev/null
))

if echo "$ALLOW_OUT" | grep -q '"decision": "allow"'; then
  ok "installed hook allows safe command (JSON allow)"
else
  bad "installed hook failed to allow safe command" "output: $ALLOW_OUT"
fi

# Test 3c: PreInvocation synthesizes banner on invocationNum == 0
INV0_PAYLOAD=$("$PYTHON" -c "
import json
print(json.dumps({
  'conversationId': 'eval-conv-installed',
  'invocationNum': 0,
  'workspacePaths': ['$PROJECT']
}))")

INV_OUT=$(printf '%s' "$INV0_PAYLOAD" | (
  cd "$PROJECT/nested/sub/dir"
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/.agents/hooks/run.sh" pre-invocation 2>/dev/null
))

if echo "$INV_OUT" | grep -q '"ephemeralMessage"'; then
  ok "PreInvocation synthesizes session banner via injectSteps"
else
  bad "PreInvocation banner synthesis failed" "output: $INV_OUT"
fi

# Test 3d: Stop cleanly returns {}
STOP_OUT=$(printf '%s' "$INV0_PAYLOAD" | (
  cd "$PROJECT/nested/sub/dir"
  env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/.agents/hooks/run.sh" stop 2>/dev/null
))

if [ "$STOP_OUT" = "{}" ]; then
  ok "Stop handler returns empty JSON"
else
  bad "Stop handler failed to return {}" "output: $STOP_OUT"
fi

# ── 4. State boundary isolation ──────────────────────────────────────────────
head_ "State boundary isolation"

if [ -d "$PROJECT/.claude/session" ]; then
  ok "state written into host project (.claude/session)"
else
  bad "state not found in host project"
fi

if [ ! -d "$PLUGIN_ROOT/.claude/session" ] && [ ! -d "$PLUGIN_ROOT/.agents/session" ]; then
  ok "zero state leaked into plugin installation root"
else
  bad "state leaked into plugin root directory"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $pass passed, $fail failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ "$fail" -eq 0 ]
