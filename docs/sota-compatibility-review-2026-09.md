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

> **R-004 through R-013 are fixed.** R-014 went with them, since correcting the
> Codex event set meant correcting the matrix and `cek_runtime.sh` in the same
> change. Entries are kept as the record of what was wrong.

### R-004 `bash_path` is not a settings key
_Status: **fixed** — key removed._

`.claude/settings.json:3`. Not in the settings schema; ignored.

### R-005 Stale and inconsistent Claude model IDs
_Status: **fixed** — `claude-opus-5` everywhere; Haiku normalised to the undated
`claude-haiku-4-5`. No Fable tier added — that is a feature, not a correction._

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
_Status: **fixed** — windows corrected (Opus 5 / Sonnet 5 to 1M, Haiku stays
200K) and the block is now labelled REFERENCE ONLY with a pointer to where the
live thresholds actually come from. Kept rather than deleted: the numbers are
what you need to reason about burn rate by hand._

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
_Status: **fixed** — matcher is bare basenames; the inline `echo` is replaced by
`.claude/hooks/config-changed.sh`, which reads `file_path` from stdin, appends to
`config-audit.log`, and reports on stderr. Verified end to end._

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
_Status: **fixed** — the work moved out of the hook rather than fighting the budget._

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

**Fixed**, though not the way the v3.0.0 notes proposed. Moving the work to
`Stop` with `async: true` would have run a handover regeneration and a git commit
on *every turn*, which is worse than the bug. Instead the body moved to
`scripts/session_finalize.sh`, and `session-end.sh` detaches it (`setsid`, or
`nohup` on BSD/macOS) and returns immediately — so the work outlives the 1.5s
budget instead of racing it. `CEK_SESSION_END_SYNC=1` runs it inline, which is
how the eval suite exercises the side effects; `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`
is documented as the other escape hatch. The ignored `timeout: 30` is gone from
the manifest. This also fixes Codex, which caps `SessionEnd` at 3s and always
runs it synchronously.

Not addressed here: `SessionEnd` also fires on `/clear` and `/resume`, so the
kit still commits on those. Gating on `reason` is a separate change.

### R-009 Skill frontmatter uses keys that do not exist
_Status: **fixed** — `auto-invoke-when` → `when_to_use` in 8 skills, `args` →
`argument-hint` (plus a real `when_to_use`) in `init-cek`._

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
_Status: **fixed** — deleted._

Its frontmatter block contains only `#` comments — no `name:`, no
`description:` — so it never registers as a subagent. It documents itself as
serving a `type: agent` PreCompact hook, which no longer exists in the wiring.
The `.claude/agents/` copy was deleted in Phase 0; this one was left behind.

### R-011 Codex config emits three unsupported events and an out-of-range timeout
_Status: **fixed** — and the gate that let it through is closed._

Codex's current event set is: `PreToolUse`, `PermissionRequest`, `PostToolUse`,
`PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStart`,
`SubagentStop`, `Stop`, `Interrupt`, `SessionStart`, `SessionEnd`.

`.codex/hooks.json` (generated by `scripts/generate_runtime_hooks.py`) declares
`PostToolUseFailure`, `StopFailure`, and `Notification` — none of which exist.

It also sets `"timeout": 30` on `SessionEnd`. Codex: *"`SessionEnd` and
`Interrupt` use `1` second by default and support up to `3` seconds."*

**Fixed:** the three events are Grok-only in the generator, and `SessionEnd` now
takes a per-runtime timeout (Codex 3, Grok 30). More importantly the *gate* is
fixed: `generate_runtime_hooks.py` gained `RUNTIME_EVENTS`, an authoritative
per-runtime allow-list, and generation now raises if the event table names an
event a runtime lacks. `--check` could never have caught this — it only proved
the generated files matched the generator. `RUNTIME_TIMEOUT_MAX` does the same
for timeout ceilings. `scripts/cek_runtime.sh` and the capability matrix were
corrected to match (that was R-014).

