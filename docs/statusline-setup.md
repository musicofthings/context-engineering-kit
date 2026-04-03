# StatusLine Setup Guide
_context-engineering-kit v2.3_

The statusline is a persistent bar at the bottom of Claude Code that updates
after every assistant response. It shows context window usage, rate limit
window consumption, session cost, git branch, and lines changed.

---

## What it looks like

```
[Claude Sonnet 4.6]  ⎇ main*3  📁 context-engineering-kit  +42/-7
████████████░░░░░░░░ 61%/200K  5h:34%  resets 2h18m  7d:12%  $0.0041  ⏱4m22s
```

Line 1: model name · git branch (dirty count) · directory · lines added/removed  
Line 2: context bar · 5h rate limit · 7d rate limit · session cost · duration

---

## Installation: Mac / Linux

The statusline is pre-configured in `.claude/settings.json` to use
`.claude/statusline-cek.sh`. It should work immediately after `bash setup.sh`.

Verify it's running: look for the two-line bar at the bottom of Claude Code
after your first exchange.

**If it doesn't appear:** check that `jq` is installed:
```bash
which jq || brew install jq   # Mac
which jq || apt install jq    # Linux
```

---

## Installation: Windows (PowerShell)

Edit `.claude/settings.json` — change the `statusLine.command` to:
```json
"statusLine": {
  "type": "command",
  "command": "powershell.exe -File \"%CLAUDE_PROJECT_DIR%\\.claude\\statusline-cek.ps1\"",
  "padding": 1
}
```

Or if using Git Bash, keep the bash version:
```json
"command": "bash.exe \"%CLAUDE_PROJECT_DIR%/.claude/statusline-cek.sh\""
```

Note: ANSI colour codes work in Windows Terminal and VS Code terminal but not
in basic `cmd.exe`. The PowerShell version uses emoji status indicators instead.

---

## User-scope vs project-scope

The statusline in `.claude/settings.json` (project scope) applies only to
this project. To use it across all your projects, move the `statusLine` block
to `~/.claude/settings.json` (user scope) and change the command path:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/statusline-cek.sh"
}
```

Then copy `.claude/statusline-cek.sh` to `~/.claude/statusline-cek.sh`:
```bash
cp .claude/statusline-cek.sh ~/.claude/statusline-cek.sh
chmod +x ~/.claude/statusline-cek.sh
```

---

## What the rate limit numbers mean

| Field | What it shows |
|-------|--------------|
| `5h: 34%` | 34% of your 5-hour rolling window is consumed |
| `resets 2h18m` | Window resets in 2 hours 18 minutes |
| `7d: 12%` | 12% of your 7-day window consumed |

When `5h` hits ~80%+, the bar turns amber/red and Claude Code will start
rate-limiting. Run `/compact-smart` to reduce context and extend the session.

The statusline reads these values directly from Claude Code's internal data —
this is real subscription window data, not an estimate.

---

## Using `/statusline` to regenerate

Claude Code has a built-in `/statusline` command that can regenerate the script:
```
/statusline show model, context bar, 5h rate limit with reset time, cost and git branch
```

This will overwrite `statusline-cek.sh`. Re-run `setup.sh` to restore the
context-engineering-kit version if needed.

---

## Customising the statusline

Edit `.claude/statusline-cek.sh` directly. The JSON fields available are:

```bash
# All fields you can use:
jq -r '.model.display_name'                      # model name
jq -r '.context_window.used_percentage'          # context %
jq -r '.context_window.context_window_size'      # 200000 or 1000000
jq -r '.cost.total_cost_usd'                     # session cost
jq -r '.cost.total_duration_ms'                  # elapsed ms
jq -r '.cost.total_lines_added'                  # lines added
jq -r '.cost.total_lines_removed'                # lines removed
jq -r '.rate_limits.five_hour.used_percentage'   # 5h window %
jq -r '.rate_limits.seven_day.used_percentage'   # 7d window %
jq -r '.rate_limits.five_hour.resets_at'         # Unix epoch reset time
jq -r '.workspace.current_dir'                   # working directory
jq -r '.session_id'                              # session ID
jq -r '.version'                                 # Claude Code version
```
