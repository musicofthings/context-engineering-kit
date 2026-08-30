#!/usr/bin/env python3
"""
usage-tracker.py  v2.3
Stop hook: reads real rate_limits.five_hour/seven_day from Stop event JSON.
Falls back to cost proxy if rate_limits not available (older Claude Code).
Called async after every response turn.
"""

import argparse
import json
import os
import sys

# Windows cp1252 consoles can't encode box-drawing chars and emoji
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cek_paths import (  # noqa: E402
    atomic_write_json, load_json, resolve_state_dir, state_update,
)

PROJECT_DIR      = Path(os.environ.get("CLAUDE_PROJECT_DIR", "."))
# Was PROJECT_DIR/.claude/session, which ignored worktree redirection: in a
# worktree this wrote usage-forecast.json where usage-sentinel.sh (which does
# honour the scope) would never read it.
SESSION_DIR      = resolve_state_dir(PROJECT_DIR)
DAILY_USAGE_FILE = SESSION_DIR / "daily-usage.json"
FORECAST_FILE    = SESSION_DIR / "usage-forecast.json"
TIMESTAMP_FMT    = "%Y-%m-%dT%H:%M:%SZ"


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


# Source of truth: settings.json env vars, with hardcoded fallback for
# users who haven't set them. Kept in sync with config/usage_budget.json
# (warn=70, compact=85, critical=92 by default).
WARN_PCT      = _env_int("CEK_TOKEN_WARN_PCT", 70)
COMPACT_PCT   = _env_int("CEK_TOKEN_COMPACT_PCT", 85)
CRITICAL_PCT  = _env_int("CEK_TOKEN_CRITICAL_PCT", 92)

# Rolling window for daily-usage.json (see accumulate()).
DAILY_RETENTION_DAYS = _env_int("CEK_DAILY_RETENTION_DAYS", 90)
# Minimum turns before a "~N turns until warn/critical" projection means
# anything. Dividing a percentage by 1 turn extrapolates the entire session
# from a single sample and produced confidently wrong ETAs on the first Stop.
MIN_TURNS_FOR_PROJECTION = 3

TIER_LIMITS = {
    "pro":  {"5h_warn": WARN_PCT, "5h_critical": CRITICAL_PCT, "cost_warn": 0.50, "cost_crit": 0.90},
    "max":  {"5h_warn": WARN_PCT, "5h_critical": CRITICAL_PCT, "cost_warn": 2.00, "cost_crit": 4.00},
    "api":  {"5h_warn": None,     "5h_critical": None,         "cost_warn": 5.00, "cost_crit": 9.00},
}


def get_tier() -> str:
    """Read subscription tier. Tries rate_limits.json (subscription_tier)
    then usage_budget.json (subscription_type) — these two configs use
    different field names for the same value, so we accept both."""
    plugin_root = Path(os.environ.get("CLAUDE_PLUGIN_ROOT", str(PROJECT_DIR)))
    for path, key in [
        (PROJECT_DIR / "config" / "rate_limits.json", "subscription_tier"),
        (PROJECT_DIR / "config" / "usage_budget.json", "subscription_type"),
        (plugin_root / "config" / "rate_limits.json", "subscription_tier"),
        (plugin_root / "config" / "usage_budget.json", "subscription_type"),
    ]:
        if path.exists():
            try:
                v = json.loads(path.read_text(encoding="utf-8")).get(key)
                if v:
                    return v
            except Exception:
                continue
    return os.environ.get("CEK_SUBSCRIPTION_TIER", "pro")


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def today_key() -> str:
    return utc_now().strftime("%Y-%m-%d")


def save_json(p: Path, d: dict):
    """Atomic write — tmp file in same dir, then os.replace.
    Prevents truncation if the script is killed mid-write (Stop hook
    is async and can be interrupted by the next turn)."""
    atomic_write_json(p, d)


def ingest_transcript(path: str) -> dict:
    """Fallback metrics from the session transcript JSONL.

    The Stop hook payload carries no cost/rate_limits/context_window fields
    (those are statusline inputs) — but it does carry transcript_path, and
    each assistant entry there records real per-message token usage.
    """
    input_tok = output_tok = turns = 0
    model = "unknown"
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except Exception:
                    continue
                if entry.get("type") != "assistant":
                    continue
                msg = entry.get("message", {}) or {}
                usage = msg.get("usage", {}) or {}
                input_tok  += usage.get("input_tokens", 0) or 0
                output_tok += usage.get("output_tokens", 0) or 0
                turns += 1
                model = msg.get("model", model)
    except OSError:
        pass
    return {"input_tok": input_tok, "output_tok": output_tok,
            "turns": turns, "model": model}