Still unused: `Interrupt`, a Codex event the kit arguably should wire — recording
an interrupted turn is squarely a handover concern.

### R-012 Codex `Stop` rejects the kit's plain-text output
_Status: **fixed** — the sentinel line goes to stderr; the `/token-status` report
path keeps stdout._

Codex: *"`Stop` expects JSON on `stdout` when it exits `0`. Plain text output
is invalid for this event."* Same for `SubagentStop`.

`scripts/usage-tracker.py:389` prints a plain-text `[usage] … WARNING …` line
to stdout whenever the forecast is WARNING or CRITICAL, and it runs inside the
Codex `stop` chain. Exactly when the sentinel matters most, Codex will mark the
hook run failed. Route that line to stderr, or emit `systemMessage` JSON.

### R-013 No `.codex-plugin/plugin.json`
_Status: **fixed** — with one trap worth naming._

Codex loads plugin hooks from `.codex-plugin/plugin.json` (`hooks` entry, or a
default `hooks/hooks.json`) and exports `PLUGIN_ROOT` / `PLUGIN_DATA` alongside
`CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA` for compatibility. The kit shipped no
Codex manifest, so the only Codex install path was cloning the repo into the
target project. CEK-CODEX-001.

**The trap:** that default matters here. *"If your plugin stores hooks at
`./hooks/hooks.json`, you don't need a `hooks` entry; Codex checks that default
file automatically."* In this repo `hooks/hooks.json` **is the Claude manifest** —
29 events including `InstructionsLoaded`, `FileChanged`, `Pre/PostModelSwitch`,
`TaskCreated`, `TeammateIdle`. A Codex manifest without an explicit `hooks` entry
would have pointed Codex straight at it.

**Fixed:** `.codex-plugin/plugin.json` declares `hooks: "./hooks/codex-hooks.json"`
and `skills: "./skills/"`. The generator emits `hooks/codex-hooks.json` as a third
target, with commands resolved under `${CLAUDE_PLUGIN_ROOT}` rather than repo-relative.
`package_plugin.py` now refuses to build if the manifests are missing, disagree on
name/version, or if the Codex manifest would inherit `hooks/hooks.json`;
`check_sync.sh` asserts the same. Codex also reads the repo's existing
`.claude-plugin/marketplace.json` as a legacy-compatible marketplace, so no second
marketplace file is needed.

Fixed in passing: `EXCLUDE_FILES` in `package_plugin.py` matches whole relative
paths, so the bare `.DS_Store` entry only ever caught the one at the repo root —
nested copies shipped in every zip. Moved to `EXCLUDE_GLOBS`, which matches on
basename (124 → 119 files).

**Still open** from CEK-CODEX-001: nothing verifies a Codex install end to end.
That needs the CI work in R-020.

---

## P2 — stale documentation and unused capability

> **R-015 through R-021 are fixed.** Fixing R-018 surfaced four defects that
> were not in the original pass; they are recorded as R-022..R-025 below.

### R-014 The capability matrix contradicts the live specs *and* the repo's own review
_Status: **fixed** alongside R-011._

`docs/runtime-capability-matrix.md` marks `PostToolUseFailure`, `StopFailure`,
and `Notification` as ✅ for Codex. `docs/codex-cli-compatibility-review.md`
(CEK-CODEX-003) says they are unsupported, and the live docs confirm it.
`scripts/cek_runtime.sh:cek_runtime_supports` encodes the same wrong table, so
`cek_runtime_supports` returns 0 for events Codex will never send.

### R-015 The Codex review's `async` finding is now out of date
_Status: **fixed** — `docs/codex-cli-compatibility-review.md` carries a status block correcting it and listing the closed IDs._

