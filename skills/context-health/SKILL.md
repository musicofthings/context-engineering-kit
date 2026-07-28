---
name: context-health
description: Run a full health check on all context engineering files. Checks CLAUDE.md freshness, session_handover.md completeness, hook wiring, session state, and git sync status. Use /context-health at session start or after switching devices.
user-invocable: true
auto-invoke-when: session just started, user asks if context files are up to date, after git pull
---

# Context Health Check

Run a comprehensive audit of the context engineering kit and report status for each component.

## Detect install mode first

Run this to determine the install mode:
```bash
echo "PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-unset}"
```

- If `CLAUDE_PLUGIN_ROOT` is set → **plugin mode** (installed via Claude Desktop)
- If unset → **standalone mode** (cloned into project, hooks in settings.json)

The checks differ between modes. Apply the correct checks for the detected mode.

---

## Checks to perform

### 1. CLAUDE.md

First, determine if we're inside a git-tracked project:
```bash
git -C "${CLAUDE_PROJECT_DIR:-$(pwd)}" rev-parse --is-inside-work-tree 2>/dev/null && echo "in_git_repo" || echo "no_git_repo"
```

- In a git repo: check for CLAUDE.md in project dir — missing = ❌
- **Not in a git repo**: missing CLAUDE.md = ⚠️ with note "(expected outside a project — open a project folder)"
- If found: is the "Active work context" section populated (not template placeholders)? ✅/⚠️
- When was it last modified? (warn if > 24 hours during active development)

### 2. session_handover.md
Run: `ls -la "${CLAUDE_PROJECT_DIR:-$(pwd)}/session_handover.md" 2>/dev/null || echo "missing"`
- **Not in a git repo**: missing or empty = ⚠️ "(expected outside a project — run /handover inside a project)"
- In a git repo: missing = ❌; empty (0 bytes) = ❌; populated = ✅
- Is the active task field populated (not template text)? ✅/⚠️
- Age: when was it last updated? (warn if > 4 hours during active dev)
- Does it have a "Commands to Resume" section? ✅/⚠️

### 3. Hook wiring

#### Plugin mode
Run:
```bash
cat ${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
hooks = d.get('hooks', {})
# All events wired as of v2.7.0
events = [
  'SessionStart','PreCompact','PostCompact','Stop','SessionEnd',
  'PreToolUse','PostToolUse','PostToolUseFailure','PermissionRequest',
  'SubagentStart','SubagentStop','Notification','UserPromptSubmit',
  'StopFailure','InstructionsLoaded','FileChanged'
]
ok = [e for e in events if e in hooks]
missing = [e for e in events if e not in hooks]
for e in events:
    status = '✅' if e in hooks else '❌'
    print(f'  {status}  {e}')
print(f'  {len(ok)}/{len(events)} wired')
" 2>/dev/null || echo "  ❌  hooks/hooks.json not found"
```
Report as: `hooks wired  ✅ 16/16 (plugin mode — hooks.json)` (or the actual count)

#### Standalone mode
Check `.claude/settings.json` for a `hooks` block with these events (all required as of v2.7.0):
`SessionStart`, `PreCompact`, `PostCompact`, `Stop`, `SessionEnd`,
`PreToolUse` (Bash), `PostToolUse` (Edit|Write), `PostToolUseFailure`,
`PermissionRequest`, `SubagentStart`, `SubagentStop`, `Notification`,
`UserPromptSubmit`, `StopFailure`, `InstructionsLoaded`, `FileChanged`

Note: `SessionStart` should have three entries — the main banner hook (no matcher),
`morning-brief-auto.sh` (async, no matcher), `compact-restore.sh` (matcher: compact),
and `session-title.sh` (matcher: startup|resume). Don't flag having multiple
`SessionStart` entries as an error.

### 4. Hook scripts

#### Plugin mode
Run:
```bash
ls -la ${CLAUDE_PLUGIN_ROOT}/.claude/hooks/*.sh 2>/dev/null | awk '{print $1, $NF}' | grep -v "^total"
```
Check that these exist and have execute bit (`-rwxr-xr-x`):
- `session-start.sh` ✅/❌
- `pre-compact.sh` ✅/❌
- `post-compact.sh` ✅/❌
- `stop.sh` ✅/❌
- `session-end.sh` ✅/❌

If any lack execute bit, the fix is automatic on next session restart (chmod hook fires at SessionStart).
Report as: `hook scripts  ✅ N/5 executable (plugin cache: ${CLAUDE_PLUGIN_ROOT})`

#### Standalone mode
Check `.claude/hooks/*.sh` exist and are executable.
If missing: "Run `bash setup.sh` to populate hook scripts"

### 5. Session state
Source the shared resolver so this check looks at the SAME state.json the
hooks write — important under worktree mode where state lives at the main
checkout, not the worktree's own directory.

