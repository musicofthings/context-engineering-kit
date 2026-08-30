#!/usr/bin/env python3
"""
update_context_files.py
Called by pre-compact.sh hook.
Updates the AUTO-UPDATED section in CLAUDE.md with current session state.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


MARKER_START = "<!-- AUTO-UPDATED by hooks — do not edit this section manually -->"
MARKER_END   = "<!-- END AUTO-UPDATED -->"

AUTO_SECTION_TEMPLATE = """{start}
<!-- LAST_UPDATED: {timestamp} -->
<!-- ACTIVE_TASK: {task} -->
<!-- PHASE: {phase} -->
<!-- NEXT_ACTION: {next_action} -->
<!-- BRANCH: {branch} -->
<!-- COMPACT_MODE: {mode} -->
{end}"""


def update_claude_md(project_dir: Path, args) -> bool:
    claude_md = project_dir / "CLAUDE.md"
    if not claude_md.exists():
        print("[update_context] CLAUDE.md not found — skipping", file=sys.stderr)
        return False

    content = claude_md.read_text(encoding="utf-8", errors="replace")

    # Build the replacement block
    new_section = AUTO_SECTION_TEMPLATE.format(
        start=MARKER_START,
        timestamp=args.timestamp,
        task=args.task or "unknown",
        phase=args.phase or "unknown",
        next_action=args.next_action or "unknown",
        branch=args.branch or "unknown",
        mode=args.mode or "unknown",
        end=MARKER_END,
    )

    # Replace between markers if they exist
    pattern = re.compile(
        re.escape(MARKER_START) + r".*?" + re.escape(MARKER_END),
        re.DOTALL
    )
    if pattern.search(content):
        updated = pattern.sub(new_section, content)
    else:
        # Append before end of file if markers not found
        updated = content.rstrip() + "\n\n" + new_section + "\n"

    tmp = claude_md.with_suffix(".md.tmp")
    try:
        tmp.write_text(updated, encoding="utf-8")
        tmp.replace(claude_md)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise
    print(f"[update_context] CLAUDE.md updated ({args.mode} mode)", file=sys.stderr)
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", default="compact", choices=["compact", "session-end", "manual"],
                        help="Update mode: compact, session-end, manual")
    parser.add_argument("--timestamp", default=datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    parser.add_argument("--branch", default="")
    parser.add_argument("--task", default="")
    parser.add_argument("--phase", default="")
    parser.add_argument("--next-action", default="", dest="next_action")
    args = parser.parse_args()

    project_dir = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))

    # CLI args win (the pre-compact hook passes them); otherwise fall back to
    # state.json and git so manual runs don't stamp "unknown" everywhere.
    state_file = project_dir / ".claude" / "session" / "state.json"
    state = {}
    if state_file.exists():
        try:
            state = json.loads(state_file.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            state = {}
    args.task = args.task or state.get("active_task", "")
    args.phase = args.phase or state.get("phase", "")
    args.next_action = args.next_action or state.get("next_action", "")
    if not args.branch:
        try:
            args.branch = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                capture_output=True, text=True, cwd=str(project_dir), timeout=10,
            ).stdout.strip()
        except Exception:
            args.branch = ""

    update_claude_md(project_dir, args)


if __name__ == "__main__":
    main()
