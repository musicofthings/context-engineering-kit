# schedule_morning_brief.ps1
# Registers a Windows Task Scheduler job to run the morning brief daily at 07:00.
# Run once from PowerShell (no admin needed for current-user tasks):
#   powershell -ExecutionPolicy Bypass -File scripts\schedule_morning_brief.ps1

$TaskName   = "AI-Morning-Brief"
$ScriptPath = (Resolve-Path "$PSScriptRoot\..\scripts\morning_brief.py").Path
$ProjectDir = (Resolve-Path "$PSScriptRoot\..").Path
$PythonExe  = (Get-Command python).Source
$LogDir     = Join-Path $ProjectDir "briefs"

# Ensure briefs directory exists
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$Action = New-ScheduledTaskAction `
    -Execute $PythonExe `
    -Argument "`"$ScriptPath`" --quiet" `
    -WorkingDirectory $ProjectDir

$Trigger = New-ScheduledTaskTrigger -Daily -At "07:00"

$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

# Register (or update if already exists)
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Set-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings
    Write-Host "Updated existing task: $TaskName"
} else {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Trigger `
        -Settings $Settings `
        -RunLevel Limited `
        -Force
    Write-Host "Registered new task: $TaskName"
}

Write-Host ""
Write-Host "Task '$TaskName' will run daily at 07:00."
Write-Host "Output saved to: $LogDir\YYYY-MM-DD.md"
Write-Host ""
Write-Host "To run manually now:"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  # or: python scripts/morning_brief.py --save"
