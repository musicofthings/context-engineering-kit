#!/usr/bin/env python3
"""
runtime_doc_events.py
Where each runtime's own hook doc states its event list, and how to read it.

One home for two things the doc pipeline needs:

  DOC_SHAPES        per runtime — the heading that anchors the event list on
                    that vendor page, and the shape the list takes there.
  extract_events()  pure and offline — page text in, the event names the page
                    documents out.

The URL is NOT here. It lives once, in config/runtime_events.json as each
runtime's `source`, and `runtime_docs()` reads it from there.

Nothing in this module touches the network, so every extractor is testable
against committed fixtures — see scripts/eval_doc_drift.py.

Why per-runtime shapes: no two vendors present their events the same way.
Grok and Antigravity use a markdown table, Cursor `####` headings, Codex `###`
headings, opencode bulleted lists grouped by category plus hook signatures that
never appear in those lists. A single generic parser across all six would have
to guess, and a wrong answer here reads as "no drift" — the exact failure this
pipeline exists to prevent. Where a page cannot be read confidently, every
function below raises ExtractError rather than returning a partial set.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY_PATH = ROOT / "config" / "runtime_events.json"

# An event name, as every one of the six vendors spells them: CamelCase
# (SessionStart), lowerCamel (beforeShellExecution) or dotted
# (tool.execute.before). Anything else in a table cell or heading is prose.
EVENT_NAME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)*$")
MAX_EVENT_NAME_LEN = 64

# Shape of each vendor's event list. `anchor` is the exact heading line that
# opens it; `mode` says how the list is written underneath.
#
#   headings  one child heading per event, at `child_depth` hashes
#   table     a markdown table whose first column holds the event names
#   bullets   `- ` + backticked name lines, possibly under sub-headings
#
# `also_keys` is a second pass over the WHOLE page, for a runtime that
# documents some hooks outside its event list (opencode's
# `experimental.session.compacting` is only ever shown as an object key).
DOC_SHAPES: dict[str, dict] = {
    "claude": {"anchor": "## Hook events", "mode": "headings", "child_depth": 3},
    "cursor": {"anchor": "### Hook events", "mode": "headings", "child_depth": 4},
    "codex": {"anchor": "## Hooks", "mode": "headings", "child_depth": 3},
    "grok": {"anchor": "## Events", "mode": "table"},
    "opencode": {
        "anchor": "### Events",
        "mode": "bullets",
        "also_keys": r'"([a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)+)"\s*:',
    },
    "antigravity": {"anchor": "## Supported events", "mode": "table"},
}


class ExtractError(Exception):
    """The page could not be read confidently. Never a partial answer."""


def load_registry(path: Path | None = None) -> dict:
    """The runtime registry, read from the kit the script itself lives in.

    Script-relative, not CLAUDE_PROJECT_DIR: these are vendor facts shared by
    every project the kit is installed in, not per-project configuration.
    `path` exists so the eval suite can drive a mutated copy.
    """
    with (path or REGISTRY_PATH).open(encoding="utf-8") as fh:
        return json.load(fh)


def runtime_docs(registry: dict | None = None) -> list[dict]:
    """One entry per runtime: where its doc is, and what to look for in it.

    `url` comes from the registry's `source` field so the URL keeps exactly one
    home; `anchor` comes from DOC_SHAPES so api_docs.md carries the event list
    rather than whichever 6000 characters happen to come first.
    """
    reg = registry if registry is not None else load_registry()
    docs = []
    for runtime, meta in reg["runtimes"].items():
        shape = DOC_SHAPES.get(runtime)
        docs.append(
            {
                "runtime": runtime,
                "display_name": meta.get("display_name", runtime),
                "url": meta.get("source", ""),
                "anchor": (shape or {}).get("anchor", ""),
            }
        )
    return docs


def accounted_events(meta: dict) -> dict[str, str]:
    """Every event the registry says something about -> why it is listed.

    `mapped`   canonical event the kit binds, under this runtime's own name
    `native`   native_extra: no canonical equivalent, used anyway
    `declined` documented by the vendor, deliberately not used by the kit

    A declined event is still accounted for. Mapped-but-unwired events are
    `mapped` too — the registry carries them on purpose (Claude Code's
    MessageDisplay, Elicitation, ElicitationResult, WorktreeCreate), and the
    kit's choice not to bind one is policy, not a capability claim, so it is
    never drift.
    """
    out: dict[str, str] = {}
    for native in meta.get("events", {}).values():
        out[native] = "mapped"
    for native in meta.get("native_extra", []):
        out.setdefault(native, "native")
    for native in meta.get("declined", []):
        out.setdefault(native, "declined")
    return out


FENCE_RE = re.compile(r"^(`{3,}|~{3,})(.*)$")


def _strip_code_fences(body: str) -> list[str]:
    """Page lines with every fenced block blanked out.

    Not cosmetic. These pages show shell and JSON samples inside the event
    section, and a `# Run your setup commands` comment in a bash block is an H1
    heading to any line-based reader — which closed Claude Code's event section
    after one event and reported the other 32 as removed by the vendor.
    """
    out: list[str] = []
    marker: str | None = None
    for line in body.split("\n"):
        m = FENCE_RE.match(line.strip())
        if marker is None:
            if m:
                marker = m.group(1)
                out.append("")
                continue
        else:
            # Close only on a bare fence of the same character, at least as
            # long as the one that opened the block.
            if m and m.group(1)[0] == marker[0] and len(m.group(1)) >= len(marker) and not m.group(2).strip():
                marker = None
            out.append("")
            continue
        out.append(line)
    return out


def _heading_depth(line: str) -> int:
    stripped = line.lstrip()
    if not stripped.startswith("#"):
        return 0
    depth = len(stripped) - len(stripped.lstrip("#"))
    return depth if stripped[depth:].startswith(" ") else 0


def _section(body: str, anchor: str) -> list[str]:
    """Lines under `anchor`, up to the next heading at the same or lower depth.

    An anchor that appears twice is refused: picking one of them would be a
    guess, and a guess that lands on the wrong section reports a clean bill of
    health for a list it never read.
    """
    lines = _strip_code_fences(body)
    anchor_depth = _heading_depth(anchor)
    if anchor_depth == 0:
        raise ExtractError(f"anchor {anchor!r} is not a heading")
    hits = [i for i, ln in enumerate(lines) if ln.strip() == anchor]
    if not hits:
        raise ExtractError(f"anchor {anchor!r} not found on the page")
    if len(hits) > 1:
        raise ExtractError(f"anchor {anchor!r} appears {len(hits)} times — ambiguous")
    start = hits[0] + 1
    for i in range(start, len(lines)):
        depth = _heading_depth(lines[i])
        if 0 < depth <= anchor_depth:
            return lines[start:i]
    return lines[start:]


def _clean_names(raw: str) -> list[str]:
    """Event names out of one heading or table cell.

    Vendors put more than one name in a single slot (Cursor documents
    `beforeShellExecution / beforeMCPExecution` under one heading; Grok pairs
    `Stop`, `StopFailure` in one row), so split before validating.
    """
    names = []
    for token in re.split(r"[/,]| or ", raw):
        token = token.strip().strip("`").strip()
        if token and len(token) <= MAX_EVENT_NAME_LEN and EVENT_NAME_RE.match(token):
            names.append(token)
    return names


def _from_headings(section: list[str], child_depth: int) -> list[str]:
    names = []
    for line in section:
        if _heading_depth(line) == child_depth:
            names.extend(_clean_names(line.lstrip().lstrip("#").strip()))
    return names


def _from_table(section: list[str]) -> list[str]:
    """First column of the FIRST markdown table in the section.

    Only the first: these pages carry field-schema tables right below the event
    table, and their first column holds payload field names.
    """
    rows = []
    seen_separator = False
    for line in section:
        stripped = line.strip()
        if not stripped.startswith("|"):
            if seen_separator and rows:
                break
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not seen_separator:
            if cells and all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
                seen_separator = True
            continue
        rows.append(cells[0] if cells else "")
    if not seen_separator:
        raise ExtractError("no markdown table found under the anchor")
    names = []
    for cell in rows:
        names.extend(_clean_names(cell))
    return names


def _from_bullets(section: list[str]) -> list[str]:
    names = []
    for line in section:
        m = re.match(r"^\s*[-*]\s+(.+?)\s*$", line)
        if m:
            names.extend(_clean_names(m.group(1)))
    return names


def extract_events(runtime: str, body: str) -> set[str]:
    """Event names the vendor page documents for `runtime`.

    Raises ExtractError when the page cannot be read confidently — a truncated
    body, a missing or ambiguous anchor, a section with no recognisable list.
    Reporting "could not extract" is the point: a wrong answer here looks
    exactly like "no drift".
    """
    shape = DOC_SHAPES.get(runtime)
    if shape is None:
        raise ExtractError(f"no extractor declared for runtime {runtime!r}")

    section = _section(body, shape["anchor"])
    mode = shape["mode"]
    if mode == "headings":
        names = _from_headings(section, shape["child_depth"])
    elif mode == "table":
        names = _from_table(section)
    elif mode == "bullets":
        names = _from_bullets(section)
    else:  # pragma: no cover - DOC_SHAPES is ours
        raise ExtractError(f"unknown extraction mode {mode!r}")

    if not names:
        raise ExtractError(f"anchor {shape['anchor']!r} found but no event names under it")

    if shape.get("also_keys"):
        names.extend(
            n for n in re.findall(shape["also_keys"], body) if EVENT_NAME_RE.match(n)
        )
    return set(names)
