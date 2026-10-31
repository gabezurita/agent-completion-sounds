#!/usr/bin/env python3
"""Unified AI Model and Subscription Usage Collector.

Collects and normalizes usage, rate limits, and remaining quota metrics across:
- Cursor (Fast requests, Cursor Models, Other Models, Spend Limit)
- Antigravity / agy (5h rolling limit, weekly limit, Argon limit, 3P models)
- OpenAI Codex (Configured models, thread history, rate limits)
- Claude Code (Session activity, tokens, estimated cost)

Provides:
- JSON telemetry output (`--json`)
- One-line human-readable summary (`--summary`)
- Local web dashboard (`--serve`, port 3333)
- Subprocess non-blocking caching for SwiftBar and CLI statuslines
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import http.server
import json
import os
import select
import sqlite3
import subprocess
import threading
import time
from typing import Any
import urllib.parse
import urllib.request

CACHE_FILE = "/tmp/ai_quota_collector_cache.json"
CACHE_TTL_SECONDS = 60
LOCK_FILE = "/tmp/ai_quota_collector.lock"


def redact_secrets(message: str, *secrets: str) -> str:
    """Remove credential values from text that may be printed or cached."""
    redacted = message
    for secret in secrets:
        if secret:
            redacted = redacted.replace(secret, "[redacted]")
    return redacted


def get_real_home() -> str:
    """Return the home directory used for local quota files.

    When HOME sits inside a directory named .agy-personal and that directory's
    parent exists, return the parent. Otherwise return HOME.
    """
    env_home = os.environ.get("HOME", "")
    if ".agy-personal" in env_home:
        real_home = os.path.dirname(env_home.rstrip("/"))
        if os.path.exists(real_home):
            return real_home
    return os.path.expanduser("~")


def cli_path_prefixes(home: str | None = None) -> list[str]:
    """Bin directories a login shell has and a launchd GUI app does not."""
    root = home if home is not None else get_real_home()
    return [
        os.path.join(root, ".local", "bin"),
        os.path.join(root, ".antigravity-ide", "antigravity-ide", "bin"),
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]


def ensure_cli_path(home: str | None = None) -> str:
    """Prepend existing user CLI directories to PATH.

    setup launches Agent Dashboard with open, so the menu's PATH is the
    launchd default and does not include Homebrew or ~/.local/bin.
    """
    parts = [entry for entry in os.environ.get("PATH", "").split(":") if entry]
    for prefix in reversed(cli_path_prefixes(home)):
        if prefix not in parts and os.path.isdir(prefix):
            parts.insert(0, prefix)
    path = ":".join(parts)
    os.environ["PATH"] = path
    return path


def format_countdown(target_iso: str | None) -> str:
    """Calculates human-readable countdown to a reset timestamp."""
    if not target_iso:
        return ""
    try:
        # Normalize ISO string
        target_iso = target_iso.replace("Z", "+00:00")
        dt = datetime.fromisoformat(target_iso)
        now = datetime.now(timezone.utc)
        diff = dt - now
        total_seconds = int(diff.total_seconds())
        if total_seconds <= 0:
            return "ready"
        days = total_seconds // 86400
        hours = (total_seconds % 86400) // 3600
        minutes = (total_seconds % 3600) // 60
        if days > 0:
            return f"{days}d {hours}h"
        if hours > 0:
            return f"{hours}h {minutes}m"
        return f"{minutes}m"
    except Exception:
        return ""


# ─────────────────────────────────────────────────────────────
# Provider: Cursor
# ─────────────────────────────────────────────────────────────

def collect_cursor_usage() -> dict[str, Any]:
    """Collects Cursor usage data via Cursor's aiserver DashboardService."""
    real_home = get_real_home()
    db_path = os.path.join(
        real_home,
        "Library/Application Support/Cursor/User/globalStorage/state.vscdb",
    )
    if not os.path.exists(db_path):
        return {"status": "unavailable", "error": "state.vscdb not found"}

    membership_status = "active"
    token = None
    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute(
            "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
        )
        row = cur.fetchone()
        if not row or not row[0]:
            conn.close()
            return {"status": "unauthenticated", "error": "no access token"}
        token = row[0]

        try:
            cur.execute(
                "SELECT value FROM ItemTable WHERE key = 'cursorAuth/stripeSubscriptionStatus'"
            )
            s_row = cur.fetchone()
            if s_row and s_row[0]:
                membership_status = s_row[0]
        except Exception:
            pass
        conn.close()
    except Exception as e:
        return {
            "status": "error",
            "error": redact_secrets(f"sqlite error: {e}", token),
        }

    def get_cursor_fallback(err_msg: str) -> dict[str, Any]:
        """Preserves existing cached quota or returns active subscription fallback."""
        if os.path.exists(CACHE_FILE):
            try:
                with open(CACHE_FILE, "r") as f:
                    cached = json.load(f)
                cached_cur = cached.get("providers", {}).get("cursor", {})
                if cached_cur.get("status") == "ok":
                    return cached_cur
            except Exception:
                pass

        if membership_status == "active":
            return {
                "status": "ok",
                "plan": "Cursor Pro",
                "models": {
                    "cursor_models": {
                        "label": "Cursor Models (Grok / Composer)",
                        "used_percent": 0,
                        "remaining_percent": 100,
                        "window": "monthly",
                    }
                },
                "reset_countdown": "",
                "display_message": "Active subscription",
            }
        return {"status": "error", "error": err_msg}

    # Query api2.cursor.sh DashboardService
    try:
        cmd = [
            "curl",
            "-s",
            "-X",
            "POST",
            "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
            "-H",
            f"Authorization: Bearer {token}",
            "-H",
            "Content-Type: application/json",
            "-d",
            "{}",
            "--max-time",
            "10",
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            return get_cursor_fallback(redact_secrets("curl error", token))

        try:
            data = json.loads(redact_secrets(res.stdout, token))
        except Exception:
            return get_cursor_fallback(redact_secrets("invalid json", token))

        # Convert cycle end timestamp
        cycle_end_ms = data.get("billingCycleEnd")
        cycle_end_iso = None
        countdown = ""
        if cycle_end_ms:
            cycle_dt = datetime.fromtimestamp(
                int(cycle_end_ms) / 1000.0, timezone.utc
            )
            cycle_end_iso = cycle_dt.isoformat()
            countdown = format_countdown(cycle_end_iso)

        spend_limit = data.get("spendLimitUsage", {})
        individual_limit = (spend_limit.get("individualLimit") or 0) / 100.0
        individual_remaining = (
            spend_limit.get("individualRemaining") or 0
        ) / 100.0

        # Handle models: legacy planUsage vs token-based / auto-bucket models
        plan_usage = data.get("planUsage")
        models_out: dict[str, Any] = {}
        if plan_usage:
            auto_used = plan_usage.get("autoPercentUsed", 0.0)
            api_used = plan_usage.get("apiPercentUsed", 0.0)
            cursor_remaining_pct = max(0, 100 - int(round(auto_used)))
            api_remaining_pct = max(0, 100 - int(round(api_used)))
            models_out["cursor_models"] = {
                "label": "Cursor Models (Grok / Composer)",
                "used_percent": int(round(auto_used)),
                "remaining_percent": cursor_remaining_pct,
                "window": "monthly",
            }
            if individual_limit > 0 or api_used > 0:
                models_out["other_models"] = {
                    "label": "Other Models (API / Claude)",
                    "used_percent": int(round(api_used)),
                    "remaining_percent": api_remaining_pct,
                    "window": "monthly",
                }
        elif (
            "billingCycleEnd" in data
            or "spendLimitUsage" in data
            or "autoBucketModels" in data
        ):
            # Token-based / Unified pricing plan without legacy request caps
            models_out["cursor_models"] = {
                "label": "Cursor Models (Grok / Composer)",
                "used_percent": 0,
                "remaining_percent": 100,
                "window": "monthly",
            }
        else:
            return get_cursor_fallback(
                redact_secrets(str(data.get("message", "invalid payload")), token)
            )

        result: dict[str, Any] = {
            "status": "ok",
            "plan": "Cursor Pro",
            "models": models_out,
            "billing_cycle_end": cycle_end_iso,
            "reset_countdown": countdown,
            "display_message": redact_secrets(
                str(data.get("displayMessage", "")), token
            ),
        }
        if individual_limit > 0 or individual_remaining > 0:
            result["spend_limit"] = {
                "limit_usd": individual_limit,
                "remaining_usd": individual_remaining,
            }

        return result
    except Exception as e:
        return get_cursor_fallback(redact_secrets(str(e), token))



# ─────────────────────────────────────────────────────────────
# Provider: Antigravity (agy / Gemini)
# ─────────────────────────────────────────────────────────────

def collect_antigravity_usage() -> dict[str, Any]:
    """Collects Antigravity (agy) model limits via headless /usage."""
    # Check if a recent usage cache exists
    agy_cache_file = "/tmp/agy_usage_cache.json"
    data = None
    if os.path.exists(agy_cache_file):
        try:
            mtime = os.path.getmtime(agy_cache_file)
            if time.time() - mtime < 120:
                with open(agy_cache_file, "r") as f:
                    data = json.load(f)
        except Exception:
            pass

    if not data:
        try:
            res = subprocess.run(
                ["agy", "-p", "/usage", "--output-format", "json"],
                capture_output=True,
                text=True,
                timeout=12,
            )
            if res.returncode == 0:
                data = json.loads(res.stdout)
                try:
                    with open(agy_cache_file, "w") as f:
                        f.write(res.stdout)
                except Exception:
                    pass
        except Exception as e:
            return {"status": "error", "error": f"agy execution error: {e}"}

    if not data:
        return {"status": "unavailable", "error": "could not retrieve usage"}

    groups = (
        data.get("command", {})
        .get("data", {})
        .get("groups", [])
    )
    if not groups and "groups" in data:
        groups = data["groups"]

    buckets_out: dict[str, Any] = {}
    for g in groups:
        gname = g.get("name", "")
        for b in g.get("buckets", []):
            bid = b.get("id", "")
            bname = b.get("name", "")
            rem_fraction = b.get("remaining_fraction")
            if rem_fraction is None:
                continue
            pct = int(round(rem_fraction * 100))
            reset_time = b.get("reset_time")
            countdown = format_countdown(reset_time)
            window = b.get("window", "")

            key = bid.replace("-", "_")
            buckets_out[key] = {
                "id": bid,
                "label": f"{gname} ({bname})",
                "group": gname,
                "name": bname,
                "remaining_percent": pct,
                "used_percent": max(0, 100 - pct),
                "reset_time": reset_time,
                "reset_countdown": countdown,
                "window": window,
            }

    return {
        "status": "ok",
        "plan": "Google Antigravity",
        "buckets": buckets_out,
    }


# ─────────────────────────────────────────────────────────────
# Provider: OpenAI Codex
# ─────────────────────────────────────────────────────────────

def query_codex_app_server_rate_limits() -> dict[str, Any] | None:
    """Queries live rate limits from codex app-server daemon via stdio."""
    real_home = get_real_home()
    env = dict(os.environ)
    env["HOME"] = real_home
    env["CODEX_HOME"] = os.path.join(real_home, ".codex")

    try:
        proc = subprocess.Popen(
            ["codex", "app-server", "--stdio"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )

        init_req = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {
                    "name": "ai-quota-collector",
                    "version": "1.0.0",
                }
            },
        }
        proc.stdin.write(json.dumps(init_req) + "\n")
        proc.stdin.flush()

        rate_req = {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "account/rateLimits/read",
            "params": None,
        }
        proc.stdin.write(json.dumps(rate_req) + "\n")
        proc.stdin.flush()

        result = None
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            ready, _, _ = select.select([proc.stdout], [], [], 0.5)
            if not ready:
                continue
            line = proc.stdout.readline()
            if not line:
                break
            try:
                msg = json.loads(line)
                if msg.get("id") == 2:
                    result = msg.get("result")
                    break
            except Exception:
                continue

        proc.terminate()
        try:
            proc.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            proc.kill()

        return result
    except Exception:
        return None


