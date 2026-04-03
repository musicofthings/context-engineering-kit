#!/usr/bin/env bash
# .claude/hooks/notify.sh
# Notification hook — cross-platform (Mac + Windows Git Bash + Linux)

MSG="Claude Code needs your attention"
TITLE="context-engineering-kit"

if [[ "$OSTYPE" == "darwin"* ]]; then
  osascript -e "display notification \"$MSG\" with title \"$TITLE\"" 2>/dev/null || true
elif command -v notify-send &>/dev/null; then
  notify-send "$TITLE" "$MSG" 2>/dev/null || true
elif command -v powershell.exe &>/dev/null; then
  powershell.exe -Command "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); \
    [System.Windows.Forms.MessageBox]::Show('$MSG','$TITLE')" 2>/dev/null || true
fi

exit 0