def ingest(ev: dict) -> dict:
    """Extract metrics from Stop event, falling back to the transcript."""
    cost   = ev.get("cost", {})
    usage  = ev.get("usage", {})
    rl     = ev.get("rate_limits", {})
    cw     = ev.get("context_window", {})
    five_h = rl.get("five_hour", {})
    seven_d = rl.get("seven_day", {})
    m = {
        "rl_5h_pct":      five_h.get("used_percentage"),    # None if absent
        "rl_7d_pct":      seven_d.get("used_percentage"),
        "rl_5h_resets_at": five_h.get("resets_at"),
        "ctx_pct":        cw.get("used_percentage"),
        "session_cost":   cost.get("totalCostUSD", cost.get("total_cost_usd", 0.0)),
        "input_tok":      cost.get("totalInputTokens", usage.get("input_tokens", 0)),
        "output_tok":     cost.get("totalOutputTokens", usage.get("output_tokens", 0)),
        "dur_ms":         cost.get("totalDurationMS", 0),
        "turns":          ev.get("turn_count", 0),
        "model":          ev.get("model", {}).get("display_name", "unknown"),
        # Claude Code passes the session id in the hook payload, NOT as
        # CLAUDE_SESSION_ID in the environment. Reading the env var meant every
        # session collapsed into one "unknown" bucket, so the per-session
        # cost/token deltas below always compared against the wrong baseline.
        "session_id":     ev.get("session_id") or os.environ.get("CLAUDE_SESSION_ID", "unknown"),
    }

    # No cost/usage in the event (the normal case for a Stop hook):
    # recover token counts and model from the transcript instead.
    if not m["input_tok"] and not m["output_tok"] and not m["session_cost"]:
        transcript = ev.get("transcript_path", "")
        if transcript:
            t = ingest_transcript(transcript)
            m["input_tok"]  = t["input_tok"]
            m["output_tok"] = t["output_tok"]
            m["turns"]      = m["turns"] or t["turns"]
            if m["model"] == "unknown":
                m["model"] = t["model"]
    return m


def accumulate(m: dict) -> dict:
    data   = load_json(DAILY_USAGE_FILE)
    key    = today_key()
    now_ts = utc_now().strftime(TIMESTAMP_FMT)
    sid    = m.get("session_id") or "unknown"

    if key not in data:
        data[key] = {
            "date": key, "turns": 0, "sessions": [],
            "cost_usd": 0.0, "input_tokens": 0, "output_tokens": 0,
            "first_activity": now_ts, "last_activity": now_ts,
            "peak_5h_pct": 0.0, "peak_ctx_pct": 0.0,
        }

    day  = data[key]
    prev = next((s for s in day["sessions"] if s.get("id") == sid), {})

    # cost/input/output all arrive as SESSION-CUMULATIVE totals — session_cost
    # from the event, and input/output summed over the whole transcript by
    # ingest_transcript(). Accumulate the delta against this session's previous
    # reading, never the raw total: `+= total` on every turn inflates the daily
    # figure quadratically (3 turns over a 300/110-token transcript recorded
    # 900/330). Cost already did this; tokens did not.
    turn_c = max(0.0, m["session_cost"] - prev.get("last_cost", 0.0))
    turn_i = max(0, m["input_tok"] - prev.get("last_input", 0))
    turn_o = max(0, m["output_tok"] - prev.get("last_output", 0))

    day["sessions"] = [s for s in day["sessions"] if s.get("id") != sid]
    day["sessions"].append({"id": sid, "last_cost": m["session_cost"],
                            "last_input": m["input_tok"], "last_output": m["output_tok"],
                            "turns": m["turns"], "model": m["model"], "updated": now_ts})

    day["turns"]         += 1
    day["cost_usd"]      += turn_c
    day["input_tokens"]  += turn_i
    day["output_tokens"] += turn_o
    day["last_activity"]  = now_ts

    if m["rl_5h_pct"] is not None:
        day["peak_5h_pct"] = max(day.get("peak_5h_pct", 0), m["rl_5h_pct"])
    if m["ctx_pct"] is not None:
        day["peak_ctx_pct"] = max(day.get("peak_ctx_pct", 0), m["ctx_pct"])

    data[key] = day
    # Retention: this file is appended to on every Stop of every session and
    # nothing ever removed a day, so it grew without bound. Keep a rolling
    # window — anything older is not used by the forecast or any skill.
    if len(data) > DAILY_RETENTION_DAYS:
        for stale in sorted(data)[:-DAILY_RETENTION_DAYS]:
            data.pop(stale, None)
    save_json(DAILY_USAGE_FILE, data)
    return day