def collect_codex_usage() -> dict[str, Any]:
    """Collects OpenAI Codex status, live rate limits, configurations, and thread activity."""
    real_home = get_real_home()
    codex_home = os.path.join(real_home, ".codex")
    auth_file = os.path.join(codex_home, "auth.json")
    config_file = os.path.join(codex_home, "config.toml")
    state_db = os.path.join(codex_home, "state_5.sqlite")

    if not os.path.exists(auth_file):
        return {"status": "unavailable", "error": "Codex auth.json not found"}

    auth_mode = "unknown"
    try:
        with open(auth_file, "r") as f:
            auth_data = json.load(f)
            auth_mode = auth_data.get("auth_mode", "ChatGPT")
    except Exception:
        pass

    # Inspect total thread token count from local state DB if available
    total_tokens = 0
    total_threads = 0
    if os.path.exists(state_db):
        try:
            conn = sqlite3.connect(state_db)
            cur = conn.cursor()
            cur.execute("SELECT count(*), sum(tokens_used) FROM threads")
            row = cur.fetchone()
            if row:
                total_threads = row[0] or 0
                total_tokens = row[1] or 0
            conn.close()
        except Exception:
            pass

    # Query live rate limits from Codex app-server
    rate_limits_payload = query_codex_app_server_rate_limits()
    buckets_out: dict[str, Any] = {}
    plan_type = auth_mode
    reset_credits = 0

    if rate_limits_payload and "rateLimits" in rate_limits_payload:
        rl = rate_limits_payload.get("rateLimits", {})
        plan_type = rl.get("planType") or auth_mode
        credits_info = rate_limits_payload.get("rateLimitResetCredits", {})
        reset_credits = credits_info.get("availableCount", 0)

        # Primary window (5h)
        prim = rl.get("primary", {})
        if prim:
            used_pct = prim.get("usedPercent", 0)
            rem_pct = max(0, 100 - used_pct)
            resets_at = prim.get("resetsAt")
            iso_str = (
                datetime.fromtimestamp(resets_at, tz=timezone.utc).isoformat()
                if resets_at
                else None
            )
            countdown = format_countdown(iso_str) if iso_str else ""
            buckets_out["five_hour"] = {
                "id": "five_hour",
                "label": "Five-Hour Limit",
                "window_minutes": prim.get("windowDurationMins", 300),
                "remaining_percent": rem_pct,
                "used_percent": used_pct,
                "resets_at": resets_at,
                "reset_time": iso_str,
                "reset_countdown": countdown,
            }

        # Secondary window (weekly)
        sec = rl.get("secondary", {})
        if sec:
            used_pct = sec.get("usedPercent", 0)
            rem_pct = max(0, 100 - used_pct)
            resets_at = sec.get("resetsAt")
            iso_str = (
                datetime.fromtimestamp(resets_at, tz=timezone.utc).isoformat()
                if resets_at
                else None
            )
            countdown = format_countdown(iso_str) if iso_str else ""
            buckets_out["weekly"] = {
                "id": "weekly",
                "label": "Weekly Limit",
                "window_minutes": sec.get("windowDurationMins", 10080),
                "remaining_percent": rem_pct,
                "used_percent": used_pct,
                "resets_at": resets_at,
                "reset_time": iso_str,
                "reset_countdown": countdown,
            }

    return {
        "status": "ok",
        "plan": f"OpenAI Codex ({plan_type})",
        "auth_mode": auth_mode,
        "plan_type": plan_type,
        "config_path": config_file,
        "rate_limits": buckets_out,
        "reset_credits_available": reset_credits,
        "total_threads": total_threads,
        "lifetime_tokens_recorded": total_tokens,
    }


