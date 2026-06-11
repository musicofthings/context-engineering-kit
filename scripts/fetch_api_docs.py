#!/usr/bin/env python3
"""
fetch_api_docs.py
Weekly GitHub Actions script: fetches latest API docs from configured sources
and writes them to api_docs.md for injection into Claude's context.
"""

import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path


CONFIG_FILE = Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")) / "config" / "api_sources.json"
OUTPUT_FILE = Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")) / "api_docs.md"
TIMEOUT = 15
MAX_FETCH_CHARS = 120_000
MAX_SECTION_CHARS = 6_000


def looks_like_html(content: str) -> bool:
    head = content[:512].lstrip().lower()
    return head.startswith(("<!doctype", "<html")) or "<head>" in head


def markdown_candidates(url: str):
    """URLs to try, most-likely-markdown first.

    The configured sources are JS-rendered doc sites whose HTML carries no
    content — but both Mintlify (docs.anthropic.com) and Starlight
    (developers.cloudflare.com) serve the raw page markdown at a .md path.
    """
    if url.endswith(".md"):
        yield url
    elif url.endswith("/"):
        yield url + "index.md"
        yield url.rstrip("/") + ".md"
    else:
        yield url + ".md"
    yield url


def _get(url: str) -> str:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": "context-engineering-kit/2.0",
            "Accept": "text/markdown, text/plain;q=0.9, */*;q=0.1",
        },
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return resp.read().decode("utf-8", errors="replace")[:MAX_FETCH_CHARS]


def fetch_url(url: str) -> str:
    """Return markdown/plaintext content, or a '[fetch failed: ...]' marker.

    An HTML response is treated as a miss, never returned: committing an SPA
    shell to api_docs.md is worse than committing a visible failure marker.
    """
    last_err = "no candidates tried"
    for candidate in markdown_candidates(url):
        try:
            content = _get(candidate)
        except (urllib.error.URLError, OSError, ValueError) as e:
            last_err = f"{candidate}: {e}"
            continue
        if looks_like_html(content):
            last_err = f"{candidate}: returned HTML, not markdown"
            continue
        if candidate != url:
            print(f"  using markdown variant: {candidate}", file=sys.stderr)
        return content
    return f"[fetch failed: {last_err}]"


def extract_sections(content: str, sections: list[str]) -> str:
    """Very basic section extraction for markdown/HTML docs."""
    lines = content.split("\n")
    result = []
    capture = False
    captured_count = 0

    for line in lines:
        # Start capturing on section header match
        for section in sections:
            if section.lower() in line.lower() and ("#" in line or "<h" in line.lower()):
                capture = True
                captured_count = 0
                break
        if capture:
            result.append(line)
            captured_count += 1
            if captured_count > 80:  # cap each section at 80 lines
                capture = False
                result.append("...(truncated)")

    return "\n".join(result) if result else content[:MAX_SECTION_CHARS]


def main():
    if not CONFIG_FILE.exists():
        print(f"Config not found: {CONFIG_FILE}", file=sys.stderr)
        sys.exit(1)

    config = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
    apis = config.get("apis", [])
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    sections = [f"# API Documentation\n_Auto-fetched: {timestamp}_\n_Source: {CONFIG_FILE}_\n"]
    sections.append("---\n")

    failures = 0
    for api in apis:
        name = api.get("name", "unknown")
        base_url = api.get("base_url", "")
        extract = api.get("extract_sections", [])
        description = api.get("description", "")

        print(f"Fetching: {name} ({base_url})", file=sys.stderr)
        content = fetch_url(base_url)
        if content.startswith("[fetch failed:"):
            failures += 1
            print(f"  FAILED: {content}", file=sys.stderr)
            extracted = content
        else:
            extracted = extract_sections(content, extract) if extract else content[:MAX_SECTION_CHARS]

        sections.append(f"## {name.upper()}\n")
        if description:
            sections.append(f"_{description}_\n")
        sections.append(f"Source: {base_url}\n\n")
        sections.append("```\n" + extracted[:MAX_SECTION_CHARS] + "\n```\n")
        sections.append("\n---\n")

    if apis and failures == len(apis):
        print("All sources failed — leaving existing api_docs.md untouched", file=sys.stderr)
        sys.exit(1)

    OUTPUT_FILE.write_text("\n".join(sections), encoding="utf-8")
    print(f"api_docs.md written ({OUTPUT_FILE.stat().st_size} bytes, {failures} source(s) failed)", file=sys.stderr)


if __name__ == "__main__":
    main()
