#!/usr/bin/env bash
# scripts/check_sync.sh
#
# Verifies single-source hook/skill wiring and Phase C portable runtime wiring.
#
#   skills/ and agents/ are the ONLY copies (.claude/ duplicates must not return)
#   .claude/settings.json declares NO hooks (hooks/hooks.json is the single source)
#   generate_runtime_hooks.py --check         (Codex/Grok hooks.json)
#   no absolute machine paths in runtime JSON
#
# Usage: bash scripts/check_sync.sh

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PROJECT_DIR"

status=0

if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  PY=""
fi

# v3.0.0: skills/ and agents/ register once via the plugin manifest. The old
# .claude/ mirror trees registered a second time (18 skill descriptions in
# context instead of 9; project agents shadowed plugin agents) and were removed.
# Fail if either duplicate tree is reintroduced.
for dup in ".claude/skills" ".claude/agents"; do
  if [ -d "$dup" ]; then
    echo "ERROR: $dup exists — duplicate of the root tree; it registers twice. Delete it."
    status=1
  else
    echo "OK: no duplicate $dup"
  fi
done

# Phase C: regenerated runtime hook configs
if [ -f scripts/generate_runtime_hooks.py ]; then
  if [ -n "$PY" ]; then
    if ! "$PY" scripts/generate_runtime_hooks.py --check; then
      echo "DRIFT: run  python scripts/generate_runtime_hooks.py  to regenerate .codex/.grok hooks"
      status=1
    fi
  else
    echo "SKIP: generate_runtime_hooks.py (no python)"
  fi
fi

# v3.0.0: hooks/hooks.json (auto-discovered plugin manifest) is the SINGLE hook
# source. The repo's .claude/settings.json used to declare the same 16 events a
# second time and Claude Code does not dedupe across plugin/project scope —
# SessionStart ran 10 handlers, Stop ran usage-tracker.py twice per turn.
# Fail if a hooks block creeps back into settings.json.
if [ -f .claude/settings.json ] && [ -n "${PY:-}" ]; then
  if "$PY" -c 'import json,sys; sys.exit(0 if "hooks" in json.load(open(".claude/settings.json")) else 1)'; then
    echo "ERROR: .claude/settings.json declares hooks — hooks/hooks.json is the single source (v3.0.0)"
    status=1
  else
    echo "OK: .claude/settings.json has no hooks block (hooks/hooks.json is the single source)"
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
  echo "OK: single-source wiring + runtime configs are in sync"
fi
exit "$status"