# ─────────────────────────────────────────────────────────────
# Provider: Claude Code
# ─────────────────────────────────────────────────────────────

CLAUDE_PROFILE_MAX_AGE_SECONDS = 24 * 60 * 60
CLAUDE_ZERO_TIER = "default_claude_zero"
CLAUDE_KEYCHAIN_SERVICE = "Claude Code-credentials"


def _epoch_seconds(value: Any) -> float | None:
    if not isinstance(value, (int, float)) or value <= 0:
        return None
    if value > 10_000_000_000:
        return float(value) / 1000.0
    return float(value)


def load_claude_credentials() -> dict[str, Any]:
    """Read the Claude OAuth blob from the keychain or credentials file.

    The access token is returned only when it is non-empty and unexpired.
    Callers must not include it in cached quota output.
    """
    raw = ""
    try:
        proc = subprocess.run(
            ["security", "find-generic-password", "-s", CLAUDE_KEYCHAIN_SERVICE, "-w"],
            capture_output=True,
            text=True,
            timeout=2.0,
        )
        if proc.returncode == 0:
            raw = proc.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        raw = ""
    if not raw:
        path = os.path.join(get_real_home(), ".claude", ".credentials.json")
        try:
            with open(path, "r") as handle:
                raw = handle.read()
        except OSError:
            raw = ""
    token = ""
    expires_at = 0
    if raw:
        try:
            oauth = json.loads(raw).get("claudeAiOauth") or {}
            token = oauth.get("accessToken") or ""
            expires_at = oauth.get("expiresAt") or 0
        except json.JSONDecodeError:
            token = ""
    expires = _epoch_seconds(expires_at)
    if token and expires is not None and expires <= time.time():
        token = ""
    return {"accessToken": token}


def read_claude_account_cache() -> dict[str, Any]:
    path = os.path.join(get_real_home(), ".claude.json")
    try:
        with open(path, "r") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return {}
    account = data.get("oauthAccount") or {}
    return {
        "hasAvailableSubscription": bool(data.get("hasAvailableSubscription")),
        "profileFetchedAt": account.get("profileFetchedAt"),
        "accountUuid": account.get("accountUuid") or "",
    }


def claude_profile_is_active(profile: dict[str, Any]) -> bool:
    """A refreshed profile is active only when the seat can still be used.

    An explicit availability flag wins. Otherwise a rate-limit tier other
    than the zero tier counts. Billing and seat-tier strings do not.
    """
    if "hasAvailableSubscription" in profile:
        return bool(profile["hasAvailableSubscription"])
    if "has_available_subscription" in profile:
        return bool(profile["has_available_subscription"])
    org = profile.get("organization") or {}
    tier = org.get("rate_limit_tier") or org.get("user_rate_limit_tier") or ""
    return bool(tier) and tier != CLAUDE_ZERO_TIER


