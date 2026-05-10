---
name: handover
description: Generate or display a complete session handover document capturing all active task state, progress, blockers, and next actions. Run /handover before compacting, switching devices, or ending a session.
user-invocable: true
auto-invoke-when: user mentions switching devices, ending session, or asks about current task state
---

# Session Handover Generator

Generate a complete, structured session_handover.md. Write the output to `session_handover.md` in the project root.

Use this exact structure (matches what `generate_session_handover.py` produces so the pre-compact hook preserves your edits):

```markdown
# Session Handover
_Generated: [ISO timestamp]_
_Branch: [git branch]_
_Trigger: [user request / pre-compact hook / context threshold] | Context at compact: [N]%_
_Compact count this project: [N]_

---

## 🎯 Active Task
**What we're building/fixing:**
[1–3 sentences describing the active task clearly enough that a fresh Claude instance can pick it up]

**Phase:** [Phase name and number if applicable]
**Next action:** [exactly what to do next — be specific]

---

## ✅ Completed This Session
- [ ] (track completed items here)

---

## 🔄 In Progress (Exact Resume Point)
**Branch:** `[branch]`
**Last commit:** `[commit hash and message]`
**Next immediate action:** [exactly what to do next]

---

## 📋 Remaining Work
1. [Next item]
2. [Item after that]
3. [Then this]

---

## 🏗 Architecture Decisions Made
| Decision | Rationale | Date |
|----------|-----------|------|
| [decision] | [why] | [date] |

---

## 🔧 Commands to Resume
```bash
# On any machine after git pull:
git pull origin [branch]
bash scripts/session_sync.sh --load

# In Claude Code:
# /context-health     — verify hooks are wired
# /handover           — review this file
# /token-status       — check context usage
```

---

## 📁 Files Modified This Session
| File | Status |
|------|--------|
| [path] | modified |

---

## 🌿 Git Context
```
Branch  : [branch]
Commit  : [commit]
Status  : [clean / dirty]
```

Recent commits:
```
[last 5 commits]
```

---

## ⚠️ Critical Rules
- Never commit secrets or API keys
- Run /handover before switching devices

---

## 🧬 Bioinformatics Context (if applicable)
- Not configured for this project

---
_Auto-updated by `pre-compact.sh` hook and `/handover` skill._
_Read this at the start of every session. Update with `/handover`._
```

After writing the file:
1. Confirm: "✅ session_handover.md updated — [N] items captured"
2. Suggest: "Run `bash scripts/session_sync.sh --save` to commit to git"
