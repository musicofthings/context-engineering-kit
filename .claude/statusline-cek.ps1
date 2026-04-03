# .claude/statusline-cek.ps1 — context-engineering-kit v2.4
# Called by statusline-launcher.sh with temp file path as first arg.
# Can also be called directly with JSON on stdin.

param([string]$TempFile = "")

# Read JSON — temp file path passed by launcher, or direct stdin
if ($TempFile -and (Test-Path $TempFile)) {
    $raw = Get-Content $TempFile -Raw -Encoding utf8
} else {
    $raw = [Console]::In.ReadToEnd().Trim()
}

if (-not $raw -or $raw.Length -lt 5) { Write-Host "[CEK] waiting..."; exit 0 }

try { $d = $raw | ConvertFrom-Json }
catch { Write-Host "[CEK] JSON error"; exit 0 }

# Fields
$model   = if ($d.model.display_name)                              { $d.model.display_name }              else { "Claude" }
$cwd     = if ($d.workspace.current_dir)                          { $d.workspace.current_dir }            else { (Get-Location).Path }
$ctx_pct = if ($null -ne $d.context_window.used_percentage)      { [int]$d.context_window.used_percentage } else { 0 }
$ctx_sz  = if ($d.context_window.context_window_size -gt 0)      { [int]$d.context_window.context_window_size } else { 200000 }
$cost    = if ($d.cost.total_cost_usd -gt 0)                     { [double]$d.cost.total_cost_usd }       else { 0.0 }
$dur_ms  = if ($d.cost.total_duration_ms -gt 0)                  { [long]$d.cost.total_duration_ms }      else { 0 }
$ladd    = if ($d.cost.total_lines_added -gt 0)                  { [int]$d.cost.total_lines_added }       else { 0 }
$ldel    = if ($d.cost.total_lines_removed -gt 0)               { [int]$d.cost.total_lines_removed }     else { 0 }
$rl5     = if ($null -ne $d.rate_limits.five_hour.used_percentage) { [int]$d.rate_limits.five_hour.used_percentage } else { -1 }
$rl7     = if ($null -ne $d.rate_limits.seven_day.used_percentage)  { [int]$d.rate_limits.seven_day.used_percentage }  else { -1 }
$rst_at  = if ($d.rate_limits.five_hour.resets_at -gt 0)         { [long]$d.rate_limits.five_hour.resets_at } else { 0 }

# Derived
$dir      = Split-Path $cwd -Leaf
$dur_s    = [int]($dur_ms / 1000)
$dur_str  = if ($dur_s -lt 60){"${dur_s}s"} elseif ($dur_s -lt 3600){"$([int]($dur_s/60))m$($dur_s%60)s"} else{"$([int]($dur_s/3600))h$([int](($dur_s%3600)/60))m"}
$cost_str = '$' + ("{0:F4}" -f $cost)
$ctx_lbl  = if ($ctx_sz -ge 900000){"1M"} else{"200K"}

# Context bar
$filled  = [Math]::Min([int](($ctx_pct * 20) / 100), 20)
$ctx_bar = ("█" * $filled) + ("░" * (20 - $filled))
$ctx_icn = if ($ctx_pct -ge 85){"🔴"} elseif ($ctx_pct -ge 70){"🟠"} elseif ($ctx_pct -ge 50){"🟡"} else{"🟢"}

# Rate limit reset
$rst_str = ""
if ($rst_at -gt 0) {
    $left = $rst_at - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($left -gt 0) {
        $ml = [int]($left / 60)
        $rst_str = if ($ml -lt 60){" rst:${ml}m"} else{" rst:$([int]($ml/60))h$($ml%60)m"}
    }
}

# Git (best-effort)
$branch = ""; $dirty = ""
try {
    $branch = (git -C $cwd rev-parse --abbrev-ref HEAD 2>$null).Trim()
    $dc = (git -C $cwd status --short 2>$null | Measure-Object -Line).Lines
    if ($dc -gt 0) { $dirty = "*$dc" }
} catch {}

# Two-line output
$ln1 = "[$model]"
if ($branch) { $ln1 += "  ⎇ $branch$dirty" }
$ln1 += "  📁 $dir"
if ($ladd -gt 0 -or $ldel -gt 0) { $ln1 += "  +$ladd/-$ldel" }

$ln2 = "$ctx_icn $ctx_bar ${ctx_pct}%/$ctx_lbl"
if ($rl5 -ge 0) { $ln2 += "  5h:${rl5}%${rst_str}" }
if ($rl7 -gt 0) { $ln2 += "  7d:${rl7}%" }
$ln2 += "  $cost_str  ⏱$dur_str"

Write-Host $ln1
Write-Host $ln2