def fetch_claude_profile(token: str, api_key: str, account_uuid: str) -> dict[str, Any] | None:
    """Refresh the Claude account profile. Failures return None."""
    if token:
        url = "https://api.anthropic.com/api/oauth/profile"
        headers = {
            "Authorization": f"Bearer {token}",
            "User-Agent": "agent-completion-sounds",
            "Cache-Control": "no-cache",
        }
    elif api_key and account_uuid:
        query = urllib.parse.urlencode({"account_uuid": account_uuid})
        url = f"https://api.anthropic.com/api/claude_cli_profile?{query}"
        headers = {
            "x-api-key": api_key,
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "agent-completion-sounds",
            "Cache-Control": "no-cache",
        }
    else:
        return None
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=8) as resp:
            body = resp.read().decode()
        data = json.loads(body)
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    return data


def claude_cached_subscription_active(cache: dict[str, Any]) -> bool:
    fetched = _epoch_seconds(cache.get("profileFetchedAt"))
    if fetched is None:
        return False
    if time.time() - fetched > CLAUDE_PROFILE_MAX_AGE_SECONDS:
        return False
    return bool(cache.get("hasAvailableSubscription"))


def claude_subscription_active() -> bool:
    creds = load_claude_credentials()
    cache = read_claude_account_cache()
    api_key = (os.environ.get("ANTHROPIC_API_KEY") or "").strip()
    profile = fetch_claude_profile(
        creds.get("accessToken") or "",
        api_key,
        cache.get("accountUuid") or "",
    )
    if profile is not None:
        return claude_profile_is_active(profile)
    return claude_cached_subscription_active(cache)


def collect_claude_usage() -> dict[str, Any]:
    """Collect Claude Code telemetry only while a refreshed seat is active."""
    if not claude_subscription_active():
        return {
            "status": "unavailable",
            "error": "Claude subscription is not active",
        }

    real_home = get_real_home()
    stats_file = os.path.join(real_home, ".claude/stats-cache.json")
    today_iso = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    total_sessions = 0
    total_messages = 0
    today_messages = 0
    today_tool_calls = 0
    if os.path.exists(stats_file):
        try:
            with open(stats_file, "r") as handle:
                stats = json.load(handle)
            total_sessions = stats.get("totalSessions", 0)
            total_messages = stats.get("totalMessages", 0)
            for entry in stats.get("dailyActivity", []):
                if entry.get("date") == today_iso:
                    today_messages = entry.get("messageCount", 0)
                    today_tool_calls = entry.get("toolCallCount", 0)
                    break
        except Exception as e:
            return {"status": "error", "error": str(e)}

    return {
        "status": "ok",
        "plan": "Claude Code",
        "total_sessions": total_sessions,
        "total_messages": total_messages,
        "today": {
            "date": today_iso,
            "message_count": today_messages,
            "tool_call_count": today_tool_calls,
        },
    }


# ─────────────────────────────────────────────────────────────
# Provider: GitHub Copilot
# ─────────────────────────────────────────────────────────────

COPILOT_BUCKET_LABELS = (
    ("chat", "Copilot Chat"),
    ("completions", "Copilot Completions"),
    ("premium_interactions", "Copilot Premium"),
)