```bash
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$PROJECT_DIR}"
RESOLVER="$PLUGIN_ROOT/scripts/resolve_state_dir.sh"
if [ -f "$RESOLVER" ]; then
  # shellcheck disable=SC1090
  source "$RESOLVER"
else
  STATE_FILE="$PROJECT_DIR/.claude/session/state.json"
  STATE_DIR="$PROJECT_DIR/.claude/session"
fi
if [ -f "$STATE_FILE" ]; then
  echo "found: $STATE_FILE"
  python3 -c "import sys,json; d=json.load(open('$STATE_FILE')); print('task:', d.get('active_task','?')); print('updated:', d.get('last_activity') or d.get('last_stop','?'))"
else
  echo "missing: $STATE_FILE  (scope=$STATE_SCOPE, in_worktree=$IN_WORKTREE)"
fi
```
- state.json exists? ✅/⚠️ (absent = expected outside a project)
- `active_task = "unknown"` when no project is open → ⚠️ "(hooks firing but no project task yet — expected)"
- `active_task` is set → ✅
- Last updated timestamp

Note: state.json is resolved via `scripts/resolve_state_dir.sh`. Under
`state.scope=auto` from a linked worktree, the live state file is in the
main checkout (`$MAIN_ROOT/.claude/session/state.json`), not the worktree
itself. The resolver handles this; do not hardcode the worktree path.

### 6. Git sync status
Run: `git -C "${CLAUDE_PROJECT_DIR:-$(pwd)}" status --short 2>/dev/null || echo "not a git repo"`
- Is the current working directory a git repo? ✅/❌
- Are context files committed? ✅/❌
- Branch name

Note: git sync is per-project. If you are running Claude Code outside a project directory, this check is expected to show ❌ — it becomes relevant once you open a project.

### 7. Skills
Check that these skills exist (in plugin mode they are namespaced):

#### Plugin mode — check for:
- `/context-engineering-kit:token-status` ✅/❌
- `/context-engineering-kit:handover` ✅/❌
- `/context-engineering-kit:model-switch` ✅/❌
- `/context-engineering-kit:compact-smart` ✅/❌
- `/context-engineering-kit:session-sync` ✅/❌
- `/context-engineering-kit:usage-forecast` ✅/❌
- `/context-engineering-kit:morning-brief` ✅/❌
- `/context-engineering-kit:init-cek` ✅/❌  _(first-run init, optional)_

Total: 7 user-facing skills (8 including init-cek)

Verify by listing: `ls ${CLAUDE_PLUGIN_ROOT}/skills/ 2>/dev/null`

#### Standalone mode — check for:
`/token-status`, `/handover`, `/model-switch`, `/compact-smart`, `/session-sync`

### 8. Config files
Run:
```bash
CDIR="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/config"
for f in model_thresholds.json rate_limits.json usage_budget.json morning_brief.json; do
  [ -f "$CDIR/$f" ] && echo "✅  $f" || echo "❌  $f"
done
```

### 9. Usage tracking
Run (reusing `$STATE_DIR` from check #5 — same worktree-aware resolution):
```bash
# Expect STATE_DIR populated by resolve_state_dir.sh sourced above.
: "${STATE_DIR:=${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/session}"
for f in daily-usage.json usage-forecast.json; do
  [ -f "$STATE_DIR/$f" ] && echo "✅  $f" || echo "❌  $f (created automatically after a few turns)"
done
SCRIPTS="${CLAUDE_PLUGIN_ROOT:-$(pwd)}/scripts"
[ -f "$SCRIPTS/usage-tracker.py" ] && echo "✅  usage-tracker.py" || echo "❌  usage-tracker.py"
```

For `CEK_SUBSCRIPTION_TIER`:
- In plugin mode: check `config/usage_budget.json` → `subscription_type` field (this is the correct config)
- If user wants to override: add to `~/.claude/settings.json` under `"env": { "CEK_SUBSCRIPTION_TIER": "max" }`

---

## Output format

```
╔════════════════════════════════════════╗
║  Context Health Report — YYYY-MM-DD    ║
╚════════════════════════════════════════╝

Install mode       : plugin (context-engineering-kit v2.7.0)
                     Plugin root: ~/.claude/plugins/cache/...

CLAUDE.md          ✅ fresh (2h ago)
session_handover   ✅ current task set
hooks wired        ✅ 16/16 (plugin mode — hooks/hooks.json)
hook scripts       ✅ 5/5 executable
session state      ⚠️  not yet created — will appear after first turn in a project
git sync           ⚠️  no project open — open a project folder to enable git sync
skills             ✅ 7/7 present (context-engineering-kit:*)
config             ✅ all present
usage tracking     ⚠️  usage files not yet created (normal on first session)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall: ✅ HEALTHY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

After the report, suggest the top 1–2 actionable fixes.

**Outside a git project directory** (the most common case after fresh install): CLAUDE.md missing,
session_handover.md empty, active_task "unknown", and git sync unavailable are ALL expected —
downgrade these to ⚠️ and note "open a project folder to enable". The overall status should be
✅ HEALTHY (not DEGRADED) when the only issues are these project-context items combined with
✅ hooks, scripts, skills, and config.
