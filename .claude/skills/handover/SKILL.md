---
name: handover
description: Generate or display a complete session handover document capturing all active task state, progress, blockers, and next actions. Run /handover before compacting, switching devices, or ending a session.
user-invocable: true
auto-invoke-when: user mentions switching devices, ending session, or asks about current task state
---

# Session Handover Generator

Generate a complete, structured session_handover.md. Write the output to `session_handover.md` in the project root.

Use this exact structure:

```markdown
# Session Handover
_Generated: [ISO timestamp]_
_Branch: [git branch]_
_Triggered by: [user request / pre-compact hook / context threshold]_

---

## 🎯 Active Task
**What we're building/fixing:**
[1–3 sentences describing the active task clearly enough that a fresh Claude instance can pick it up]

**Phase:** [Phase name and number if applicable]
**Progress:** [X% complete — describe what's done vs what remains]

---

## ✅ Completed This Session
- [Specific thing done, with file paths where relevant]
- [Another completed item]

---

## 🔄 In Progress (Exact Resume Point)
**File:** [path/to/file.ext]
**Function/Section:** [exact location]
**What was happening:** [description]
**Next immediate action:** [exactly what to do next — be specific]

---

## 🚧 Blockers & Known Issues
- [Blocker 1: description + what was tried]
- [Known issue: description]

---

## 📋 Remaining Work
1. [Next item]
2. [Item after that]
3. [Then this]

---

## 🏗 Architecture Decisions Made This Session
| Decision | Rationale | Date |
|----------|-----------|------|
| [decision] | [why] | [date] |

---

## 🔧 Commands to Resume
```bash
# Clone / pull latest
git pull origin [branch]

# Load session state
bash scripts/session_sync.sh --load

# Resume context
claude /handover
```

---

## 📁 Key Files Modified
| File | What changed |
|------|--------------|
| [path] | [what] |

---

## ⚠️ Critical Rules for This Project
- [Rule 1]
- [Rule 2]

---

## 🧬 Bioinformatics Context (if applicable)
- Reference genome: [GRCh38 / hg19 / other]
- Pipeline stage: [stage]
- Sample/cohort: [description]
- ACMG criteria in use: [criteria]

---
_Read this file at the start of every session. Update it with /handover before compacting._
```

After writing the file:
1. Confirm: "✅ session_handover.md updated — [N] items captured"
2. Suggest: "Run `bash scripts/session_sync.sh --save` to commit to git"