def fetch_copilot_user() -> dict[str, Any] | None:
    """Read the Copilot seat. The public /user/copilot route 404s."""
    ensure_cli_path()
    try:
        proc = subprocess.run(
            ["gh", "api", "copilot_internal/user"],
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    return data


def copilot_quota_buckets(seat: dict[str, Any]) -> dict[str, Any]:
    snapshots = seat.get("quota_snapshots") or {}
    reset_at = seat.get("quota_reset_date_utc") or seat.get("quota_reset_date")
    countdown = format_countdown(reset_at) if isinstance(reset_at, str) else ""
    buckets: dict[str, Any] = {}
    for key, label in COPILOT_BUCKET_LABELS:
        snap = snapshots.get(key)
        if not isinstance(snap, dict) or not snap.get("has_quota"):
            continue
        try:
            remaining = int(round(float(snap.get("percent_remaining") or 0)))
        except (TypeError, ValueError):
            remaining = 0
        remaining = max(0, min(100, remaining))
        buckets[key] = {
            "label": label,
            "remaining_percent": remaining,
            "used_percent": 100 - remaining,
            "reset_countdown": countdown,
        }
    return buckets


def collect_copilot_usage() -> dict[str, Any]:
    """Show Copilot while chat or completions still has a quota."""
    seat = fetch_copilot_user() or {}
    buckets = copilot_quota_buckets(seat)
    if "chat" not in buckets and "completions" not in buckets:
        return {
            "status": "unavailable",
            "message": "Copilot seat has no chat or completions quota",
        }

    telemetry = _collect_copilot_telemetry()
    countdown = ""
    for bucket in buckets.values():
        countdown = bucket.get("reset_countdown") or ""
        if countdown:
            break
    result: dict[str, Any] = {
        "status": "ok",
        "name": "copilot",
        "plan": "GitHub Copilot",
        "plan_type": seat.get("copilot_plan") or "individual",
        "reset_countdown": countdown,
        "buckets": buckets,
    }
    result.update(telemetry)
    return result


def _collect_copilot_telemetry() -> dict[str, Any]:
    """Collects local Copilot telemetry from session-store.db."""
    candidate_paths: list[str] = []
    for path in (
        os.path.expanduser("~/.copilot/session-store.db"),
        os.path.join(get_real_home(), ".copilot", "session-store.db"),
    ):
        if path not in candidate_paths:
            candidate_paths.append(path)
    conn = None
    for p in candidate_paths:
        try:
            usable = os.path.exists(p) and os.path.getsize(p) > 0
        except OSError:
            usable = False
        if usable:
            try:
                # Open with immutable=1 so WAL/read-only locks succeed across users/processes
                conn = sqlite3.connect(f"file:{p}?immutable=1", uri=True, timeout=2.0)
                cursor = conn.cursor()
                cursor.execute("SELECT count(*) FROM sessions")
                break
            except Exception:
                if conn:
                    conn.close()
                conn = None

    if not conn:
        return {}

    try:
        cursor = conn.cursor()

        # Session count
        cursor.execute("SELECT count(*) FROM sessions")
        total_sessions = cursor.fetchone()[0] or 0

        # Usage events (tokens, nano AI credits)
        cursor.execute(
            """
            SELECT
                count(*),
                coalesce(sum(input_tokens), 0),
                coalesce(sum(output_tokens), 0),
                coalesce(sum(total_nano_aiu), 0)
            FROM assistant_usage_events
            """
        )
        row = cursor.fetchone()
        total_events = row[0] or 0
        total_input = row[1] or 0
        total_output = row[2] or 0
        total_nano_aiu = row[3] or 0
        total_credits = round(total_nano_aiu / 1_000_000_000.0, 2)
        total_tokens = total_input + total_output

        # Today's events and credits
        cursor.execute(
            """
            SELECT
                count(*),
                coalesce(sum(total_nano_aiu), 0)
            FROM assistant_usage_events
            WHERE date(created_at) = date('now')
            """
        )
        today_row = cursor.fetchone()
        today_events = today_row[0] or 0
        today_credits = round((today_row[1] or 0) / 1_000_000_000.0, 2)

        conn.close()

        return {
            "total_sessions": total_sessions,
            "total_events": total_events,
            "total_tokens": total_tokens,
            "total_ai_credits": total_credits,
            "today": {
                "events_count": today_events,
                "ai_credits_used": today_credits,
            },
        }
    except Exception:
        if conn:
            conn.close()
        return {}


# ─────────────────────────────────────────────────────────────
# Provider: OpenRouter Gateway
# ─────────────────────────────────────────────────────────────

def get_openrouter_api_key() -> str | None:
    token = os.environ.get("OPENROUTER_API_KEY")
    if token:
        return token
    try:
        user = os.environ.get("USER") or os.environ.get("LOGNAME")
        if not user:
            return None
        proc = subprocess.run(
            ["security", "find-generic-password", "-s", "OPENROUTER_API_KEY", "-a", user, "-w"],
            capture_output=True,
            text=True,
            timeout=2.0
        )
        if proc.returncode == 0:
            return proc.stdout.strip()
    except Exception:
        pass
    return None


def collect_openrouter_usage() -> dict[str, Any]:
    """Collects OpenRouter credit balance, monthly spend, and reset countdown."""
    key = get_openrouter_api_key()
    if not key:
        return {"status": "unavailable", "message": "OPENROUTER_API_KEY not found in env or Keychain"}
    try:
        req = urllib.request.Request(
            "https://openrouter.ai/api/v1/auth/key",
            headers={
                "Authorization": f"Bearer {key}",
                "User-Agent": "Antigravity-Quota-Collector/1.0",
            },
        )
        with urllib.request.urlopen(req, timeout=5.0) as resp:
            body = redact_secrets(resp.read().decode(), key)
            data = json.loads(body).get("data", {})

        limit = float(data.get("limit") or 0.0)
        remaining = float(data.get("limit_remaining") or 0.0)
        spend = float(data.get("usage_monthly") or 0.0)

        eff_budget = data.get("effective_budget") or {}
        resets_at = eff_budget.get("resets_at")
        countdown = format_countdown(resets_at) if resets_at else ""

        rem_pct = int(round((remaining / limit) * 100)) if limit > 0 else 100
        rem_pct = max(0, min(100, rem_pct))

        if rem_pct > 20:
            meter_color = "green"
        elif rem_pct > 5:
            meter_color = "yellow"
        else:
            meter_color = "red"

        return {
            "status": "ok",
            "name": "openrouter",
            "plan": "OpenRouter Gateway",
            "reset_countdown": countdown,
            "limit_usd": round(limit, 2),
            "remaining_usd": round(remaining, 2),
            "spend_usd": round(spend, 4),
            "models": {
                "credits": {
                    "name": "Credits Balance",
                    "remaining_percent": rem_pct,
                    "meter_color": meter_color,
                    "reset_countdown": countdown,
                    "limit_usd": round(limit, 2),
                    "remaining_usd": round(remaining, 2),
                    "spend_usd": round(spend, 4),
                }
            },
        }
    except Exception as e:
        return {"status": "error", "error": redact_secrets(str(e), key)}


# ─────────────────────────────────────────────────────────────
# Provider: OpenCode CLI (Local Telemetry)
# ─────────────────────────────────────────────────────────────

def collect_opencode_usage() -> dict[str, Any]:
    """Collects OpenCode local session telemetry from opencode.db."""
    real_home = get_real_home()
    candidate_paths = [
        os.path.join(real_home, ".local/share/opencode/opencode.db"),
        os.path.join(real_home, ".agy-personal/.local/share/opencode/opencode.db"),
    ]
    for p in candidate_paths:
        try:
            usable = os.path.exists(p) and os.path.getsize(p) > 0
        except OSError:
            usable = False
        if usable:
            try:
                conn = sqlite3.connect(f"file:{p}?immutable=1", uri=True, timeout=2.0)
                c = conn.cursor()
                c.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='session'")
                if not c.fetchone():
                    conn.close()
                    continue
                c.execute("SELECT count(*) FROM session")
                total_sessions = c.fetchone()[0] or 0
                c.execute("SELECT count(*) FROM message")
                total_messages = c.fetchone()[0] or 0
                conn.close()

                return {
                    "status": "ok",
                    "name": "opencode",
                    "plan": "OpenCode (Local Telemetry)",
                    "total_sessions": total_sessions,
                    "total_messages": total_messages,
                }
            except Exception:
                pass

    return {"status": "unavailable", "message": "OpenCode database not initialized"}


# ─────────────────────────────────────────────────────────────
# Orchestration & Cache Management
# ─────────────────────────────────────────────────────────────

def collect_all_data() -> dict[str, Any]:
    """Collects usage data across all providers concurrently."""
    ensure_cli_path()
    results: dict[str, Any] = {}
    threads = []

    def run_collector(name: str, fn: Any):
        try:
            results[name] = fn()
        except Exception as exc:
            results[name] = {"status": "error", "error": str(exc)}

    for name, fn in [
        ("cursor", collect_cursor_usage),
        ("antigravity", collect_antigravity_usage),
        ("codex", collect_codex_usage),
        ("claude", collect_claude_usage),
        ("copilot", collect_copilot_usage),
        ("openrouter", collect_openrouter_usage),
        ("opencode", collect_opencode_usage),
    ]:
        t = threading.Thread(target=run_collector, args=(name, fn))
        t.start()
        threads.append(t)

    for t in threads:
        t.join(timeout=20)

    now_utc = datetime.now(timezone.utc)
    return {
        "timestamp": int(now_utc.timestamp()),
        "collected_at": now_utc.isoformat(),
        "providers": results,
    }


def get_cached_or_fresh(force_refresh: bool = False) -> dict[str, Any]:
    """Retrieves cached metrics if fresh; otherwise spawns refresh."""
    if not force_refresh and os.path.exists(CACHE_FILE):
        try:
            mtime = os.path.getmtime(CACHE_FILE)
            age = time.time() - mtime
            if age < CACHE_TTL_SECONDS:
                with open(CACHE_FILE, "r") as f:
                    return json.load(f)
        except Exception:
            pass

    # If cache is older or missing, do fresh collection
    data = collect_all_data()
    try:
        tmp_file = f"{CACHE_FILE}.tmp"
        with open(tmp_file, "w") as f:
            json.dump(data, f, indent=2)
        os.replace(tmp_file, CACHE_FILE)
    except Exception:
        pass
    return data


def generate_summary_line(data: dict[str, Any]) -> str:
    """Generates a compact summary string for terminal or menu bar headers."""
    providers = data.get("providers", {})
    parts = []

    # Cursor
    cursor = providers.get("cursor", {})
    if cursor.get("status") == "ok":
        models = cursor.get("models", {})
        cur_rem = models.get("cursor_models", {}).get("remaining_percent")
        if cur_rem is not None:
            parts.append(f"Cur: {cur_rem}%")

    # Antigravity
    agy = providers.get("antigravity", {})
    if agy.get("status") == "ok":
        buckets = agy.get("buckets", {})
        gemini_5h = buckets.get("gemini_5h", {}).get("remaining_percent")
        gemini_wk = buckets.get("gemini_weekly", {}).get("remaining_percent")
        argon_wk = buckets.get("gemini_argon_wtu_weekly", {}).get(
            "remaining_percent"
        )

        agy_parts = []
        if gemini_5h is not None:
            agy_parts.append(f"{gemini_5h}%(5h)")
        if gemini_wk is not None:
            agy_parts.append(f"{gemini_wk}%(wk)")
        if argon_wk is not None and argon_wk < 100:
            agy_parts.append(f"Arg:{argon_wk}%")
        if agy_parts:
            parts.append(f"AGY: {'/'.join(agy_parts)}")

    # Codex
    cdx = providers.get("codex", {})
    if cdx.get("status") == "ok":
        rl = cdx.get("rate_limits", {})
        five_h = rl.get("five_hour", {}).get("remaining_percent")
        if five_h is not None:
            parts.append(f"Cdx: {five_h}%")
        else:
            parts.append("Cdx: Active")

    # Claude
    claude = providers.get("claude", {})
    if claude.get("status") == "ok":
        today_msgs = (
            claude.get("today", {}).get("message_count", 0)
        )
        if today_msgs > 0:
            parts.append(f"Cld: {today_msgs}msg")

    # Copilot
    cpl = providers.get("copilot", {})
    if cpl.get("status") == "ok":
        percents = [
            bucket.get("remaining_percent")
            for bucket in (cpl.get("buckets") or {}).values()
            if isinstance(bucket, dict) and bucket.get("remaining_percent") is not None
        ]
        if percents:
            parts.append(f"Cpl: {min(percents)}%")
        else:
            parts.append(f"Cpl: {cpl.get('total_ai_credits', 0)}cred")

    # OpenRouter
    openrouter = providers.get("openrouter", {})
    if openrouter.get("status") == "ok":
        rem_usd = openrouter.get("remaining_usd")
        if rem_usd is not None:
            parts.append(f"OR: ${rem_usd:.2f}")

    if not parts:
        return "🤖 Quota: updating..."
    return f"🤖 {' | '.join(parts)}"


# ─────────────────────────────────────────────────────────────
# Local Web Dashboard Server (localhost:3333)
# ─────────────────────────────────────────────────────────────

DASHBOARD_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AI Model & Quota Monitor</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            darkbg: '#0f172a',
            darkcard: '#1e293b',
            darkborder: '#334155'
          }
        }
      }
    }
  </script>
