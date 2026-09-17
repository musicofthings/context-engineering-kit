# context-engineering-kit v3.2.0

**Date:** 2026-09-17
**Tag:** `v3.2.0`
**Artifact:** `context-engineering-kit-3.2.0.zip` (build with `python scripts/package_plugin.py`)

Phase 1 of the [v4.0 universal-runtime plan](PLAN_v4_universal_runtime.md): the
enabling refactor. No new runtimes, no behaviour change — this exists so that
adding the fifth, sixth and seventh runtimes is a table entry plus an adapter,
rather than three hand-edits that can silently disagree.

Codex and Grok configs regenerate **byte-identical** to v3.1.2, and the Cursor
config is semantically identical (formatting and key order only). Drop-in
upgrade.

---

## One registry

The per-runtime event table existed in three places:

| Copy | Covered | Validated anything? |
|---|---|---|
| `RUNTIME_EVENTS` in `generate_runtime_hooks.py` | codex, grok | yes |
| `cek_runtime_supports()` in `cek_runtime.sh` | claude, cursor, codex, grok | no |
| the event table in `runtime-capability-matrix.md` | claude, cursor, codex, grok | no |

Three copies cannot disagree safely, and **Cursor was absent from the only one
that validated anything** — so the guard that caught `.codex/hooks.json`
shipping three events Codex does not have could never fire for Cursor, whose
config was hand-written besides.

There is now exactly one: **`config/runtime_events.json`**. Per runtime it
records the events emitted and what that runtime calls them, payload casing,
async support, timeout defaults and ceilings, which config file to generate —
and a `source` URL with a `verified` date.

The provenance fields are not decoration. The v4 plan's first draft was built on
a January 2026 blog post about Gemini CLI, a product Google had shut off three
months earlier. A capability claim with no date and no URL is a claim nobody can
re-check, and an eval now fails if any runtime is missing either.

Three consumers read the registry and nothing carries a second copy:

- `scripts/generate_runtime_hooks.py` — emits every adapter config **and** the
  matrix table
- `cek_runtime_supports()` — reads it with `jq`, falls back to Python, and
  **fails open** if neither is available. A capability hint that wrongly answers
  "no" silently disables real handlers; a wrong "yes" costs one no-op hook run.
- `docs/runtime-capability-matrix.md` — the event table is now a generated block
  between markers, so the surrounding prose stays hand-written

## Cursor is inside the validation boundary

`.cursor/hooks.json` is generated. One caveat is now encoded rather than relying
on whoever edits the file remembering it: **Cursor's `matcher` is not a
tool-name filter.** On `beforeShellExecution` it matches the command *text*, so
emitting the canonical `"Bash"` matcher there would quietly narrow the
dangerous-command guard to commands containing the literal word "bash". The
generator never emits canonical matchers for Cursor, and an eval asserts the
config contains none.

Cursor's two native hooks with no canonical equivalent — `afterAgentResponse`
and `beforeReadFile` — are declared in the registry's `native_extra` and
generated from an explicit list, so they cannot be dropped by accident.

## The Claude manifest is validated, not generated

`hooks/hooks.json` stays hand-maintained on purpose: Claude Code is the
reference runtime, its manifest carries events no other runtime has, and its
per-event `async` choices are policy rather than capability. Being the one
config the generator does not write also makes it the one that can drift
silently, so it is now checked against the registry — an event Claude Code does
not emit cannot sit in it unnoticed.

The generated matrix reads that manifest for the handler column, so the eleven
Claude-only events (`Setup`, `PostToolBatch`, `InstructionsLoaded`,
`FileChanged` and the rest) still show what handles them instead of reporting as
unwired.

---

## Evals

137 → 144, with eight new assertions in `eval_phase_c.sh`. Every one was
negative-controlled — the guarantee was broken and the eval confirmed to fail:

| Control | Eval that caught it |
|---|---|
| Hand-edit `.cursor/hooks.json` | `generate_runtime_hooks --check drift` |
| Add a `matcher` to the Cursor config | `cursor config emits a matcher` |
| Wire a non-existent event in `hooks/hooks.json` | `wires an event absent from the claude registry` |
| Delete a runtime's `verified` date | `registry incomplete: grok.verified` |
| Make the capability cache runtime-blind | `claude should support PermissionRequest` |

### One regression found during the work

The registry lookup is cached, and the first implementation keyed that cache on
"have we loaded yet" rather than on *which runtime*. The `case` statement it
replaced re-read `$CEK_RUNTIME` on every call, so a caller that flips it — the
Phase C evals do exactly that — kept getting correct answers. The memo answered
every later query from whichever runtime asked first.

Caught by an existing eval rather than a new one. The cache is now keyed on the
runtime, and check 19 asserts a `grok → claude → grok` switch within one shell
returns `no → yes → no`.

A second, subtler version of the same mistake was fixed before it shipped: the
memo also has to replay the cached *outcome*, not an unconditional success.
Returning 0 after a failed load would leave the event list empty while telling
the caller the registry was read — flipping the fail-open guard into
fail-closed for every call after the first.

---

## Adding a runtime after this

1. Add it to `config/runtime_events.json` with its event map, metadata, `source`
   and `verified` date.
2. Add its adapter under `<runtime>/hooks/run.sh` on the `cek_runtime.sh`
   pattern.
3. Add `"<runtime>"` to the `runtimes` list of each applicable `EVENTS` entry in
   `generate_runtime_hooks.py`.
4. Run the generator.

The generator refuses to emit an event the registry says the runtime does not
have, so step 3 cannot quietly invent capability.
