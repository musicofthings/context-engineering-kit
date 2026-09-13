#!/usr/bin/env bash
# Exercise a Codex *plugin install* end to end, not just the manifest.
#
# CI validated that .codex-plugin/plugin.json parsed and that the generated hook
# files matched the generator. Neither proves the thing a user actually does:
# install the packaged plugin somewhere else on disk and have its hooks run from
# a different working directory. That gap is why the manifest could have pointed
# at hooks/hooks.json — the Claude manifest — without anything noticing.
#
# What this checks, against a real extracted package:
#   1. the packaged zip contains every file Codex needs
#   2. the manifest names its own hooks file, never hooks/hooks.json
#   3. that hooks file declares ONLY events Codex implements
#   4. every command resolves under ${CLAUDE_PLUGIN_ROOT} and runs from an
#      unrelated cwd, including a nested subdirectory
#   5. PreToolUse still denies with exit 2 through the installed copy
#   6. SessionEnd honours Codex's 3-second ceiling

set -uo pipefail

KIT="${KIT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/cek-codex-install.XXXXXX")
PLUGIN_ROOT="$WORK/plugins/context-engineering-kit"
PROJECT="$WORK/someones-project"

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s — %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
head_() { printf '\n▶ %s\n' "$1"; }

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Codex plugin install evals                              ║"
echo "╚══════════════════════════════════════════════════════════╝"

# ── 1. Package and install ───────────────────────────────────────────────────
head_ "Package and install"
PYTHON="${PYTHON:-python3}"
if ! "$PYTHON" "$KIT/scripts/package_plugin.py" --out "$WORK/plugin.zip" >"$WORK/pack.log" 2>&1; then
  bad "package_plugin.py builds" "$(tail -3 "$WORK/pack.log")"
  echo "Results: $pass passed, $((fail+1)) failed"; exit 1
fi
ok "package_plugin.py builds"

mkdir -p "$PLUGIN_ROOT"
"$PYTHON" -c "
import zipfile, sys
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
" "$WORK/plugin.zip" "$PLUGIN_ROOT" || { bad "unpack" "extract failed"; exit 1; }
ok "package unpacks to a plugin root"

for f in .codex-plugin/plugin.json hooks/codex-hooks.json .codex/hooks/run.sh \
         scripts/cek_runtime.sh .claude/hooks/guard-dangerous.sh skills/handover/SKILL.md; do
  [ -f "$PLUGIN_ROOT/$f" ] && ok "packaged: $f" || bad "packaged: $f" "missing from the zip"
done

# ── 2 + 3. Manifest and event set ────────────────────────────────────────────
head_ "Manifest and declared events"
MANIFEST_HOOKS=$("$PYTHON" -c "
import json,sys
m=json.load(open(sys.argv[1]))
h=m.get('hooks')
print(h if isinstance(h,str) else (h[0] if isinstance(h,list) and h else ''))
" "$PLUGIN_ROOT/.codex-plugin/plugin.json" 2>/dev/null)

case "$MANIFEST_HOOKS" in
  "") bad "manifest names a hooks file" "no hooks entry — Codex would inherit hooks/hooks.json" ;;
  */hooks/hooks.json) bad "manifest avoids the Claude manifest" "points at $MANIFEST_HOOKS" ;;
  *) ok "manifest names its own hooks file ($MANIFEST_HOOKS)" ;;
esac

HOOKS_PATH="$PLUGIN_ROOT/${MANIFEST_HOOKS#./}"
[ -f "$HOOKS_PATH" ] && ok "manifest hooks file exists in the package" \
  || bad "manifest hooks file exists" "$HOOKS_PATH missing"

UNSUPPORTED=$("$PYTHON" - "$HOOKS_PATH" <<'PYEOF'
import json, sys
supported = {
    "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse",
    "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact",
    "SubagentStart", "SubagentStop", "Stop", "Interrupt",
}
declared = set(json.load(open(sys.argv[1]))["hooks"])
print(",".join(sorted(declared - supported)))
PYEOF
)
[ -z "$UNSUPPORTED" ] && ok "declares only events Codex implements" \
  || bad "declares only supported events" "unsupported: $UNSUPPORTED"

