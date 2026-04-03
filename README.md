# context-engineering-kit

> **Automated context preservation for Claude Code across sessions, devices, and subscriptions.**

A Claude Code plugin that wires hooks, skills, and scripts so your context never falls off a cliff — whether you're hitting the 5-hour Pro window, switching from your office Windows machine to your home Mac, or moving between Claude subscriptions.

---

## What it does

| Problem | This kit's solution |
|---------|-------------------|
| Context window fills up, Claude forgets everything | `PreCompact` hook saves full state before compaction |
| Can't resume after `/compact` | `PostCompact` hook re-injects critical context |
| Switching devices loses task state | `session_sync.sh` commits state to git |
| Switching Pro → Max → API loses continuity | Same git repo, same session state |
| No visibility into token usage | `/token-status` skill with visual burn-rate display |
| Manual model switching is tedious | `/model-switch auto` analyses task and picks Haiku/Sonnet/Opus |
| Context rot creeps in over long sessions | `/compact-smart` preserves high-value content selectively |
| Hard to hand off work to fresh session | `/handover` generates structured `session_handover.md` |

---

## Quick start

```bash
# 1. Clone (or fork and clone)
git clone https://github.com/YOUR_USER/context-engineering-kit.git
cd context-engineering-kit

# 2. Run setup (Mac/Linux)
bash setup.sh

# 3. Windows (Git Bash)
bash.exe setup.sh

# 4. Start Claude Code
claude          # Mac/Linux
claude.cmd      # Windows (no-admin)

# 5. Verify everything is wired
/context-health
```

---

## Available slash commands (skills)

| Command | What it does |
|---------|-------------|
| `/token-status` | Context usage %, burn rate, model recommendation |
| `/handover` | Generate full `session_handover.md` with task state |
| `/compact-smart` | Relevance-scored compaction (preserves code + decisions) |
| `/model-switch [haiku\|sonnet\|opus\|auto]` | Switch model manually or auto-select by task |
| `/session-sync [save\|load\|status]` | Sync state to/from git for cross-device continuity |
| `/context-health` | Full audit of hooks, files, session state, git sync |

Built-in Claude Code commands still work: `/compact`, `/clear`, `/model`, `/hooks`, `/doctor`, `/fast`

---

## Hooks wired automatically

| Hook event | Script | Purpose |
|------------|--------|---------|
| `SessionStart` | `session-start.sh` | Injects date, git state, task summary |
| `SessionStart` (compact) | `post-compact.sh` | Re-injects context after compaction resume |
| `PreCompact` | `pre-compact.sh` | Updates `session_handover.md` + CLAUDE.md before compaction |
| `PostCompact` | `post-compact.sh` | Re-injects critical context after compaction |
| `Stop` | `stop.sh` | Lightweight state capture each turn |
| `SessionEnd` | `session-end.sh` | Git commits session state on close |
| `PreToolUse` (Bash) | `guard-dangerous.sh` | Blocks `rm -rf /` and other dangerous commands |
| `PostToolUse` (Edit\|Write) | `track-changes.sh` | Logs file edits to `state.json` |
| `Notification` | `notify.sh` | Desktop notification (Mac/Linux/Windows) |
| `ConfigChange` | inline | Appends to `config-audit.log` |
| `InstructionsLoaded` | inline | Welcome message + quick command list |

---

## Cross-device / cross-subscription workflow

```bash
# Before switching device or subscription:
claude /session-sync save        # or: bash scripts/session_sync.sh --save

# On the new device, after git pull:
bash scripts/session_sync.sh --load
claude                           # then /context-health to verify
```

All state lives in `.claude/session/state.json` (committed to git). Works across:
- Office Windows ↔ Home Mac
- Claude Pro ↔ Claude Max ↔ API billing

---

## Multi-device setup

| Machine | Setup notes |
|---------|------------|
| Mac/Linux | `bash setup.sh` — sets `chmod +x` on hooks |
| Windows (no-admin) | `bash.exe setup.sh` in Git Bash; use `claude.cmd` not `claude` |
| CI/CD | Hooks disabled in headless mode; GitHub Actions handle state CI |

---

## File structure

```
context-engineering-kit/
├── CLAUDE.md                    # Living context doc — auto-maintained
├── session_handover.md          # Live task state — auto-generated
├── agents.md                    # Subagent role definitions
├── api_docs.md                  # Auto-fetched API docs (weekly CI)
├── setup.sh                     # One-command setup
│
├── .claude/
│   ├── settings.json            # All hooks wired here
│   ├── hooks/                   # Shell scripts called by hook events
│   │   ├── pre-compact.sh       # ⭐ Core — updates all context files
│   │   ├── post-compact.sh      # Re-injects context after compaction
│   │   ├── session-start.sh     # Date + state injection on start
│   │   ├── stop.sh              # Lightweight per-turn state capture
│   │   ├── session-end.sh       # Git commit on close
│   │   ├── guard-dangerous.sh   # Blocks destructive bash commands
│   │   ├── track-changes.sh     # Logs file edits
│   │   └── notify.sh            # Cross-platform notifications
│   ├── skills/                  # Slash commands
│   │   ├── token-status/        # /token-status
│   │   ├── handover/            # /handover
│   │   ├── model-switch/        # /model-switch
│   │   ├── compact-smart/       # /compact-smart
│   │   ├── session-sync/        # /session-sync
│   │   └── context-health/      # /context-health
│   ├── rules/                   # Auto-loaded modular rules
│   │   ├── commit-protocol.md
│   │   ├── security.md
│   │   └── token-hygiene.md
│   └── session/
│       └── state.json           # Live session state (committed to git)
│
├── scripts/
│   ├── generate_session_handover.py
│   ├── update_context_files.py
│   ├── session_sync.sh
│   └── fetch_api_docs.py
│
├── config/
│   ├── model_thresholds.json
│   ├── rate_limits.json
│   └── api_sources.json
│
├── examples/
│   └── bioinformatics-ngs/CLAUDE.md   # NGS / VariantGPT example
│
└── .github/workflows/
    ├── sync-api-docs.yml        # Weekly API doc refresh
    └── session-state.yml        # Validates context files on push
```

---

## For bioinformatics / genomics projects

Copy `examples/bioinformatics-ngs/CLAUDE.md` into your project and customise:

```bash
cp examples/bioinformatics-ngs/CLAUDE.md /path/to/your-ngs-project/CLAUDE.md
```

Pre-configured for: VCF/FASTA token hygiene, ACMG criteria, NGS pipeline stages, gnomAD/ClinVar annotation, AWS Batch, GRCh38, Lynch syndrome panels.

---

## Requirements

- Claude Code (latest) — `npm install -g @anthropic-ai/claude-code` or `npm.cmd` on Windows no-admin
- `bash` (built into Mac/Linux; Git Bash on Windows)
- `git`
- `jq` (for hooks JSON parsing)
- `python3` (for handover and context update scripts)

---

## Contributing

This kit is designed to be forked and customised. To add a new skill:

```bash
mkdir -p .claude/skills/my-skill
cat > .claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: What this skill does and when Claude should invoke it
user-invocable: true
---
# My Skill
[Instructions for Claude here]
EOF
```

Then in Claude Code: `/my-skill`

---

## Windows no-admin install

See `docs/windows-no-admin.md` for the complete guide to installing Claude Code CLI
without admin rights on a corporate Windows machine.

---

*context-engineering-kit v2.0 — Built for multi-device, multi-subscription Claude Code workflows.*
