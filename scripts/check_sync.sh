#!/usr/bin/env bash
# scripts/check_sync.sh
#
# Verifies duplicated trees and Phase C portable runtime wiring stay consistent.
#
#   skills/            + .claude/skills/
#   agents/            + .claude/subagents/   (when both exist)
#   generate_runtime_hooks.py --check         (Codex/Grok hooks.json)
#   no absolute machine paths in runtime JSON
#
# Usage: bash scripts/check_sync.sh

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PROJECT_DIR"

status=0

check_pair() {
  local a="$1" b="$2"
  if [ ! -d "$a" ] || [ ! -d "$b" ]; then
    echo "SKIP: $a or $b missing"
    return 0
  fi
  if ! diff -rq "$a" "$b"; then
    echo "DRIFT: $a and $b differ (see above). Copy the newer tree over the older one."
    status=1
  fi
}

check_pair "skills" ".claude/skills"
check_pair "agents" ".claude/subagents"

# Phase C: regenerated runtime hook configs
if [ -f scripts/generate_runtime_hooks.py ]; then
  if command -v python3 >/dev/null 2>&1; then
    PY=python3
  elif command -v python >/dev/null 2>&1; then
    PY=python
  else
    PY=""
  fi
  if [ -n "$PY" ]; then
    if ! "$PY" scripts/generate_runtime_hooks.py --check; then
      echo "DRIFT: run  python scripts/generate_runtime_hooks.py  to regenerate .codex/.grok hooks"
      status=1
    fi
  else
    echo "SKIP: generate_runtime_hooks.py (no python)"
  fi
fi

# Absolute path smell test on tracked runtime entrypoints
for f in .codex/hooks.json .grok/hooks/cek-hooks.json .cursor/hooks.json; do
  if [ -f "$f" ]; then
    if grep -E 'C:\\\\Users|/Users/[A-Za-z]|C:/Users' "$f" >/dev/null 2>&1; then
      echo "ERROR: absolute machine path in $f"
      status=1
    else
      echo "OK: no absolute paths in $f"
    fi
  fi
done

# Required adapter entrypoints
for f in scripts/cek_runtime.sh .codex/hooks/run.sh .grok/hooks/run.sh .cursor/hooks/_common.sh \
         docs/runtime-capability-matrix.md; do
  if [ -f "$f" ]; then
    echo "OK: $f"
  else
    echo "MISSING: $f"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "OK: duplicated trees + runtime wiring are in sync"
fi
exit "$status"
