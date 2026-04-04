---
name: session-sync
description: Save or load session state to/from git for cross-device and cross-subscription continuity. Use /session-sync save before switching machines or subscriptions. Use /session-sync load on a new device after git pull.
user-invocable: true
auto-invoke-when: user mentions switching devices, switching subscriptions, working from home vs office
---

# Session Sync — Cross-Device Continuity

Usage: `/session-sync [save|load|status]`

## If called with `save`:

1. Run `/handover` to update `session_handover.md` with current task state
2. Execute:
```bash
bash scripts/session_sync.sh --save
```
3. Confirm what was committed:
   - `.claude/session/state.json`
   - `.claude/session/history.jsonl`
   - `session_handover.md`
   - `CLAUDE.md`
4. Report: "✅ Session saved to git. On your other device: `git pull && claude /session-sync load`"

## If called with `load`:

1. Execute:
```bash
bash scripts/session_sync.sh --load
```
2. Read `session_handover.md` and report:
   - Last active task
   - Phase and next action
   - Compaction count
   - Last saved timestamp
3. Say: "✅ Session restored. Continue with: [next action from handover]"

## If called with `status` or no argument:

Report the current sync state:
- Last save timestamp (from state.json)
- Which device last saved (from state.json `saved_by` field)
- Whether local changes are ahead of git
- Git branch and commit

## Cross-subscription guide

If switching between Claude Pro, Max, and API:

| Subscription | Setup needed |
|-------------|-------------|
| Claude Pro → Max | Git pull, `claude /session-sync load`, same repo |
| Claude Pro/Max → API | Same repo, set `ANTHROPIC_API_KEY`, use `claude.cmd` |
| Office → Home machine | Git pull first, then `/session-sync load` |
| Windows → Mac | Git pull, `bash scripts/session_sync.sh --load` |

## Windows note

On Windows (no-admin), use:
```powershell
claude.cmd /session-sync save
```
Or run sync directly:
```powershell
bash.exe scripts/session_sync.sh --save
```
