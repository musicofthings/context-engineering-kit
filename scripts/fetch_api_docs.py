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


def fetch_url(url: str) -> str:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "context-engineering-kit/2.0"})
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.read().decode("utf-8", errors="replace")[:8000]  # cap at 8k chars
    except urllib.error.URLError as e:
        return f"[fetch failed: {e}]"
    except Exception as e:
        return f"[error: {e}]"


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

    return "\n".join(result) if result else content[:2000]


def main():
    if not CONFIG_FILE.exists():
        print(f"Config not found: {CONFIG_FILE}", file=sys.stderr)
        sys.exit(1)

    config = json.loads(CONFIG_FILE.read_text())
    apis = config.get("apis", [])
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    sections = [f"# API Documentation\n_Auto-fetched: {timestamp}_\n_Source: {CONFIG_FILE}_\n"]
    sections.append("---\n")

    for api in apis:
        name = api.get("name", "unknown")
        base_url = api.get("base_url", "")
        extract = api.get("extract_sections", [])
        description = api.get("description", "")

        print(f"Fetching: {name} ({base_url})", file=sys.stderr)
        content = fetch_url(base_url)
        extracted = extract_sections(content, extract) if extract else content[:3000]

        sections.append(f"## {name.upper()}\n")
        if description:
            sections.append(f"_{description}_\n")
        sections.append(f"Source: {base_url}\n\n")
        sections.append("```\n" + extracted[:3000] + "\n```\n")
        sections.append("\n---\n")

    OUTPUT_FILE.write_text("\n".join(sections))
    print(f"api_docs.md written ({OUTPUT_FILE.stat().st_size} bytes)", file=sys.stderr)


if __name__ == "__main__":
    main()
