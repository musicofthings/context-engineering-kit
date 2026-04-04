# context-engineering-kit

> **Automated context preservation for Claude Code — across sessions, devices, and subscriptions.**

A drop-in Claude Code plugin that wires hooks, skills, and scripts so your context never disappears — whether you're hitting the 5-hour Pro window, switching from a Windows office machine to a home Mac, or moving between Claude Pro, Max, and API billing.

---

## What problem does it solve?

| Problem | This kit's solution |
|---------|-------------------|
| Context window fills up, Claude forgets everything | `PreCompact` hook saves full state before compaction |
| Can't resume where you left off after `/compact` | `PostCompact` hook re-injects critical context after every compaction |
| Switching devices loses task state | `session_sync.sh` commits state to git — pull and resume anywhere |
| Switching Pro → Max → API loses continuity | Same git repo, same `session_handover.md`, same state |
| No visibility into token/cost burn rate | `/token-status` and `/usage-forecast` with live window metrics |
| Tedious manual model switching | `/model-switch auto` analyses your task and picks Haiku/Sonnet/Opus |
| Context rot from undifferentiated compaction | `/compact-smart` preserves code, decisions, and task state at higher fidelity |
| Hard to hand work off to a fresh session | `/handover` generates a structured `session_handover.md` in one command |
| Dangerous commands allowed silently | `guard-dangerous.sh` blocks `rm -rf /` and production config writes |

---

## Architecture overview

```
Every prompt           ─── usage-sentinel.sh ──► inject warning if near limit
Every response turn    ─── extract-state-on-stop.sh ──► update state.json (async)
                       ─── usage-tracker.py ──► update usage-forecast.json (async)
Before compaction      ─── pre-compact.sh ──► generate session_handover.md
After compaction       ─── post-compact.sh ──► re-inject critical context
Session start          ─── session-start.sh ──► inject date, git state, task summary
Session end            ─── session-end.sh ──► git commit state files
File edits             ─── track-changes.sh ──► log to state.json
Bash commands          ─── guard-dangerous.sh ──► block destructive patterns

State lives in:
  .claude/session/state.json          ← committed to git (cross-device sync)
  session_handover.md                 ← structured task state (human-readable)
  CLAUDE.md                           ← living project context (auto-updated)
```

---

## Install as a Claude Code plugin (recommended)

The kit is packaged as a Claude Code plugin. This is the recommended way to use it — hooks, skills, and agents load automatically without any manual file copying.

### Prerequisites

- Claude Code latest: `npm install -g @anthropic-ai/claude-code`
- `jq`, `python3`, `bash`, `git` (same as standalone)
- `feedparser` for morning-brief: `pip install feedparser`

### Option A — Load locally with `--plugin-dir`

Test or use the plugin without installing it globally:

```bash
git clone https://github.com/musicofthings/context-engineering-kit.git
claude --plugin-dir ./context-engineering-kit
```

All hooks fire automatically. Skills are available as:

```
/context-engineering-kit:handover
/context-engineering-kit:token-status
/context-engineering-kit:compact-smart
/context-engineering-kit:model-switch
/context-engineering-kit:session-sync
/context-engineering-kit:context-health
/context-engineering-kit:usage-forecast
/context-engineering-kit:morning-brief
```

### Option B — Install to user scope (available in all projects)

```bash
claude plugin install context-engineering-kit@your-marketplace
```

Or install directly from a local directory:

```bash
claude plugin install --scope user --plugin-dir ./context-engineering-kit
```

### Option C — Install to project scope (shared with team via git)

```bash
claude plugin install context-engineering-kit@your-marketplace --scope project
```

This writes to `.claude/settings.json` — commit it and everyone who clones the repo gets the plugin.

### Verify the plugin loaded

```
/context-engineering-kit:context-health
```

### Configure subscription type after install

Edit `config/usage_budget.json` inside the plugin directory, or set the environment variable:

```bash
export CEK_SUBSCRIPTION_TIER=max   # pro | max | api | team
```

### Skill namespacing

