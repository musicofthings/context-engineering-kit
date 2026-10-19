#!/usr/bin/env python3
"""
check_runtime_doc_drift.py
Compares every runtime capability claim against the vendor page it cites.

The gap this closes: until v4.0.1 nothing in this repo ever read a vendor doc.
generate_runtime_hooks.py --check proves the generated hook configs match
config/runtime_events.json, and check_sync.sh proves the rest of the wiring is
single-sourced — but both are internally consistent by construction. A registry
entry that had drifted away from the page in its own `source` field stayed green
for a month, which is how Antigravity's native SessionStart went on being
synthesized on PreInvocation long after Google shipped it.

What it checks, per runtime:

  registry_only   The registry claims an event its own cited doc no longer
                  lists. That is a false statement in a committed file, so it
                  is a DEFECT.
  doc_only        The doc lists an event the registry does not mention at all
                  — not mapped, not native_extra, not declined. Nobody has
                  looked at it. A vendor shipping an event is not a repo bug,
                  so it is ADVISORY — but never silent.
  declined_gone   An event the registry declines on purpose has disappeared
                  from the doc. Stale bookkeeping, not a capability claim:
                  ADVISORY.

Mapped-but-unwired is NOT drift. The registry deliberately carries events the
kit does not bind (Claude Code's MessageDisplay, Elicitation, ElicitationResult,
WorktreeCreate). Which mapped event gets a handler is kit policy and lives in
generate_runtime_hooks.py; this script only asks whether the registry's picture
of the runtime is still true.

Exit codes — deliberate, because the three findings are not the same kind of
thing and one shared code would force every caller to treat them alike:

  0  clean
  1  DEFECT      the repo states something false, or its own bookkeeping is
                 inconsistent. Fails CI.
  2  ADVISORY    the vendor moved; the repo is not wrong yet. Loud, not red:
                 a scheduled job that goes red every time a vendor ships an
                 event gets muted, and a muted job is how v4.0.1 happened.
  3  UNKNOWN     a page could not be fetched or could not be parsed. Nothing
                 was verified, which is NOT the same as nothing being wrong.
                 Never reported as clean.

  --strict collapses 2 and 3 into 1 for callers that want a hard gate.

Usage:
  python scripts/check_runtime_doc_drift.py                 # live fetch, all runtimes
  python scripts/check_runtime_doc_drift.py --runtime cursor
  python scripts/check_runtime_doc_drift.py --offline        # no network, bookkeeping only
  python scripts/check_runtime_doc_drift.py --from-dir DIR   # fixtures: DIR/<runtime>.page.md
  python scripts/check_runtime_doc_drift.py --strict
"""

from __future__ import annotations

import argparse
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from runtime_doc_events import (  # noqa: E402  (after sys.path setup)
    DOC_SHAPES,
    ExtractError,
    accounted_events,
    extract_events,
    load_registry,
)

EXIT_OK = 0
EXIT_DEFECT = 1
EXIT_ADVISORY = 2
EXIT_UNKNOWN = 3

# Far above fetch_api_docs.py's 120k context budget: this script is not in the
# session-start path, and a page clipped mid-list reads as "the vendor removed
# these events". Claude Code's hooks reference is already ~270k characters.
MAX_DOC_CHARS = 1_200_000

# A `verified` date this old means nobody has re-checked the page in longer than
# the gap that produced v4.0.1 (one month).
DEFAULT_MAX_VERIFIED_AGE_DAYS = 30

DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def fetch(url: str) -> str:
    """The page as markdown, or raise OSError.

    Reuses fetch_api_docs.py's candidate ladder and HTML guard rather than
    carrying a second fetcher: those two behaviours (a .md variant per doc
    platform, never accepting an SPA shell) are the whole reason the existing
    pipeline returns usable text.
    """
    # Imported here, not at module scope: --offline must not pull in urllib or
    # the doc-pipeline module at all.
    import fetch_api_docs

    body = fetch_api_docs.fetch_url_raw(url, max_chars=MAX_DOC_CHARS)
    if len(body) >= MAX_DOC_CHARS:
        raise OSError(f"page exceeds {MAX_DOC_CHARS} chars — refusing to parse a clipped page")
    return body


