# .claude/statusline-cek.ps1
# context-engineering-kit statusline — Windows PowerShell version
#
# Install: Add to ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": "powershell.exe -File %USERPROFILE%\\.claude\\statusline-cek.ps1" }
#
# Or for Git Bash users, use the .sh version with:
#   "command": "bash.exe ~/.claude/statusline-cek.sh"

$input_data = $input | ConvertFrom-Json -ErrorAction SilentlyContinue

if (-not $input_data) {
    Write-Host "[context-kit] statusline: no data"
    exit 0
}

# Extract fields
$model     = if ($input_data.model.display_name) { $input_data.model.display_name } else { "unknown" }
$cwd       = if ($input_data.workspace.current_dir) { $input_data.workspace.current_dir } else { (Get-Location).Path }
$ctx_pct   = if ($null -ne $input_data.context_window.used_percentage) { [int]$input_data.context_window.used_percentage } else { 0 }
$ctx_size  = if ($input_data.context_window.context_window_size) { $input_data.context_window.context_window_size } else { 200000 }
$cost      = if ($input_data.cost.total_cost_usd) { $input_data.cost.total_cost_usd } else { 0 }
$dur_ms    = if ($input_data.cost.total_duration_ms) { [long]$input_data.cost.total_duration_ms } else { 0 }
$lines_add = if ($input_data.cost.total_lines_added) { $input_data.cost.total_lines_added } else { 0 }
$lines_del = if ($input_data.cost.total_lines_removed) { $input_data.cost.total_lines_removed } else { 0 }
$rl_5h     = if ($null -ne $input_data.rate_limits.five_hour.used_percentage) { [int]$input_data.rate_limits.five_hour.used_percentage } else { -1 }
$rl_7d     = if ($null -ne $input_data.rate_limits.seven_day.used_percentage) { [int]$input_data.rate_limits.seven_day.used_percentage } else { -1 }
$rl_5h_reset = if ($input_data.rate_limits.five_hour.resets_at) { [long]$input_data.rate_limits.five_hour.resets_at } else { 0 }

# Derive
$dir       = Split-Path $cwd -Leaf
$dur_s     = [int]($dur_ms / 1000)
if ($dur_s -lt 60)        { $dur_str = "${dur_s}s" }
elseif ($dur_s -lt 3600)  { $dur_str = "$([int]($dur_s/60))m$($dur_s % 60)s" }
else                      { $dur_str = "$([int]($dur_s/3600))h$([int](($dur_s%3600)/60))m" }

$cost_str  = '$' + ("{0:F4}" -f $cost)
$ctx_label = if ($ctx_size -ge 900000) { "1M" } else { "200K" }

# Context bar (20 chars)
$bar_width = 20
$filled    = [int](($ctx_pct * $bar_width) / 100)
$filled    = [Math]::Min($filled, $bar_width)
$ctx_bar   = ("█" * $filled) + ("░" * ($bar_width - $filled))

# Status indicators (no ANSI on basic PS, use symbols)
$ctx_status = if ($ctx_pct -ge 85) { "🔴" } elseif ($ctx_pct -ge 70) { "🟠" } elseif ($ctx_pct -ge 50) { "🟡" } else { "🟢" }

# Rate limit reset time
$reset_str = ""
if ($rl_5h_reset -gt 0) {
    $now_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $secs_left = $rl_5h_reset - $now_epoch
    if ($secs_left -gt 0) {
        $mins_left = [int]($secs_left / 60)
        $reset_str = if ($mins_left -lt 60) { " (resets ${mins_left}m)" } else { " (resets $([int]($mins_left/60))h$($mins_left%60)m)" }
    }
}

# Git info
$git_branch = ""
$git_dirty  = ""
try {
    $git_branch = (git -C $cwd rev-parse --abbrev-ref HEAD 2>$null).Trim()
    $dirty      = (git -C $cwd status --short 2>$null | Measure-Object -Line).Lines
    if ($dirty -gt 0) { $git_dirty = "*$dirty" }
} catch { }

# Line 1: model | git | dir | lines
$line1 = "[$model]"
if ($git_branch) { $line1 += "  ⎇ $git_branch$git_dirty" }
$line1 += "  📁 $dir"
if ($lines_add -gt 0 -or $lines_del -gt 0) {
    $line1 += "  +$lines_add/-$lines_del"
} else {
    $line1 += "  no changes"
}

# Line 2: context bar | rate limits | cost | duration
$line2 = "$ctx_status $ctx_bar ${ctx_pct}%/$ctx_label"
if ($rl_5h -ge 0) { $line2 += "  5h:${rl_5h}%$reset_str" }
if ($rl_7d -gt 0) { $line2 += "  7d:${rl_7d}%" }
$line2 += "  $cost_str  ⏱$dur_str"

Write-Host $line1
Write-Host $line2