def forecast(m: dict, day: dict, tier_name: str) -> dict:
    tier    = TIER_LIMITS.get(tier_name, TIER_LIMITS["pro"])
    now     = utc_now()
    now_ts  = now.strftime(TIMESTAMP_FMT)
    turns   = max(1, day.get("turns", 1))
    cost_t  = day.get("cost_usd", 0.0)

    # Use real rate limit if available, else cost proxy
    rl_5h  = m.get("rl_5h_pct")
    real   = rl_5h is not None
    warn_p  = tier["5h_warn"]   or 70
    crit_p  = tier["5h_critical"] or 90
    warn_c  = tier["cost_warn"]
    crit_c  = tier["cost_crit"]

    if real:
        pct            = rl_5h
        session_turns  = max(1, m.get("turns", 1))  # use session turns; aligns with 5h window scope
        ppt            = pct / session_turns
        turns_to_warn  = int((warn_p - pct) / ppt) if ppt > 0 and pct < warn_p else 0
        turns_to_crit  = int((crit_p - pct) / ppt) if ppt > 0 and pct < crit_p else 0
        source         = "rate_limit_window"
        reliable       = session_turns >= MIN_TURNS_FOR_PROJECTION
    else:
        pct           = (cost_t / crit_c * 100) if crit_c > 0 else 0
        cpt           = cost_t / turns
        turns_to_warn = int((warn_c - cost_t) / cpt) if cpt > 0 and cost_t < warn_c else 0
        turns_to_crit = int((crit_c - cost_t) / cpt) if cpt > 0 and cost_t < crit_c else 0
        source        = "cost_proxy"
        reliable      = turns >= MIN_TURNS_FOR_PROJECTION

    # ETA
    try:
        first_dt    = datetime.fromisoformat(day["first_activity"].replace("Z", "+00:00"))
        elapsed_h   = max(0.01, (now - first_dt).total_seconds() / 3600)
        turns_per_h = turns / elapsed_h
        hrs_left    = turns_to_crit / turns_per_h if turns_per_h > 0 else 99
        eta = f"~{int(hrs_left*60)}m" if hrs_left < 1 else f"~{hrs_left:.1f}h"
    except Exception:
        eta = "unknown"

    # Rate limit reset
    reset_str = ""
    rst = m.get("rl_5h_resets_at")
    if rst:
        # resets_at may be an epoch int OR an ISO-8601 string depending on the
        # Claude Code version. A bare int() on the ISO form raised ValueError
        # and killed the whole Stop hook.
        try:
            left = int(rst) - int(now.timestamp())
        except (TypeError, ValueError):
            try:
                reset_dt = datetime.fromisoformat(str(rst).replace("Z", "+00:00"))
                if reset_dt.tzinfo is None:
                    reset_dt = reset_dt.replace(tzinfo=timezone.utc)
                left = int(reset_dt.timestamp()) - int(now.timestamp())
            except Exception:
                left = 0
        if left > 0:
            ml = left // 60
            reset_str = f"resets {ml}m" if ml < 60 else f"resets {ml//60}h{ml%60}m"

    # Ladder: WARN (70) → COMPACT (85) → CRITICAL (92).
    # COMPACT is the documented threshold for /compact-smart action.
    if pct >= crit_p:
        status, ind, action = "CRITICAL", "🔴", "compact_smart_now"
    elif pct >= COMPACT_PCT:
        status, ind, action = "COMPACT", "🟠", "compact_smart_now"
    elif pct >= warn_p:
        status, ind, action = "WARNING", "🟡", "compact_smart_soon"
    elif pct >= warn_p * 0.7:
        status, ind, action = "CAUTION", "🟡", "monitor"
    else:
        status, ind, action = "HEALTHY", "🟢", "none"

    return {
        "updated": now_ts, "tier": tier_name, "data_source": source,
        "status": status, "indicator": ind, "recommended_action": action,
        "rl_5h_pct": rl_5h, "rl_7d_pct": m.get("rl_7d_pct"),
        "rl_5h_reset": reset_str,
        "pct_used": round(pct, 1),
        "turns_today": turns, "cost_today_usd": round(cost_t, 4),
        "turns_to_warn": max(0, turns_to_warn),
        "turns_to_critical": max(0, turns_to_crit),
        "eta_to_critical": eta if reliable else "unknown",
        "projection_reliable": reliable,
        "ctx_pct": m.get("ctx_pct"),
        "peak_5h_pct": day.get("peak_5h_pct", 0),
        "peak_ctx_pct": day.get("peak_ctx_pct", 0),
    }


