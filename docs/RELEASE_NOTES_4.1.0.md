# context-engineering-kit v4.1.0

**Date:** 2026-10-19
**Tag:** `v4.1.0`
**Artifact:** `context-engineering-kit-4.1.0.zip` (build with `python scripts/package_plugin.py --runtime all`)

v4.0.1 found a month-old capability error by hand. This release closes the
structural gap that let it hide: **the kit now re-reads the vendor pages its
claims cite, and says so when they disagree.**

---

## The gap

v4.0.1's own summary said the quiet part out loud. Antigravity had shipped a
native `SessionStart`; the registry did not mention it; the kit synthesized the
event on `PreInvocation` for a month — and every check in this repo was green
the whole time.

They were green because none of them ever looked outside the repo:

- `generate_runtime_hooks.py --check` proves the generated hook configs match
  `config/runtime_events.json`.
- `check_sync.sh` proves the wiring is single-sourced and portable.
- `validate_readme_counts()` proves README's `N of M` matches the registry.

All three are internally consistent by construction. A registry entry that has
drifted away from the page in its own `source` field satisfies every one of
them. The registry's `_why` note had already named this failure mode — the first
draft of the v4 plan was built on a blog post about Gemini CLI three months
after Google shut that product off — but naming it is not checking it.

Meanwhile `config/api_sources.json`, which drives the automated doc refresh,
tracked three sources: Claude Code hooks, the Claude API, and Cloudflare
Workers. Five of the six runtimes the kit depends on were not in the pipeline at
all. The one that was, was listed under a *second* URL.

---

## What is new

### 1. All six runtime hook docs are in the refresh pipeline

`scripts/fetch_api_docs.py` now appends one entry per runtime, taking each URL
from `runtimes.<rt>.source` in `config/runtime_events.json` rather than from a
copy. They land in `api_docs.md` beside the existing sources, under the same
untrusted-remote-data banner, anchored at each page's event-list heading so the
section that survives the 6,000-character cap is the part that matters.

**Claude Code's entry moved out of `config/api_sources.json`.** It was the one
runtime doc in both files, under two different URLs —
`docs.anthropic.com/en/docs/claude-code/hooks` there and
`code.claude.com/docs/en/hooks` in the registry. Two URLs for one page is one
too many to keep true, and only the registry's is the one a capability claim
cites, so that is the one the pipeline follows. `api_sources.json` keeps the
sources that are not runtime docs and now says where runtime docs live.

### 2. A drift detector: `scripts/check_runtime_doc_drift.py`

The fetch was never the valuable part. For each runtime the detector extracts
the event names the vendor page documents and compares that set against the
registry:

| Finding | Meaning | Exit |
|---|---|---|
| `DEFECT` | the registry claims an event its own cited doc no longer lists, or its bookkeeping is self-inconsistent | 1 |
| `ADVISORY` | the doc lists an event the registry does not mention, a `declined` event has vanished, or `verified` is over 30 days old | 2 |
| `UNKNOWN` | a page could not be fetched or could not be parsed — **nothing was verified** | 3 |

Mapped-but-unwired is **not** drift. The registry carries events the kit
deliberately never binds (`MessageDisplay`, `Elicitation`, `ElicitationResult`,
`WorktreeCreate`); which mapped event gets a handler is kit policy and lives in
`generate_runtime_hooks.py`. The detector only asks whether the registry's
picture of the runtime is still true.

### 3. `declined`: the thing that makes the comparison mean something

"Deliberately unused, not overlooked" was a paragraph in
`docs/runtime-capability-matrix.md` and nowhere else. Comparing a page against
`events` + `native_extra` alone therefore reported nine findings for Cursor and
nineteen for opencode on every run — all of them decisions already made, and
noise on that scale is how a real finding gets missed.

Each runtime now carries a `declined` list: events its own doc documents and the
kit deliberately does not use. The invariant is exact and checked offline:

```
documented_event_total == | events ∪ native_extra ∪ declined |
```

Every documented event is in exactly one of the three. **Anything the page lists
and the registry does not mention is, by construction, an event nobody has
looked at** — which is precisely what Antigravity's `SessionStart` was.

### 4. Wired into the three places it has to be

- **By hand** — `python scripts/check_runtime_doc_drift.py`, with `--runtime`,
  `--offline`, `--from-dir`, `--registry` and `--strict`.
- **`scripts/check_sync.sh`** — runs it with `--offline`. No network, so the
  local gate stays fast and never depends on six vendor sites; it still checks
  the bookkeeping invariant above, which is what gives the live check its teeth.
  Exit 1 fails, 2 and 3 print a warning.
- **`.github/workflows/sync-api-docs.yml`** — runs it live after the fetch.
  Exit 1 fails the job with `::error` annotations; 2 and 3 emit `::warning` and
  a step summary, and the whole report is pasted into the body of the weekly
  doc-refresh PR so a vendor change arrives where someone reviews it. The
  commit step is `if: always()`, so a DEFECT reddens the job without also
  swallowing the refreshed docs you need in order to act on it.

