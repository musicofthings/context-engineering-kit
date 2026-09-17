# context-engineering-kit v3.1.1

**Date:** 2026-09-17
**Tag:** `v3.1.1`
**Artifact:** `context-engineering-kit-3.1.1.zip` (build with `python scripts/package_plugin.py`)

Phase 0 of the [v4.0 universal-runtime plan](PLAN_v4_universal_runtime.md).
Core fixes only — no new runtimes, no behaviour change beyond the fixes. These
land first because every one of them is in the shared logic core, and Gemini
CLI, opencode and the MCP server would each have inherited them.

Upgrading is a drop-in replacement. Nothing in the config format changed.

---

## Fixed

### `session_handover.md` no longer grows on every regeneration

`_extract_section()` captured everything between one `## ` heading and the
next — which includes the `---` separator the template emits after each
section, and, for the decisions table, the two header rows the template prints
*above* the interpolated body. Each regeneration therefore re-emitted the
scaffold it had just read back.

Measured on a clean checkout, four regenerations:

```
round 1: "---" separators=13   decision-header-rows=1   lines=103
round 2: "---" separators=17   decision-header-rows=2   lines=113
round 3: "---" separators=21   decision-header-rows=3   lines=123
round 4: "---" separators=25   decision-header-rows=4   lines=133
```

+10 lines per run, unbounded. The handover regenerates on `PreCompact`, at the
85% and 92% usage thresholds, and at `SessionEnd` — several times a working
day — and the file is re-read into context at every session start. A
token-hygiene tool was spending tokens on its own noise.

There were two separate causes. The scaffold re-capture above, and the *last*
section's capture running to end-of-file and swallowing the template footer,
which was then re-emitted underneath it. Both are fixed, and the strip loops,
so a handover that already accreted several rounds is repaired on the next
write rather than merely frozen. The handover in this repo carried six rounds
and collapsed back on the first regeneration after the fix.

### The handover lock no longer lands in the repo root

`state_lock()` leaves its `.lock` file behind deliberately — unlinking it races
a peer that already holds the inode. But the handover writer took that lock on
the output path, i.e. `session_handover.md.lock` at the **repo root**, where
`.gitignore`'s `.claude/session/*.lock` rule does not reach. Every project the
kit touched grew a permanent untracked file, which is exactly what the
self-ignoring `.claude/session/.gitignore` exists to prevent.

The lock now lives beside `state.json`, inside the directory that is already
ignored twice over. Writing a rule into the host project's root `.gitignore`
was the alternative; this kit does not do that.

### Four writers bypassed the containment guard

`resolve_state_dir.sh` refuses to create kit state outside a real project, and
for `$HOME` / `~/.claude` it additionally removes any stale directory an older
version left. `permission-denied.sh` then ran an unconditional `mkdir -p` and a
bare `>>`, recreating what the guard had just deleted:

```
--- permission-denied.sh leaked: ---
<HOME>/.claude
<HOME>/.claude/session
<HOME>/.claude/session/tool-failures.jsonl
```

`usage-sentinel.sh`, `stop-failure.sh` and `post-tool-failure.sh` had the same
bare-append pattern and were clean only by accident — no `mkdir`, so the
redirect failed against a missing directory and the error was swallowed. All
four now route through `state_append()`.

On the Python side, `state_lock()` `mkdir -p`'d its lock's parent with no guard
at all. `state_update()` checked containment before calling in, but
`usage-tracker.py` and the handover writer did not, so moving the handover lock
under `.claude/session/` surfaced it immediately. `state_lock()` now refuses.

### `StopFailure` recorded every failure as `"unknown"`

The hook read `.failure_type // .error_type`. Neither field appears anywhere in
the `StopFailure` payload. Verified against the hooks reference on 2026-09-17,
the event carries `error` (the type: `rate_limit`, `overloaded`,
`billing_error`, …), optional `error_details`, and optional
`last_assistant_message` — which for this event holds the API error string, not
Claude's output as it does on `Stop`. The hook now reads `error` and
`error_details` and records both, so the rate-limit-frequency signal it exists
to provide actually distinguishes one failure from another.

### `PermissionDenied` ran the wrong handler on Claude Code

`docs/runtime-capability-matrix.md` listed the row as `permission-denied.sh +
native-event-log.sh`; `hooks/hooks.json` wired only the generic logger, so
`.permission_denials` was permanently 0 and denial reasons were never recorded.
The dedicated handler ran on Grok only. It is now wired on both — the payloads
agree on the fields it reads — and the matrix says what the manifest does.

`hookSpecificOutput.retry: true` remains deliberately unused: a context
preservation kit has no basis for second-guessing a permission decision, and
the retry prompt would fire on every denial in auto mode.

### Injected text is factual rather than imperative

The usage-sentinel banners told the model what to say — "Tell the user in one
line…", "Mention \"State auto-saved.\" once". That is the shape prompt-injection
defences are built to distrust, and it arrives through the same channel as
untrusted tool output. The banners now state what happened and leave the
response to the model.

### Cursor sees the compaction banner

`preCompact` on Cursor accepts `{"user_message": …}` and shows it when
compaction fires. The adapter was routing the kit banner to stderr, where only
the Hooks output channel saw it.

---

## Evals

130 → 135. Five new assertions, each negative-controlled (verified to fail when
the bug it covers is reintroduced):

- handover regeneration is idempotent across three runs
- no duplicated decisions table header
- no hook leaks state under `$HOME/.claude` — **all 21 hooks**, checked after
  each one rather than once at the end. The previous test covered a hand-picked
  two, and running the appenders back-to-back masked the leak anyway: the next
  hook's containment cleanup deleted the previous one's.
- the handover writer honours containment
- `state_lock()` honours containment, tested directly rather than through a
  caller that has its own pre-check

---

## Known, unchanged

- `PreCompact` still stamps `ctx=unknown%` into snapshot commit messages on
  Claude Code. `context_percent` is not a field on that event; Cursor supplies
  the real number and is unaffected. Scheduled with the rest of the native-signal
  work, not in this release.
- Cursor remains outside `generate_runtime_hooks.py`'s authoritative allow-list,
  and the per-runtime event table still exists in three hand-synced copies.
  That is Phase 1.
