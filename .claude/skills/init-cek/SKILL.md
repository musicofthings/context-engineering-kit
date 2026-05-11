---
name: init-cek
description: Bootstrap context-engineering-kit in any project folder — creates CLAUDE.md, session_handover.md, state.json, and usage config so auto-save, /handover, and context tracking work from the very first session. Run once per project.
user-invocable: true
args: "[project description] — optional one-line description; if omitted, Claude infers from the codebase"
---

# CEK Project Init

Run this skill when the user types `/init-cek` or `/init cek`.

This skill bootstraps the **context-engineering-kit (CEK) scaffolding** in the current project directory. It creates the files that CEK hooks and skills depend on, so context auto-save, `/handover`, and usage tracking work immediately — no manual setup needed.

---

## Step 1 — Analyse the project

Before writing anything, scan the project:

```bash
ls -la                          # root layout
git rev-parse --abbrev-ref HEAD # current branch
git log --oneline -1            # last commit
```

Check which of these already exist (skip creation for those that do, unless `--force` was passed):
- `CLAUDE.md`
- `session_handover.md`
- `.claude/session/state.json`
- `config/usage_budget.json`

Note the project type from the file listing (Node, Python, Go, etc.) and any existing README or package.json for the project description.

---

## Step 2 — Create CLAUDE.md (if missing)

Analyse the codebase and write a project-specific `CLAUDE.md`. Use the template at `templates/CLAUDE.md.template` as the structure, filling in real values:

- `{{PROJECT_NAME}}` — infer from directory name, package.json, pyproject.toml, or README
- `{{PROJECT_DESCRIPTION}}` — 1–3 sentences describing what the project does
- `{{QUICK_ORIENTATION}}` — key entry points, important modules, what to read first
- `{{PROJECT_TREE}}` — a concise tree (important dirs/files only, not exhaustive)
- `{{ADD_PROJECT_SPECIFIC_RULES}}` — infer from the project (e.g. "always run tests before committing", "migrations must be reviewed")
- `{{ADD_PROJECT_COMMANDS_HERE}}` — real commands from package.json scripts, Makefile, or README

If `CLAUDE.md` already exists and contains real content (not just template placeholders), **do not overwrite it**. Ask the user if they want to regenerate it.

---

## Step 3 — Create session_handover.md (if missing)

Use the template at `templates/session_handover.template.md`, substituting:

- `{{TIMESTAMP}}` — current ISO timestamp (`date -u +"%Y-%m-%dT%H:%M:%SZ"`)
- `{{GIT_BRANCH}}` — current branch name
- `{{GIT_LAST_COMMIT}}` — last commit hash + message, or `"no commits yet"` for a fresh repo

---

## Step 4 — Create .claude/session/state.json (if missing)

Create `.claude/session/` directory if needed, then write:

```json
{
  "last_updated": "<ISO timestamp>",
  "initialized_by": "<hostname>",
  "active_task": "initial setup",
  "phase": "Phase 0 — Setup",
  "next_action": "run /context-health in Claude Code",
  "compact_count": 0,
  "session_cost_usd": "0",
  "changed_files": []
}
```

---

## Step 5 — Create config/usage_budget.json (if missing)

Create `config/` directory if needed, then write:

```json
{
  "_doc": "Configure your Claude subscription type and daily limits. The usage-sentinel hook reads this on every prompt.",
  "subscription_type": "pro",
  "subscriptions": {
    "pro":  { "window_type": "time", "window_minutes": 300, "note": "Pro: 5-hour window." },
    "max":  { "window_type": "time", "window_minutes": 300, "note": "Max: same 5-hour window, 5× throughput." },
    "api":  { "window_type": "cost", "daily_budget_usd": 10.00, "note": "API: set your daily cost limit." },
    "team": { "window_type": "time", "window_minutes": 300, "note": "Team: per-seat, same window as Pro." }
  },
  "thresholds": {
    "warn_pct": 70,
    "pre_save_pct": 80,
    "auto_save_pct": 85,
    "critical_pct": 92
  },
  "actions": {
    "at_warn":      "inject_warning",
    "at_pre_save":  "inject_save_reminder",
    "at_auto_save": "inject_save_directive",
    "at_critical":  "inject_save_directive_urgent"
  }
}
```

Tell the user to change `subscription_type` to match their account (pro / max / api / team).

---

## Step 6 — Git commit (if in a git repo and not in a worktree)

Check if we're in a git repo and NOT in a linked worktree:

```bash
git rev-parse --git-dir   # contains /worktrees/ → skip commit, we're in a worktree
```

If safe to commit:
```bash
git add CLAUDE.md session_handover.md .claude/session/state.json config/usage_budget.json
git commit -m "chore(context): init CEK scaffolding [<timestamp>]"
```

If not a git repo at all, suggest `git init` but do not run it automatically.

---

## Step 7 — Report

Output a clean summary:

```
╔══════════════════════════════════════════════════════════╗
║  /init-cek complete                                       ║
╚══════════════════════════════════════════════════════════╝

  CLAUDE.md              ✅ [created | already existed — skipped]
  session_handover.md    ✅ [created | already existed — skipped]
  .claude/session/       ✅ [created | already existed — skipped]
  config/usage_budget.json ✅ [created | already existed — skipped]

Auto-save thresholds (edit config/usage_budget.json to tune):
  70%  → warning injected
  80%  → save reminder injected
  85%  → /handover runs automatically before next response
  92%  → urgent: /handover + /session-sync save run immediately

Next steps:
  /context-health   — verify all hooks are wired and firing
  /token-status     — confirm usage monitoring is live
  /handover         — review and refine the initial handover doc
```

---

## Edge cases

| Situation | Behaviour |
|-----------|-----------|
| File already exists with real content | Skip, report "already existed — skipped" |
| File exists but is empty or template-only | Offer to regenerate |
| Not a git repo | Create files, skip git commit, suggest `git init` |
| In a linked worktree | Create files, skip git commit (state lives on main branch) |
| `--force` arg passed | Overwrite all files, even if they already exist |
| User provides a description arg | Use it as `{{PROJECT_DESCRIPTION}}` instead of inferring |
