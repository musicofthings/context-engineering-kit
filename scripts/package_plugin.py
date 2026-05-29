#!/usr/bin/env python3
"""
package_plugin.py — build a versioned plugin zip for Claude Desktop upload.

Reads version from .claude-plugin/plugin.json, walks the project root,
applies an exclusion list (vcs, runtime state, machine-local files,
caches), and writes context-engineering-kit-<version>.zip in the project
root.

Usage:
    python scripts/package_plugin.py
    python scripts/package_plugin.py --out path/to/file.zip
"""

import argparse
import fnmatch
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Patterns matched against POSIX-style paths relative to project root.
# Directory matches use a trailing slash (e.g. ".git/").
EXCLUDE_DIRS = {
    ".git",
    ".claude/session",
    ".claude/worktrees",
    "briefs",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
    ".idea",
    ".vscode",
    "dist",
    "build",
}

EXCLUDE_FILES = {
    ".claude/settings.local.json",
    ".claude/config-audit.log",
    ".claude/compact-audit.log",
    ".DS_Store",
    "Thumbs.db",
    "desktop.ini",
}

EXCLUDE_GLOBS = [
    "*.pyc",
    "*.pyo",
    "*.swp",
    "*.zip",
    "*.tar.gz",
]


def is_excluded(rel_posix: str, is_dir: bool) -> bool:
    if is_dir:
        return rel_posix in EXCLUDE_DIRS or any(
            rel_posix.startswith(d + "/") for d in EXCLUDE_DIRS
        )
    if rel_posix in EXCLUDE_FILES:
        return True
    parent = rel_posix.rsplit("/", 1)[0] if "/" in rel_posix else ""
    if parent in EXCLUDE_DIRS or any(parent.startswith(d + "/") for d in EXCLUDE_DIRS):
        return True
    name = rel_posix.rsplit("/", 1)[-1]
    return any(fnmatch.fnmatch(name, g) for g in EXCLUDE_GLOBS)


def read_version() -> str:
    manifest = ROOT / ".claude-plugin" / "plugin.json"
    return json.loads(manifest.read_text(encoding="utf-8"))["version"]


def build(out_path: Path) -> tuple[int, int]:
    file_count = 0
    total_bytes = 0
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path in sorted(ROOT.rglob("*")):
            rel = path.relative_to(ROOT).as_posix()
            if rel == out_path.name:
                continue  # don't include the zip in itself
            if is_excluded(rel, path.is_dir()):
                continue
            if path.is_file():
                zf.write(path, arcname=rel)
                file_count += 1
                total_bytes += path.stat().st_size
    return file_count, total_bytes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=None,
                        help="Output path (default: context-engineering-kit-<version>.zip)")
    args = parser.parse_args()

    version = read_version()
    out_path = args.out or (ROOT / f"context-engineering-kit-{version}.zip")
    out_path = out_path.resolve()

    if out_path.exists():
        out_path.unlink()

    print(f"[package] version: {version}")
    print(f"[package] writing: {out_path}")
    file_count, total_bytes = build(out_path)
    final_size = out_path.stat().st_size
    print(f"[package] included: {file_count} files ({total_bytes:,} raw bytes)")
    print(f"[package] zip size: {final_size:,} bytes")
    print(f"[package] OK")


if __name__ == "__main__":
    main()
