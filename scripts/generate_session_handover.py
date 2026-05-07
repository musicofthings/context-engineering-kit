#!/usr/bin/env python3
"""
generate_session_handover.py
Called by .claude/hooks/pre-compact.sh
Reads .claude/session/state.json and git context to generate/update session_handover.md
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def run(cmd: str, cwd: str = None) -> str:
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, cwd=cwd, timeout=10
        )
        return result.stdout.strip()
    except Exception:
        return ""


def load_state(project_dir: Path) -> dict:
    state_file = project_dir / ".claude" / "session" / "state.json"
    if state_file.exists():
        try:
            return json.loads(state_file.read_text())
        except Exception:
            return {}
    return {}


def load_existing_handover(project_dir: Path) -> dict:
    """Extract structured sections from existing session_handover.md"""
    handover_file = project_dir / "session_handover.md"
    if not handover_file.exists():
        return {}

    content = handover_file.read_text()
    sections = {}

    # Extract active task
    if "## 🎯 Active Task" in content:
        start = content.find("## 🎯 Active Task") + len("## 🎯 Active Task")
        end = content.find("\n## ", start)
        sections["active_task_section"] = content[start:end].strip() if end > 0 else content[start:].strip()

    # Extract completed items
    _completed_header = "## ✅ Completed This Session"
    if _completed_header in content:
        start = content.find(_completed_header) + len(_completed_header)
        end = content.find("\n## ", start + 1)
        sections["completed"] = content[start:end].strip() if end > 0 else content[start:].strip()

    # Extract remaining work
    if "## 📋 Remaining Work" in content:
        start = content.find("## 📋 Remaining Work") + len("## 📋 Remaining Work")
        end = content.find("\n## ", start)
        sections["remaining"] = content[start:end].strip() if end > 0 else content[start:].strip()

    # Extract architecture decisions table
    _decisions_header = "## 🏗 Architecture Decisions Made"
    if _decisions_header in content:
        start = content.find(_decisions_header) + len(_decisions_header)
        end = content.find("\n## ", start)
        sections["decisions"] = content[start:end].strip() if end > 0 else content[start:].strip()

    # Extract critical rules
    if "## ⚠️ Critical Rules" in content:
        start = content.find("## ⚠️ Critical Rules") + len("## ⚠️ Critical Rules")
        end = content.find("\n## ", start)
        sections["rules"] = content[start:end].strip() if end > 0 else content[start:].strip()

    # Extract bioinfo context
    _bioinfo_header = "## 🧬 Bioinformatics Context (if applicable)"
    if _bioinfo_header in content:
        start = content.find(_bioinfo_header) + len(_bioinfo_header)
        sections["bioinfo"] = content[start:].split("---")[0].strip()

    return sections


def get_git_context(project_dir: Path) -> dict:
    cwd = str(project_dir)
    return {
        "branch": run("git rev-parse --abbrev-ref HEAD", cwd) or "unknown",
        "commit": run("git log --oneline -1", cwd) or "none",
        "status": run("git status --short", cwd) or "clean",
        "recent_commits": run("git log --oneline -5", cwd) or "",
        "modified_files": run("git diff --name-only", cwd) or "",
        "staged_files": run("git diff --cached --name-only", cwd) or "",
    }


def generate(args) -> str:
    project_dir = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    state = load_state(project_dir)
    git = get_git_context(project_dir)
    existing = load_existing_handover(project_dir)

    active_task = state.get("active_task", "not set — update via /handover skill")
    phase = state.get("phase", "not set")
    next_action = state.get("next_action", "review session_handover.md")
    compact_count = state.get("compact_count", 0)
    changed_files = state.get("changed_files", [])

    # Pull from CLI args if provided (hook passes these)
    trigger = args.trigger or state.get("trigger", "auto")
    context_pct = args.context_pct or str(state.get("context_pct_at_compact", "unknown"))
    branch = args.branch or git["branch"]
    commit = args.commit or git["commit"]

    # Build modified files section
    all_modified = list(set(
        changed_files
        + [f for f in git["modified_files"].split("\n") if f]
        + [f for f in git["staged_files"].split("\n") if f]
    ))
    MAX_FILES = 15
    if all_modified:
        table_files = all_modified[:MAX_FILES]
        modified_table = "\n".join(f"| `{f}` | modified |" for f in table_files)
        if len(all_modified) > MAX_FILES:
            modified_table += f"\n| _(+{len(all_modified) - MAX_FILES} more files not shown)_ | — |"
    else:
        modified_table = "| (none tracked yet) | — |"

    # Preserve existing sections or use defaults
    completed_section = existing.get("completed", "- [ ] (track completed items here)")
    remaining_section = existing.get("remaining", "1. (add remaining work items here)")
    decisions_section = existing.get("decisions", "| (none yet) | — | — |")
    rules_section = existing.get("rules", "- Never commit secrets or API keys\n- Run /handover before switching devices")
    bioinfo_section = existing.get("bioinfo", "- Not configured for this project")

    handover = f"""# Session Handover
_Generated: {timestamp}_
_Branch: {branch}_
_Trigger: {trigger} | Context at compact: {context_pct}%_
_Compact count this project: {compact_count}_

---

## 🎯 Active Task
**What we're building/fixing:**
{active_task}

**Phase:** {phase}
**Next action:** {next_action}

---

## ✅ Completed This Session
{completed_section}

---

## 🔄 In Progress (Exact Resume Point)
**Branch:** `{branch}`
**Last commit:** `{commit}`
**Next immediate action:** {next_action}

---

## 📋 Remaining Work
{remaining_section}

---

## 🏗 Architecture Decisions Made
| Decision | Rationale | Date |
|----------|-----------|------|
{decisions_section}

---

## 🔧 Commands to Resume
```bash
# On any machine after git pull:
git pull origin {branch}
bash scripts/session_sync.sh --load

# In Claude Code:
# /context-health     — verify hooks are wired
# /handover           — review this file
# /token-status       — check context usage
```

---

## 📁 Files Modified This Session
| File | Status |
|------|--------|
{modified_table}

---

## 🌿 Git Context
```
Branch  : {branch}
Commit  : {commit}
Status  : {git['status'] or 'clean'}
```

Recent commits:
```
{git['recent_commits'] or '(none)'}
```

---

## ⚠️ Critical Rules
{rules_section}

---

## 🧬 Bioinformatics Context (if applicable)
{bioinfo_section}

---
_Auto-updated by `pre-compact.sh` hook and `/handover` skill._
_Read this at the start of every session. Update with `/handover`._
"""

    return handover


def main():
    parser = argparse.ArgumentParser(description="Generate session_handover.md")
    parser.add_argument("--trigger", default="", help="Compact trigger type")
    parser.add_argument("--context-pct", default="", dest="context_pct", help="Context percentage at trigger")
    parser.add_argument("--branch", default="", help="Git branch")
    parser.add_argument("--commit", default="", help="Git commit")
    parser.add_argument("--output", default="", help="Output file (default: session_handover.md)")
    args = parser.parse_args()

    project_dir = Path(os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    output_path = Path(args.output) if args.output else project_dir / "session_handover.md"

    content = generate(args)
    output_path.write_text(content)
    print(f"[handover] Written to {output_path}", file=sys.stderr)
    sys.exit(0)


if __name__ == "__main__":
    main()