class Findings:
    """Findings for one run, grouped by how much they mean."""

    def __init__(self) -> None:
        self.defects: list[str] = []
        self.advisories: list[str] = []
        self.unknowns: list[str] = []
        self.clean: list[str] = []

    def exit_code(self, strict: bool = False) -> int:
        if self.defects:
            return EXIT_DEFECT
        if strict and (self.advisories or self.unknowns):
            return EXIT_DEFECT
        if self.unknowns:
            return EXIT_UNKNOWN
        if self.advisories:
            return EXIT_ADVISORY
        return EXIT_OK


def check_bookkeeping(runtime: str, meta: dict, f: Findings, max_age_days: int) -> None:
    """Registry invariants that hold without touching the network.

    These are the repo's own statements about itself, so a violation is a
    defect — except a stale `verified` date, which is a prompt to re-run this
    script rather than evidence that anything is wrong.
    """
    source = meta.get("source", "")
    if not source.startswith(("http://", "https://")):
        f.defects.append(f"{runtime}: `source` is not a URL ({source!r}) — the claim cannot be re-checked")
    if runtime not in DOC_SHAPES:
        f.defects.append(
            f"{runtime}: no extractor in runtime_doc_events.DOC_SHAPES — "
            f"its claims are unverifiable, which is how a runtime goes unchecked"
        )

    mapped = list(meta.get("events", {}).values())
    native = list(meta.get("native_extra", []))
    declined = list(meta.get("declined", []))
    for label, names in (("events", mapped), ("native_extra", native), ("declined", declined)):
        dupes = {n for n in names if names.count(n) > 1}
        if dupes:
            f.defects.append(f"{runtime}: {label} lists {sorted(dupes)} more than once")
    overlap = (set(mapped) & set(native)) | (set(mapped) & set(declined)) | (set(native) & set(declined))
    if overlap:
        f.defects.append(
            f"{runtime}: {sorted(overlap)} appears in more than one of events / native_extra / declined — "
            f"the kit cannot both use and decline an event"
        )

    union = set(mapped) | set(native) | set(declined)
    total = meta.get("documented_event_total")
    if not isinstance(total, int):
        f.defects.append(f"{runtime}: documented_event_total is not an integer")
    elif len(union) != total:
        f.defects.append(
            f"{runtime}: documented_event_total is {total} but events + native_extra + declined "
            f"account for {len(union)} — every documented event must be accounted for "
            f"(see _declined_format in the registry)"
        )

    verified = meta.get("verified", "")
    if not DATE_RE.match(str(verified)):
        f.defects.append(f"{runtime}: `verified` is not a YYYY-MM-DD date ({verified!r})")
        return
    when = date.fromisoformat(verified)
    today = datetime.now(timezone.utc).date()
    if when > today:
        f.defects.append(f"{runtime}: `verified` is {verified}, in the future")
        return
    age = (today - when).days
    if age > max_age_days:
        f.advisories.append(
            f"{runtime}: last verified {verified} ({age} days ago, limit {max_age_days}) — "
            f"re-run this check against {source}"
        )


