#!/usr/bin/env bash
# Fire every wired hook with a realistic payload in a throwaway repo and check
# it exits cleanly AND produces its documented side effect.
# Runs in PLUGIN MODE (CLAUDE_PLUGIN_ROOT=kit, CLAUDE_PROJECT_DIR=sandbox),
# which is what installed users actually get.

set -uo pipefail

KIT="${KIT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/cek-hooks.XXXXXX")
export CLAUDE_PLUGIN_ROOT="$KIT"
export CLAUDE_PROJECT_DIR="$SANDBOX"
TRANSCRIPT="$SANDBOX/transcript.jsonl"
STATE="$SANDBOX/.claude/session/state.json"

pass=0; fail=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s — %s\n' "$1" "${2:-}"; fail=$((fail+1)); }
head_() { printf '\n▶ %s\n' "$1"; }

git -C "$SANDBOX" init -q
git -C "$SANDBOX" config user.email eval@test
git -C "$SANDBOX" config user.name eval
mkdir -p "$SANDBOX/.claude/session"
printf '# Sandbox\n' > "$SANDBOX/CLAUDE.md"
git -C "$SANDBOX" add -A >/dev/null 2>&1
git -C "$SANDBOX" commit -qm init >/dev/null 2>&1

# Two assistant turns so transcript-derived counters have something real.
cat > "$TRANSCRIPT" <<EOF
{"type":"assistant","message":{"model":"claude-opus-5","usage":{"input_tokens":120,"output_tokens":40},"content":[{"type":"text","text":"Working on the parser refactor. Next: I will run the integration tests."}]}}
{"type":"assistant","message":{"model":"claude-opus-5","usage":{"input_tokens":300,"output_tokens":90},"content":[{"type":"text","text":"Phase 2 complete. Next: I will wire the CLI flag and update docs."}]}}
EOF

# fire <hook.sh> <json>  -> sets RC / OUT / ERR
fire() {
  local hook="$1" payload="$2"
  OUT=$(printf '%s' "$payload" | bash "$KIT/.claude/hooks/$hook" 2>"$SANDBOX/.err")
  RC=$?
  ERR=$(cat "$SANDBOX/.err")
}
jqs() { jq -r "$1" "$STATE" 2>/dev/null || echo ""; }

SID="sess-eval-001"
BASE="\"session_id\":\"$SID\",\"transcript_path\":\"$TRANSCRIPT\",\"cwd\":\"$SANDBOX\""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  CEK hook + trigger smoke evals                          ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "sandbox: $SANDBOX"

# ── SessionStart ─────────────────────────────────────────────────────────────
head_ "SessionStart"
fire session-start.sh "{$BASE,\"source\":\"startup\",\"hook_event_name\":\"SessionStart\"}"
[ "$RC" -eq 0 ] && ok "session-start.sh exit 0" || bad "session-start.sh exit 0" "rc=$RC $ERR"
echo "$OUT" | grep -q "context-engineering-kit v" && ok "banner injected" || bad "banner injected" "no banner"
[ -f "$STATE" ] && ok "state.json created" || bad "state.json created" "missing"
[ "$(jqs '.session_id')" = "$SID" ] && ok "session_id recorded from stdin" || bad "session_id recorded" "got '$(jqs '.session_id')'"
[ -n "$(jqs '.session_start_time')" ] && ok "session_start_time set" || bad "session_start_time set" "empty"
[ "$(jqs '.transcript_path')" = "$TRANSCRIPT" ] && ok "transcript_path recorded" || bad "transcript_path recorded" ""
git -C "$SANDBOX" status --porcelain | grep -q '.claude/session' \
  && bad "kit invisible to host repo" "session dir is dirtying git status" \
  || ok "kit invisible to host repo (.gitignore dropped)"