def report(fc: dict) -> str:
    src = "(real window)" if fc["data_source"] == "rate_limit_window" else "(cost proxy — upgrade Claude Code for real data)"
    lines = [
        "╔══════════════════════════════════════════════╗",
        f"║  Usage Forecast  {fc['indicator']}  {fc['status']:<8}                 ║",
        "╚══════════════════════════════════════════════╝",
        "",
        f"Tier          : {fc['tier'].upper()}  {src}",
    ]
    if fc["rl_5h_pct"] is not None:
        lines += [f"5h window     : {fc['rl_5h_pct']:.1f}% used  {fc['rl_5h_reset']}"]
    if fc["rl_7d_pct"] is not None:
        lines += [f"7d window     : {fc['rl_7d_pct']:.1f}% used"]
    ctx_now = "n/a" if fc.get("ctx_pct") is None else f"{fc['ctx_pct']}%"
    lines += [
        f"Context now   : {ctx_now}   (peak: {fc['peak_ctx_pct']:.0f}%)",
        f"Cost today    : ${fc['cost_today_usd']:.4f}",
        f"Turns today   : {fc['turns_today']}",
        "",
        (f"To warn       : ~{fc['turns_to_warn']} turns"
         if fc.get("projection_reliable", True)
         else f"To warn       : — (need {MIN_TURNS_FOR_PROJECTION}+ turns to project)"),
        (f"To critical   : ~{fc['turns_to_critical']} turns ({fc['eta_to_critical']})"
         if fc.get("projection_reliable", True)
         else "To critical   : — (not enough turns yet)"),
        "",
    ]
    if fc["recommended_action"] == "compact_smart_now":
        lines += ["⚡ ACTION: /compact-smart NOW then /handover"]
    elif fc["recommended_action"] == "compact_smart_soon":
        lines += [f"⚠️  Plan /compact-smart — ~{fc['turns_to_critical']} turns remaining"]
    else:
        lines += ["✅ Usage healthy."]
    return "\n".join(lines)


def run_hook():
    raw = sys.stdin.read().strip()
    if not raw:
        sys.exit(0)
    try:
        ev = json.loads(raw)
    except Exception:
        sys.exit(0)
    tier = get_tier()
    m    = ingest(ev)
    day  = accumulate(m)
    fc   = forecast(m, day, tier)
    save_json(FORECAST_FILE, fc)

    # Mirror key metrics into state.json so usage-sentinel can prefer real
    # rate-limit % over wall-clock session age (Phase D / pending tasks).
    # Lock-guarded: extract-state-on-stop.sh fires on this same Stop event and
    # does its own read-modify-write of state.json. A bare load/save here (what
    # this used to do) races it and drops whichever writer finished first —
    # resolve_state_dir.sh sets the contract that ALL state.json updates take
    # the shared lock, and this was the one writer ignoring it.
    def _mirror(st: dict) -> dict:
        st["usage_pct"] = fc.get("pct_used")
        st["usage_source"] = fc.get("data_source")
        st["rl_5h_pct"] = fc.get("rl_5h_pct")
        st["rl_7d_pct"] = fc.get("rl_7d_pct")
        st["ctx_pct"] = fc.get("ctx_pct")
        st["usage_updated"] = fc.get("updated")
        if m.get("session_cost") is not None:
            st["session_cost_usd"] = str(m.get("session_cost") or st.get("session_cost_usd") or "0")
        return st

    try:
        state_update(SESSION_DIR / "state.json", _mirror)
    except Exception:
        pass

    if fc["status"] in ("WARNING", "CRITICAL"):
        src  = "5h" if fc["data_source"] == "rate_limit_window" else "est"
        left = fc["turns_to_critical"]
        eta  = fc["eta_to_critical"]
        print(
            f"\n[usage] {fc['indicator']} {fc['status']} "
            f"({src}: {fc['pct_used']:.0f}%) — "
            f"~{left} turns left ({eta}). /compact-smart to extend.",
            flush=True
        )
    sys.exit(0)


def run_report():
    tier = get_tier()
    data = load_json(DAILY_USAGE_FILE)
    day  = data.get(today_key(), {"cost_usd": 0.0, "turns": 0,
                                   "first_activity": utc_now().strftime(TIMESTAMP_FMT)})
    fc_prev = load_json(FORECAST_FILE)
    m = {"rl_5h_pct": fc_prev.get("rl_5h_pct"), "rl_7d_pct": fc_prev.get("rl_7d_pct"),
         "rl_5h_resets_at": None, "ctx_pct": fc_prev.get("ctx_pct")}
    fc = forecast(m, day, tier)
    print(report(fc))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--report", action="store_true")
    args = p.parse_args()
    run_report() if args.report else run_hook()
