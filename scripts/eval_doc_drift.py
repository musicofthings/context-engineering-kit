#!/usr/bin/env python3
"""
eval_doc_drift.py — drives scripts/check_runtime_doc_drift.py offline.

Every assertion here runs against committed fixtures under
scripts/fixtures/runtime-docs/, never the network: a suite that needs six
vendor sites to be up is a suite that gets skipped, and the detector exists
precisely because nobody was checking.

The case that matters most is `antigravity_regression`. It replays v4.0.1:
Antigravity's page listed SessionStart, the registry did not mention it, every
check in the repo was green, and the kit went on synthesizing the event on
PreInvocation for a month. That fixture must come back as drift.

Run: python3 scripts/eval_doc_drift.py
"""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from datetime import date, timedelta
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(KIT / "scripts"))

import fetch_api_docs  # noqa: E402
from runtime_doc_events import (  # noqa: E402
    DOC_SHAPES,
    ExtractError,
    accounted_events,
    extract_events,
    load_registry,
)

DETECTOR = KIT / "scripts" / "check_runtime_doc_drift.py"
FIXTURES = KIT / "scripts" / "fixtures" / "runtime-docs"

EXIT_OK, EXIT_DEFECT, EXIT_ADVISORY, EXIT_UNKNOWN = 0, 1, 2, 3

PASS = 0
FAIL = 0


def ok(msg: str) -> None:
    global PASS
    print(f"  PASS  {msg}")
    PASS += 1


def bad(msg: str, detail: str = "") -> None:
    global FAIL
    print(f"  FAIL  {msg} — {detail}")
    FAIL += 1


