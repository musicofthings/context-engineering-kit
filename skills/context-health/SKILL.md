---
name: context-health
description: Run a full health check on all context engineering files. Checks CLAUDE.md freshness, session_handover.md completeness, hook wiring, session state, and git sync status. Use /context-health at session start or after switching devices.
user-invocable: true
auto-invoke-when: session just started, user asks if context files are up to date, after git pull
---

# Context Health Check

Run a comprehensive audit of the context engineering kit and report status for each component.

## Checks to perform

### 1. CLAUDE.md
- Does it exist? ✅/❌
- Is the "Active work context" section populated (not just template placeholders)? ✅/❌
- When was it last modified? (warn if > 24 hours ago during active development)
- Does it contain the project structure section? ✅/❌

### 2. session_handover.md
- Does it exist? ✅/❌
- Is the active task field populated? ✅/❌
- Is next action specified? ✅/❌
- Age: when was it last updated? (warn if > 4 hours during active dev)
- Does it have a "Commands to Resume" section? ✅/❌

### 3. Hook wiring (.claude/settings.json)
Check that these hooks are present:
- `PreCompact` ✅/❌
- `SessionStart` with `compact` matcher ✅/❌
- `Stop` ✅/❌
- `SessionEnd` ✅/❌
- `PreToolUse` (Bash guard) ✅/❌
- `PostToolUse` (change tracker) ✅/❌
- `Notification` ✅/❌

### 4. Hook scripts
Check that these files exist and are executable:
- `.claude/hooks/pre-compact.sh` ✅/❌
- `.claude/hooks/post-compact.sh` ✅/❌
- `.claude/hooks/session-start.sh` ✅/❌
- `.claude/hooks/stop.sh` ✅/❌
- `.claude/hooks/session-end.sh` ✅/❌

### 5. Session state
- `.claude/session/state.json` exists? ✅/❌
- Last updated timestamp
- Active task captured
- Compact count this project

### 6. Git sync status
- Is this a git repo? ✅/❌
- Are session files committed? ✅/❌
- Any uncommitted changes to context files?
- Branch name

### 7. Skills
Check that these skills exist:
- `/token-status` ✅/❌
- `/handover` ✅/❌
- `/model-switch` ✅/❌
- `/compact-smart` ✅/❌
- `/session-sync` ✅/❌

### 8. Config files
- `config/model_thresholds.json` ✅/❌
- `config/rate_limits.json` ✅/❌

## Output format

```
╔════════════════════════════════════════╗
║  Context Health Report                 ║
╚════════════════════════════════════════╝

CLAUDE.md          ✅ fresh (2h ago)
session_handover   ✅ current task set
hooks wired        ✅ 7/7 events
hook scripts       ✅ 5/5 executable
session state      ✅ last saved 1h ago
git sync           ✅ committed, clean
skills             ✅ 5/5 present
config             ✅ all present

Overall: ✅ HEALTHY  (or ⚠️ ISSUES FOUND)

Issues:
  ⚠️  session_handover.md is 6 hours old — run /handover
  ❌  .claude/hooks/stop.sh not executable — run: chmod +x .claude/hooks/*.sh
```

After the report, suggest the top 1–2 fixes if any issues found.

### 9. Usage tracking (v2.2)
- `.claude/session/daily-usage.json` exists? ✅/❌
- `.claude/session/usage-forecast.json` current? ✅/❌
- `auto-approve-permissions.sh` exists? ✅/❌
- `scripts/usage-tracker.py` exists? ✅/❌
- `CEK_SUBSCRIPTION_TIER` set in settings.json env? ✅/❌

For any issues found, suggest fix:
- Missing usage files: "Run a few turns — usage-tracker.py creates them automatically"
- Wrong tier: "Edit config/rate_limits.json → set subscription_tier to pro/max/api"
- Missing auto-approve hook: "hooks/auto-approve-permissions.sh not found — run setup.sh"