</head>
<body class="bg-darkbg text-slate-100 min-h-screen font-sans antialiased p-6 md:p-12">
  <div class="max-w-5xl mx-auto space-y-8">
    <header class="flex flex-col md:flex-row md:items-center justify-between pb-6 border-b border-darkborder gap-4">
      <div>
        <h1 class="text-3xl font-extrabold tracking-tight flex items-center gap-3">
          <span>🤖</span> AI Subscription & Model Quota Monitor
        </h1>
        <p class="text-slate-400 text-sm mt-1">Live capacity, rate-limit windows, and usage runway across providers.</p>
      </div>
      <div class="flex items-center gap-3">
        <button onclick="refreshData(true)" id="refreshBtn" class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 active:scale-95 transition text-white text-sm font-semibold rounded-lg shadow flex items-center gap-2">
          <span>🔄</span> Refresh Now
        </button>
        <span id="lastUpdated" class="text-xs text-slate-500 font-mono">Updating...</span>
      </div>
    </header>

    <div id="grid" class="grid grid-cols-1 md:grid-cols-2 gap-6">
      <!-- Cards dynamically injected here -->
    </div>
  </div>

  <script>
    function renderProgressBar(label, remaining, used, subtext, color = "indigo") {
      let colorClass = "bg-indigo-500";
      if (remaining <= 5) colorClass = "bg-rose-500";
      else if (remaining <= 20) colorClass = "bg-amber-500";
      else if (color === "emerald") colorClass = "bg-emerald-500";
      else if (color === "blue") colorClass = "bg-blue-500";
      else if (color === "purple") colorClass = "bg-purple-500";

      return `
        <div class="space-y-1.5">
          <div class="flex justify-between text-xs font-medium">
            <span class="text-slate-300">${label}</span>
            <span class="font-mono ${remaining <= 20 ? 'text-amber-400 font-bold' : 'text-slate-200'}">${remaining}% left</span>
          </div>
          <div class="w-full bg-slate-800 rounded-full h-2.5 overflow-hidden border border-slate-700/60">
            <div class="${colorClass} h-2.5 rounded-full transition-all duration-500" style="width: ${remaining}%"></div>
          </div>
          ${subtext ? `<div class="text-[11px] text-slate-500 flex justify-between font-mono"><span>${subtext}</span><span>${used}% used</span></div>` : ''}
        </div>
      `;
    }

    async function refreshData(force = false) {
      const btn = document.getElementById('refreshBtn');
      btn.classList.add('opacity-70', 'cursor-not-allowed');
      try {
        const res = await fetch('/api/quota' + (force ? '?refresh=1' : ''));
        const data = await res.json();
        renderDashboard(data);
      } catch (err) {
        console.error(err);
      } finally {
        btn.classList.remove('opacity-70', 'cursor-not-allowed');
      }
    }

    function renderDashboard(payload) {
      const p = payload.providers || {};
      const grid = document.getElementById('grid');
      document.getElementById('lastUpdated').innerText = 'Synced ' + new Date(payload.timestamp * 1000).toLocaleTimeString();

      let html = '';

      // Cursor Card
      if (p.cursor) {
        const c = p.cursor;
        const curModels = c.models?.cursor_models;
        const otherModels = c.models?.other_models;
        html += `
          <div class="bg-darkcard border border-darkborder rounded-2xl p-6 shadow-xl space-y-5">
            <div class="flex justify-between items-start">
              <div>
                <span class="text-xs uppercase tracking-wider text-emerald-400 font-bold">IDE · Monthly Allocation</span>
                <h2 class="text-xl font-bold mt-0.5 text-slate-100 flex items-center gap-2">Cursor Pro</h2>
              </div>
              ${c.reset_countdown ? `<span class="text-xs px-2.5 py-1 bg-slate-800 border border-slate-700 text-slate-300 rounded-md font-mono">Resets: ${c.reset_countdown}</span>` : ''}
            </div>
            <div class="space-y-4">
              ${curModels ? renderProgressBar(curModels.label, curModels.remaining_percent, curModels.used_percent, 'Monthly Fast Requests', 'emerald') : ''}
              ${otherModels ? renderProgressBar(otherModels.label, otherModels.remaining_percent, otherModels.used_percent, 'Named Models (API)', 'blue') : ''}
              ${c.spend_limit ? `
                <div class="pt-2 border-t border-slate-800 flex justify-between text-xs text-slate-400 font-mono">
                  <span>Spend Limit Runway</span>
                  <span class="text-slate-200 font-semibold">$${c.spend_limit.remaining_usd.toFixed(2)} / $${c.spend_limit.limit_usd.toFixed(2)}</span>
                </div>` : ''}
            </div>
          </div>
        `;
      }

      // Antigravity Card
      if (p.antigravity) {
        const a = p.antigravity;
        const b = a.buckets || {};
        html += `
          <div class="bg-darkcard border border-darkborder rounded-2xl p-6 shadow-xl space-y-5">
            <div class="flex justify-between items-start">
              <div>
                <span class="text-xs uppercase tracking-wider text-blue-400 font-bold">Google Antigravity</span>
                <h2 class="text-xl font-bold mt-0.5 text-slate-100">Antigravity CLI (agy)</h2>
              </div>
              <span class="text-xs px-2.5 py-1 bg-blue-950/60 border border-blue-800/60 text-blue-300 rounded-md font-mono">Multi-Window</span>
            </div>
            <div class="space-y-4">
              ${b.gemini_5h ? renderProgressBar('Gemini Rolling Burst (5h)', b.gemini_5h.remaining_percent, b.gemini_5h.used_percent, 'Refreshes in ' + b.gemini_5h.reset_countdown, 'blue') : ''}
              ${b.gemini_weekly ? renderProgressBar('Gemini Tier Allowance (Weekly)', b.gemini_weekly.remaining_percent, b.gemini_weekly.used_percent, 'Refreshes in ' + b.gemini_weekly.reset_countdown, 'indigo') : ''}
              ${b.gemini_argon_wtu_weekly ? renderProgressBar('Gemini 4 Argon (Weekly)', b.gemini_argon_wtu_weekly.remaining_percent, b.gemini_argon_wtu_weekly.used_percent, 'Refreshes in ' + b.gemini_argon_wtu_weekly.reset_countdown, 'purple') : ''}
              ${b['3p_5h'] ? renderProgressBar('Claude / 3P Models (5h)', b['3p_5h'].remaining_percent, b['3p_5h'].used_percent, 'Refreshes in ' + b['3p_5h'].reset_countdown, 'blue') : ''}
            </div>
          </div>
        `;
      }

      // Codex Card
      if (p.codex) {
        const cdx = p.codex;
        const rl = cdx.rate_limits || {};
        html += `
          <div class="bg-darkcard border border-darkborder rounded-2xl p-6 shadow-xl space-y-5">
            <div class="flex justify-between items-start">
              <div>
                <span class="text-xs uppercase tracking-wider text-teal-400 font-bold">OpenAI</span>
                <h2 class="text-xl font-bold mt-0.5 text-slate-100">${cdx.plan}</h2>
              </div>
              <span class="text-xs px-2.5 py-1 bg-teal-950/60 border border-teal-800/60 text-teal-300 rounded-md font-mono">${cdx.plan_type || 'Active'}</span>
            </div>
            ${Object.keys(rl).length > 0 ? `
              <div class="space-y-4">
                ${rl.five_hour ? renderProgressBar('Codex Rolling Burst (5h)', rl.five_hour.remaining_percent, rl.five_hour.used_percent, 'Refreshes in ' + rl.five_hour.reset_countdown, 'teal') : ''}
                ${rl.weekly ? renderProgressBar('Codex Tier Allowance (Weekly)', rl.weekly.remaining_percent, rl.weekly.used_percent, 'Refreshes in ' + rl.weekly.reset_countdown, 'emerald') : ''}
              </div>` : ''}
            <div class="space-y-3 text-sm text-slate-300 font-mono">
              ${cdx.reset_credits_available > 0 ? `
                <div class="flex justify-between py-1 border-b border-slate-800">
                  <span>Reset Credits</span>
                  <span class="text-emerald-400 font-semibold">${cdx.reset_credits_available} available</span>
                </div>` : ''}
              <div class="flex justify-between py-1 border-b border-slate-800">
                <span>Auth Mode</span>
                <span class="text-slate-100 font-semibold">${cdx.auth_mode}</span>
              </div>
              <div class="flex justify-between py-1 border-b border-slate-800">
                <span>Active Threads</span>
                <span class="text-slate-100">${cdx.total_threads} sessions</span>
              </div>
              <div class="flex justify-between py-1 border-b border-slate-800">
                <span>Recorded Token Volume</span>
                <span class="text-slate-100">${(cdx.lifetime_tokens_recorded || 0).toLocaleString()} tokens</span>
              </div>
            </div>
          </div>
        `;
      }

      // Copilot Card
      if (p.copilot && p.copilot.status === 'ok') {
        const cpl = p.copilot;
        const b = cpl.buckets || {};
        html += `
          <div class="bg-darkcard border border-darkborder rounded-2xl p-6 shadow-xl space-y-5">
            <div class="flex justify-between items-start">
              <div>
                <span class="text-xs uppercase tracking-wider text-violet-400 font-bold">GitHub</span>
                <h2 class="text-xl font-bold mt-0.5 text-slate-100">GitHub Copilot</h2>
              </div>
              <span class="text-xs px-2.5 py-1 bg-violet-950/60 border border-violet-800/60 text-violet-300 rounded-md font-mono">${cpl.plan_type || 'Active'}</span>
            </div>
            <div class="space-y-4">
              ${b.chat ? renderProgressBar(b.chat.label, b.chat.remaining_percent, b.chat.used_percent, 'Resets in ' + (b.chat.reset_countdown || ''), 'indigo') : ''}
              ${b.completions ? renderProgressBar(b.completions.label, b.completions.remaining_percent, b.completions.used_percent, 'Resets in ' + (b.completions.reset_countdown || ''), 'emerald') : ''}
              ${b.premium_interactions ? renderProgressBar(b.premium_interactions.label, b.premium_interactions.remaining_percent, b.premium_interactions.used_percent, 'Resets in ' + (b.premium_interactions.reset_countdown || ''), 'purple') : ''}
            </div>
          </div>
        `;
      }

      // Claude Card
      if (p.claude && p.claude.status === 'ok') {
        const cld = p.claude;
        html += `
          <div class="bg-darkcard border border-darkborder rounded-2xl p-6 shadow-xl space-y-5">
            <div class="flex justify-between items-start">
              <div>
                <span class="text-xs uppercase tracking-wider text-amber-400 font-bold">Anthropic</span>
                <h2 class="text-xl font-bold mt-0.5 text-slate-100">Claude Code</h2>
              </div>
              <span class="text-xs px-2.5 py-1 bg-amber-950/60 border border-amber-800/60 text-amber-300 rounded-md font-mono">Local Tracker</span>
            </div>
            <div class="space-y-3 text-sm text-slate-300 font-mono">
              <div class="flex justify-between py-1 border-b border-slate-800">
                <span>Lifetime Sessions</span>
                <span class="text-slate-100 font-semibold">${cld.total_sessions}</span>
              </div>
              <div class="flex justify-between py-1 border-b border-slate-800">
                <span>Total Messages Recorded</span>
                <span class="text-slate-100">${(cld.total_messages || 0).toLocaleString()}</span>
              </div>
              <div class="flex justify-between py-1 border-b border-slate-800">
                <span>Today's Messages</span>
                <span class="text-slate-100">${cld.today?.message_count || 0}</span>
              </div>
            </div>
          </div>
        `;
      }

      grid.innerHTML = html;
    }

    refreshData();
    setInterval(() => refreshData(false), 30000);
  </script>
