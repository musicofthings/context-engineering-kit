#!/usr/bin/env bash
# .claude/statusline-launcher.sh
#
# Cross-platform statusline launcher — part of context-engineering-kit plugin.
# Called by the statusLine.command in .claude/settings.json.
#
# How it works:
#   1. Reads ALL stdin (the JSON Claude Code sends) into a variable
#   2. Extracts workspace.project_dir from the JSON — no hardcoded paths
#   3. Detects platform (Windows via powershell.exe presence, else Mac/Linux)
#   4. Passes the JSON to the right platform script via temp file (Windows)
#      or stdin (Mac/Linux)
#
# This file is committed to the repo. Works on any machine that clones it.

set -euo pipefail

# ── Step 1: Read ALL stdin before doing anything else ────────────────────────
# We must capture it now — stdin can only be read once
DATA=$(cat)

# ── Step 2: Extract project dir from the JSON ────────────────────────────────
PROJECT_DIR=""

# Try jq first (fast, reliable)
if command -v jq &>/dev/null; then
    PROJECT_DIR=$(printf '%s' "$DATA" | jq -r '.workspace.project_dir // empty' 2>/dev/null || true)
fi

# Fallback: use CLAUDE_PROJECT_DIR env var (set by Claude Code for hooks)
if [[ -z "$PROJECT_DIR" ]] && [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    PROJECT_DIR="$CLAUDE_PROJECT_DIR"
fi

# Fallback: use current directory
if [[ -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$(pwd)"
fi

# Normalise Windows paths (C:\foo\bar → /c/foo/bar in Git Bash)
PROJECT_DIR="${PROJECT_DIR//\\//}"

# ── Step 3: Verify the script exists ─────────────────────────────────────────
BASH_SCRIPT="$PROJECT_DIR/.claude/statusline-cek.sh"
PS1_SCRIPT="$PROJECT_DIR/.claude/statusline-cek.ps1"

# ── Step 4: Dispatch to platform script ──────────────────────────────────────
if command -v powershell.exe &>/dev/null 2>&1; then
    # ── Windows (Git Bash) ───────────────────────────────────────────────────
    # PowerShell can't read stdin reliably when called from Git Bash.
    # Write JSON to a temp file and pass the path as $args[0].
    TMPFILE=$(mktemp).json
    printf '%s' "$DATA" > "$TMPFILE"

    # Convert Git Bash path to Windows path for PowerShell
    WIN_SCRIPT=$(cygpath -w "$PS1_SCRIPT" 2>/dev/null || echo "$PS1_SCRIPT")
    WIN_TMPFILE=$(cygpath -w "$TMPFILE" 2>/dev/null || echo "$TMPFILE")

    powershell.exe -NoProfile -File "$WIN_SCRIPT" "$WIN_TMPFILE" 2>/dev/null
    rm -f "$TMPFILE" 2>/dev/null || true

elif [[ -f "$BASH_SCRIPT" ]]; then
    # ── Mac / Linux ──────────────────────────────────────────────────────────
    printf '%s' "$DATA" | bash "$BASH_SCRIPT"

else
    # ── Fallback: minimal inline output ─────────────────────────────────────
    CTX=$(printf '%s' "$DATA" | jq -r '.context_window.used_percentage // 0' 2>/dev/null || echo "?")
    MODEL=$(printf '%s' "$DATA" | jq -r '.model.display_name // "Claude"' 2>/dev/null || echo "Claude")
    echo "[$MODEL] context: ${CTX}%  (install statusline-cek.sh for full display)"
fi
