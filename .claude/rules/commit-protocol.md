# Commit Protocol
_Loaded automatically by Claude Code from .claude/rules/_

## Rules that always apply to git operations

- Never commit directly to `main` or `master`
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

## Protected files — never commit these directly

- `.env` and `.env.*`
- `production.*`
- Any file containing `sk-ant-`, `ghp_`, or other token patterns

## Branch strategy

- Feature branches: `feat/description`
- Bug fixes: `fix/description`
- Context updates: auto-committed by `session-end.sh` to current branch