CEK-CODEX-011 states Codex *"parses this key without executing command hooks
asynchronously."* The current docs describe a full background-hook
implementation — `"async": true`, up to 8 concurrent per session, output
delivered at the next safe point — with one carve-out: *"`SessionEnd` hooks
always run synchronously, even when `async` is `true`."* Update that finding
rather than removing `async` from the generator.

### R-016 Cursor `sessionStart` can inject context; the adapter throws it away
_Status: **fixed** — the adapter returns `{"additional_context": …}` on stdout and mirrors the banner to stderr._

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
_Status: **fixed** — `pre-compact.sh` resolves the percentage from `.context_usage_percent`, then `.context_percent`, then the kit's own `usage-forecast.json`, and only then gives up._

Cursor's `preCompact` input carries `trigger`, `context_usage_percent`,
`context_tokens`, `context_window_size`, `message_count`, `messages_to_compact`,
`is_first_compaction`. The kit stamps `ctx=unknown%` into snapshot commits.
This is a free, exact context-percentage source on one of the four runtimes.

### R-018 Unused Cursor hooks worth adopting
_Status: **fixed** for the two that serve existing kit goals; the rest stay listed as unused._

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
_Status: **fixed** — everything reads 3.0.0 and the README has a v3.0.0 section._

`plugin.json`, `marketplace.json`, `CEK_VERSION`, the session banner, and the
README all say **2.7.0**. `README.md:327`, `README.md:474`,
`docs/runtime-capability-matrix.md`, `.grok/hooks/run.sh:5`, and
`.grok/hooks/README.md:8` all describe behaviour *"since v3.0.0"*. The Phase 0
change (`a63b71e`, marked `feat!:`) was breaking for anyone opening the repo
directly rather than installing the plugin, and shipped without a bump.

### R-020 CI gaps
_Status: **fixed** — shellcheck, a Windows job, and four new semantic gates._

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
_Status: **fixed** for the `set -u` hazard; the unused surface is catalogued, not adopted._

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

---

## Found while fixing (not in the original pass)

These four surfaced while implementing R-018. Each is fixed in the same commit.

### R-022 `next_action` extraction could not match the most common phrasing
_Status: **fixed**._

`extract-state-on-stop.sh` guarded and extracted with `next[: ]` — a bracket
expression matching exactly **one** separator character. "Next: I will run the
tests" has a colon *and* a space, so it never matched, and every such turn fell
through to the `check session_handover.md` default. The kit's headline feature
was silently inert for its most natural input. Now `next[: ]+`.

### R-023 A trailing newline made every payload look non-empty
_Status: **fixed**._

Reading the assistant text as `jq -r '…' | tr '\n' ' '` turns jq's trailing
newline into a space, so an absent field yields `" "`, not `""`. Every
`[ -z "$RESPONSE" ]` fallback below it was therefore dead — including the
transcript fallback this review had just added. Trimmed before the test.

### R-024 `source` of a missing file aborts despite `|| true`
_Status: **fixed**._

`source` is a POSIX special builtin: under `set -e` a missing file exits the
shell outright and the trailing `|| true` does not catch it. Three hooks used
that pattern (`native-event-log.sh`, `session-start.sh`, and the new
`config-changed.sh`), so a wrong `CLAUDE_PLUGIN_ROOT` made them exit non-zero
rather than degrade. On `native-event-log.sh` that matters: it sits on
`PreModelSwitch`, which can block. Each now tests for the file first.

This is the deeper cause of the `set -u` hazard filed as R-021 — the guard there
never ran because the script had already exited.

### R-025 The `next_action` assertion could not fail, and one placeholder was sticky
_Status: **fixed**._

The eval's assertion ended in `|| ok "next_action=$(…)"`, so it passed whatever
happened — which is how R-022 survived. It now uses `bad`, and two assertions
were added for source precedence. Separately, `read session_handover.md
(auto-saved)` was missing from the list of placeholders a real extraction may
overwrite, so a single threshold auto-save froze `next_action` for the rest of
the session.