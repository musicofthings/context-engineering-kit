# SOTA coding-tool compatibility review — September 2026

Review date: 2026-09-13
Kit version: 2.7.0 (`.claude-plugin/plugin.json`, `CEK_VERSION`)
Reviewed at: `b8598db` (main, in sync with `origin/main`)

Runtimes checked against their **live** specs, not cached docs:

| Runtime | Source consulted |
|---|---|
| Claude Code | `docs.anthropic.com/en/docs/claude-code/hooks`, `.../skills` |
| Cursor | `cursor.com/docs/hooks` |
| Codex CLI | `learn.chatgpt.com/docs/hooks` |
| Claude API model IDs | bundled `claude-api` skill model table |
| Grok Build | **not verified** — no authoritative public hook spec located |

The repo's own gates (`generate_runtime_hooks.py --check`, `check_sync.sh`,
`ruff`, `bash -n`) all pass. Every finding below is something those gates do
not cover.

---

## P0 — actively breaks the host tool

> **R-001, R-002 and R-003 are fixed** as of this commit. Their entries are kept
> below as the record of what was wrong and why the fix takes the shape it does.

### R-001 `WorktreeCreate` replaces git worktree creation and returns no path
_Status: **fixed** — entry removed from `hooks/hooks.json`; rationale recorded in
`docs/runtime-capability-matrix.md` so it is not re-added for observability._

`hooks/hooks.json` wires `WorktreeCreate` → `.claude/hooks/native-event-log.sh`.

Per the Claude Code hooks reference:

> Configuring a WorktreeCreate hook replaces that default git behavior […]
> The hook must return the path to the created worktree directory. Claude Code
> uses this path as the working directory for the isolated session.
> Command hooks: print the path as the last non-empty line.

`native-event-log.sh` is an explicit no-op logger — it writes JSONL and prints
nothing to stdout. Any install of this plugin therefore disables `git worktree`
creation and supplies no replacement path, breaking:

- `claude --worktree`
- subagents with `isolation: "worktree"`
- background sessions that Claude Code isolates in their own worktree

`.worktreeinclude` also stops being processed.

This is the exact case the v3.0.0 planning notes marked **rejected**
("WorktreeCreate — replaces default git behaviour"); commit `162663f` wired it
anyway. This repo itself runs seven worktrees.

**Fixed:** the `WorktreeCreate` entry is gone. `WorktreeRemove` is kept — its
output is discarded by Claude Code, so a logging handler is harmless there.

### R-002 Codex adapter swallows the blocking exit code
_Status: **fixed** in `.codex/hooks/run.sh`._

`.codex/hooks/run.sh`:

```bash
run_pipe() {
  local script="$1"
  printf '%s' "$INPUT" | cek_run_hook "$script" || true
}
```

