# Session Handover
_Generated: [auto-updated by /handover skill and pre-compact hook]_
_Branch: main_
_Triggered by: initial template_

---

## 🎯 Active Task
**What we're building:**
Setting up context-engineering-kit from scratch. Installing hooks, skills, and configuration
files so that context is preserved automatically across sessions, devices, and subscriptions.

**Phase:** Phase 1 — Initial Setup
**Progress:** 0% — fresh clone, no work done yet

---

## ✅ Completed This Session
- [ ] Clone / create repo
- [ ] Run `chmod +x .claude/hooks/*.sh`
- [ ] Run `git init && git add . && git commit -m "feat: initial context-engineering-kit setup"`
- [ ] Run `/context-health` to verify all hooks are wired
- [ ] Run `/token-status` to confirm session monitoring is active

---

## 🔄 In Progress (Exact Resume Point)
**File:** (none yet)
**Next immediate action:** Follow the setup steps in README.md → Quick Start section

---

## 🚧 Blockers & Known Issues
- Windows (no-admin): use `claude.cmd` not `claude` — see docs/windows-no-admin.md
- Mac/Linux: run `chmod +x .claude/hooks/*.sh` before first use
- Git Bash on Windows: set path in `.claude/settings.json` `bash_path` field if hooks fail

---

## 📋 Remaining Work
1. Complete Quick Start in README.md
2. Customise `config/model_thresholds.json` for your workflow
3. Add project-specific rules to `.claude/rules/`
4. Run `/context-health` to verify everything is wired
5. Fork and customise `examples/bioinformatics-ngs/` if doing genomics work

---

## 🏗 Architecture Decisions Made
| Decision | Rationale | Date |
|----------|-----------|------|
| Skills over commands | `.claude/skills/` is the 2026 recommended format | 2026-04-03 |
| git as continuity backbone | Works across all subscriptions and devices | 2026-04-03 |
| PreCompact + PostCompact | Official hook pair for context preservation | 2026-04-03 |

---

## 🔧 Commands to Resume
```bash
# On any machine after git pull:
bash scripts/session_sync.sh --load
# Then in Claude Code:
# /context-health     — verify everything is wired
# /handover           — review this file
```

---

## 📁 Key Files
| File | Purpose |
|------|---------|
| CLAUDE.md | Living context doc — auto-maintained |
| session_handover.md | This file — live task state |
| .claude/settings.json | All hooks wired here |
| .claude/hooks/pre-compact.sh | Updates handover before compaction |
| config/model_thresholds.json | Auto-switch thresholds |

---

## ⚠️ Critical Rules
- Never commit secrets or API keys
- Never modify .env files
- Run `bash scripts/session_sync.sh --save` before switching devices
- Use `/compact-smart` over `/compact` for better context retention

---

## 🧬 Bioinformatics Context (if applicable)
- Reference genome: not set
- Pipeline: not set
- See `examples/bioinformatics-ngs/CLAUDE.md` for NGS-specific setup

---
_Updated automatically by `/handover` skill and `pre-compact.sh` hook._
_Read this at the start of every session._
