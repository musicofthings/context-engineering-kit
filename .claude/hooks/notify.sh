#!/usr/bin/env bash
# .claude/hooks/notify.sh
set -euo pipefail

# Notification hook — uses terminalSequence (Claude Code v2.1.141+) as the
# primary path. Falls back to platform-specific desktop notifications for
# older versions or environments where the terminal doesn't support OSC 777.
#
# Hooks run without a controlling terminal, so writing escape sequences to
# /dev/tty is not supported. terminalSequence emits through Claude Code's own
# terminal write path and works inside tmux, screen, and Windows Terminal.

INPUT=$(cat 2>/dev/null || true)
MSG=$(printf '%s' "$INPUT" | jq -r '.message // "Claude Code needs your attention"' 2>/dev/null || echo "Claude Code needs your attention")
TITLE="context-engineering-kit"

# ── Primary: terminalSequence (OSC 777 — urxvt/Ghostty/Warp/iTerm2) ──────────
# Build the escape sequence with printf octal escapes so control bytes never
# appear in the shell command line. jq --arg escapes the value for JSON safely.
SEQ=$(printf '\033]777;notify;%s;%s\007' "$TITLE" "$MSG")
jq -nc --arg seq "$SEQ" '{"terminalSequence": $seq}'

# ── Fallback: platform-specific desktop notifications ─────────────────────────
# These fire after the JSON response — Claude Code processes them as side effects.
# They handle terminals that don't support OSC 777.
if [[ "$OSTYPE" == "darwin"* ]]; then
  osascript -e "display notification \"$MSG\" with title \"$TITLE\"" 2>/dev/null || true
elif command -v notify-send &>/dev/null; then
  notify-send "$TITLE" "$MSG" 2>/dev/null || true
elif command -v powershell.exe &>/dev/null; then
  powershell.exe -Command "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); [System.Windows.Forms.MessageBox]::Show([string]::Copy('${MSG//\'/\'\'}'),'${TITLE//\'/\'\'}')" 2>/dev/null || true
fi

exit 0
