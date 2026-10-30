#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 "${REPO_ROOT}/tests/ai_quota_collector_test.py"
printf '%s\n' "quota-collector-test: PASS"