def check_against_doc(runtime: str, meta: dict, body: str, f: Findings) -> None:
    try:
        documented = extract_events(runtime, body)
    except ExtractError as e:
        f.unknowns.append(f"{runtime}: could not extract events from {meta.get('source', '?')} — {e}")
        return

    accounted = accounted_events(meta)
    doc_only = sorted(documented - set(accounted))
    missing = sorted(set(accounted) - documented)

    registry_only = [n for n in missing if accounted[n] in ("mapped", "native")]
    declined_gone = [n for n in missing if accounted[n] == "declined"]

    if registry_only:
        f.defects.append(
            f"{runtime}: registry claims {registry_only} but {meta['source']} no longer lists "
            f"{'them' if len(registry_only) > 1 else 'it'} — a capability claim with nothing behind it"
        )
    if doc_only:
        f.advisories.append(
            f"{runtime}: {meta['source']} documents {doc_only}, which the registry does not mention "
            f"at all — map {'them' if len(doc_only) > 1 else 'it'} in `events`/`native_extra`, or "
            f"record {'them' if len(doc_only) > 1 else 'it'} in `declined` with a reason"
        )
    if declined_gone:
        f.advisories.append(
            f"{runtime}: `declined` still lists {declined_gone}, which {meta['source']} no longer "
            f"documents — drop {'them' if len(declined_gone) > 1 else 'it'}"
        )
    if not (doc_only or missing):
        f.clean.append(
            f"{runtime}: {len(documented)} documented events, all accounted for ({meta['source']})"
        )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--runtime", action="append", help="check only this runtime (repeatable)")
    ap.add_argument("--offline", action="store_true", help="no network: registry bookkeeping only")
    ap.add_argument("--from-dir", help="read pages from DIR/<runtime>.page.md instead of the network")
    ap.add_argument("--strict", action="store_true", help="treat ADVISORY and UNKNOWN as failure")
    ap.add_argument("--registry", help="registry JSON to check instead of config/runtime_events.json")
    ap.add_argument(
        "--max-verified-age-days",
        type=int,
        default=DEFAULT_MAX_VERIFIED_AGE_DAYS,
        help=f"warn when `verified` is older than this (default {DEFAULT_MAX_VERIFIED_AGE_DAYS})",
    )
    args = ap.parse_args()

    registry = load_registry(Path(args.registry) if args.registry else None)
    runtimes = registry["runtimes"]

    unknown_names = [r for r in (args.runtime or []) if r not in runtimes]
    if unknown_names:
        print(f"unknown runtime(s): {unknown_names} — known: {sorted(runtimes)}", file=sys.stderr)
        return EXIT_DEFECT
    selected = args.runtime or sorted(runtimes)

    # A runtime present in DOC_SHAPES but missing from the registry means the
    # extractor table and the registry have drifted apart from each other.
    f = Findings()
    orphans = [] if args.registry else sorted(set(DOC_SHAPES) - set(runtimes))
    if orphans:
        f.defects.append(f"runtime_doc_events.DOC_SHAPES declares {orphans}, absent from the registry")

    fixtures = Path(args.from_dir) if args.from_dir else None

    for runtime in selected:
        meta = runtimes[runtime]
        check_bookkeeping(runtime, meta, f, args.max_verified_age_days)
        if args.offline:
            continue
        if fixtures is not None:
            # .page.md, not .md: a fixture named claude.md is discovered by
            # Claude Code's own CLAUDE.md lookup on a case-insensitive
            # filesystem, loading untrusted fetched vendor text as project
            # instructions in every project the kit is installed in.
            path = fixtures / f"{runtime}.page.md"
            if not path.exists():
                f.unknowns.append(f"{runtime}: no fixture at {path.name} in {fixtures}")
                continue
            body = path.read_text(encoding="utf-8")
        else:
            url = meta.get("source", "")
            print(f"fetching {runtime}: {url}", file=sys.stderr)
            try:
                body = fetch(url)
            except (OSError, ValueError) as e:
                # Never fatal on its own. A vendor site being down says nothing
                # about this repo — but it must not read as a pass either.
                f.unknowns.append(f"{runtime}: fetch failed ({url}) — {e}")
                continue
        check_against_doc(runtime, meta, body, f)

    print()
    if args.offline:
        against = "offline (bookkeeping only)"
    elif fixtures is not None:
        against = f"against fixtures in {fixtures}"
    else:
        against = "against live docs"
    print("Runtime doc drift —", against)
    print("=" * 72)
    for line in f.clean:
        print(f"  OK        {line}")
    for line in f.advisories:
        print(f"  ADVISORY  {line}")
    for line in f.unknowns:
        print(f"  UNKNOWN   {line}")
    for line in f.defects:
        print(f"  DEFECT    {line}")
    if args.offline:
        print()
        print("  NOTE      no page was read. Live drift is unchecked — run without --offline.")
    print("=" * 72)
    code = f.exit_code(args.strict)
    verdict = {
        EXIT_OK: "clean",
        EXIT_DEFECT: "DEFECT — a committed claim is false or inconsistent",
        EXIT_ADVISORY: "ADVISORY — a vendor doc moved ahead of the registry",
        EXIT_UNKNOWN: "UNKNOWN — a page could not be read; nothing was verified",
    }[code]
    print(
        f"{len(f.defects)} defect(s), {len(f.advisories)} advisory, "
        f"{len(f.unknowns)} unknown, {len(f.clean)} clean  ->  exit {code} ({verdict})"
    )
    return code


if __name__ == "__main__":
    sys.exit(main())
