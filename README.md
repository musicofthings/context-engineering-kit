# context-engineering-kit

> **Automated context preservation for Claude Code, Cursor, Grok, and Codex — across sessions, devices, and subscriptions.**

Hooks, skills, and scripts that keep your context alive through compaction, device switches, and subscription changes. **One logic core** under `.claude/hooks/`; thin adapters for each runtime.

Works in **Claude Cowork**, **Claude Code Desktop**, **Claude Code CLI**, **Cursor IDE**, **Grok Build**, and **Codex**.

🌐 **[Landing page & full docs →](https://musicofthings.github.io/context-engineering-kit/)**  
📦 **[Download plugin zip (v2.7.0) →](https://github.com/musicofthings/context-engineering-kit/releases/latest)** — for Cowork or Desktop Plugin upload  
📐 **[Runtime capability matrix →](docs/runtime-capability-matrix.md)**

---

## What's new in v2.7.0

- **Real auto-save at usage thresholds (Phase A).** At 85% / 92%, the kit **writes** `session_handover.md` (and optionally `session_sync --save`) — it no longer only injects “please run /handover” for the model to obey.
- **Subagent-safe lifecycle (Phase B).** Mid-flight subagents are tracked with ids + grace window; SessionStart preserves active counts and snapshots state before a usage-window reset instead of zeroing children mid-flight.
- **Multi-runtime adapters (Phase C).** Shared `scripts/cek_runtime.sh`; portable `.codex/hooks.json` + `.grok/hooks/cek-hooks.json` (no machine-absolute paths); Cursor `_common.sh` uses the same bootstrap. Grok wires `PermissionDenied`; Claude settings use `${CLAUDE_PROJECT_DIR:-.}`.
- **Real usage signal preference.** `usage-tracker` mirrors rate-limit / forecast metrics into `state.json`; `usage-sentinel` prefers fresh `usage-forecast.json` (`rl_5h_pct`) over wall-clock session age.
- **CI quality gate.** `.github/workflows/cek-quality.yml` runs syntax checks, `generate_runtime_hooks.py --check`, `check_sync`, and Phase A/B/C evals on push/PR.
- **Evals.** `scripts/eval_usage_lifecycle.sh` (29 scenarios) and `scripts/eval_phase_c.sh` (28 checks).

## What's new in v2.6.0

- Five new hook events (`StopFailure`, `InstructionsLoaded`, `FileChanged`, session-title on `SessionStart`).
- Prompt caching strategy documented for CLAUDE.md stable prefix.
- PermissionRequest schema, sentinel WARN path, statusLine path, and Actions pin fixes.
- Default models: Sonnet 5 / Opus 4.8.

## What's new in v2.5.0

- Cursor IDE adapters, unified `resolve_state_dir.sh`, worktree `state.scope`, lock-guarded writes, Agent SDK resume capture, `hook_once` de-dupe, usage clock fix, hooks flowchart docs.

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
| Dangerous commands allowed silently | `guard-dangerous.sh` blocks `rm -rf /`, `rm -rf .`, quoted `$HOME`, and production config writes |
| New repos need manual context-kit setup | `auto_activate_new_repos` bootstraps any new git project automatically |
| Worktrees fragment/clobber session state | All hooks resolve state through one helper; `state.scope` controls branch vs. worktree behaviour, writes are lock-guarded |
| Can't find the exact session to `--resume` | SessionStart records the SDK `session_id` + transcript path; handover prints the exact resume command and the cwd caveat |
| Using Cursor instead of Claude Code | `.cursor/hooks.json` adapters exec the same kit scripts — state tracking, dangerous-command guard, compaction snapshots all work |
| Usage window resets mid-subagent | Phase B preserves running counts (grace); auto-saves handover before reset |
| Model ignores “run /handover” injects | Phase A **executes** handover at 85%/92% — not model-dependent |
| Using Grok or Codex | Portable `.grok/` / `.codex/` adapters dispatch into the same `.claude/hooks` core |

---

## Installation

Choose the path that matches your agent runtime:

| | Claude Cowork | Claude Code Desktop | Claude Code CLI | Cursor | Grok Build | Codex |
|--|--------------|---------------------|-----------------|--------|------------|-------|
| **How** | Upload zip | Upload zip | Clone + `setup.sh` | Clone (`.cursor/`) | Clone; `/hooks-trust` | Clone (`.codex/`) |
| **Skills** | `/context-engineering-kit:*` | `/context-engineering-kit:*` | `/handover` etc. | Chat / scripts | Skills if mirrored | Scripts |
| **Hooks** | Skills only | ✅ Full | ✅ Full | ✅ Adapters | ✅ `.grok/hooks` (+ optional Claude settings) | ✅ `.codex/hooks` |
| **Best for** | Chat context | Always-on desktop | Terminal project | Cursor agents | Grok TUI | Codex CLI |

Full event support table: [`docs/runtime-capability-matrix.md`](docs/runtime-capability-matrix.md).

> **Cowork vs. Claude Code:** the same zip works for both Cowork and Claude Code Desktop because the plugin format is identical. The difference is what runs — Cowork executes the **skills** (`/handover`, `/token-status`, etc.) but doesn't run the **hooks** (which need a shell environment). Claude Code runs both.

---

## Option A — Download the plugin zip (Cowork or Desktop)

The easiest path. One zip works in both **Claude Cowork** and **Claude Code Desktop**.

### Step 1 — Get the zip

**Either** download the prebuilt zip from the [latest GitHub release](https://github.com/musicofthings/context-engineering-kit/releases/latest):

```
context-engineering-kit-2.7.0.zip
```

**Or** build it from source (requires Python 3):

```bash
git clone https://github.com/musicofthings/context-engineering-kit.git
cd context-engineering-kit
python scripts/package_plugin.py
# → writes context-engineering-kit-2.7.0.zip in the project root
```

The packaging script reads the version from `.claude-plugin/plugin.json` and excludes git history, runtime session state, audit logs, and caches automatically.

### Step 2a — Upload to Claude Cowork

1. Open Cowork → **Settings** → **Plugins** (or **Skills** → **Add plugin**)
2. Click **Upload plugin** → select `context-engineering-kit-2.7.0.zip`
3. Confirm install — the eight skills appear as `/context-engineering-kit:*` commands
4. Type `/context-engineering-kit:handover` in any conversation to use it

> Cowork installs only enable the **skills** layer (the slash commands). Hooks, auto-save, usage sentinel, and git-sync are no-ops in Cowork because there's no shell environment. For the full hook-driven experience, use Claude Code (Option B or C below).

### Step 2b — Upload to Claude Code Desktop

1. Open **Claude Code Desktop** → click **Customize** (bottom-left gear) → **Upload Plugin**
2. Select `context-engineering-kit-2.7.0.zip` and restart Claude Code
3. Verify in any project:
   ```
   /context-engineering-kit:context-health
   ```

### Prerequisites for Desktop (not needed for Cowork)

- Claude Code desktop app (latest)
- `jq`, `bash`, `git` on PATH
- `python3` or `python` (v3.x) — the kit auto-detects the right command
- `feedparser` for morning brief: `pip install feedparser` (optional)

### Skills in Cowork / Desktop mode

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
    "auto_execute_handover": true,
    "morning_brief":     false,
    "tool_failure_log":  true,
    "subagent_tracking": true
  },
  "skip_repos": ["/path/to/repo-to-skip"],
  "state": { "scope": "auto" }
}
```

Set `auto_activate_new_repos: false` to disable entirely, or add individual project paths to `skip_repos`. See [Branch & worktree state scope](#branch--worktree-state-scope) for `state.scope`. At 85%/92% usage, `auto_execute_handover` writes `session_handover.md` automatically (see `config/usage_budget.json` → `auto_save`).

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

## Option B — Claude Code CLI (standalone, per-project, full hooks)

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

## Option D — Cursor IDE (project hooks)

Use this if you work in **Cursor** rather than Claude Code. The kit ships a
`.cursor/hooks.json` manifest and thin adapter scripts that translate Cursor's
hook events and stdin JSON into the shape the kit's existing `.claude/hooks/*.sh`
scripts expect — so you get the same `state.json`, `session_handover.md`, git
snapshots, and dangerous-command guard without maintaining two codebases.

### Prerequisites

- [Cursor](https://cursor.com) (latest — hooks require a recent build)
- `bash`, `git`, `jq` on PATH
- `python3` or `python` (v3.x) — for `usage-tracker.py` and handover generation

### Install steps

```bash
# 1. Clone into your project (or add as a submodule)
git clone https://github.com/musicofthings/context-engineering-kit.git my-project
cd my-project

# 2. Make hook scripts executable (adapters + kit scripts)
chmod +x .cursor/hooks/*.sh .claude/hooks/*.sh scripts/*.sh

# 3. Open the project in Cursor — hooks load automatically from .cursor/hooks.json
#    Cursor watches hooks.json and reloads on save; restart Cursor if they don't appear.
```

No separate plugin upload is needed. The `.cursor/` directory is part of the
repo and is picked up as **project hooks** when you open the folder in Cursor.

### Verify hooks are firing

1. Open **Cursor Settings → Hooks** (or the **Hooks** output channel).
2. Start a new Agent session — you should see `on-session-start.sh` run.
3. Edit a file — `track-edit.sh` should append the path to `state.json`'s
   `changed_files`.
4. Check `.claude/session/state.json` — `last_updated` and `session_start_time`
   should advance on session start.

### What runs under Cursor

| Cursor event | Adapter | Kit script | What it does |
|--------------|---------|------------|--------------|
| `sessionStart` | `on-session-start.sh` | `session-start.sh` | Init state, clear sentinels, record session metadata |
| `sessionEnd` | `on-session-end.sh` | `session-end.sh` | Git-commit session state on close |
| `beforeSubmitPrompt` | `on-prompt.sh` | `usage-sentinel.sh` | Log usage %, arm threshold sentinels |
| `beforeShellExecution` | `guard-shell.sh` | `guard-dangerous.sh` | Block destructive shell (exit 2 = deny) |
| `afterFileEdit` | `track-edit.sh` | `track-changes.sh` | Append edited paths to `changed_files` |
| `stop` | `on-stop.sh` | extract → usage-tracker → stop | Heuristic state extract + usage log |
| `postToolUseFailure` | `on-tool-failure.sh` | `post-tool-failure.sh` | Log failures to `tool-failures.jsonl` |
| `subagentStart/Stop` | `on-subagent.sh` | `subagent-lifecycle.sh` | Track delegated subagent work |
| `preCompact` | `on-precompact.sh` | `pre-compact.sh` | Handover + CLAUDE.md + git snapshot |

**Not mapped to Cursor** (Claude Code only): `PostCompact` context re-injection,
`PermissionRequest` auto-approve, `Notification` desktop alerts. Dangerous-command
blocking uses Cursor's `beforeShellExecution` instead of Claude Code's `PreToolUse`.

### Cursor vs Claude Code — same state, different runtime

Both runtimes write to the same `state.json` via `resolve_state_dir.sh`. You can
switch between Cursor and Claude Code on the same repo and pick up continuity
from `session_handover.md` and git-committed state. Skill slash commands
(`/handover`, `/token-status`, etc.) are Claude Code features — in Cursor, ask
the Agent to read `session_handover.md` or run the underlying scripts manually.

Full event-mapping diagram: [`docs/hooks-flowchart.md` §7](docs/hooks-flowchart.md).  
Capability matrix (Claude / Cursor / Codex / Grok): [`docs/runtime-capability-matrix.md`](docs/runtime-capability-matrix.md).

---

## Option E — Grok Build

Grok discovers project hooks under `.grok/hooks/` when the folder is trusted.

```bash
git clone https://github.com/musicofthings/context-engineering-kit.git my-project
cd my-project
# In Grok: open the project, then:
#   /hooks-trust
# Confirm Hooks tab shows cek-hooks.json entries
```

- Entry: `.grok/hooks/cek-hooks.json` → `.grok/hooks/run.sh` → `.claude/hooks/*`
- Grok may also load `.claude/settings.json`, which declares **no hooks** since v3.0.0 — `.grok/hooks/cek-hooks.json` is the only Grok hook source (usage sentinels still guard threshold saves)
- Uses `PermissionDenied` (not `PermissionRequest`); see capability matrix
- Optional: disable Claude hook scan in `~/.grok/config.toml` with `[compat.claude] hooks = false` if you want a single source

---

## Option F — Codex

```bash
git clone https://github.com/musicofthings/context-engineering-kit.git my-project
cd my-project
# Run Codex with this project as cwd so relative hook commands resolve
```

- Entry: `.codex/hooks.json` → `.codex/hooks/run.sh` → `.claude/hooks/*`
- **Portable only** — regenerate with `python scripts/generate_runtime_hooks.py` (never commit absolute machine paths)
- Verify: `python scripts/generate_runtime_hooks.py --check` and `bash scripts/check_sync.sh`


---

## Skills reference

| Skill | Cowork / Desktop | CLI | Description |
|-------|------------------|-----|-------------|
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

> **Dual runtime:** Claude Code reads `.claude/settings.json` (CLI) or
> `hooks/hooks.json` (plugin). Cursor reads `.cursor/hooks.json` and routes
> through adapters in `.cursor/hooks/*.sh`. Both exec the same scripts in
> `.claude/hooks/`. See [Option D](#option-d--cursor-ide-project-hooks) for the
> Cursor event mapping.

### Claude Code events

| Hook event | Script | When it fires | What it does |
|------------|--------|--------------|--------------|
| `SessionStart` | `auto_init_project.sh` | First open of any new project | Auto-bootstraps `session_handover.md` + `state.json` |
| `SessionStart` | `session-start.sh` | Every new session | Injects date, git branch, task summary, budget status |
| `SessionStart` | `morning-brief-auto.sh` | First session each day | Generates daily AI news brief silently |
| `UserPromptSubmit` | `usage-sentinel.sh` | Before every prompt | Tracks usage; injects warnings at 70/80/85/92% |
| `PreCompact` | `pre-compact.sh` | Before any compaction | Saves handover + state (merged), commits to git |
| `PostCompact` | `post-compact.sh` | After any compaction | Re-injects task state so Claude retains context |
| `Stop` | `extract-state-on-stop.sh` | After every response | Heuristically extracts next_action and active task |
| `Stop` | `usage-tracker.py` | After every response | Records rate limit %, context %, cost to `daily-usage.json` |
| `Stop` | `stop.sh` | After every response | Updates `state.json` with timestamp, stop reason, session id |
| `SessionEnd` | `session-end.sh` | When Claude Code closes | Git commits all session state files |
| `PreToolUse` (Bash) | `guard-dangerous.sh` | Before any bash command | Blocks `rm -rf /`, `rm -rf .`, quoted `$HOME`, production writes |
| `PostToolUse` (Edit/Write) | `track-changes.sh` | After every file edit | Logs modified files to `state.json` |
| `PostToolUseFailure` | `post-tool-failure.sh` | When any tool call fails | Logs error to `tool-failures.jsonl` + `state.json` |
| `SubagentStart/Stop` | `subagent-lifecycle.sh` | Subagent lifecycle | Tracks delegated work in `subagents.jsonl` |
| `Notification` | `notify.sh` | On notifications | Cross-platform desktop notification |
| `PermissionRequest` | `auto-approve-permissions.sh` | Permission dialogs | Auto-approves context-file writes + kit scripts (echoes back the firing event) |

> The three `Stop` hooks run **sequentially in a single hook entry** (not async) so they can't race on `state.json`. Every hook that mutates `state.json` does so through `state_write()` in `scripts/resolve_state_dir.sh`, which takes a portable lock (`flock`, or a `mkdir` spinlock on macOS) and writes atomically — concurrent writers field-merge instead of clobbering. Since v3.0.0, `hooks/hooks.json` is the **single hook source** (the repo's `.claude/settings.json` declares no hooks), so nothing fires twice. Permission/deny rules in `.claude/settings.json` use the canonical `Read(./.env)` / `Write(./session_handover.md)` path-anchored form.

> **`guard-dangerous.sh` is defense-in-depth, not a hard guarantee.** It matches
> the *literal text* of a command against a fixed regex list, so it catches the
> common destructive spellings (`rm -rf /`, `rm -rf .`, quoted `$HOME`, reordered
> flags) but **cannot** stop a command that hides its target behind indirection —
> e.g. `X=/; rm -rf "$X"`, a variable, a subshell, or a script it invokes. Treat
> it as a safety net that reduces accidents, not a sandbox. Real isolation must
> come from OS-level permissions and running in a disposable environment.

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
`session_start_time` is preserved across resume and within-window restarts so the
clock measures the real rolling window, not wall-clock since the last SessionStart.

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

> **Sync through git, not through a shared filesystem.** The workflow above is
> safe because each device writes `state.json` locally and hands off via
> `git commit` / `git pull` — the writes never overlap in time. Do **not** point
> two machines at one `state.json` living on a shared cloud drive (iCloud,
> Dropbox, OneDrive, NFS) at the same time. The concurrency lock uses `flock` on
> Linux/Git-Bash and a `mkdir` spinlock on macOS (which has no `flock`), and
> those two mechanisms lock different paths — a Linux writer and a macOS writer
> would not see each other's lock and could corrupt the file. This is documented
> at the lock in `scripts/resolve_state_dir.sh`.

---

## Branch & worktree state scope

Every hook resolves where `state.json` lives through one shared helper,
`scripts/resolve_state_dir.sh`, so the path can never diverge between hooks.
Behaviour is controlled by `state.scope` in `config/plugin_settings.json`:

- **Branch flow** (no worktrees — the common case): state is one shared file at
  the repo root, per *project* not per *branch*, so switching branches keeps
  continuity.
- **Worktree flow**: linked worktrees are ephemeral, so by default state is
  redirected to the **main checkout** and survives the worktree being deleted.
  Choose `local` to keep isolated per-worktree state, or `main` to force
  cross-worktree continuity.

Concurrent sessions/worktrees are safe: `state_write()` takes a portable lock
and field-merges, so parallel writers never clobber each other.

If you don't use git worktrees, this is all transparent — leave `state.scope`
at `auto`.

## Session resume (Agent SDK)

The SDK/CLI stores each conversation transcript at
`~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` — **resume is cwd-bound**.
SessionStart and Stop now record the `session_id`, `transcript_path`, and
`session_cwd` into `state.json`, and `/handover` writes a **Commands to Resume**
block with:

- the exact `claude --resume <id>` command,
- the transcript path and computed storage location,
- a warning that a session started in a worktree can only be resumed from that
  same directory (resuming from `main` silently starts a fresh session).

Per the [Agent SDK guidance](https://code.claude.com/docs/en/agent-sdk/sessions),
the robust cross-machine / cross-worktree path is **not** transcript resume —
it's feeding `session_handover.md` into a fresh session as application state,
which is exactly what this kit produces.

A full visual map of every hook, trigger, the state-scope decision tree, the
permission-evaluation flow, and the resume flow lives in
[`docs/hooks-flowchart.md`](docs/hooks-flowchart.md) (Mermaid diagrams).

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
  "skip_repos": [],
  "state": { "scope": "auto" }
}
```

`state.scope` — where session state lives:

| Value | No worktrees (typical) | Worktree users |
|-------|------------------------|----------------|
| `auto` *(default)* | repo root, one shared state | redirect to main checkout (survives worktree deletion) |
| `main` / `repo` / `shared` | repo root (identical) | always main checkout — cross-worktree continuity |
| `local` / `worktree` | repo root (identical) | isolated per-worktree state |

If you don't use git worktrees, all values behave identically and you can ignore this setting.

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
| `CEK_MODEL_SONNET` | `claude-sonnet-5` | Sonnet model ID |
| `CEK_MODEL_OPUS` | `claude-opus-4-8` | Opus model ID |

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
| `.claude/session/state.json.lock` / `.lockd` | Concurrency locks for `state_write()` | No (gitignored) |
| `session_handover.md` | Structured task handover (human-readable) | Yes |
| `CLAUDE.md` | Living project context document | Yes |
| `api_docs.md` | Weekly API-doc snapshot from `fetch_api_docs.py` | No (gitignored) |

> In a git **worktree**, these files resolve to the **main checkout** by
> default (`state.scope: auto`) so they survive the worktree being removed.

> **`api_docs.md` is gitignored on purpose.** Running `scripts/fetch_api_docs.py`
> locally produces a file that `git status` will not show — this is expected, not
> a bug. The file is committed **only** by the `sync-api-docs` CI workflow, which
> force-adds it (`git add -f`) onto a bot-authored PR branch for review. Don't try
> to commit a locally generated copy.

---

## File structure

```
context-engineering-kit/
├── .cursor/                         ← Cursor project hooks
│   ├── hooks.json
│   └── hooks/                       ← adapters → .claude/hooks (via cek_runtime.sh)
├── .codex/                          ← Codex portable hooks (generated)
│   ├── hooks.json
│   └── hooks/run.sh
├── .grok/hooks/                     ← Grok Build hooks (generated)
│   ├── cek-hooks.json
│   └── run.sh
├── .claude-plugin/
│   ├── plugin.json                  ← version + marketplace metadata
│   └── marketplace.json
├── hooks/hooks.json                 ← Claude plugin hook wiring
├── skills/  agents/                 ← plugin skills + agents
├── docs/
│   ├── index.html                   ← GitHub Pages landing page
│   ├── hooks-flowchart.md
│   └── runtime-capability-matrix.md ← Claude / Cursor / Codex / Grok events
├── .claude/                         ← shared logic + CLI settings
│   ├── settings.json
│   ├── hooks/                       ← **single logic core** for all runtimes
│   ├── skills/  rules/
│   └── statusline.sh
├── scripts/
│   ├── cek_runtime.sh               ← multi-runtime bootstrap
│   ├── cek_auto_save.sh             ← Phase A handover execute helpers
│   ├── find_python.sh / find_jq.sh
│   ├── resolve_state_dir.sh         ← state path + lock-guarded state_write()
│   ├── generate_runtime_hooks.py    ← regenerate .codex/.grok JSON
│   ├── generate_session_handover.py
│   ├── usage-tracker.py
│   ├── eval_usage_lifecycle.sh      ← Phase A/B scenarios
│   ├── eval_phase_c.sh              ← multi-runtime wiring checks
│   └── check_sync.sh
├── config/                          ← plugin_settings, usage_budget, …
├── .github/workflows/cek-quality.yml
├── setup.sh
├── CLAUDE.md
└── session_handover.md
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
  → 80%: soft reminder inject
  → 85%/92%: kit WRITES session_handover.md (Phase A), not model-only
  → prefers real rate-limit % from usage-forecast when fresh
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
| macOS | Full support — `bash setup.sh`; Cursor hooks via `.cursor/hooks.json` |
| Linux | Full support — `bash setup.sh`; Cursor hooks via `.cursor/hooks.json` |
| Windows (Git Bash) | `bash.exe setup.sh`; use `claude.cmd` not `claude` |
| Windows (no `python3`) | `scripts/find_python.sh` auto-detects `python` and `py.exe` |
| Cursor IDE | Project hooks in `.cursor/` — no plugin upload; open repo in Cursor |
| Grok Build | `.grok/hooks/cek-hooks.json`; trust project with `/hooks-trust` |
| Codex | `.codex/hooks.json` relative paths; cwd = project root |
| CI/CD | `cek-quality.yml` runs evals + `generate_runtime_hooks --check` |

### Verify / release checks

```bash
bash scripts/check_sync.sh
bash scripts/eval_phase_c.sh
bash scripts/eval_usage_lifecycle.sh
python scripts/package_plugin.py    # → context-engineering-kit-2.7.0.zip
```

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

*context-engineering-kit v2.7.0 — Multi-runtime context preservation for Claude Code, Cursor, Grok, and Codex.*
