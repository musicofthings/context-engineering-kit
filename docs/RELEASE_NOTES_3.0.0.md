# context-engineering-kit v3.0.0

**Release date:** 2026-09-13  
**Tag:** `v3.0.0`  
**Artifact:** `context-engineering-kit-3.0.0.zip` (build with `python scripts/package_plugin.py`)

A correctness release. Every adapter was re-checked against the **live** Claude
Code, Cursor and Codex specifications rather than a cached snapshot, and all 25
findings from that review are closed. Full write-up:
`docs/sota-compatibility-review-2026-09.md`.

The short version: several load-bearing features were not running. A logging
hook was breaking `git worktree`. The Codex security guard could not block. The
end-of-session handover was being killed by a timeout it could not raise. Eight
skills were dropping their trigger hints. And `next_action` extraction — the
kit's headline feature — could not match the most natural way to write a next
action.

---

## Breaking changes

**1. `hooks/hooks.json` is the only Claude hook source.** The repo's
`.claude/settings.json` no longer declares hooks. Opening this repo directly,
rather than installing it as a plugin, previously double-fired every event —
`SessionStart` ran ten handlers and `Stop` ran `usage-tracker.py` twice per turn,
because Claude Code does not dedupe across plugin and project scope. If you had
copied that block into your own settings, remove it.

**2. `WorktreeCreate` is no longer wired, and must not be re-added.**
Configuring the event *replaces* Claude Code's default `git worktree` behaviour:
the hook has to create the working copy itself and print its path as the last
non-empty line of stdout, and `.worktreeinclude` stops being processed. It was
pointed at a no-op logger that prints nothing, so `claude --worktree`, subagents
with `isolation: "worktree"`, and background sessions all silently broke for
every plugin install. `WorktreeRemove` is the safe half of the pair and stays.

**3. End-of-session work detaches.** `SessionEnd` hooks share a 1.5-second
budget, and a plugin's own `timeout` cannot raise it. The handover and git
commit now live in `scripts/session_finalize.sh`, which `session-end.sh`
detaches before returning. Set `CEK_SESSION_END_SYNC=1` to run it inline.

**4. `agents.md` is now `AGENTS.md`.** It was only ever tracked in lowercase;
`core.ignorecase` made it *look* correct on macOS and Windows while Linux and CI
clones got no `AGENTS.md` at all, so Codex found no instruction file.

---

## Highlights

### Codex is a real target now

- `.codex-plugin/plugin.json` ships, so Codex installs as a plugin instead of
  requiring a clone into the target repo.
- It names `./hooks/codex-hooks.json` **explicitly**. This matters more than it
  looks: Codex falls back to `hooks/hooks.json` when a manifest declares no
  `hooks` entry, and in this repo that file is the *Claude* manifest. Both
  `package_plugin.py` and `check_sync.sh` now refuse to ship the inherited case.
- The adapter propagates blocking exit `2`. A blanket `|| true` was turning it
  into `0`, so `guard-dangerous.sh` could not block anything on Codex.
- `PostToolUseFailure`, `StopFailure` and `Notification` are gone — Codex has
  none of them. `SessionEnd` respects the documented 3-second ceiling.
- The `[usage]` sentinel moved to stderr. Codex treats plain text on a `Stop`
  hook's stdout as invalid, so the hook was being marked failed on exactly the
  turns the sentinel mattered.

### Cursor stops being a second-class adapter

- `sessionStart` returns `{"additional_context": …}`, so Cursor sessions now
  start with the same handover state Claude Code sessions get. The banner was
  previously written to stderr and injected nowhere.
- `preCompact` supplies the real `context_usage_percent`. Snapshots used to be
  stamped `ctx=unknown%` on every runtime.
- `afterAgentResponse` feeds the final assistant text into state extraction.
  Cursor's `stop` payload is only `{status, loop_count}` and its transcript is
  not in the Claude JSONL shape, so extraction was effectively dead there.
- `beforeReadFile` (`failClosed: true`) enforces the `.env` rule from
  `.claude/rules/security.md`. Claude Code gets that from its `deny` rules;
  on Cursor it had been documentation only.

### Silently dead wiring, now live

- **`next_action` extraction.** The pattern was `next[: ]` — a bracket
  expression matching exactly **one** separator character. "Next: I will run the
  tests" has a colon *and* a space, so it never matched, and every such turn fell
  through to the `check session_handover.md` default.