#### Why a vendor change does not fail CI

This was the deliberate call. A false claim in a committed file is this repo's
defect and should be red. A vendor shipping a new event is not — and a scheduled
job that goes red every time one does is a job that gets muted. A muted job is
how v4.0.1 happened. So `ADVISORY` and `UNKNOWN` are loud and non-fatal:
annotated, summarised, and carried into a PR body. `--strict` collapses them
into exit 1 for anyone who wants the hard gate anyway.

`UNKNOWN` is its own code rather than folded into either. A page that could not
be fetched or parsed means nothing was verified, which is not the same as
nothing being wrong, and it is never reported as clean.

---

## Extraction, and why it refuses to guess

No two vendors present their events the same way: a markdown table for Grok and
Antigravity, `####` headings for Cursor, `###` headings for Codex and Claude
Code, bulleted lists grouped by category for opencode — plus, for opencode,
hook signatures that appear only as object keys in an example and never in the
event list at all.

`scripts/runtime_doc_events.py` holds one declarative entry per runtime (anchor
heading, list shape) and three small generic extractors. Every one of them
**raises rather than returning a partial set** when the page cannot be read
confidently — a missing anchor, an anchor that appears twice, a section with no
recognisable list, a body at the fetch cap. A wrong answer here is
indistinguishable from "no drift", and a false clean bill of health is the exact
failure this release exists to prevent.

Two hazards found while building it, both now regression-tested:

- **Code fences.** Claude Code's hooks reference shows a bash sample containing
  `# Run your setup commands`, which any line-based reader takes for an H1. It
  closed the event section after one event and reported the other 32 as removed.
  Fences are stripped before parsing.
- **Truncation.** That page is ~270,000 characters and `fetch_api_docs.py` caps
  at 120,000 for the context budget, so parsing the pipeline's copy would have
  seen 5 of 33 events. The detector fetches with its own large cap and refuses
  to parse a body that reaches it.

---

## Tests

`scripts/eval_doc_drift.py` — 36 assertions, **no network**. Fixtures are
trimmed excerpts of the six live pages under
`scripts/fixtures/runtime-docs/*.page.md`, each extracting exactly the event set
its live page does.

The suite's centre is the **Antigravity regression**: the real page, plus the
registry as it read before v4.0.1 (`SessionStart` absent, five events claimed,
synthesized on `PreInvocation`). It asserts both halves of the original failure
— that stale registry passes offline bookkeeping, and only reading the page
catches it, where it is reported as drift naming `SessionStart`.

Also covered: a fabricated claim is a `DEFECT` and not an advisory; the four
unwired Claude Code events do not register as drift; a `declined` event dropped
by a vendor is reported; unreadable pages are `UNKNOWN` and never clean; a
clipped body raises; fences do not end a section; and no runtime URL has two
homes.

Registered as suite 9 in `scripts/eval_all_runtimes.sh` — **9 / 9 pass**.

> The fixtures are `<runtime>.page.md`, never `<runtime>.md`. A fixture called
> `claude.md` is picked up by Claude Code's own `CLAUDE.md` discovery on a
> case-insensitive filesystem, which loads a page of untrusted fetched vendor
> text as project instructions. Found the hard way during this work.

---

## Corrected

- **opencode's `documented_event_total` was `~25`; it is `28`.** The plugins
  page lists 27 bus events and documents `experimental.session.compacting` as a
  hook signature in its compaction example. Both surfaces count — the kit binds
  from both — so the total is now exact rather than approximate, and README's
  tier row reads `9 of 28 events`. The `~` marker is gone from that row because
  the number no longer needs it.
- **`docs/runtime-capability-matrix.md`** — *Deliberately unused* now says the
  list is backed by `declined` and checked, not asserted. A new section records
  what `--check` cannot tell you and what does.

---

## Verified

All six pages fetched and compared on **2026-10-19**:

| Runtime | Documented events | Result |
|---|---|---|
| Claude Code | 33 | all accounted for |
| Cursor | 21 | all accounted for (12 used, 9 declined) |
| Codex | 12 | all accounted for |
| Grok Build | 14 | all accounted for |
| opencode | 28 | all accounted for (9 used, 19 declined) |
| Antigravity CLI | 6 | all accounted for |

`verified` still reads `2026-10-19` for all six. **No date was moved** — v4.0.1
set them by hand on the same day and this run confirms them rather than
re-stamping them. A `verified` date that moves without a real check is worse
than a stale one; that is the whole premise of the registry, and it applies to
the tool as much as to the person.

No runtime adapter behaviour changed in this release. Detection only.

```
ruff check .                                  clean
bash scripts/check_sync.sh                    pass
python scripts/generate_runtime_hooks.py --check   pass
python scripts/check_runtime_doc_drift.py     exit 0, 6 clean
bash scripts/eval_all_runtimes.sh             9 / 9
```
