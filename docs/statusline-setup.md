# StatusLine Setup Guide
_context-engineering-kit v2.4_

The statusline is a two-line bar at the bottom of Claude Code that updates
after every assistant response. It shows context window usage, rate limit
window, session cost, git branch, and lines changed.

## What it looks like

```
[Claude Sonnet 4.6]  ⎇ master  📁 context-engineering-kit  +3/-1
🟢 ████░░░░░░░░░░░░░░░░ 18%/200K  5h:9%  rst:2h18m  $0.0020  ⏱12s
```

Line 1: model · git branch (dirty count) · directory · lines changed
Line 2: context bar · 5h rate limit · 7d rate limit · session cost · duration

## Installation: automatic

The statusline is pre-configured in `.claude/settings.json`:
```json
"statusLine": { "type": "command", "command": "bash .claude/statusline.sh" }
```

Claude Code uses Git Bash (configured via `CLAUDE_CODE_GIT_BASH_PATH`) to run
the script. It should appear automatically after `setup.sh` runs.

## Workspace trust required

**If the statusline doesn't appear:** Claude Code requires workspace trust before
running statusLine commands. When you open a new project directory for the first
time, accept the trust dialog. If you missed it, restart `claude.cmd` and accept
it at the prompt.

You'll see `statusline skipped · restart to fix` in the status area if trust
hasn't been accepted.

## Troubleshooting

**Test the script directly (Git Bash):**
```bash
echo '{"model":{"display_name":"Claude Sonnet 4.6"},"context_window":{"used_percentage":18,"context_window_size":200000},"cost":{"total_cost_usd":0.002,"total_duration_ms":12000},"rate_limits":{"five_hour":{"used_percentage":9,"resets_at":1780000000}},"workspace":{"current_dir":"D:/Projects/context-engineering-kit","project_dir":"D:/Projects/context-engineering-kit"}}' | bash .claude/statusline.sh
```

Should output two lines. If it doesn't:
- Check jq is installed: `jq --version`
- Check the script has LF line endings: `file .claude/statusline.sh`
- Fix CRLF if needed: `sed -i 's/\r//' .claude/statusline.sh`

## Available data fields

The script can use any of these JSON fields from Claude Code:
```
.model.display_name                      model name
.context_window.used_percentage          context %
.context_window.context_window_size      200000 or 1000000
.cost.total_cost_usd                     session cost
.cost.total_duration_ms                  elapsed ms
.cost.total_lines_added/removed          lines changed
.rate_limits.five_hour.used_percentage   5h window %
.rate_limits.seven_day.used_percentage   7d window %
.rate_limits.five_hour.resets_at         Unix epoch reset time
.workspace.current_dir                   working directory
.workspace.project_dir                   project root
```
