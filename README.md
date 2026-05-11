# context-engineering-kit

> **Automated context preservation for Claude Code — across sessions, devices, and subscriptions.**

Hooks, skills, and scripts that keep your context alive through compaction, device switches, and subscription changes. Works as a **Claude Code Desktop plugin** or a **Claude Code CLI standalone install**.

🌐 **[Landing page & full docs →](https://musicofthings.github.io/context-engineering-kit/)**

---

## What problem does it solve?

| Problem | This kit's solution |
|---------|-------------------|
| Context window fills up, Claude forgets everything | `PreCompact` hook saves full state before compaction |
| Can't resume where you left off after `/compact` | `PostCompact` hook re-injects critical context automatically |
| Switching devices loses task state | `session_sync.sh` commits state to git — pull and resume anywhere |
| Switching Pro → Max → API loses continuity | Same git repo, same `session_handover.md`, same state |
| No visibility into token/cost burn rate | `/token-status` and `/usage-forecast` with live window metrics |
| Tedious manual model switching | `/model-switch auto` analyses your task and picks Haiku/Sonnet/Opus |
| Context rot from undifferentiated compaction | `/compact-smart` preserves code, decisions, and task state at higher fidelity |
| Hard to hand work off to a fresh session | `/handover` generates a structured `session_handover.md` in one command |
| Dangerous commands allowed silently | `guard-dangerous.sh` blocks `rm -rf /` and production config writes |
| New repos need manual context-kit setup | `auto_activate_new_repos` bootstraps any new git project automatically |

---

## Installation

Choose the install path that matches how you use Claude Code:

| | Claude Code Desktop | Claude Code CLI |
|--|---------------------|-----------------|
| **How** | Upload zip via Customize UI | Clone repo + `bash setup.sh` |
| **Skill names** | `/context-engineering-kit:handover` | `/handover` |
| **Hooks wired by** | `hooks/hooks.json` (auto) | `.claude/settings.json` |
| **Auto-activates on new repos** | ✅ Yes (plugin toggle) | Manual per-project |
| **Best for** | Always-on across all projects | One specific project |

---

## Option A — Claude Code Desktop (plugin)

The recommended path if you use the **Claude Code desktop app**. The plugin loads automatically in every project — no per-project setup needed. New projects are bootstrapped automatically on first open.

### Prerequisites

- Claude Code desktop app (latest)
- `jq`, `bash`, `git`
- `python3` or `python` (v3.x) — the kit auto-detects the right command
- `feedparser` for morning brief: `pip install feedparser`

### Install steps

1. **Download** `context-engineering-kit-plugin.zip` from the [latest release](https://github.com/musicofthings/context-engineering-kit/releases)

   Or build from source:
   ```bash
   git clone https://github.com/musicofthings/context-engineering-kit.git
   cd context-engineering-kit
   zip -r ../context-engineering-kit-plugin.zip . --exclude "*.git*" --exclude "briefs/*" --exclude "*.pyc"
   ```

2. **Open Claude Code Desktop** → click **Customize** (bottom-left gear icon) → **Upload Plugin** → select the zip

3. **Restart Claude Code Desktop**

4. **Verify** — in any project:
   ```
   /context-engineering-kit:context-health
   ```

### Skills in Desktop mode

All skills are namespaced with the plugin name:

```
/context-engineering-kit:context-health     ← run this first after install
/context-engineering-kit:handover
/context-engineering-kit:token-status
/context-engineering-kit:compact-smart
/context-engineering-kit:model-switch
/context-engineering-kit:session-sync
/context-engineering-kit:usage-forecast
/context-engineering-kit:morning-brief
```

### Auto-activation on new repos

By default the plugin bootstraps `session_handover.md` and `state.json` in any new git project on first open. To configure:

```json
// config/plugin_settings.json
{
  "auto_activate_new_repos": true,
  "features": {
    "session_tracking":  true,
    "usage_sentinel":    true,
    "morning_brief":     false,
    "tool_failure_log":  true,
    "subagent_tracking": true
  },
  "skip_repos": ["/path/to/repo-to-skip"]
}
```

Set `auto_activate_new_repos: false` to disable entirely, or add individual project paths to `skip_repos`.

### Configure subscription type

Edit `config/usage_budget.json` inside the plugin directory, or set an environment variable in Claude Code's settings:

```json
{
  "env": {
    "CEK_SUBSCRIPTION_TIER": "max"
  }
}
```

Valid tiers: `pro` | `max` | `api` | `team`

---

## Option B — Claude Code CLI (standalone, per-project)

Use this if you run `claude` from the terminal. Hooks wire directly into the project's `.claude/settings.json`. Skill names are short (`/handover` instead of `/context-engineering-kit:handover`).

### Prerequisites

- Claude Code CLI: `npm install -g @anthropic-ai/claude-code`
- `bash`, `git`, `jq` (`brew install jq` / `apt install jq`)
- `python3` or `python` (v3.x) — auto-detected
- `feedparser` for morning brief: `pip install feedparser`

### Install steps

```bash
# 1. Clone (or fork if you want to customise)
git clone https://github.com/musicofthings/context-engineering-kit.git my-project
cd my-project

# 2. Run setup
bash setup.sh          # Mac / Linux
bash.exe setup.sh      # Windows Git Bash (no-admin)
```

`setup.sh` will:
- Check all dependencies
- Make hook scripts executable
- Initialise `state.json` with your machine's hostname
- Set `subscription_type` in `config/usage_budget.json`
- Confirm hooks are wired in `.claude/settings.json`

```bash
# 3. Set subscription type in config/usage_budget.json
#    or export the env var:
export CEK_SUBSCRIPTION_TIER=max   # pro | max | api | team

# 4. Launch
claude          # Mac / Linux
claude.cmd      # Windows no-admin

# 5. Verify
/context-health
```

### Skills in CLI mode

Short names — no prefix needed:

```
/context-health      ← run this first to verify the install
/handover
/token-status
/compact-smart
/model-switch
/session-sync
/usage-forecast
/morning-brief
```

---

## Skills reference

| Skill | Desktop | CLI | Description |
|-------|---------|-----|-------------|
| `/context-health` | `/context-engineering-kit:context-health` | `/context-health` | Full audit: hooks, scripts, state, git, config |
| `/handover` | `/context-engineering-kit:handover` | `/handover` | Generate `session_handover.md` with full task state |
| `/token-status` | `/context-engineering-kit:token-status` | `/token-status` | Context %, burn rate, subscription window, cost |
| `/compact-smart` | `/context-engineering-kit:compact-smart` | `/compact-smart` | Relevance-scored compaction (preserves code + decisions) |
| `/model-switch` | `/context-engineering-kit:model-switch` | `/model-switch` | Switch Haiku/Sonnet/Opus or let `auto` decide |
| `/session-sync` | `/context-engineering-kit:session-sync` | `/session-sync` | Save/load state to git for cross-device continuity |
| `/usage-forecast` | `/context-engineering-kit:usage-forecast` | `/usage-forecast` | Daily burn rate, turns-to-warn, ETA to limit |
| `/morning-brief` | `/context-engineering-kit:morning-brief` | `/morning-brief` | AI news digest from RSS feeds |

### `/token-status`

```
╔══════════════════════════════════════════════╗
║  Usage Forecast  🟢  HEALTHY                 ║
╚══════════════════════════════════════════════╝

Tier          : PRO  (real window)
5h window     : 34.2% used  resets 1h47m
Context now   : 41%   (peak: 58%)
Cost today    : $0.0021
Turns today   : 12

To warn       : ~18 turns
To critical   : ~38 turns (~2.1h)

✅ Usage healthy.
```

Auto-invoked when context exceeds 65%.

### `/handover`

Generates a complete, structured `session_handover.md` and commits it:

```
✅ session_handover.md updated — 7 items captured
Run: bash scripts/session_sync.sh --save  to commit to git
```

Run before switching devices, hitting the context limit, or ending a session.

### `/compact-smart`

Unlike `/compact` which summarises everything uniformly, this:
1. Writes `session_handover.md` first
2. Tags high-value content (code written, decisions, error solutions) to preserve verbatim
3. Tags low-value content (abandoned exploration, verbose output) to summarise aggressively

### `/model-switch [haiku|sonnet|opus|auto]`

| Model | Use for |
|-------|---------|
| `haiku` | Formatting, linting, renames, boilerplate |
| `sonnet` | Standard development, analysis (default) |
| `opus` | Architecture decisions, complex reasoning |

```bash
/model-switch auto     # let Claude analyse the task and recommend
```

### `/session-sync [save|load|status]`

```bash
/session-sync save      # commit state.json + session_handover.md + push
/session-sync load      # pull from git and restore state on this machine
/session-sync status    # show what's committed, what's dirty, which device last saved
```

### `/morning-brief`

Fetches today's AI/ML news from configured RSS feeds. Auto-generated once per day on session start.

Edit `config/morning_brief.json` to add/remove feeds:

```json
{
  "feeds": [
    { "name": "My Feed", "url": "https://example.com/rss", "emoji": "🔗" }
  ],
  "max_items_per_feed": 3,
  "max_age_hours": 24,
  "fallback_max_age_hours": 120
}
```

Default feeds: The Rundown AI · VentureBeat AI · MIT Tech Review AI · Ars Technica · Google DeepMind Blog · Anthropic News · OpenAI Blog · Import AI

Requires `pip install feedparser`. If not installed, the auto hook skips silently.

---

## Hooks reference

All hooks fire automatically — you never call them manually.

| Hook event | Script | When it fires | What it does |
|------------|--------|--------------|--------------|
| `SessionStart` | `auto_init_project.sh` | First open of any new project | Auto-bootstraps `session_handover.md` + `state.json` |
| `SessionStart` | `session-start.sh` | Every new session | Injects date, git branch, task summary, budget status |
| `SessionStart` | `morning-brief-auto.sh` | First session each day | Generates daily AI news brief silently |
| `UserPromptSubmit` | `usage-sentinel.sh` | Before every prompt | Tracks usage; injects warnings at 70/80/85/92% |
| `PreCompact` | `pre-compact.sh` | Before any compaction | Saves handover + state (merged), commits to git |
| `PostCompact` | `post-compact.sh` | After any compaction | Re-injects task state so Claude retains context |
| `Stop` | `extract-state-on-stop.sh` | After every response (async) | Heuristically extracts next_action and active task |
| `Stop` | `usage-tracker.py` | After every response (async) | Records rate limit %, context %, cost to `daily-usage.json` |
| `Stop` | `stop.sh` | After every response | Updates `state.json` with timestamp and stop reason |
| `SessionEnd` | `session-end.sh` | When Claude Code closes | Git commits all session state files |
| `PreToolUse` (Bash) | `guard-dangerous.sh` | Before any bash command | Blocks `rm -rf /`, production config writes |
| `PostToolUse` (Edit/Write) | `track-changes.sh` | After every file edit | Logs modified files to `state.json` |
| `PostToolUseFailure` | `post-tool-failure.sh` | When any tool call fails | Logs error to `tool-failures.jsonl` + `state.json` |
| `SubagentStart/Stop` | `subagent-lifecycle.sh` | Subagent lifecycle | Tracks delegated work in `subagents.jsonl` |
| `Notification` | `notify.sh` | On notifications | Cross-platform desktop notification |
| `PermissionRequest` | `auto-approve-permissions.sh` | Permission dialogs | Auto-approves safe context file writes |

### PreCompact — what gets saved

Every compaction triggers a full save sequence:

1. **Merge** `state.json` (preserves `session_start_time`, `last_tool_failure`, all existing fields)
2. **Regenerate** `session_handover.md` from current conversation state
3. **Update** `CLAUDE.md` active-work section
4. **Git commit** all session files so `session_sync` can push them

### Usage sentinel — auto-save escalation

| Threshold | Action |
|-----------|--------|
| 70% | Soft note: "Consider /handover + /session-sync save" |
| 80% | Reminder injected into context |
| 85% | Directive: Claude runs save sequence before responding |
| 92% | Urgent: Claude saves immediately, then notifies you |

Each threshold fires once per session (sentinel files prevent repeated injections).

---

## Cross-device workflow

```bash
# ── Before switching device or subscription ──────────────────────────────────
/session-sync save

# ── On the new device, after git pull ────────────────────────────────────────
git pull origin main
bash scripts/session_sync.sh --load
claude
/context-health    # verify everything loaded
/handover          # review what was in progress
```

Works across: Office Windows ↔ Home Mac ↔ Linux · Claude Pro ↔ Max ↔ API billing

---

## Status line

Live status displayed at the bottom of the Claude Code terminal:

```
[sonnet] ctx:41% 5h:34% turns:12 cost:$0.00 | branch:main task:implementing auth
```

Updates after every turn. Reads from `.claude/session/state.json` and `.claude/session/usage-forecast.json`.

---

## Configuration

### `config/plugin_settings.json`

Global plugin behaviour — controls auto-activation and per-feature toggles:

```json
{
  "auto_activate_new_repos": true,
  "features": {
    "session_tracking":  true,
    "usage_sentinel":    true,
    "morning_brief":     false,
    "tool_failure_log":  true,
    "subagent_tracking": true
  },
  "skip_repos": []
}
```

### `config/usage_budget.json`

```json
{
  "subscription_type": "pro",
  "subscriptions": {
    "api": { "daily_budget_usd": 10.00 }
  },
  "thresholds": {
    "warn_pct": 70,
    "pre_save_pct": 80,
    "auto_save_pct": 85,
    "critical_pct": 92
  }
}
```

### Environment variables

Set in Claude Code settings under `"env"`, or export in your shell:

| Variable | Default | Description |
|----------|---------|-------------|
| `CEK_SUBSCRIPTION_TIER` | `pro` | Subscription tier |
| `CEK_TOKEN_WARN_PCT` | `70` | Context % at which to warn |
| `CEK_TOKEN_CRITICAL_PCT` | `85` | Context % at which to auto-save |
| `CEK_MODEL_HAIKU` | `claude-haiku-4-5-20251001` | Haiku model ID |
| `CEK_MODEL_SONNET` | `claude-sonnet-4-6` | Sonnet model ID |
| `CEK_MODEL_OPUS` | `claude-opus-4-7` | Opus model ID |

---

## Session state files

| File | Description | Committed |
|------|-------------|-----------|
| `.claude/session/state.json` | Active task, phase, next action, compact count | Yes |
| `.claude/session/daily-usage.json` | Per-day cost, tokens, turns, peak % | Yes |
| `.claude/session/usage-forecast.json` | Latest forecast: status, turns-to-warn, ETA | Yes |
| `.claude/session/turn-ledger.jsonl` | Per-turn log of extracted next_action hints | Yes |
| `.claude/session/tool-failures.jsonl` | Failed tool calls (tool, error, path, timestamp) | Yes |
| `.claude/session/subagents.jsonl` | Subagent invocations (type, description, lifecycle) | No |
| `session_handover.md` | Structured task handover (human-readable) | Yes |
| `CLAUDE.md` | Living project context document | Yes |

---

## File structure

```
context-engineering-kit/
├── .claude-plugin/
│   ├── plugin.json                  ← plugin manifest (name, version, metadata)
│   └── marketplace.json             ← marketplace listing metadata
├── hooks/
│   └── hooks.json                   ← Desktop/plugin hook wiring (${CLAUDE_PLUGIN_ROOT})
├── skills/                          ← plugin-format skills (context-engineering-kit:*)
│   └── */SKILL.md
├── agents/
│   ├── context-updater.md
│   └── session-scribe.md
├── docs/
│   └── index.html                   ← GitHub Pages landing page
│
├── .claude/                         ← CLI standalone config
│   ├── settings.json                ← CLI hook wiring + env config
│   ├── statusline.sh                ← status bar
│   ├── hooks/                       ← all hook scripts (shared by both modes)
│   ├── skills/                      ← CLI standalone skills (short names)
│   └── rules/                       ← auto-loaded rules
│
├── scripts/
│   ├── find_python.sh               ← Python 3 resolver (python3 → python → py)
│   ├── auto_init_project.sh         ← bootstraps new repos on SessionStart
│   ├── generate_session_handover.py
│   ├── update_context_files.py
│   ├── session_sync.sh
│   ├── usage-tracker.py
│   └── morning_brief.py
│
├── config/
│   ├── plugin_settings.json         ← auto-activation toggle + feature flags
│   ├── usage_budget.json
│   ├── model_thresholds.json
│   ├── rate_limits.json
│   └── morning_brief.json
│
├── setup.sh                         ← one-command CLI standalone setup
├── CLAUDE.md                        ← living context doc (auto-maintained)
└── session_handover.md              ← live task state (auto-generated)
```

---

## Recommended daily workflow

```
Session start
  → Claude Code opens
  → auto_init_project.sh fires (bootstraps if new project)
  → session-start.sh fires (date, git, task injected automatically)
  → /context-health      — verify everything is wired
  → /handover            — review what was in progress

During work
  → usage-sentinel.sh tracks usage silently on every prompt
  → /token-status        — check usage at any time
  → /model-switch haiku  — drop to Haiku for routine tasks

Approaching limit (auto-triggered at 80%+)
  → sentinel injects save reminder / directive automatically
  → /compact-smart       — smarter compaction to extend session
  → pre-compact.sh fires automatically, saves + commits everything

Session end
  → /session-sync save   — push state to git
  → session-end.sh commits automatically on close

Resuming on another device
  → git pull
  → bash scripts/session_sync.sh --load
  → claude → /context-health → /handover
```

---

## Platform notes

| Platform | Notes |
|----------|-------|
| macOS | Full support — `bash setup.sh` |
| Linux | Full support — `bash setup.sh` |
| Windows (Git Bash) | `bash.exe setup.sh`; use `claude.cmd` not `claude` |
| Windows (no `python3`) | `scripts/find_python.sh` auto-detects `python` and `py.exe` |
| CI/CD | Hooks run headlessly; GitHub Actions handle state validation |

---

## Stack-specific starter files

The `examples/` directory contains ready-made `CLAUDE.md` snippets for common project
types. Copy the relevant file into your project root (or paste sections into your
global `~/.claude/CLAUDE.md` to apply them across all matching projects).

| Example | What it covers |
|---------|---------------|
| [`examples/fullstack-web/CLAUDE.md`](examples/fullstack-web/CLAUDE.md) | CORS + proxy config for every major frontend/backend combo, `.env` hygiene, testing checklist |
| [`examples/bioinformatics-ngs/CLAUDE.md`](examples/bioinformatics-ngs/CLAUDE.md) | NGS pipeline context, ACMG classification rules, genomics token hygiene |

### Full-stack web: why this example exists

CORS errors are the single most common failure mode when Claude scaffolds a
frontend + backend app. The example encodes four fixes that must happen together
and are routinely left as TODOs:

1. Frontend uses relative `/api/…` paths — no hardcoded `localhost` URLs.
2. Dev server proxy wired in the first response (Vite / Next.js / CRA snippets included).
3. Backend CORS middleware with working code for Express, FastAPI, Django, and Go.
4. `ALLOWED_ORIGINS` env var pattern so production origins are never hardcoded.

**Quickest way to use it globally** (applies to all your web projects):

```bash
# Append the CORS section to your global CLAUDE.md
cat examples/fullstack-web/CLAUDE.md >> ~/.claude/CLAUDE.md
```

Or copy the whole file into a specific project:

```bash
cp examples/fullstack-web/CLAUDE.md ~/projects/my-app/CLAUDE.md
# Then customise the Architecture and Key file paths sections
```

---

## Adding a custom skill

```bash
mkdir -p .claude/skills/my-skill
cat > .claude/skills/my-skill/SKILL.md << 'EOF'
---
name: my-skill
description: What this skill does
user-invocable: true
---

# My Skill
[Instructions for Claude here]
EOF
```

Then in Claude Code: `/my-skill`

---

*context-engineering-kit v2.5.0 — Built for multi-device, multi-subscription Claude Code workflows.*