def run(*args: str, registry: Path | None = None, from_dir: Path | None = FIXTURES) -> tuple[int, str]:
    cmd = [sys.executable, str(DETECTOR), *args]
    if registry is not None:
        cmd += ["--registry", str(registry)]
    if from_dir is not None:
        cmd += ["--from-dir", str(from_dir)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def temp_registry(mutate) -> Path:
    reg = copy.deepcopy(load_registry())
    mutate(reg)
    path = Path(tempfile.mkdtemp(prefix="cek-drift-")) / "runtime_events.json"
    path.write_text(json.dumps(reg, indent=2), encoding="utf-8")
    return path


def temp_fixtures(mutate_files: dict[str, str]) -> Path:
    """A copy of the fixture tree with the named pages replaced."""
    out = Path(tempfile.mkdtemp(prefix="cek-pages-"))
    for src in FIXTURES.glob("*.page.md"):
        (out / src.name).write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
    for name, body in mutate_files.items():
        (out / name).write_text(body, encoding="utf-8")
    return out


print("── extraction: every fixture yields exactly what the registry accounts for ──")

registry = load_registry()
for runtime, meta in sorted(registry["runtimes"].items()):
    page = FIXTURES / f"{runtime}.page.md"
    if not page.exists():
        bad(f"{runtime}: fixture missing", str(page))
        continue
    try:
        documented = extract_events(runtime, page.read_text(encoding="utf-8"))
    except ExtractError as e:
        bad(f"{runtime}: extraction raised", str(e))
        continue
    accounted = set(accounted_events(meta))
    if documented == accounted:
        ok(f"{runtime}: {len(documented)} events extracted, all accounted for")
    else:
        bad(
            f"{runtime}: extraction disagrees with the registry",
            f"doc_only={sorted(documented - accounted)} registry_only={sorted(accounted - documented)}",
        )
    total = meta["documented_event_total"]
    if len(documented) == total:
        ok(f"{runtime}: documented_event_total ({total}) matches the page")
    else:
        bad(f"{runtime}: documented_event_total is {total}", f"page lists {len(documented)}")

print()
print("── the v4.0.1 case: a native event the registry never mentions ──")

# Antigravity as the registry described it BEFORE v4.0.1: SessionStart absent
# from `events`, synthesized on PreInvocation instead, five events claimed.
# Bookkeeping is internally consistent, so nothing but a read of the page can
# catch it.
def _pre_401(reg):
    agy = reg["runtimes"]["antigravity"]
    agy["events"] = {
        "PreToolUse": "PreToolUse",
        "PostToolUse": "PostToolUse",
        "Stop": "Stop",
    }
    agy["native_extra"] = ["PreInvocation", "PostInvocation"]
    agy["declined"] = []
    agy["documented_event_total"] = 5


pre_401 = temp_registry(_pre_401)
code, out = run("--runtime", "antigravity", registry=pre_401)
if code == EXIT_ADVISORY and "SessionStart" in out and "ADVISORY" in out:
    ok("antigravity regression fixture reported as drift (exit 2, names SessionStart)")
else:
    bad("antigravity regression not flagged", f"exit {code}: {out.strip()[-400:]}")

code, out = run("--runtime", "antigravity", "--offline", registry=pre_401, from_dir=None)
if code == EXIT_OK:
    ok("the same stale registry passes offline bookkeeping — only the page catches it")
else:
    bad("pre-v4.0.1 registry should be internally consistent", f"exit {code}")

code, out = run("--runtime", "antigravity", "--strict", registry=pre_401)
if code == EXIT_DEFECT:
    ok("--strict promotes the advisory to a failure")
else:
    bad("--strict did not promote", f"exit {code}")

print()
print("── a claim with nothing behind it is a defect, not an advisory ──")


def _bogus_claim(reg):
    reg["runtimes"]["grok"]["events"]["WarpDrive"] = "WarpDrive"
    reg["runtimes"]["grok"]["documented_event_total"] = 15


code, out = run("--runtime", "grok", registry=temp_registry(_bogus_claim))
if code == EXIT_DEFECT and "WarpDrive" in out and "DEFECT" in out:
    ok("event claimed by the registry but absent from the doc -> DEFECT (exit 1)")
else:
    bad("fabricated claim not reported as a defect", f"exit {code}: {out.strip()[-300:]}")

print()
print("── mapped-but-unwired is policy, not drift ──")

unwired = {"MessageDisplay", "Elicitation", "ElicitationResult", "WorktreeCreate"}
claude_events = set(registry["runtimes"]["claude"]["events"])
if unwired <= claude_events:
    ok("registry still carries the four deliberately unwired Claude Code events")
else:
    bad("unwired events missing from the registry", f"absent: {sorted(unwired - claude_events)}")

code, out = run("--runtime", "claude")
if code == EXIT_OK and "ADVISORY" not in out and "DEFECT" not in out:
    ok("Claude Code is clean although four mapped events are never bound")
else:
    bad("unwired events reported as drift", f"exit {code}: {out.strip()[-300:]}")

print()
print("── declined events are accounted for, and noticed when they vanish ──")

declined_cursor = set(registry["runtimes"]["cursor"].get("declined", []))
if "workspaceOpen" in declined_cursor and "preToolUse" in declined_cursor:
    ok("Cursor's deliberately unused events are recorded in `declined`")
else:
    bad("Cursor `declined` is incomplete", f"got {sorted(declined_cursor)}")

page = (FIXTURES / "cursor.page.md").read_text(encoding="utf-8")
code, out = run(
    "--runtime", "cursor",
    from_dir=temp_fixtures({"cursor.page.md": page.replace("#### workspaceOpen\n", "")}),
)
if code == EXIT_ADVISORY and "workspaceOpen" in out and "declined" in out:
    ok("a declined event dropped by the vendor -> ADVISORY, named")
else:
    bad("declined-but-gone not reported", f"exit {code}: {out.strip()[-300:]}")

print()
print("── an unreadable page is UNKNOWN, never clean ──")

for label, body in (
    ("no anchor", "# Hooks\n\nWe rewrote this page and dropped the event list.\n"),
    ("anchor, no names", "# Hooks\n\n## Supported events\n\nSee the SDK reference.\n"),
    ("ambiguous anchor", "## Supported events\n\n| a |\n| - |\n| `X` |\n\n## Supported events\n\n| a |\n| - |\n| `Y` |\n"),
):
    code, out = run(
        "--runtime", "antigravity",
        from_dir=temp_fixtures({"antigravity.page.md": body}),
    )
    if code == EXIT_UNKNOWN and "UNKNOWN" in out and "OK " not in out:
        ok(f"{label}: reported as UNKNOWN (exit 3), not clean")
    else:
        bad(f"{label}: should be UNKNOWN", f"exit {code}: {out.strip()[-300:]}")

code, out = run("--runtime", "antigravity", from_dir=Path(tempfile.mkdtemp(prefix="cek-empty-")))
if code == EXIT_UNKNOWN:
    ok("a missing page is UNKNOWN, not a pass")
else:
    bad("missing page should be UNKNOWN", f"exit {code}")

print()
print("── a clipped page is refused rather than parsed ──")

import check_runtime_doc_drift as drift  # noqa: E402

_real = fetch_api_docs.fetch_url_raw
try:
    fetch_api_docs.fetch_url_raw = lambda url, max_chars=0: "x" * max_chars
    try:
        drift.fetch("https://example.invalid/hooks")
        bad("clipped page accepted", "fetch() returned a body at the cap")
    except OSError as e:
        if "clipped" in str(e) or "exceeds" in str(e):
            ok("a body at the character cap raises instead of being parsed")
        else:
            bad("wrong error for a clipped page", str(e))
finally:
    fetch_api_docs.fetch_url_raw = _real

print()
print("── code fences do not end an event section ──")

fenced = (
    "# Hooks\n\n## Hook events\n\n### SessionStart\n\n"
    "```bash\n#!/bin/bash\n# Run your setup commands\nexit 0\n```\n\n"
    "### SessionEnd\n"
)
got = extract_events("claude", fenced)
if got == {"SessionStart", "SessionEnd"}:
    ok("a shell comment inside a fence is not read as a heading")
else:
    bad("fence handling regressed", f"extracted {sorted(got)}")

print()
print("── registry bookkeeping ──")

code, out = run("--offline", from_dir=None)
if code == EXIT_OK:
    ok("the committed registry passes offline bookkeeping")
else:
    bad("committed registry fails bookkeeping", out.strip()[-400:])

if "no page was read" in out:
    ok("--offline says plainly that live drift was not checked")
else:
    bad("--offline does not disclaim what it skipped", out.strip()[-200:])


def _bad_total(reg):
    reg["runtimes"]["codex"]["documented_event_total"] = 11


code, out = run("--runtime", "codex", "--offline", registry=temp_registry(_bad_total), from_dir=None)
if code == EXIT_DEFECT and "accounted for" in out:
    ok("documented_event_total that does not match events+native_extra+declined -> DEFECT")
else:
    bad("total mismatch not caught offline", f"exit {code}")


def _double_booked(reg):
    reg["runtimes"]["cursor"]["declined"].append("sessionStart")
    reg["runtimes"]["cursor"]["documented_event_total"] = 21


code, out = run("--runtime", "cursor", "--offline", registry=temp_registry(_double_booked), from_dir=None)
if code == EXIT_DEFECT and "more than one" in out:
    ok("an event both used and declined -> DEFECT")
else:
    bad("double-booked event not caught", f"exit {code}")


def _future_verified(reg):
    reg["runtimes"]["grok"]["verified"] = str(date.today() + timedelta(days=2))


code, out = run("--runtime", "grok", "--offline", registry=temp_registry(_future_verified), from_dir=None)
if code == EXIT_DEFECT and "future" in out:
    ok("a `verified` date in the future -> DEFECT")
else:
    bad("future verified date accepted", f"exit {code}")


def _stale_verified(reg):
    reg["runtimes"]["grok"]["verified"] = str(date.today() - timedelta(days=400))


code, out = run("--runtime", "grok", "--offline", registry=temp_registry(_stale_verified), from_dir=None)
if code == EXIT_ADVISORY and "last verified" in out:
    ok("a `verified` date older than the limit -> ADVISORY")
else:
    bad("stale verified date not surfaced", f"exit {code}")


def _unverifiable(reg):
    reg["runtimes"]["grok"]["source"] = "see the docs"


code, out = run("--runtime", "grok", "--offline", registry=temp_registry(_unverifiable), from_dir=None)
if code == EXIT_DEFECT and "not a URL" in out:
    ok("a `source` that is not a URL -> DEFECT (the claim cannot be re-checked)")
else:
    bad("unverifiable source accepted", f"exit {code}")

print()
print("── the URL keeps one home ──")

apis = fetch_api_docs.runtime_doc_apis()
reg_urls = {m["source"] for m in registry["runtimes"].values()}
if len(apis) == len(registry["runtimes"]) and {a["base_url"] for a in apis} == reg_urls:
    ok(f"fetch_api_docs appends {len(apis)} runtime sources, all taken from the registry")
else:
    bad("runtime sources do not match the registry", f"{sorted(a['base_url'] for a in apis)}")

cfg = json.loads((KIT / "config" / "api_sources.json").read_text(encoding="utf-8"))
configured = {a["base_url"] for a in cfg["apis"]}
overlap = configured & reg_urls
if not overlap:
    ok("no runtime doc URL is duplicated in config/api_sources.json")
else:
    bad("a runtime URL has two homes", f"{sorted(overlap)}")

if set(DOC_SHAPES) == set(registry["runtimes"]):
    ok("every runtime in the registry has an extractor, and vice versa")
else:
    bad(
        "extractor table and registry disagree",
        f"shapes_only={sorted(set(DOC_SHAPES) - set(registry['runtimes']))} "
        f"registry_only={sorted(set(registry['runtimes']) - set(DOC_SHAPES))}",
    )

print()
print("━" * 40)
print(f"Results: {PASS} passed, {FAIL} failed")
print("━" * 40)
sys.exit(0 if FAIL == 0 else 1)