`guard-dangerous.sh` blocks with exit `2`. Codex honours exit `2` on
`PreToolUse` ("You can also use exit code 2 and write the blocking reason to
stderr"), but `|| true` converts it to `0`, so **the dangerous-command guard
cannot block anything on Codex**. Same pattern on every `||  true` in the
`session-start` / `stop` / `subagent-*` chains.

Previously filed as CEK-CODEX-002 (2026-07-31).

**Fixed:** `preserve_decision` propagates exit `2` verbatim and ends the chain;
any other non-zero status is logged as a broken hook and fails open, so a kit bug
cannot wedge a Codex session. Verified with fixtures — a destructive command exits
`2` with the reason on stderr, a safe command exits `0`, a missing hook exits `0`
with a fail-open log. The identical `|| true` pattern is still present in
`.grok/hooks/run.sh`; Grok's exit-code contract is unverified, so that one is
left alone pending a spec.

### R-003 `AGENTS.md` is not in the repository
_Status: **fixed** — renamed in git; the wider content split stays open as CEK-CODEX-006._

```
$ git ls-files | grep -i '^agents.md'
agents.md

$ ls -li AGENTS.md agents.md
158607230 … AGENTS.md
158607230 … agents.md      # same inode
```

`core.ignorecase=true` and APFS make `AGENTS.md` *look* present locally; it is
the same file as `agents.md`. On any case-sensitive filesystem — Linux, CI,
cloud agents — a clone yields `agents.md` only, and Codex finds no instruction
file. Its content also points exclusively at `CLAUDE.md`, `.claude/`, and
Claude slash commands.

Previously filed as CEK-CODEX-006.

**Fixed:** `git mv agents.md AGENTS.md` (via a temp name, since `core.ignorecase`
makes the direct rename a no-op), with references updated in `CLAUDE.md:26`,
`.claude/settings.json` (`Write`/`Edit` rules) and
`.claude/hooks/auto-approve-permissions.sh` (`APPROVED_PATHS`). `AGENTS.md` now
carries the Codex invocation syntax (`$context-engineering-kit:<skill>` / `/skills`),
the hook-trust requirement, and the 3-second `SessionEnd` cap.

**Still open:** the deeper half of CEK-CODEX-006 — splitting durable,
runtime-neutral project context from Claude-specific instructions, and making
`init-cek` preserve an existing `AGENTS.md` instead of writing `CLAUDE.md` only.

---

## P1 — silently dead or factually wrong

### R-004 `bash_path` is not a settings key

`.claude/settings.json:3`. Not in the settings schema; ignored.

### R-005 Stale and inconsistent Claude model IDs

| File | Value | Current |
|---|---|---|
| `.claude/settings.json:47` | `claude-opus-4-8` | `claude-opus-5` |
| `config/model_thresholds.json:14,30,46` | `claude-opus-4-8` | `claude-opus-5` |
| `README.md:651` | `claude-opus-4-8` | `claude-opus-5` |
| `skills/model-switch/SKILL.md:32`, `skills/token-status/SKILL.md:74` | `claude-opus-4-8` | `claude-opus-5` |

`claude-opus-4-8` is still served, so nothing errors — the kit just steers
every "architecture task" onto the previous generation.

Separately, Haiku is spelled two ways across the repo — `claude-haiku-4-5`
(`.claude/settings.json:45`) and `claude-haiku-4-5-20251001`
(`config/model_thresholds.json`, two SKILL.md files). Pick one.

No tier exists for the Fable 5.1 class of model at all.

### R-006 `config/rate_limits.json` token budgets are both dead and wrong

```json
"claude_opus":   { "context_window": 200000, "warn_at_pct": 65, … }
"claude_sonnet": { "context_window": 200000, … }
```

Opus 5 and Sonnet 5 have **1M** context windows; only Haiku 4.5 is 200K.

Nothing reads these values — `usage-tracker.py` reads only
`subscription_tier` from this file, and the live thresholds come from
`config/usage_budget.json` and `CEK_TOKEN_*` env vars. So this is dead config
carrying wrong numbers, while `CLAUDE.md` and the README present it as the
tunable budget file. Either wire it up with correct windows or delete the
`token_budgets` block.

### R-007 `FileChanged` hook cannot fire, and reads a variable that does not exist

`hooks/hooks.json`:

```json
"matcher": "config/model_thresholds.json|config/usage_budget.json|config/plugin_settings.json",
"command": "bash -c 'echo \"[cek] Config file changed: $CLAUDE_FILE_PATH …\" >&2'"
```

Per the hooks reference, the `FileChanged` matcher is split on `|` and each
segment is registered as a **literal filename in the working directory** — so
this watches three files literally named `config/model_thresholds.json` etc.,
which never exist. The second filter pass matches against the changed file's
**basename**, so even a correct watch list would not match a path segment.

`CLAUDE_FILE_PATH` appears nowhere in the hooks documentation. The changed
file's absolute path arrives as `file_path` on stdin (`FILE=$(jq -r .file_path)`).

**Fix:** matcher `model_thresholds.json|usage_budget.json|plugin_settings.json`;
read `file_path` from stdin.

### R-008 `SessionEnd` timeout is ignored for plugin installs

`hooks/hooks.json` sets `"timeout": 30` on `session-end.sh`. From the hooks
reference:

> SessionEnd hooks have a default timeout of 1.5 seconds. […] The overall
> budget is automatically raised to the highest per-hook timeout configured in
> settings files, up to 60 seconds. **Timeouts set on plugin-provided hooks
> don't raise the budget.**

`session-end.sh` runs handover generation plus a git commit inside 1.5 s. It
worked while `.claude/settings.json` also declared the hook (project scope
*does* raise the budget); Phase 0 removed that block, so the behaviour now
differs between "repo is open in Claude Code" and "plugin is installed".

**Fix:** move the expensive work to `Stop` with `async: true`, leave
`SessionEnd` a fast marker write, and document
`CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`.

### R-009 Skill frontmatter uses keys that do not exist

The Agent Skills frontmatter reference lists `name`, `description`,
`when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`,
`user-invocable`, `allowed-tools`, and others. It does **not** list:

- `auto-invoke-when:` — used by 8 of 9 skills (every one except `init-cek`).
  All of that trigger text is dropped; only `description` reaches the listing.
  The correct key is `when_to_use`, which is appended to `description`.
- `args:` — `skills/init-cek/SKILL.md:5`. The correct key is `argument-hint`.

Worth verifying before the next release: the same page notes that for the
claude.ai / Cowork skill-upload path, frontmatter outside the spec's six
allowed fields (`allowed-tools`, `compatibility`, `description`, `license`,
`metadata`, `name`) is a **hard error**, not an ignored key. `README.md:10`
advertises the zip "for Cowork or Desktop Plugin upload".

### R-010 `agents/precompact-extract-agent.md` is an orphan

Its frontmatter block contains only `#` comments — no `name:`, no
`description:` — so it never registers as a subagent. It documents itself as
serving a `type: agent` PreCompact hook, which no longer exists in the wiring.
The `.claude/agents/` copy was deleted in Phase 0; this one was left behind.

### R-011 Codex config emits three unsupported events and an out-of-range timeout

Codex's current event set is: `PreToolUse`, `PermissionRequest`, `PostToolUse`,
`PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStart`,
`SubagentStop`, `Stop`, `Interrupt`, `SessionStart`, `SessionEnd`.

`.codex/hooks.json` (generated by `scripts/generate_runtime_hooks.py`) declares
`PostToolUseFailure`, `StopFailure`, and `Notification` — none of which exist.

It also sets `"timeout": 30` on `SessionEnd`. Codex: *"`SessionEnd` and
`Interrupt` use `1` second by default and support up to `3` seconds."*

`Interrupt` is a Codex event the kit does not use and arguably should
(recording an interrupted turn is squarely a handover concern).

### R-012 Codex `Stop` rejects the kit's plain-text output

Codex: *"`Stop` expects JSON on `stdout` when it exits `0`. Plain text output
is invalid for this event."* Same for `SubagentStop`.

`scripts/usage-tracker.py:389` prints a plain-text `[usage] … WARNING …` line
to stdout whenever the forecast is WARNING or CRITICAL, and it runs inside the
Codex `stop` chain. Exactly when the sentinel matters most, Codex will mark the
hook run failed. Route that line to stderr, or emit `systemMessage` JSON.

### R-013 No `.codex-plugin/plugin.json`

Codex loads plugin hooks from `.codex-plugin/plugin.json` (`hooks` entry, or a
default `hooks/hooks.json`) and exports `PLUGIN_ROOT` / `PLUGIN_DATA` alongside
`CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA` for compatibility. The kit ships no
Codex manifest, so the only Codex install path is cloning the repo into the
target project. CEK-CODEX-001; still open.

---

## P2 — stale documentation and unused capability

### R-014 The capability matrix contradicts the live specs *and* the repo's own review

`docs/runtime-capability-matrix.md` marks `PostToolUseFailure`, `StopFailure`,
and `Notification` as ✅ for Codex. `docs/codex-cli-compatibility-review.md`
(CEK-CODEX-003) says they are unsupported, and the live docs confirm it.
`scripts/cek_runtime.sh:cek_runtime_supports` encodes the same wrong table, so
`cek_runtime_supports` returns 0 for events Codex will never send.

### R-015 The Codex review's `async` finding is now out of date

CEK-CODEX-011 states Codex *"parses this key without executing command hooks
asynchronously."* The current docs describe a full background-hook
implementation — `"async": true`, up to 8 concurrent per session, output
delivered at the next safe point — with one carve-out: *"`SessionEnd` hooks
always run synchronously, even when `async` is `true`."* Update that finding
rather than removing `async` from the generator.

### R-016 Cursor `sessionStart` can inject context; the adapter throws it away

`.cursor/hooks/on-session-start.sh` sends the whole kit banner to stderr with
the comment *"Cursor's sessionStart does not inject hook stdout."* True for raw
stdout — but `sessionStart` supports a JSON output shape:

```json
{ "env": { "KEY": "value" }, "additional_context": "<added to the conversation's initial system context>" }
```

Cursor users currently get none of the session handover context that Claude
Code users get. The `env` field would also carry `CEK_*` into every later hook
in the session.

### R-017 Cursor `preCompact` already supplies the numbers the kit calls "unknown"

Cursor's `preCompact` input carries `trigger`, `context_usage_percent`,
`context_tokens`, `context_window_size`, `message_count`, `messages_to_compact`,
`is_first_compaction`. The kit stamps `ctx=unknown%` into snapshot commits.
This is a free, exact context-percentage source on one of the four runtimes.

### R-018 Unused Cursor hooks worth adopting

| Hook | Why it fits this kit |
|---|---|
| `afterAgentResponse` | Gives `text` = the assistant's final message, removing the transcript grepping in `extract-state-on-stop.sh` |
| `beforeReadFile` | Would actually enforce `.claude/rules/security.md` ("never read `.env`"), with `failClosed: true` |
| `preToolUse` / `postToolUse` | Generic tool hooks — the kit only uses the shell- and file-specific ones |
| `workspaceOpen` | Fires outside any agent session; the natural place for project bootstrap |
| `beforeMCPExecution` | MCP-call governance, none today |

Note also that Cursor loads third-party (Claude Code) hooks. With
`.claude/settings.json` now hook-free the double-fire risk is closed, but an
installed plugin's `hooks/hooks.json` may still be picked up — worth an
explicit test, same as the Grok case already documented.

### R-019 Version numbers do not match the shipped behaviour

`plugin.json`, `marketplace.json`, `CEK_VERSION`, the session banner, and the
README all say **2.7.0**. `README.md:327`, `README.md:474`,
`docs/runtime-capability-matrix.md`, `.grok/hooks/run.sh:5`, and
`.grok/hooks/README.md:8` all describe behaviour *"since v3.0.0"*. The Phase 0
change (`a63b71e`, marked `feat!:`) was breaking for anyone opening the repo
directly rather than installing the plugin, and shipped without a bump.

### R-020 CI gaps

`.github/workflows/cek-quality.yml` runs `ubuntu-latest` only. Missing:

- `windows-latest` (the kit explicitly targets no-admin Windows —
  `docs/windows-no-admin.md`, `scripts/schedule_morning_brief.ps1`)
- `shellcheck` (only `bash -n` runs today; it would have caught R-002)
- a Codex/Cursor **event allow-list** check — `generate_runtime_hooks.py
  --check` only verifies the generated files match the generator, so a wrong
  event list stays green (and does: R-011)
- a case-sensitivity check for `AGENTS.md` (R-003)
- a model-ID freshness check (R-005)
- a `SessionEnd` timeout bound per runtime (R-008, R-011)

### R-021 Other unused current-spec surface

- Claude hook fields never used: `if` (conditional hooks), `once`,
  `statusMessage`, `watchPaths`, `additionalContextLimit` (Codex).
- Claude events never wired: `Elicitation` / `ElicitationResult`,
  `MessageDisplay` (deliberately rejected — keep it that way).
- `native-event-log.sh` runs `set -euo pipefail` and then
  `mkdir -p "$STATE_DIR"`. If `resolve_state_dir.sh` fails to source (it is
  guarded with `|| true`), `STATE_DIR` is unbound and `set -u` aborts the
  script with a non-zero status that `|| true` cannot catch. Harmless on
  logging-only events; it compounds R-001 and sits on `PreModelSwitch`, which
  can block.

---

## Suggested order

1. **R-001** — one line to delete, removes a break for every plugin user.
2. **R-002, R-003** — Codex security and discovery; both small.
3. **R-007, R-008, R-009, R-004, R-010** — the silently-dead Claude wiring.
4. **R-005, R-006** — model IDs and context windows; mechanical.
5. **R-011, R-012, R-013** + **R-014, R-015** — Codex event set, then make the
   matrix and `cek_runtime.sh` generated from one capability map.
6. **R-016, R-017, R-018** — Cursor is the weakest adapter and has the most
   free capability available.
7. **R-019, R-020** — version bump and the CI gates that keep the above fixed.
