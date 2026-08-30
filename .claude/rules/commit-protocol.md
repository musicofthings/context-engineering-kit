# Commit Protocol
_Loaded automatically by Claude Code from .claude/rules/_

## Solo default — commit on `main`

This is a **solo-developer** repo. Prefer committing and pushing directly on
`main` / `master`. Do **not** create feature branches, fix branches, or
worktrees unless the user asks for them or the change truly needs isolation
(e.g. experimental spike, parallel unfinished work, or a PR for an external
collaborator).

## Rules that always apply to git operations

- **Default branch:** commit on `main` (or `master` if that is the default)
- Only use a side branch when the user requests one, or when isolation is clearly needed
- Always use descriptive commit messages with conventional prefix:
  - `feat:` new feature
  - `fix:` bug fix
  - `chore(context):` context file updates (session state, handover, CLAUDE.md)
  - `docs:` documentation
  - `refactor:` code restructure, no behaviour change
- Never include API keys, secrets, or patient data in commits
- Session state commits use `--no-verify` (hooks already ran)
- Before committing: check `git diff --stat` to confirm only intended files staged
- After major work: tag with `git tag v[version]`
- Ask before `git push` only if the user has not already asked to ship/push;
  when they say "commit to main" that includes a local commit on main — push
  only when they also ask to push, or when a prior instruction already covers it

## Protected files — never commit these directly

- `.env` and `.env.*`
- `production.*`
- Any file containing `sk-ant-`, `ghp_`, or other token patterns

## Branch strategy (optional, not the default)

- Default: work and commit on `main`
- Optional feature branches only when requested: `feat/description`
- Optional bugfix branches only when requested: `fix/description`
- Context updates: auto-committed by `session-end.sh` to the current branch
- Worktrees: use only when the user asks or when running parallel isolated agents