</body>
</html>
"""


class DashboardRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(DASHBOARD_HTML.encode("utf-8"))
        elif self.path.startswith("/api/quota"):
            force = "refresh=1" in self.path
            data = get_cached_or_fresh(force_refresh=force)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format: str, *args: Any) -> None:
        # Suppress routine HTTP request logging to keep output clean
        pass


def make_dashboard_server(port: int = 3333) -> http.server.HTTPServer:
    """Serve the quota page on loopback only."""
    return http.server.HTTPServer(("127.0.0.1", port), DashboardRequestHandler)


def serve_dashboard(port: int = 3333):
    server = make_dashboard_server(port)
    print(f"🚀 AI Quota Web Dashboard running at: http://localhost:{port}")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server.")
    finally:
        server.server_close()


def main():
    parser = argparse.ArgumentParser(
        description="Unified AI Model & Quota Collector"
    )
    parser.add_argument(
        "--json", action="store_true", help="Output normalized JSON"
    )
    parser.add_argument(
        "--summary", action="store_true", help="Output compact summary line"
    )
    parser.add_argument(
        "--refresh", action="store_true", help="Bypass cache and force refresh"
    )
    parser.add_argument(
        "--serve", action="store_true", help="Start local web dashboard on localhost:3333"
    )
    parser.add_argument(
        "--port", type=int, default=3333, help="Port for web dashboard (default 3333)"
    )

    args = parser.parse_args()

    if args.serve:
        serve_dashboard(port=args.port)
        return

    data = get_cached_or_fresh(force_refresh=args.refresh)

    if args.json:
        print(json.dumps(data, indent=2))
    elif args.summary:
        print(generate_summary_line(data))
    else:
        # Default: readable terminal report
        summary = generate_summary_line(data)
        print(summary)
        print("-" * len(summary))
        providers = data.get("providers", {})
        for name, p in providers.items():
            print(f"\n[{p.get('name', name).upper()}] - {p.get('plan', '')}")
            if name == "cursor" and "models" in p:
                for mk, m in p["models"].items():
                    print(
                        f"  • {m['label']}: {m['remaining_percent']}% remaining ({m['used_percent']}% used)"
                    )
                if "spend_limit" in p:
                    sl = p["spend_limit"]
                    print(
                        f"  • Spend Limit: ${sl['remaining_usd']:.2f} / ${sl['limit_usd']:.2f} left"
                    )
                if p.get("reset_countdown"):
                    print(f"  • Billing Reset: in {p['reset_countdown']}")
            elif name == "antigravity" and "buckets" in p:
                for bk, b in p["buckets"].items():
                    cd = f" (resets in {b['reset_countdown']})" if b.get('reset_countdown') else ""
                    print(
                        f"  • {b['label']}: {b['remaining_percent']}% remaining{cd}"
                    )
            elif name == "codex":
                print(f"  • Auth Mode: {p.get('auth_mode')}")
                print(f"  • Tracked Threads: {p.get('total_threads')}")
            elif name == "claude":
                print(f"  • Total Sessions: {p.get('total_sessions')}")
                if "today" in p:
                    print(f"  • Today's Messages: {p['today'].get('message_count')}")
            elif name == "copilot" and "buckets" in p:
                for bk, b in p["buckets"].items():
                    cd = f" (resets in {b['reset_countdown']})" if b.get("reset_countdown") else ""
                    print(f"  • {b['label']}: {b['remaining_percent']}% remaining{cd}")


if __name__ == "__main__":
    main()
