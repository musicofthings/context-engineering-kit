# Windows No-Admin Install Guide

Installing Claude Code on a Windows machine without local administrator rights.

## Prerequisites

- Windows 10/11 (no admin required)
- Node.js ≥ 18 installed via `nvm-windows` or a per-user installer
- PowerShell 5.1+ or Windows Terminal

## Step 1 — Install Node.js without admin

Download the **"Windows Binary (.zip)"** build from https://nodejs.org/en/download and
extract it to `%USERPROFILE%\node`. Then add it to your PATH:

```powershell
[Environment]::SetEnvironmentVariable(
  "PATH",
  "$env:USERPROFILE\node;$env:USERPROFILE\node\node_modules\.bin;$env:PATH",
  "User"
)
```

Restart your terminal and verify: `node --version`

## Step 2 — Install Claude Code

```powershell
npm install -g @anthropic-ai/claude-code
```

npm installs global packages to `%APPDATA%\npm` by default on Windows. Confirm the
directory is on your PATH:

```powershell
$env:APPDATA + "\npm" -in $env:PATH.Split(";")
```

If it returns `False`:

```powershell
[Environment]::SetEnvironmentVariable(
  "PATH",
  "$env:APPDATA\npm;$env:PATH",
  "User"
)
```

## Step 3 — Use `claude.cmd`, not `claude`

The Claude Desktop app registers a conflicting `claude` entry in PATH. Always invoke
Claude Code via:

```powershell
claude.cmd
```

Or create a per-session alias:

```powershell
Set-Alias claude claude.cmd
```

Add that line to your `$PROFILE` to make it permanent.

## Step 4 — Verify setup.sh can find Claude

`setup.sh` calls `claude.cmd --version` to verify the install. If the check fails,
confirm `%APPDATA%\npm` appears in PATH **before** any Claude Desktop entry:

```powershell
$env:PATH.Split(";") | Select-String "npm|Claude"
```

The npm entry should be listed first.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `claude` opens Claude Desktop instead of CLI | Use `claude.cmd` explicitly |
| `npm install -g` fails with EPERM | Set `npm config set prefix %APPDATA%\npm` |
| Hooks not running | Confirm WSL or Git Bash is used; native cmd.exe doesn't execute `.sh` hooks |
| `jq` not found | Install via `winget install jqlang.jq` (no admin) |

## WSL alternative

If you can use WSL2 (it installs per-user on modern Windows 11 via the Store), the
Linux install path in `setup.sh` works without any of the above workarounds.
