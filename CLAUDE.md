# context-engineering-kit

## What this repo is
A Claude Code plugin and boilerplate for maintaining rich context across sessions,
devices, and Claude subscriptions. It provides hooks, skills, and automation scripts
that keep CLAUDE.md, session_handover.md, and supporting files always up to date —
so every new session picks up exactly where the last one left off.

## Quick orientation
- **Hooks fire automatically** — you do not need to call them manually
- **Skills are slash commands** — type `/token-status`, `/handover`, `/compact-smart`, etc.
- **session_handover.md** is the live state file — always read it at session start
- **config/** holds all tunable thresholds (model switching, token budgets, rate limits)

## Critical rules
- Never commit secrets, API keys, or patient data
- Never modify `.claude/hooks/*.sh` without testing with `/doctor` afterward
- Always run `bash scripts/session_sync.sh --save` before switching devices
- Use `/fast` for quick edits; reserve Opus for architecture decisions

## Project structure
```
context-engineering-kit/
├── CLAUDE.md                        ← this file (auto-updated by hooks)
├── session_handover.md              ← live task state (auto-updated at 70% context)
├── agents.md                        ← subagent role definitions
├── .claude/
│   ├── settings.json                ← hooks wired here
│   ├── hooks/                       ← shell scripts run by hooks
│   │   ├── pre-compact.sh           ← runs before context compaction
│   │   ├── post-compact.sh          ← re-injects context after compaction
│   │   ├── session-start.sh         ← injects state on fresh/resumed session
│   │   ├── stop.sh                  ← captures state when Claude finishes turn
│   │   └── session-end.sh           ← final git commit of session state
│   ├── skills/                      ← slash commands (type /skill-name)
│   │   ├── token-status/            ← /token-status
│   │   ├── handover/                ← /handover
│   │   ├── model-switch/            ← /model-switch
│   │   ├── compact-smart/           ← /compact-smart
│   │   ├── session-sync/            ← /session-sync
│   │   └── context-health/          ← /context-health
│   ├── rules/
│   │   ├── commit-protocol.md
│   │   ├── security.md
│   │   └── token-hygiene.md
│   └── subagents/
│       ├── context-updater.md
│       └── session-scribe.md
├── scripts/
│   ├── generate_session_handover.py ← called by pre-compact hook
│   ├── update_context_files.py      ← updates README, CLAUDE.md, specs
│   ├── session_sync.sh              ← cross-device / cross-subscription sync
│   └── fetch_api_docs.py            ← weekly API doc refresh (CI)
├── config/
│   ├── model_thresholds.json        ← auto-switch trigger points
│   ├── rate_limits.json             ← token budgets per model
│   └── api_sources.json             ← API doc sources for weekly refresh
├── templates/
│   ├── CLAUDE.md.template
│   └── session_handover.template.md
└── .github/workflows/
    ├── sync-api-docs.yml
    └── session-state.yml
```

## Active work context
<!-- AUTO-UPDATED by hooks — do not edit this section manually -->
<!-- LAST_UPDATED: [timestamp] -->
<!-- ACTIVE_TASK: [task] -->
<!-- PHASE: [phase] -->
<!-- NEXT_ACTION: [action] -->

## Architecture decisions
<!-- Append decisions here. Format: [date] Decision: Rationale: -->

## Lessons learned
<!-- Append after each session. Format: [date] Problem → Fix -->

## Known gotchas
- Windows (no-admin): use `claude.cmd` not `claude`; see docs/windows-no-admin.md
- On first run: `chmod +x .claude/hooks/*.sh` (Mac/Linux) or check Git Bash on Windows
- Git Bash path on Windows: set in `.claude/settings.json` as `"bash_path"`
- hooks read stdin as JSON — always pipe through `jq` for field extraction

## Useful commands
```bash
# Check hook health
claude /doctor

# See all wired hooks
claude /hooks

# Check context usage
claude /token-status

# Generate session handover now
claude /handover

# Sync state to git (before switching device/subscription)
bash scripts/session_sync.sh --save

# Restore state from git (on new device)
bash scripts/session_sync.sh --load

# Force smart compaction
claude /compact-smart
```

<!-- AUTO-UPDATED by hooks — do not edit this section manually -->
<!-- LAST_UPDATED: 2026-05-03T13:18:33Z -->
<!-- ACTIVE_TASK: unknown -->
<!-- PHASE: unknown -->
<!-- NEXT_ACTION: unknown -->
<!-- BRANCH: unknown -->
<!-- COMPACT_MODE: manual -->
<!-- END AUTO-UPDATED -->