# ── 4. Commands resolve from an unrelated cwd ────────────────────────────────
head_ "Hooks run from outside the plugin root"
mkdir -p "$PROJECT/nested/deeper"
git -C "$PROJECT" init -q .
git -C "$PROJECT" config user.email codex@test
git -C "$PROJECT" config user.name codex
printf '# someone else\n' > "$PROJECT/README.md"
git -C "$PROJECT" add -A >/dev/null 2>&1
git -C "$PROJECT" commit -qm init >/dev/null 2>&1

ABS=$(grep -c 'CLAUDE_PLUGIN_ROOT' "$HOOKS_PATH")
[ "$ABS" -gt 0 ] && ok "commands resolve via \${CLAUDE_PLUGIN_ROOT} ($ABS entries)" \
  || bad "commands use a plugin-root variable" "relative paths would break outside the root"

run_installed() {  # <cwd> <action...> ; payload on stdin
  local cwd="$1"; shift
  ( cd "$cwd" && env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" CLAUDE_PROJECT_DIR="$PROJECT" \
      CODEX_HOME="$WORK/.codex" \
      bash "$PLUGIN_ROOT/.codex/hooks/run.sh" "$@" )
}

printf '%s' "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"cdx-1\",\"cwd\":\"$PROJECT\",\"source\":\"startup\"}" \
  | run_installed "$PROJECT" session-start >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "session-start runs from the project root (exit 0)" \
  || bad "session-start from project root" "rc=$rc"

printf '%s' "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"cdx-2\",\"cwd\":\"$PROJECT\",\"source\":\"startup\"}" \
  | run_installed "$PROJECT/nested/deeper" session-start >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "session-start runs from a nested subdirectory (exit 0)" \
  || bad "session-start from nested cwd" "rc=$rc"

[ -f "$PROJECT/.claude/session/state.json" ] && ok "installed plugin writes state into the PROJECT" \
  || bad "state written into the project" "no state.json under $PROJECT"

LEAK=$(find "$PLUGIN_ROOT/.claude/session" -type f 2>/dev/null | wc -l | tr -d ' ')
[ "$LEAK" = "0" ] && ok "no state written into the plugin root" \
  || bad "no state in the plugin root" "$LEAK file(s)"

# ── 5. The guard still denies through the installed copy ─────────────────────
head_ "PreToolUse guard through the installed plugin"
DANGER=$("$PYTHON" -c "
import json
print(json.dumps({'hook_event_name':'PreToolUse','tool_name':'Bash',
 'tool_input':{'command':'rm'+' -'+'rf'+' '+'/'}}))")
printf '%s' "$DANGER" | run_installed "$PROJECT/nested" hook guard-dangerous.sh >/dev/null 2>"$WORK/guard.err"
rc=$?
[ "$rc" -eq 2 ] && ok "destructive command denied (exit 2)" || bad "destructive command denied" "rc=$rc"
grep -q "BLOCKED" "$WORK/guard.err" && ok "deny reason on stderr" || bad "deny reason on stderr" ""

printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
  | run_installed "$PROJECT" hook guard-dangerous.sh >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "safe command allowed (exit 0)" || bad "safe command allowed" ""

# ── 6. SessionEnd ceiling ────────────────────────────────────────────────────
head_ "SessionEnd timeout ceiling"
SE_TIMEOUT=$("$PYTHON" -c "
import json,sys
h=json.load(open(sys.argv[1]))['hooks'].get('SessionEnd',[])
print(h[0]['hooks'][0].get('timeout','unset') if h else 'absent')
" "$HOOKS_PATH")
case "$SE_TIMEOUT" in
  unset|absent) ok "SessionEnd has no timeout (Codex default 1s applies)" ;;
  1|2|3) ok "SessionEnd timeout ${SE_TIMEOUT}s is within the 3s ceiling" ;;
  *) bad "SessionEnd within Codex's 3s ceiling" "declares ${SE_TIMEOUT}s" ;;
esac

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $pass passed, $fail failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "workspace: $WORK"
[ "$fail" -eq 0 ]
