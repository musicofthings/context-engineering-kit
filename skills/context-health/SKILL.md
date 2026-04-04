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
- Does it exist in the project directory or plugin root? ✅/❌
- Is the "Active work context" section populated (not just template placeholders)? ✅/❌
- When was it last modified? (warn if > 24 hours ago during active development)

### 2. session_handover.md
Run: `ls -la session_handover.md 2>/dev/null || echo "missing"`
- Does it exist in the current project directory? ✅/❌
- Is the active task field populated? ✅/❌
- Is next action specified? ✅/❌
- Age: when was it last updated? (warn if > 4 hours during active dev)
- Does it have a "Commands to Resume" section? ✅/❌

### 3. Hook wiring

#### Plugin mode
Run:
```bash
cat ${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
hooks = d.get('hooks', {})
events = ['SessionStart','PreCompact','PostCompact','Stop','SessionEnd','PreToolUse','PostToolUse']
for e in events:
    status = '✅' if e in hooks else '❌'
    print(f'  {status}  {e}')
" 2>/dev/null || echo "  ❌  hooks/hooks.json not found"
```
Report as: `hooks wired  ✅ 7/7 (plugin mode — hooks.json)`

#### Standalone mode
Check `.claude/settings.json` for a `hooks` block with these events:
`PreCompact`, `SessionStart` (compact matcher), `Stop`, `SessionEnd`, `PreToolUse` (Bash), `PostToolUse` (Edit|Write), `Notification`

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
Run:
```bash
# Check project-level state (where hooks write to)
STATE="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/session/state.json"
if [ -f "$STATE" ]; then
  echo "found: $STATE"
  cat "$STATE" | python3 -c "import sys,json; d=json.load(sys.stdin); print('task:', d.get('active_task','?')); print('updated:', d.get('last_activity','?'))"
else
  echo "missing: $STATE"
fi
```
- state.json exists? ✅/❌
- Last updated timestamp
- Active task captured

Note: state.json is written to the **current project directory** (not the plugin directory). It will be absent until the first session-start hook fires in a project directory.

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
Run:
```bash
STATE_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/session"
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

Install mode       : plugin (context-engineering-kit v2.4.0)
                     Plugin root: ~/.claude/plugins/cache/...

CLAUDE.md          ✅ fresh (2h ago)
session_handover   ✅ current task set
hooks wired        ✅ 7/7 (plugin mode — hooks/hooks.json)
hook scripts       ✅ 5/5 executable
session state      ⚠️  not yet created — will appear after first turn in a project
git sync           ⚠️  no project open — open a project folder to enable git sync
skills             ✅ 8/8 present (context-engineering-kit:*)
config             ✅ all present
usage tracking     ⚠️  usage files not yet created (normal on first session)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Overall: ✅ HEALTHY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

After the report, suggest the top 1–2 actionable fixes. Do not flag "session state missing" or "git sync unavailable" as critical errors when running outside a project directory — these are expected until a project is opened.