- **`FileChanged`** could not fire. Its matcher is not a path glob: Claude Code
  splits it on `|` and registers each segment as a literal filename, so
  `config/usage_budget.json` watched a file that does not exist. The handler also
  read `$CLAUDE_FILE_PATH`, which is not a variable Claude Code sets.
- **Skill frontmatter.** `auto-invoke-when:` (8 skills) and `args:` are not
  valid keys, so every trigger hint was being discarded. Now `when_to_use` and
  `argument-hint`.
- **Stop state extraction** prefers `last_assistant_message` over the
  transcript. The transcript is written asynchronously and may lag the current
  turn, so reading it could yield the *previous* turn's next action.

### Config and model IDs

- `claude-opus-5` replaces `claude-opus-4-8`; Haiku normalised to the undated
  `claude-haiku-4-5`.
- `rate_limits.json` claimed a 200K window for Opus and Sonnet; both are 1M.
  Corrected, and the block is labelled REFERENCE ONLY — nothing reads it, and
  presenting it as the live budget file was the actual problem.
- `bash_path` removed from settings.json; it is not a settings key.

### Gates that can actually fail

`--check` only proved the generated files matched the generator, so a wrong
event list stayed green indefinitely. Added:

- `RUNTIME_EVENTS` — an authoritative per-runtime allow-list. Generation now
  **raises** rather than emitting an event a runtime does not implement.
- `RUNTIME_TIMEOUT_MAX` — per-runtime timeout ceilings.
- `shellcheck` at `-S warning` (four real findings fixed to get there).
- A `windows-latest` job. The kit explicitly targets no-admin Windows and every
  gate had been Ubuntu-only.
- Semantic gates for `AGENTS.md` casing, manifest/version agreement, the Codex
  hooks-inheritance trap, and stale model IDs.
- The eval's `next_action` assertion ended in `|| ok "…"`, so it passed whatever
  happened — which is how the extraction bug survived. It now uses `bad`.

---

## Upgrade

No migration steps for a normal plugin install. Two things to check if you
customised anything:

1. If you copied the `hooks` block out of `.claude/settings.json`, delete it —
   `hooks/hooks.json` is the single source.
2. If you wired `WorktreeCreate` yourself, unwire it unless your handler really
   does create the worktree and print its path.

## Install

**Plugin zip (Cowork / Desktop):** download `context-engineering-kit-3.0.0.zip`
from this release.

**CLI / Cursor / Grok / Codex:**
```bash
git clone https://github.com/musicofthings/context-engineering-kit.git
cd context-engineering-kit
bash setup.sh   # Claude CLI
# Codex:  /hooks once to review and trust; plugin or project-adapter mode
# Grok:   /hooks-trust after open
# Cursor: open the project in a trusted workspace
```

## Verify
```bash
bash scripts/check_sync.sh
bash scripts/eval_phase_c.sh          # 28 checks
bash scripts/eval_usage_lifecycle.sh  # 29 checks
bash scripts/eval_hooks_smoke.sh      # 64 checks
python scripts/generate_runtime_hooks.py --check
/context-health   # in Claude Code
```

## Docs
- Landing: https://musicofthings.github.io/context-engineering-kit/
- Compatibility review: `docs/sota-compatibility-review-2026-09.md`
- Capability matrix: `docs/runtime-capability-matrix.md`
- Codex review + status: `docs/codex-cli-compatibility-review.md`
- Hooks flowchart: `docs/hooks-flowchart.md`

## Known gaps

Named here rather than left to be rediscovered:

- **Grok is unverified.** No authoritative public hook spec was found, so its
  column in the capability matrix mirrors the Claude schema by inference. The
  same `|| true` that disarmed the Codex guard is still present in
  `.grok/hooks/run.sh`, left alone pending a spec worth checking against.
- `AGENTS.md` is tracked correctly but still points mostly at Claude-specific
  paths and commands. The runtime-neutral content split is open (CEK-CODEX-006).
- `SessionEnd` fires on `/clear` and `/resume` too, so the kit commits on those.
  Gating on `reason` is its own change.
- Codex `Interrupt` is unused, as are Cursor's `preToolUse` / `postToolUse`,
  `beforeMCPExecution`, `afterShellExecution`, `workspaceOpen` and Tab hooks.
- An end-to-end Codex *install* is still not exercised by CI — only the manifest
  and packaging are.