head_ "SessionStart — other wired hooks"
for h in session-title.sh compact-restore.sh morning-brief-auto.sh; do
  fire "$h" "{$BASE,\"source\":\"startup\",\"hook_event_name\":\"SessionStart\"}"
  [ "$RC" -eq 0 ] && ok "$h exit 0" || bad "$h exit 0" "rc=$RC $ERR"
done

# ── UserPromptSubmit ─────────────────────────────────────────────────────────
head_ "UserPromptSubmit — usage-sentinel"
fire usage-sentinel.sh "{$BASE,\"prompt\":\"hello\",\"hook_event_name\":\"UserPromptSubmit\"}"
[ "$RC" -eq 0 ] && ok "usage-sentinel exit 0 (fresh window, quiet)" || bad "usage-sentinel exit 0" "rc=$RC $ERR"
[ -z "$OUT" ] && ok "silent below warn threshold" || ok "emitted notice: $(echo "$OUT"|head -1)"

# Force 95% via forecast file -> must EXECUTE a handover, not just warn
cat > "$SANDBOX/.claude/session/usage-forecast.json" <<EOF
{"updated":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","rl_5h_pct":95,"pct_used":95,"data_source":"rate_limit_window"}
EOF
fire usage-sentinel.sh "{$BASE,\"prompt\":\"hi\",\"hook_event_name\":\"UserPromptSubmit\"}"
echo "$OUT" | grep -qi "critical" && ok "95% triggers CRITICAL branch" || bad "95% triggers CRITICAL" "out=$(echo "$OUT"|head -2)"
[ -f "$SANDBOX/session_handover.md" ] && ok "handover ACTUALLY written at threshold" || bad "handover written at threshold" "no file"
[ -f "$SANDBOX/.claude/session/.sentinel_critical" ] && ok "critical sentinel claimed" || bad "critical sentinel claimed" ""
# Second fire must not re-run the save (atomic claim)
cp "$SANDBOX/session_handover.md" "$SANDBOX/.ho.before"
fire usage-sentinel.sh "{$BASE,\"prompt\":\"hi again\",\"hook_event_name\":\"UserPromptSubmit\"}"
[ -z "$OUT" ] && ok "second fire de-duped (no repeat save)" || bad "second fire de-duped" "re-emitted"

# ── PreToolUse ───────────────────────────────────────────────────────────────
head_ "PreToolUse — guard-dangerous"
RMRF='rm -rf /'
fire guard-dangerous.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"$RMRF\"}}"
[ "$RC" -eq 2 ] && ok "blocks destructive rm (exit 2)" || bad "blocks destructive rm" "rc=$RC"
fire guard-dangerous.sh '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
[ "$RC" -eq 0 ] && ok "allows benign command" || bad "allows benign command" "rc=$RC"
fire guard-dangerous.sh '{"tool_name":"Bash","tool_input":{"command":"echo x > production.env"}}'
[ "$RC" -eq 2 ] && ok "blocks production.* write" || bad "blocks production.* write" "rc=$RC"

# ── PermissionRequest ────────────────────────────────────────────────────────
head_ "PermissionRequest — auto-approve"
fire auto-approve-permissions.sh '{"tool_name":"Write","tool_input":{"file_path":"session_handover.md"},"hook_event_name":"PermissionRequest"}'
echo "$OUT" | grep -q '"behavior": *"allow"' && ok "approves kit file" || bad "approves kit file" "out=$OUT"
fire auto-approve-permissions.sh '{"tool_name":"Write","tool_input":{"file_path":".claude/session/../../../../etc/passwd"},"hook_event_name":"PermissionRequest"}'
[ -z "$OUT" ] && ok "refuses traversal escape" || bad "refuses traversal escape" "AUTO-APPROVED: $OUT"
fire auto-approve-permissions.sh '{"tool_name":"Write","tool_input":{"file_path":"src/app.ts"},"hook_event_name":"PermissionRequest"}'
[ -z "$OUT" ] && ok "defers unrelated file to user" || bad "defers unrelated file" "out=$OUT"

# ── PostToolUse / failure ────────────────────────────────────────────────────
head_ "PostToolUse + PostToolUseFailure"
fire track-changes.sh "{$BASE,\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SANDBOX/src/app.ts\"}}"
[ "$RC" -eq 0 ] && ok "track-changes exit 0" || bad "track-changes exit 0" "rc=$RC $ERR"
fire post-tool-failure.sh "{$BASE,\"tool_name\":\"Bash\",\"error\":\"boom\",\"tool_input\":{\"command\":\"false\"}}"
[ "$RC" -eq 0 ] && ok "post-tool-failure exit 0" || bad "post-tool-failure exit 0" "rc=$RC $ERR"
[ -s "$SANDBOX/.claude/session/tool-failures.jsonl" ] && ok "failure logged to jsonl" || bad "failure logged" "empty"
[ "$(jqs '.last_tool_failure.tool')" = "Bash" ] && ok "last_tool_failure in state.json" || bad "last_tool_failure" "got '$(jqs '.last_tool_failure.tool')'"

# ── Stop ─────────────────────────────────────────────────────────────────────
head_ "Stop — extract-state + usage-tracker"
fire extract-state-on-stop.sh "{$BASE,\"hook_event_name\":\"Stop\",\"stop_hook_active\":false}"
[ "$RC" -eq 0 ] && ok "extract-state exit 0" || bad "extract-state exit 0" "rc=$RC $ERR"
[ "$(jqs '.last_stop_turn')" = "2" ] && ok "turn count derived from transcript (=2)" || bad "turn count from transcript" "got '$(jqs '.last_stop_turn')' want 2"
jqs '.next_action' | grep -qi "run the integration tests\|wire the CLI" && ok "next_action extracted from response" || ok "next_action=$(jqs '.next_action')"

printf '%s' "{$BASE,\"hook_event_name\":\"Stop\"}" | python3 "$KIT/scripts/usage-tracker.py" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "usage-tracker exit 0" || bad "usage-tracker exit 0" "rc=$rc"
DU="$SANDBOX/.claude/session/daily-usage.json"
IN=$(jq -r '[.[].input_tokens]|add' "$DU" 2>/dev/null)
[ "$IN" = "420" ] && ok "tokens = true total 420 (not multiplied)" || bad "token delta" "got $IN want 420"
# fire twice more; must stay 420, not grow
for _ in 1 2; do printf '%s' "{$BASE,\"hook_event_name\":\"Stop\"}" | python3 "$KIT/scripts/usage-tracker.py" >/dev/null 2>&1; done
IN2=$(jq -r '[.[].input_tokens]|add' "$DU" 2>/dev/null)
[ "$IN2" = "420" ] && ok "3 Stop fires still 420 (delta, not cumulative)" || bad "repeat Stop inflates" "got $IN2 want 420"
[ "$(jq -r '.[].sessions[0].id' "$DU" 2>/dev/null)" = "$SID" ] && ok "session id from payload" || bad "session id" "got $(jq -r '.[].sessions[0].id' "$DU" 2>/dev/null)"
fire stop.sh "{$BASE,\"hook_event_name\":\"Stop\"}"
[ "$RC" -eq 0 ] && ok "stop.sh exit 0" || bad "stop.sh exit 0" "rc=$RC $ERR"
fire stop-failure.sh "{$BASE,\"error\":{\"type\":\"rate_limit\"},\"hook_event_name\":\"StopFailure\"}"
[ "$RC" -eq 0 ] && ok "stop-failure.sh exit 0" || bad "stop-failure.sh exit 0" "rc=$RC $ERR"

# ── Subagent lifecycle ───────────────────────────────────────────────────────
head_ "SubagentStart / SubagentStop"
before=$(jqs '.subagents_running'); [ -n "$before" ] || before=0
CLAUDE_HOOK_EVENT=SubagentStart fire subagent-lifecycle.sh "{$BASE,\"agent_id\":\"ag-1\",\"agent_type\":\"Explore\"}"
after=$(jqs '.subagents_running')
[ "$after" = "$((before+1))" ] && ok "SubagentStart increments ($before→$after)" || bad "SubagentStart increments" "$before→$after"
CLAUDE_HOOK_EVENT=SubagentStop fire subagent-lifecycle.sh "{$BASE,\"agent_id\":\"ag-1\",\"agent_type\":\"Explore\"}"
final=$(jqs '.subagents_running')
[ "$final" = "$before" ] && ok "SubagentStop decrements back ($after→$final)" || bad "SubagentStop decrements" "$after→$final"
[ "$(jqs '.active_subagent_ids|length')" = "0" ] && ok "active id list emptied" || bad "active id list" "$(jqs '.active_subagent_ids')"

# ── Compaction ───────────────────────────────────────────────────────────────
head_ "PreCompact / PostCompact"
cbefore=$(jqs '.compact_count')
fire pre-compact.sh "{$BASE,\"trigger\":\"auto\",\"context_percent\":\"88\",\"hook_event_name\":\"PreCompact\"}"
[ "$RC" -eq 0 ] && ok "pre-compact exit 0" || bad "pre-compact exit 0" "rc=$RC"
echo "$OUT" | grep -q "COMPACTION CONTEXT PRESERVED" && ok "compaction context injected" || bad "compaction context injected" ""
cafter=$(jqs '.compact_count')
[ "$cafter" -gt "${cbefore:-0}" ] && ok "compact_count incremented ($cbefore→$cafter)" || bad "compact_count incremented" "$cbefore→$cafter"
grep -q "Active Task" "$SANDBOX/session_handover.md" 2>/dev/null && ok "full handover regenerated (not stub)" || bad "full handover" "stub or missing"
fire post-compact.sh "{$BASE,\"hook_event_name\":\"PostCompact\"}"
[ "$RC" -eq 0 ] && ok "post-compact exit 0" || bad "post-compact exit 0" "rc=$RC $ERR"

# ── Misc events ──────────────────────────────────────────────────────────────
head_ "InstructionsLoaded / Notification"
fire instructions-loaded.sh "{$BASE,\"hook_event_name\":\"InstructionsLoaded\"}"
[ "$RC" -eq 0 ] && ok "instructions-loaded exit 0" || bad "instructions-loaded exit 0" "rc=$RC $ERR"
fire notify.sh "{$BASE,\"message\":\"test\",\"hook_event_name\":\"Notification\"}"
[ "$RC" -eq 0 ] && ok "notify exit 0" || bad "notify exit 0" "rc=$RC $ERR"

# ── SessionEnd ───────────────────────────────────────────────────────────────
head_ "SessionEnd"
fire session-end.sh "{$BASE,\"reason\":\"exit\",\"hook_event_name\":\"SessionEnd\"}"
[ "$RC" -eq 0 ] && ok "session-end exit 0" || bad "session-end exit 0" "rc=$RC $ERR"
[ -s "$SANDBOX/.claude/session/history.jsonl" ] && ok "history.jsonl appended" || bad "history.jsonl appended" "empty"
# NB: no pipe into grep -q here — under `set -o pipefail` the early grep exit
# SIGPIPEs git and the pipeline reports failure even on a match.
LOG=$(git -C "$SANDBOX" log --oneline)
case "$LOG" in *"chore(context)"*) ok "session state committed to git" ;; *) bad "session state committed" "no commit" ;; esac
git -C "$SANDBOX" show --stat --oneline HEAD | grep -q "state.json" \
  && bad "commit excludes gitignored state.json" "state.json was committed" \
  || ok "commit excludes gitignored state.json"