Plugin skills are prefixed with `context-engineering-kit:` to avoid conflicts with other plugins. If you prefer short names (`/handover`, `/token-status`), use the **standalone** install below instead.

---

## Standalone install (single project, short skill names)

Use this if you want `/handover` instead of `/context-engineering-kit:handover`, or if you're customising the kit for a specific project.

### Requirements

- [Claude Code](https://docs.anthropic.com/claude-code) (latest) — `npm install -g @anthropic-ai/claude-code`
- `bash` — built into Mac/Linux; use Git Bash on Windows
- `git`
- `jq` — for JSON parsing in hooks (`brew install jq` / `apt install jq`)
- `python3` — for handover and usage tracking scripts

---

## Installation

### 1. Clone or fork

```bash
git clone https://github.com/YOUR_USER/context-engineering-kit.git my-project
cd my-project
```

> **Tip:** Fork first if you want to customise skills and push changes to your own repo.

### 2. Run setup

```bash
# Mac / Linux
bash setup.sh

# Windows (Git Bash, no-admin)
bash.exe setup.sh
```

`setup.sh` will:
- Check dependencies (`jq`, `python3`, `git`, `claude`)
- Make all hook scripts executable
- Initialise `state.json` with your machine's hostname
- Set `subscription_type` in `config/usage_budget.json` based on a prompt
- Confirm hooks are wired via `.claude/settings.json`

### 3. Set your subscription type

Edit `config/usage_budget.json`:

```json
{
  "subscription_type": "pro",   // "pro" | "max" | "api" | "team"
  ...
}
```

For API billing, also set `daily_budget_usd` under `subscriptions.api`.

Alternatively, set the environment variable (no file edit needed):

```bash
export CEK_SUBSCRIPTION_TIER=max
```

### 4. Launch Claude Code

```bash
claude          # Mac / Linux
claude.cmd      # Windows no-admin
```

### 5. Verify everything is wired

```
/context-health
```

You should see all 8 checks passing. If any hooks are not executable, the output will suggest the fix.

---

## Slash commands (skills)

Type any of these directly in the Claude Code prompt:

### `/token-status`
Shows current context window usage, burn rate, model recommendation, and subscription window progress.

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

---

### `/handover`
Generates a complete, structured `session_handover.md` capturing active task, progress, blockers, remaining work, architecture decisions, and exact resume commands.

Run this before:
- Switching devices
- Ending a session
- Hitting the context limit
- Handing work to a colleague

```
✅ session_handover.md updated — 7 items captured
Run: bash scripts/session_sync.sh --save  to commit to git
```

---

### `/compact-smart`
Relevance-scored compaction. Unlike `/compact` which summarises everything uniformly, this:
1. Writes `session_handover.md` first (preserves task state)
2. Tags high-value content (code written, decisions, error solutions) to preserve verbatim
3. Tags low-value content (abandoned exploration, verbose output) to summarise aggressively
4. Runs `/compact` with a custom context-preserving prompt

Use instead of `/compact` whenever you're mid-task and don't want to lose code or decisions.

---

### `/model-switch [haiku|sonnet|opus|auto]`

Switch models manually or let `auto` analyse your current task:

| Model | Use for |
|-------|---------|
| `haiku` | Formatting, linting, renames, boilerplate, simple transforms |
| `sonnet` | Standard development, analysis, pipelines, debugging (default) |
| `opus` | Architecture decisions, complex reasoning, edge-case analysis |

```bash
/model-switch haiku    # switch to Haiku for fast formatting work
/model-switch opus     # switch to Opus for architecture decisions
/model-switch auto     # let Claude analyse the task and recommend
```

---

### `/session-sync [save|load|status]`

Sync session state to/from git for cross-device and cross-subscription continuity.

```bash
/session-sync save      # commit state.json + session_handover.md to git and push
/session-sync load      # pull from git and restore state on this machine
/session-sync status    # show what's committed, what's dirty, which device last saved
```

---

### `/context-health`

Full audit of all context engineering components:

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
usage tracking     ✅ forecast current

Overall: ✅ HEALTHY
```

Run at session start and after switching devices.

---

### `/usage-forecast`

Detailed daily usage burn rate, cost tracking, and predicted time to subscription limit.

```bash
/usage-forecast   # show current forecast with turns-to-warn and ETA to critical
```

---

### `/morning-brief`

Fetches today's AI/ML news from configured RSS feeds and presents a digest in the terminal. Also saves the brief to `briefs/YYYY-MM-DD.md`.

**Auto-enabled:** the brief is generated automatically on your first session start each day. Claude will notify you it's ready — just type `/morning-brief` to read it. If a brief for today already exists, the hook skips silently.

```bash
/morning-brief                                      # display today's brief
python scripts/morning_brief.py                     # run directly (terminal output only)
python scripts/morning_brief.py --save              # run and save to briefs/YYYY-MM-DD.md
python scripts/morning_brief.py --quiet             # generate file silently (used by auto hook)
```

**Example output:**

```
════════════════════════════════════════════════════════════
  AI Morning Brief — Friday, 04 April 2026 at 07:12 UTC
  Window: last 24h
════════════════════════════════════════════════════════════

  📰  The Rundown AI
  ──────────────────────────────────────────────────
  • Claude 4 Opus sets new reasoning benchmark
    https://...
    Anthropic released... [09:30 UTC]

  💼  VentureBeat AI
  ──────────────────────────────────────────────────
  • OpenAI expands o3 access to Plus users
    https://...

════════════════════════════════════════════════════════════
  12 stories across 5 sources
════════════════════════════════════════════════════════════
```

**Adding or removing RSS feeds** — edit `config/morning_brief.json`:

```json
{
  "feeds": [
    { "name": "My Feed",  "url": "https://example.com/rss", "emoji": "🔗" }
  ],
  "max_items_per_feed": 3,
  "max_age_hours": 24,
  "fallback_max_age_hours": 120,
  "fallback_threshold": 3
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `max_items_per_feed` | `3` | Max stories per source |
| `max_age_hours` | `24` | Only show stories from the last N hours |
| `fallback_max_age_hours` | `120` | Extend window to N hours if fewer than `fallback_threshold` stories found |
| `fallback_threshold` | `3` | Min stories before triggering the extended window |

**Included feeds by default:**
The Rundown AI · VentureBeat AI · MIT Tech Review AI · Ars Technica · Google DeepMind Blog · Anthropic News · OpenAI Blog · Import AI (Jack Clark)

**Dependency:** requires `feedparser` — install once:
```bash
pip install feedparser
```

If `feedparser` is not installed, the auto hook skips silently and prints a one-line install hint to stderr.

---

## Hooks reference

All hooks are wired in `.claude/settings.json` and fire automatically — you never need to call them manually.

| Hook event | Script | When it fires | What it does |
|------------|--------|--------------|--------------|
| `SessionStart` | `session-start.sh` | Every new session | Injects current date, git branch, task summary, budget window status |
| `SessionStart` | `morning-brief-auto.sh` | First session of each day | Generates today's AI news brief silently; notifies Claude it's ready |
| `SessionStart` (compact) | `post-compact.sh` | When resuming a compacted session | Re-injects critical context so Claude knows where it left off |
| `UserPromptSubmit` | `usage-sentinel.sh` | Before every prompt | Tracks time/cost elapsed; injects warnings at 70%, 80%, 85%, 92% of limit |
| `PreCompact` | `pre-compact.sh` | Before any compaction | Generates `session_handover.md`, updates `CLAUDE.md`, appends compact audit log |
| `PostCompact` | `post-compact.sh` | After any compaction | Re-injects `state.json` content so Claude retains task awareness |
| `Stop` | `extract-state-on-stop.sh` | After every response (async) | Heuristically extracts next_action, active task, and phase from response text |
| `Stop` | `usage-tracker.py` | After every response (async) | Records rate limit %, context %, cost, tokens to `daily-usage.json` |
| `Stop` | `stop.sh` | After every response | Updates `state.json` with timestamp and stop reason |
| `SessionEnd` | `session-end.sh` | When Claude Code closes | Git commits all session state files |
| `PreToolUse` (Bash) | `guard-dangerous.sh` | Before any bash command | Blocks `rm -rf /`, production config writes, and other destructive patterns |
| `PostToolUse` (Edit/Write) | `track-changes.sh` | After every file edit | Logs modified file paths to `state.json` |
| `Notification` | `notify.sh` | On Claude Code notifications | Cross-platform desktop notification (macOS, Linux, Windows) |
| `ConfigChange` | inline | On settings change | Appends audit entry to `.claude/config-audit.log` |
| `InstructionsLoaded` | inline | On instructions load | Prints ready message with quick command list |

---

## Usage sentinel — automatic save escalation

`usage-sentinel.sh` fires before every prompt and tracks elapsed time against your subscription window (or cost against your API budget). It injects progressively urgent directives as you approach the limit:

| Threshold | Action |
|-----------|--------|
| 70% | Soft warning: "Consider /handover + /session-sync save" |
| 80% | Reminder injected: "Run /handover soon" |
| 85% | Directive injected: Claude runs `generate_session_handover.py` + `session_sync.sh --save` before responding |
| 92% | Urgent directive: Claude saves immediately, then notifies you the limit is near |

Each threshold only fires once per session (sentinel files prevent repeated injections).

---

## Cross-device workflow

```bash
# ── Before switching device or subscription ──────────────────────────────────
/session-sync save
# or: bash scripts/session_sync.sh --save

# ── On the new device, after git pull ────────────────────────────────────────
git pull origin main
bash scripts/session_sync.sh --load
claude
/context-health   # verify everything loaded correctly
/handover         # review what was in progress
```

Works across:
- Office Windows ↔ Home Mac ↔ Linux
- Claude Pro ↔ Claude Max ↔ API billing
- Any machine that can `git pull`

---

## Status line

The kit includes a live status line displayed at the bottom of the Claude Code terminal:

```
[sonnet] ctx:41% 5h:34% turns:12 cost:$0.00 | branch:main task:implementing auth
```

Fields shown:
- Active model
- Context window % used
- 5-hour rate limit window % used (Pro/Max) or cost % of budget (API)
- Turns this session
- Cost today (USD)
- Current git branch
- Active task from `state.json`

The status line updates after every turn. It reads from `.claude/session/state.json` and `.claude/session/usage-forecast.json`.

---

## Configuration

### `config/usage_budget.json`
Controls subscription type and auto-save thresholds.

```json
{
  "subscription_type": "pro",       // pro | max | api | team
  "subscriptions": {
    "api": {
      "daily_budget_usd": 10.00     // only used when subscription_type = "api"
    }
  },
  "thresholds": {
    "warn_pct": 70,                 // soft warning injection
    "pre_save_pct": 80,             // save reminder injection
    "auto_save_pct": 85,            // auto-save directive injection
    "critical_pct": 92              // urgent save directive
  }
}
```

### `config/rate_limits.json`
Per-model token budgets and subscription tier used by the usage tracker.

```json
{
  "subscription_tier": "pro",       // must match usage_budget.json
  "models": { ... }
}
```

### `config/model_thresholds.json`
Documents context % thresholds at which each model is recommended for `/model-switch auto`.

### `config/morning_brief.json`
RSS feed sources and date range for `/morning-brief`.

### Environment variables (override without editing files)

Set in `.claude/settings.json` under `"env"`, or export in your shell:

| Variable | Default | Description |
|----------|---------|-------------|
| `CEK_VERSION` | `2.4.0` | Kit version (informational) |
| `CEK_TOKEN_WARN_PCT` | `70` | Context % at which to warn |
| `CEK_TOKEN_CRITICAL_PCT` | `85` | Context % at which to auto-save |
| `CEK_MODEL_HAIKU` | `claude-haiku-4-5-20251001` | Haiku model ID |
| `CEK_MODEL_SONNET` | `claude-sonnet-4-6` | Sonnet model ID |
| `CEK_MODEL_OPUS` | `claude-opus-4-6` | Opus model ID |
| `CEK_SUBSCRIPTION_TIER` | `pro` | Subscription tier (overrides config file) |

---

## Session state files

| File | Description | Committed to git |
|------|-------------|-----------------|
| `.claude/session/state.json` | Live session state: active task, phase, next action, changed files | Yes |
| `.claude/session/daily-usage.json` | Per-day usage metrics: cost, tokens, turns, peak % | Yes |
| `.claude/session/usage-forecast.json` | Latest forecast: status, turns-to-warn, ETA | Yes |
| `.claude/session/usage.jsonl` | Per-prompt usage log (append-only) | Yes |
| `.claude/session/turn-ledger.jsonl` | Per-turn next_action extraction log | Yes |
| `session_handover.md` | Structured task handover (human-readable) | Yes |
| `CLAUDE.md` | Living project context document | Yes |

---

## File structure

```
context-engineering-kit/             ← plugin root
├── .claude-plugin/
│   └── plugin.json                  ← plugin manifest (name, version, metadata)
├── hooks/
│   └── hooks.json                   ← plugin hook wiring (uses ${CLAUDE_PLUGIN_ROOT})
├── skills/                          ← plugin-format skills (namespaced as context-engineering-kit:*)
│   ├── token-status/SKILL.md
│   ├── handover/SKILL.md
│   ├── compact-smart/SKILL.md
│   ├── model-switch/SKILL.md
│   ├── session-sync/SKILL.md
│   ├── context-health/SKILL.md
│   ├── usage-forecast/SKILL.md
│   └── morning-brief/SKILL.md
├── agents/                          ← plugin-format agents
│   ├── context-updater.md
│   └── session-scribe.md
│
├── CLAUDE.md                        ← living context doc (auto-maintained)
├── session_handover.md              ← live task state (auto-generated)
├── agents.md                        ← subagent role definitions
├── setup.sh                         ← one-command standalone setup
│
├── .claude/                         ← standalone config (also used by plugin hook scripts)
│   ├── settings.json                ← standalone hook wiring + env config
│   ├── statusline.sh                ← status bar rendered each turn
│   ├── hooks/                       ← event-driven scripts
│   │   ├── pre-compact.sh           ← ⭐ updates all context before compaction
│   │   ├── post-compact.sh          ← re-injects context after compaction
│   │   ├── session-start.sh         ← injects date + state on session open
│   │   ├── stop.sh                  ← per-turn state capture
│   │   ├── extract-state-on-stop.sh ← heuristic next_action extraction (async)
│   │   ├── session-end.sh           ← git commits state on session close
│   │   ├── usage-sentinel.sh        ← usage tracking + auto-save directives
│   │   ├── guard-dangerous.sh       ← blocks destructive bash commands
│   │   ├── track-changes.sh         ← logs file edits to state.json
│   │   ├── morning-brief-auto.sh    ← auto-generates daily brief on session start
│   │   ├── auto-approve-permissions.sh ← auto-approves safe file writes
│   │   └── notify.sh                ← cross-platform desktop notifications
│   ├── skills/                      ← slash commands
│   │   ├── token-status/            ← /token-status
│   │   ├── handover/                ← /handover
│   │   ├── model-switch/            ← /model-switch
│   │   ├── compact-smart/           ← /compact-smart
│   │   ├── session-sync/            ← /session-sync
│   │   ├── context-health/          ← /context-health
│   │   ├── usage-forecast/          ← /usage-forecast
│   │   └── morning-brief/           ← /morning-brief
│   ├── rules/                       ← auto-loaded modular rules
│   │   ├── commit-protocol.md       ← conventional commits, branch strategy
│   │   ├── security.md              ← hard limits, credential hygiene
│   │   └── token-hygiene.md         ← context window best practices
│   ├── subagents/                   ← subagent role definitions
│   │   ├── context-updater.md
│   │   └── session-scribe.md
│   └── session/
│       ├── state.json               ← live session state (committed to git)
│       ├── daily-usage.json         ← usage metrics
│       └── usage-forecast.json      ← latest forecast
│
├── scripts/
│   ├── generate_session_handover.py ← called by pre-compact hook
│   ├── update_context_files.py      ← updates CLAUDE.md sections
│   ├── session_sync.sh              ← cross-device git sync
│   ├── usage-tracker.py             ← Stop hook: records metrics + forecasts
│   ├── fetch_api_docs.py            ← weekly API doc refresh (CI)
│   └── morning_brief.py             ← RSS digest for /morning-brief
│
├── config/
│   ├── usage_budget.json            ← subscription type + thresholds
│   ├── model_thresholds.json        ← model selection thresholds
│   ├── rate_limits.json             ← per-model token budgets
│   ├── api_sources.json             ← API doc sources (weekly CI)
│   └── morning_brief.json           ← RSS feeds for morning-brief
│
├── briefs/                          ← daily morning briefs (gitignored, local only)
│   └── YYYY-MM-DD.md
│
├── examples/
│   └── bioinformatics-ngs/CLAUDE.md ← NGS/VariantGPT example config
│
└── .github/workflows/
    ├── sync-api-docs.yml            ← weekly API doc refresh
    └── session-state.yml            ← validates context files on push
```

---

## Recommended daily workflow

```
Session start
  → Claude Code opens
  → session-start.sh fires automatically (date, git, task injected)
  → /context-health  — verify everything is wired
  → /handover        — review what was in progress

During work
  → usage-sentinel.sh tracks usage silently on every prompt
  → extract-state-on-stop.sh updates state.json after every response
  → /token-status    — check usage at any time
  → /model-switch haiku  — drop to Haiku for routine tasks to save tokens

Approaching limit (auto-triggered at 80%+)
  → sentinel injects save reminder / directive automatically
  → /compact-smart   — smarter compaction to extend session
  → /handover        — generate handover before compacting

Session end
  → /session-sync save  — push state to git
  → session-end.sh commits automatically on close

Resuming on another device
  → git pull
  → bash scripts/session_sync.sh --load
  → claude → /context-health → /handover
```

---

## Adding a new skill

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

## For bioinformatics / genomics projects

Copy the pre-configured example into your project:

```bash
cp examples/bioinformatics-ngs/CLAUDE.md /path/to/your-ngs-project/CLAUDE.md
```

Pre-configured for: VCF/FASTA token hygiene, ACMG criteria, NGS pipeline stages, gnomAD/ClinVar annotation, AWS Batch, GRCh38, Lynch syndrome panels.

Key token hygiene rules from `.claude/rules/token-hygiene.md`:
- Never paste VCF, FASTA, BAM, or log files inline — reference by path
- Extract only error lines from pipeline stdout (saves 80–95% tokens)
- Reference variants by HGVS notation, not raw VCF content
- Never include patient identifiers in session_handover.md

---

## Windows no-admin install

```bash
# In Git Bash:
bash.exe setup.sh

# Use claude.cmd (not claude) to avoid PATH conflicts with desktop app
claude.cmd

# Global npm installs go to %APPDATA%\npm — no admin needed:
npm.cmd install -g @anthropic-ai/claude-code
```

See `docs/windows-no-admin.md` for the complete guide.

---

## Multi-platform notes

| Platform | Notes |
|----------|-------|
| macOS | `bash setup.sh` — full support |
| Linux | `bash setup.sh` — full support |
| Windows (Git Bash) | `bash.exe setup.sh`; use `claude.cmd`; hooks use bash path set in `settings.json` |
| CI/CD | Hooks run headlessly; GitHub Actions handle state validation and API doc sync |

---

## Built-in Claude Code commands (still work normally)

`/compact` `/clear` `/model` `/hooks` `/doctor` `/fast` `/help`

---

*context-engineering-kit v2.4.0 — Built for multi-device, multi-subscription Claude Code workflows.*
