#!/usr/bin/env bash
# scripts/eval_all_runtimes.sh
#
# Master evaluation runner for context-engineering-kit v4.0.
# Runs all runtime test suites across all supported agent platforms:
#   1. scripts/check_sync.sh            (Single-source wiring & rules sync)
#   2. scripts/eval_phase_c.sh          (Phase C multi-runtime adapters & guards)
#   3. scripts/eval_mcp.py              (cek-mcp protocol & tool lifecycle)
#   4. scripts/eval_usage_lifecycle.sh  (Token tracking, thresholds & subagents)
#   5. scripts/eval_hooks_smoke.sh      (Hook lifecycle & containment)
#   6. scripts/eval_codex_install.sh    (Codex plugin package & install)
#   7. scripts/eval_antigravity_install.sh (Antigravity plugin package & install)
#   8. scripts/eval_opencode.mjs        (opencode plugin & compaction prompt)
#   9. scripts/eval_doc_drift.py        (runtime claims vs the docs they cite)
#
# Usage: bash scripts/eval_all_runtimes.sh

set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║  CEK v4.0 Universal Runtime Master Test Suite                     ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

suites_total=0
suites_passed=0
suites_failed=0

run_suite() {
  local name="$1" cmd="$2"
  suites_total=$((suites_total + 1))
  echo "────────────────────────────────────────────────────────────────────"
  echo "▶ Running Suite $suites_total: $name"
  echo "  Command: $cmd"
  echo "────────────────────────────────────────────────────────────────────"
  
  local start_time end_time elapsed
  start_time=$(date +%s)
  
  if eval "$cmd"; then
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    echo "  → [PASS] $name (${elapsed}s)"
    suites_passed=$((suites_passed + 1))
  else
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    echo "  → [FAIL] $name (${elapsed}s)"
    suites_failed=$((suites_failed + 1))
  fi
  echo ""
}

# 1. Single-source sync & generator validation
run_suite "check_sync" "bash scripts/check_sync.sh"

# 2. Phase C multi-runtime adapters
run_suite "eval_phase_c" "bash scripts/eval_phase_c.sh"

# 3. MCP protocol and tool lifecycle
run_suite "eval_mcp" "python3 scripts/eval_mcp.py"

# 4. Token usage lifecycle & subagent tracking
run_suite "eval_usage_lifecycle" "bash scripts/eval_usage_lifecycle.sh"

# 5. Core hooks smoke & containment
run_suite "eval_hooks_smoke" "bash scripts/eval_hooks_smoke.sh"

# 6. Codex plugin packaging & install
run_suite "eval_codex_install" "bash scripts/eval_codex_install.sh"

# 7. Antigravity plugin packaging & install
run_suite "eval_antigravity_install" "bash scripts/eval_antigravity_install.sh"

# 8. opencode plugin & compaction injection (if node available)
if command -v node >/dev/null 2>&1; then
  run_suite "eval_opencode" "node --experimental-strip-types scripts/eval_opencode.mjs"
else
  echo "SKIP: eval_opencode (node not found)"
fi

# 9. Runtime capability claims vs the vendor docs they cite (offline fixtures)
run_suite "eval_doc_drift" "python3 scripts/eval_doc_drift.py"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Master Suite Summary: $suites_passed / $suites_total suites passed ($suites_failed failed)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ "$suites_failed" -eq 0 ]
