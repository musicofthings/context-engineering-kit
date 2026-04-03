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
from datetime import datetime, timezone
from pathlib import Path

PROJECT_DIR      = Path(os.environ.get("CLAUDE_PROJECT_DIR", "."))
SESSION_DIR      = PROJECT_DIR / ".claude" / "session"
DAILY_USAGE_FILE = SESSION_DIR / "daily-usage.json"
FORECAST_FILE    = SESSION_DIR / "usage-forecast.json"
TIMESTAMP_FMT    = "%Y-%m-%dT%H:%M:%SZ"

TIER_LIMITS = {
    "pro":  {"5h_warn": 70,   "5h_critical": 90,  "cost_warn": 0.50, "cost_crit": 0.90},
    "max":  {"5h_warn": 70,   "5h_critical": 90,  "cost_warn": 2.00, "cost_crit": 4.00},
    "api":  {"5h_warn": None, "5h_critical": None, "cost_warn": 5.00, "cost_crit": 9.00},
}


def get_tier() -> str:
    f = PROJECT_DIR / "config" / "rate_limits.json"
    if f.exists():
        try:
            return json.loads(f.read_text()).get("subscription_tier", "pro")
        except Exception:
            pass
    return os.environ.get("CEK_SUBSCRIPTION_TIER", "pro")


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def today_key() -> str:
    return utc_now().strftime("%Y-%m-%d")


def load_json(p: Path) -> dict:
    try:
        return json.loads(p.read_text()) if p.exists() else {}
    except Exception:
        return {}


def save_json(p: Path, d: dict):
    SESSION_DIR.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(d, indent=2))


def ingest(ev: dict) -> dict:
    """Extract metrics from Stop event. v2.3 reads real rate_limits fields."""
    cost   = ev.get("cost", {})
    usage  = ev.get("usage", {})
    rl     = ev.get("rate_limits", {})
    cw     = ev.get("context_window", {})
    five_h = rl.get("five_hour", {})
    seven_d = rl.get("seven_day", {})
    return {
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
    }


def accumulate(m: dict) -> dict:
    data   = load_json(DAILY_USAGE_FILE)
    key    = today_key()
    now_ts = utc_now().strftime(TIMESTAMP_FMT)
    sid    = os.environ.get("CLAUDE_SESSION_ID", "unknown")

    if key not in data:
        data[key] = {
            "date": key, "turns": 0, "sessions": [],
            "cost_usd": 0.0, "input_tokens": 0, "output_tokens": 0,
            "first_activity": now_ts, "last_activity": now_ts,
            "peak_5h_pct": 0.0, "peak_ctx_pct": 0.0,
        }

    day     = data[key]
    prev_c  = next((s["last_cost"] for s in day["sessions"] if s.get("id") == sid), 0.0)
    turn_c  = max(0.0, m["session_cost"] - prev_c)

    day["sessions"] = [s for s in day["sessions"] if s.get("id") != sid]
    day["sessions"].append({"id": sid, "last_cost": m["session_cost"],
                             "turns": m["turns"], "model": m["model"], "updated": now_ts})

    day["turns"]         += 1
    day["cost_usd"]      += turn_c
    day["input_tokens"]  += m["input_tok"]
    day["output_tokens"] += m["output_tok"]
    day["last_activity"]  = now_ts

    if m["rl_5h_pct"] is not None:
        day["peak_5h_pct"] = max(day.get("peak_5h_pct", 0), m["rl_5h_pct"])
    if m["ctx_pct"] is not None:
        day["peak_ctx_pct"] = max(day.get("peak_ctx_pct", 0), m["ctx_pct"])

    data[key] = day
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
        pct           = rl_5h
        ppt           = pct / turns  # % per turn
        turns_to_warn = int((warn_p - pct) / ppt) if ppt > 0 and pct < warn_p else 0
        turns_to_crit = int((crit_p - pct) / ppt) if ppt > 0 and pct < crit_p else 0
        source        = "rate_limit_window"
    else:
        pct           = (cost_t / crit_c * 100) if crit_c > 0 else 0
        cpt           = cost_t / turns
        turns_to_warn = int((warn_c - cost_t) / cpt) if cpt > 0 and cost_t < warn_c else 0
        turns_to_crit = int((crit_c - cost_t) / cpt) if cpt > 0 and cost_t < crit_c else 0
        source        = "cost_proxy"

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
        left = int(rst) - int(now.timestamp())
        if left > 0:
            ml = left // 60
            reset_str = f"resets {ml}m" if ml < 60 else f"resets {ml//60}h{ml%60}m"

    if pct >= crit_p:   status, ind, action = "CRITICAL", "🔴", "compact_smart_now"
    elif pct >= warn_p: status, ind, action = "WARNING",  "🟠", "compact_smart_soon"
    elif pct >= warn_p * 0.7: status, ind, action = "CAUTION", "🟡", "monitor"
    else:               status, ind, action = "HEALTHY",  "🟢", "none"

    return {
        "updated": now_ts, "tier": tier_name, "data_source": source,
        "status": status, "indicator": ind, "recommended_action": action,
        "rl_5h_pct": rl_5h, "rl_7d_pct": m.get("rl_7d_pct"),
        "rl_5h_reset": reset_str,
        "pct_used": round(pct, 1),
        "turns_today": turns, "cost_today_usd": round(cost_t, 4),
        "turns_to_warn": max(0, turns_to_warn),
        "turns_to_critical": max(0, turns_to_crit),
        "eta_to_critical": eta,
        "ctx_pct": m.get("ctx_pct"),
        "peak_5h_pct": day.get("peak_5h_pct", 0),
        "peak_ctx_pct": day.get("peak_ctx_pct", 0),
    }


def report(fc: dict) -> str:
    src = "(real window)" if fc["data_source"] == "rate_limit_window" else "(cost proxy — upgrade Claude Code for real data)"
    lines = [
        f"╔══════════════════════════════════════════════╗",
        f"║  Usage Forecast  {fc['indicator']}  {fc['status']:<8}                 ║",
        f"╚══════════════════════════════════════════════╝",
        f"",
        f"Tier          : {fc['tier'].upper()}  {src}",
    ]
    if fc["rl_5h_pct"] is not None:
        lines += [f"5h window     : {fc['rl_5h_pct']:.1f}% used  {fc['rl_5h_reset']}"]
    if fc["rl_7d_pct"] is not None:
        lines += [f"7d window     : {fc['rl_7d_pct']:.1f}% used"]
    lines += [
        f"Context now   : {fc['ctx_pct']}%   (peak: {fc['peak_ctx_pct']:.0f}%)",
        f"Cost today    : ${fc['cost_today_usd']:.4f}",
        f"Turns today   : {fc['turns_today']}",
        f"",
        f"To warn       : ~{fc['turns_to_warn']} turns",
        f"To critical   : ~{fc['turns_to_critical']} turns ({fc['eta_to_critical']})",
        f"",
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
