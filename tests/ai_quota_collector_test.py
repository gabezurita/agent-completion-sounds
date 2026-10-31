#!/usr/bin/env python3
"""Unit tests for ai_quota_collector."""

from datetime import datetime, timedelta, timezone
import io
import json
import os
import sys
import tempfile
import time
import unittest
from unittest.mock import MagicMock, mock_open, patch

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "scripts"))

import ai_quota_collector


class TestAiQuotaCollector(unittest.TestCase):
    def test_format_countdown_future_days(self):
        target = datetime.now(timezone.utc) + timedelta(days=3, hours=5)
        cd = ai_quota_collector.format_countdown(target.isoformat())
        self.assertIn("3d", cd)

    def test_format_countdown_future_hours(self):
        target = datetime.now(timezone.utc) + timedelta(hours=4, minutes=20)
        cd = ai_quota_collector.format_countdown(target.isoformat())
        self.assertIn("4h", cd)

    def test_format_countdown_past(self):
        target = datetime.now(timezone.utc) - timedelta(minutes=10)
        cd = ai_quota_collector.format_countdown(target.isoformat())
        self.assertEqual(cd, "ready")

    def test_format_countdown_none(self):
        self.assertEqual(ai_quota_collector.format_countdown(None), "")
        self.assertEqual(ai_quota_collector.format_countdown("invalid-date"), "")

    def test_generate_summary_line(self):
        mock_data = {
            "providers": {
                "cursor": {
                    "status": "ok",
                    "models": {
                        "cursor_models": {"remaining_percent": 75}
                    },
                },
                "antigravity": {
                    "status": "ok",
                    "buckets": {
                        "gemini_5h": {"remaining_percent": 90},
                        "gemini_weekly": {"remaining_percent": 95},
                        "gemini_argon_wtu_weekly": {"remaining_percent": 40},
                    },
                },
                "codex": {"status": "ok"},
                "claude": {
                    "status": "ok",
                    "today": {"message_count": 14},
                },
            }
        }
        line = ai_quota_collector.generate_summary_line(mock_data)
        self.assertIn("Cur: 75%", line)
        self.assertIn("AGY: 90%(5h)/95%(wk)/Arg:40%", line)
        self.assertIn("Cdx: Active", line)
        self.assertIn("Cld: 14msg", line)

        # With codex rate limits
        mock_data["providers"]["codex"]["rate_limits"] = {
            "five_hour": {"remaining_percent": 92}
        }
        line2 = ai_quota_collector.generate_summary_line(mock_data)
        self.assertIn("Cdx: 92%", line2)

    @patch("subprocess.run")
    def test_collect_cursor_usage_mock(self, mock_run):
        mock_api_response = {
            "billingCycleStart": "1792090318717",
            "billingCycleEnd": str(
                int((datetime.now(timezone.utc) + timedelta(days=4)).timestamp() * 1000)
            ),
            "planUsage": {
                "autoPercentUsed": 25.0,
                "apiPercentUsed": 5.0,
                "totalPercentUsed": 25.0,
            },
            "spendLimitUsage": {
                "individualLimit": 5000,
                "individualRemaining": 4500,
            },
            "displayMessage": "You have used 25% of your quota",
        }
        mock_run.return_value = MagicMock(
            returncode=0, stdout=json.dumps(mock_api_response)
        )

        with patch("os.path.exists", return_value=True), patch(
            "sqlite3.connect"
        ) as mock_conn:
            mock_cursor = MagicMock()
            mock_cursor.fetchone.return_value = ["fake-token-12345"]
            mock_conn.return_value.cursor.return_value = mock_cursor

            res = ai_quota_collector.collect_cursor_usage()
            self.assertEqual(res["status"], "ok")
            self.assertNotIn("fake-token-12345", json.dumps(res))
            self.assertEqual(
                res["models"]["cursor_models"]["remaining_percent"], 75
            )
            self.assertEqual(res["models"]["cursor_models"]["used_percent"], 25)
            self.assertEqual(
                res["models"]["other_models"]["remaining_percent"], 95
            )
            self.assertEqual(res["spend_limit"]["limit_usd"], 50.0)
            self.assertEqual(res["spend_limit"]["remaining_usd"], 45.0)

    @patch("subprocess.run")
    def test_collect_cursor_usage_pro_no_api_credits_mock(self, mock_run):
        mock_api_response = {
            "billingCycleStart": "1790812800000",
            "billingCycleEnd": str(
                int((datetime.now(timezone.utc) + timedelta(days=4)).timestamp() * 1000)
            ),
            "planUsage": {
                "autoPercentUsed": 32.0,
                "apiPercentUsed": 0.0,
                "totalPercentUsed": 32.0,
            },
            "spendLimitUsage": {
                "individualLimit": 0,
                "limitType": "user",
            },
            "displayMessage": "You've used 32% of your included usage",
        }
        mock_run.return_value = MagicMock(
            returncode=0, stdout=json.dumps(mock_api_response)
        )

        with patch("os.path.exists", return_value=True), patch(
            "sqlite3.connect"
        ) as mock_conn:
            mock_cursor = MagicMock()
            mock_cursor.fetchone.return_value = ["fake-token-12345"]
            mock_conn.return_value.cursor.return_value = mock_cursor

            res = ai_quota_collector.collect_cursor_usage()
            self.assertEqual(res["status"], "ok")
            self.assertNotIn("fake-token-12345", json.dumps(res))
            self.assertEqual(
                res["models"]["cursor_models"]["remaining_percent"], 68
            )
            self.assertEqual(res["models"]["cursor_models"]["used_percent"], 32)
            self.assertNotIn("other_models", res["models"])
            self.assertNotIn("spend_limit", res)

    @patch("subprocess.run")
    def test_collect_cursor_usage_token_based_mock(self, mock_run):
        mock_api_response = {
            "billingCycleStart": "1790812800000",
            "billingCycleEnd": str(
                int((datetime.now(timezone.utc) + timedelta(days=5)).timestamp() * 1000)
            ),
            "spendLimitUsage": {
                "individualLimit": 0,
                "limitType": "user",
            },
            "displayThreshold": 200,
            "autoModelSelectedDisplayMessage": "",
            "namedModelSelectedDisplayMessage": "",
            "autoBucketModels": ["default"],
        }
        mock_run.return_value = MagicMock(
            returncode=0, stdout=json.dumps(mock_api_response)
        )

        with patch("os.path.exists", return_value=True), patch(
            "sqlite3.connect"
        ) as mock_conn:
            mock_cursor = MagicMock()
            mock_cursor.fetchone.side_effect = [["fake-token-12345"], ["active"]]
            mock_conn.return_value.cursor.return_value = mock_cursor

            res = ai_quota_collector.collect_cursor_usage()
            self.assertEqual(res["status"], "ok")
            self.assertNotIn("fake-token-12345", json.dumps(res))
            self.assertEqual(res["plan"], "Cursor Pro")
            self.assertEqual(
                res["models"]["cursor_models"]["remaining_percent"], 100
            )
            self.assertEqual(res["models"]["cursor_models"]["used_percent"], 0)
            self.assertNotIn("other_models", res["models"])
            self.assertNotIn("spend_limit", res)
            self.assertTrue(res["reset_countdown"])

    @patch("subprocess.run")
    def test_collect_cursor_usage_fallback_mock(self, mock_run):
        mock_run.return_value = MagicMock(returncode=28, stdout="")

        with patch("sqlite3.connect") as mock_conn, \
             patch("os.path.exists", return_value=True), \
             patch("builtins.open", side_effect=FileNotFoundError):
            mock_cursor = MagicMock()
            mock_cursor.fetchone.side_effect = [["fake-token-12345"], ["active"]]
            mock_conn.return_value.cursor.return_value = mock_cursor

            res = ai_quota_collector.collect_cursor_usage()
            self.assertEqual(res["status"], "ok")
            self.assertEqual(res["plan"], "Cursor Pro")
            self.assertEqual(
                res["models"]["cursor_models"]["remaining_percent"], 100
            )
            self.assertEqual(res["models"]["cursor_models"]["used_percent"], 0)

    @patch("subprocess.run")
    def test_collect_antigravity_usage_mock(self, mock_run):
        mock_agy_json = {
            "command": {
                "name": "usage",
                "data": {
                    "groups": [
                        {
                            "name": "Gemini Models",
                            "buckets": [
                                {
                                    "id": "gemini-weekly",
                                    "name": "Weekly Limit Remaining",
                                    "remaining_fraction": 0.92,
                                    "reset_time": "2026-10-25T00:00:00Z",
                                    "window": "weekly",
                                },
                                {
                                    "id": "gemini-5h",
                                    "name": "Five Hour Limit Remaining",
                                    "remaining_fraction": 0.88,
                                    "reset_time": "2026-10-19T03:00:00Z",
                                    "window": "5h",
                                },
                            ],
                        }
                    ]
                },
            }
        }
        mock_run.return_value = MagicMock(
            returncode=0, stdout=json.dumps(mock_agy_json)
        )

        with patch("os.path.exists", return_value=False):
            res = ai_quota_collector.collect_antigravity_usage()
            self.assertEqual(res["status"], "ok")
            buckets = res["buckets"]
            self.assertIn("gemini_weekly", buckets)
            self.assertEqual(buckets["gemini_weekly"]["remaining_percent"], 92)
            self.assertEqual(buckets["gemini_weekly"]["used_percent"], 8)
            self.assertEqual(buckets["gemini_5h"]["remaining_percent"], 88)

    @patch("ai_quota_collector.query_codex_app_server_rate_limits")
    def test_collect_codex_rate_limits_mock(self, mock_query):
        mock_query.return_value = {
            "rateLimits": {
                "primary": {
                    "usedPercent": 8,
                    "windowDurationMins": 300,
                    "resetsAt": int(time.time()) + 16200,
                },
                "secondary": {
                    "usedPercent": 5,
                    "windowDurationMins": 10080,
                    "resetsAt": int(time.time()) + 525600,
                },
                "planType": "plus",
            },
            "rateLimitResetCredits": {
                "availableCount": 3,
            },
        }

        with patch("os.path.exists", return_value=True), \
             patch("builtins.open", mock_open(read_data='{"auth_mode": "ChatGPT"}')), \
             patch("sqlite3.connect") as mock_conn:
            mock_cursor = MagicMock()
            mock_cursor.fetchone.return_value = [10, 1000000]
            mock_conn.return_value.cursor.return_value = mock_cursor

            res = ai_quota_collector.collect_codex_usage()
            self.assertEqual(res["status"], "ok")
            self.assertEqual(res["plan_type"], "plus")
            self.assertEqual(res["reset_credits_available"], 3)
            self.assertIn("five_hour", res["rate_limits"])
            self.assertEqual(res["rate_limits"]["five_hour"]["remaining_percent"], 92)
            self.assertEqual(res["rate_limits"]["five_hour"]["used_percent"], 8)
            self.assertEqual(res["rate_limits"]["weekly"]["remaining_percent"], 95)
            self.assertEqual(res["total_threads"], 10)
            self.assertEqual(res["lifetime_tokens_recorded"], 1000000)

    def test_dashboard_handler_routes(self):
        handler = ai_quota_collector.DashboardRequestHandler.__new__(
            ai_quota_collector.DashboardRequestHandler
        )
        handler.rfile = io.BytesIO(b"")
        handler.wfile = io.BytesIO()
        handler.path = "/"
        handler.command = "GET"
        handler.request_version = "HTTP/1.1"
        handler.send_response = MagicMock()
        handler.send_header = MagicMock()
        handler.end_headers = MagicMock()

        handler.do_GET()
        handler.send_response.assert_called_with(200)
        out = handler.wfile.getvalue().decode()
        self.assertIn("AI Subscription & Model Quota Monitor", out)

        # Test API route
        handler.wfile = io.BytesIO()
        handler.path = "/api/quota"
        handler.send_response.reset_mock()
        with patch(
            "ai_quota_collector.get_cached_or_fresh",
            return_value={"test_status": "ok"},
        ):
            handler.do_GET()
            handler.send_response.assert_called_with(200)
            res_json = json.loads(handler.wfile.getvalue().decode())
            self.assertEqual(res_json["test_status"], "ok")

    def test_collect_copilot_usage_missing_db(self):
        with patch("os.path.exists", return_value=False):
            res = ai_quota_collector.collect_copilot_usage()
            self.assertEqual(res["status"], "unavailable")

    def test_collect_copilot_usage_ok(self):
        with patch("os.path.exists", return_value=True), patch(
            "sqlite3.connect"
        ) as mock_conn:
            mock_cursor = MagicMock()
            mock_cursor.fetchone.side_effect = [
                (5,),  # total_sessions
                (12, 100000, 5000, 1080000000),  # total_events, input, output, nano_aiu
                (3, 250000000),  # today_events, today_nano_aiu
            ]
            mock_conn.return_value.cursor.return_value = mock_cursor

            res = ai_quota_collector.collect_copilot_usage()
            self.assertEqual(res["status"], "ok")
            self.assertEqual(res["total_sessions"], 5)
            self.assertEqual(res["total_events"], 12)
            self.assertEqual(res["total_tokens"], 105000)
            self.assertEqual(res["total_ai_credits"], 1.08)
            self.assertEqual(res["today"]["events_count"], 3)
            self.assertEqual(res["today"]["ai_credits_used"], 0.25)

    def test_ensure_cli_path_prepends_existing_user_bins(self):
        with tempfile.TemporaryDirectory() as tmp:
            local_bin = os.path.join(tmp, ".local", "bin")
            os.makedirs(local_bin)
            missing = os.path.join(tmp, "missing-bin")
            gui_path = "/usr/bin:/bin:/usr/sbin:/sbin"
            with patch.dict(os.environ, {"PATH": gui_path}), patch.object(
                ai_quota_collector,
                "cli_path_prefixes",
                return_value=[local_bin, missing],
            ):
                path = ai_quota_collector.ensure_cli_path()
                again = ai_quota_collector.ensure_cli_path()
            entries = path.split(":")
            self.assertEqual(entries[0], local_bin)
            self.assertNotIn(missing, entries)
            self.assertEqual(entries.count(local_bin), 1)
            self.assertIn("/usr/bin", entries)
            self.assertEqual(again, path)

    def test_collector_source_has_no_personal_home(self):
        with open(ai_quota_collector.__file__, encoding="utf-8") as handle:
            source = handle.read()
        self.assertNotIn("/Users/gabrielzurita", source)
        self.assertNotIn("gabrielzurita", source)

    def test_get_real_home_uses_parent_of_agy_personal(self):
        with patch.dict(os.environ, {"HOME": "/tmp/example/.agy-personal"}), patch(
            "os.path.exists", return_value=True
        ):
            self.assertEqual(ai_quota_collector.get_real_home(), "/tmp/example")

    def test_get_real_home_keeps_normal_home(self):
        with patch.dict(os.environ, {"HOME": "/tmp/example"}):
            self.assertEqual(ai_quota_collector.get_real_home(), "/tmp/example")

    def test_copilot_checks_tilde_and_real_home_session_store(self):
        with patch.dict(os.environ, {"HOME": "/tmp/nested/.agy-personal"}), patch.object(
            ai_quota_collector, "get_real_home", return_value="/tmp/nested"
        ), patch("os.path.exists", return_value=False) as exists:
            res = ai_quota_collector.collect_copilot_usage()
        self.assertEqual(res["status"], "unavailable")
        checked = [call.args[0] for call in exists.call_args_list]
        self.assertIn(
            "/tmp/nested/.agy-personal/.copilot/session-store.db", checked
        )
        self.assertIn("/tmp/nested/.copilot/session-store.db", checked)

    def test_opencode_checks_agy_personal_database(self):
        with patch.object(
            ai_quota_collector, "get_real_home", return_value="/tmp/example"
        ), patch("os.path.exists", return_value=False) as exists:
            res = ai_quota_collector.collect_opencode_usage()
        self.assertEqual(res["status"], "unavailable")
        checked = [call.args[0] for call in exists.call_args_list]
        self.assertIn("/tmp/example/.local/share/opencode/opencode.db", checked)
        self.assertIn(
            "/tmp/example/.agy-personal/.local/share/opencode/opencode.db",
            checked,
        )

    def test_openrouter_error_redacts_key(self):
        secret = "sk-test-openrouter-secret"
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": secret}), patch(
            "urllib.request.urlopen",
            side_effect=RuntimeError(f"failed for {secret}"),
        ):
            res = ai_quota_collector.collect_openrouter_usage()
        self.assertEqual(res["status"], "error")
        self.assertNotIn(secret, json.dumps(res))
        self.assertIn("[redacted]", res["error"])

    def test_server_binds_loopback(self):
        server = ai_quota_collector.make_dashboard_server(0)
        try:
            self.assertEqual(server.server_address[0], "127.0.0.1")
        finally:
            server.server_close()


if __name__ == "__main__":
    unittest.main()