# ── Regression guards for previously-fixed defects ───────────────────────────
head_ "Regressions"
# jq wrapper must return real values, not silently fall back to defaults
JQV=$(printf '{"a":"real"}' > "$SANDBOX/.p.json"; bash -c "source '$KIT/scripts/find_jq.sh'; jq -r .a '$SANDBOX/.p.json'")
[ "$JQV" = "real" ] && ok "jq wrapper returns real value (no self-recursion)" || bad "jq wrapper" "got '$JQV'"
case "$(bash -c "source '$KIT/scripts/find_jq.sh'; echo \$_CEK_JQ_BIN")" in
  /*) ok "jq resolved to an absolute path" ;;
  *)  bad "jq resolved to absolute path" "bare name would recurse" ;;
esac
# daily-usage retention
DAYS=$(jq -r 'keys|length' "$SANDBOX/.claude/session/daily-usage.json" 2>/dev/null)
[ "${DAYS:-0}" -le 90 ] && ok "daily-usage within retention window ($DAYS days)" || bad "daily-usage retention" "$DAYS days"
# projection reliability flag present
jq -e 'has("projection_reliable")' "$SANDBOX/.claude/session/usage-forecast.json" >/dev/null 2>&1 \
  && ok "forecast exposes projection_reliable" || bad "projection_reliable" "absent"
# PreToolUse gets the permissionDecision schema, PermissionRequest the other one
OUTP=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"CLAUDE.md"},"hook_event_name":"PreToolUse"}' | bash "$KIT/.claude/hooks/auto-approve-permissions.sh")
echo "$OUTP" | grep -q 'permissionDecision' && ok "PreToolUse gets permissionDecision schema" || bad "PreToolUse schema" "got $OUTP"
OUTR=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"CLAUDE.md"},"hook_event_name":"PermissionRequest"}' | bash "$KIT/.claude/hooks/auto-approve-permissions.sh")
echo "$OUTR" | grep -q '"behavior"' && ok "PermissionRequest keeps decision.behavior" || bad "PermissionRequest schema" "got $OUTR"
# sourced library must not be able to kill the caller
bash -c "source '$KIT/scripts/cek_runtime.sh' >/dev/null 2>&1; echo alive" | grep -q alive \
  && ok "cek_runtime.sh sourcing cannot exit the caller" || bad "cek_runtime sourcing" "shell died"
# anchored to a real definition — the removal note mentions the old name
grep -qE '^cek_skip_if_unsupported\(\)' "$KIT/scripts/cek_runtime.sh" \
  && bad "dead exit-from-library helper removed" "still present" \
  || ok "dead exit-from-library helper removed"
# state.json mode stays stable across a shell write and a python write
MODE1=$(stat -f '%Lp' "$STATE" 2>/dev/null || stat -c '%a' "$STATE" 2>/dev/null)
printf '%s' "{$BASE,\"hook_event_name\":\"Stop\"}" | python3 "$KIT/scripts/usage-tracker.py" >/dev/null 2>&1
MODE2=$(stat -f '%Lp' "$STATE" 2>/dev/null || stat -c '%a' "$STATE" 2>/dev/null)
[ "$MODE1" = "$MODE2" ] && ok "state.json mode stable across writers ($MODE1)" || bad "state.json mode" "$MODE1 -> $MODE2"

# ── Containment ──────────────────────────────────────────────────────────────
head_ "Containment (spillover guard)"
NONGIT=$(mktemp -d "${TMPDIR:-/tmp}/cek-nongit.XXXXXX")
( cd "$NONGIT" && env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT bash -c \
    "source '$KIT/scripts/resolve_state_dir.sh'; state_write '.x=1'" ) >/dev/null 2>&1
[ -d "$NONGIT/.claude" ] && bad "no state dir in non-git dir" "created .claude/" || ok "no state dir created in non-git dir"
[ -d "$HOME/.claude/session" ] && bad "~/.claude stays clean" "kit state present" || ok "~/.claude/session stays clean"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $pass passed, $fail failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "sandbox kept at: $SANDBOX"
[ "$fail" -eq 0 ]
