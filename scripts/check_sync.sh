#!/usr/bin/env bash
# scripts/check_sync.sh
#
# Verifies duplicated trees and Phase C portable runtime wiring stay consistent.
#
#   skills/            + .claude/skills/
#   agents/            + .claude/agents/      (when both exist)
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
check_pair "agents" ".claude/agents"

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

# Claude Code hook wiring parity: hooks/hooks.json (what INSTALLED plugin users
# get) vs .claude/settings.json (what this repo runs on itself). These are two
# hand-maintained copies of the same wiring and nothing was comparing them —
# session-title.sh sat in settings.json for a full release without ever being
# added to the plugin manifest, so it silently never ran for anyone who
# installed the kit. Plugin-only bootstrap entries are allowlisted below.
if [ -f hooks/hooks.json ] && [ -f .claude/settings.json ] && [ -n "${PY:-}" ]; then
  if ! "$PY" - <<'PARITY'
import json, sys

PLUGIN_ONLY = {"auto_init_project.sh", "chmod"}   # bootstrap, plugin mode only

def by_event(path):
    hooks = json.load(open(path)).get("hooks", {})
    out = {}
    for ev, matchers in hooks.items():
        names = []
        for m in matchers:
            for h in m.get("hooks", []):
                cmd = h.get("command", "")
                if cmd.startswith("chmod"):
                    names.append("chmod")
                    continue
                tok = [t for t in cmd.replace('"', " ").split() if t.endswith((".sh", ".py"))]
                if tok:
                    names.append(tok[-1].split("/")[-1])
        out[ev] = set(names)
    return out

plugin = by_event("hooks/hooks.json")
repo = by_event(".claude/settings.json")
bad = False
for ev in sorted(set(plugin) | set(repo)):
    missing_in_plugin = repo.get(ev, set()) - plugin.get(ev, set())
    missing_in_repo = plugin.get(ev, set()) - repo.get(ev, set()) - PLUGIN_ONLY
    if missing_in_plugin:
        print(f"DRIFT: {ev}: in .claude/settings.json but NOT hooks/hooks.json: {sorted(missing_in_plugin)}")
        bad = True
    if missing_in_repo:
        print(f"DRIFT: {ev}: in hooks/hooks.json but NOT .claude/settings.json: {sorted(missing_in_repo)}")
        bad = True
sys.exit(1 if bad else 0)
PARITY
  then
    echo "DRIFT: Claude Code hook wiring differs between plugin manifest and repo settings"
    status=1
  else
    echo "OK: hooks/hooks.json and .claude/settings.json wire the same hooks"
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
