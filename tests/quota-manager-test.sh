#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "SKIP: AgentSoundsMenu requires macOS (Darwin). Skipping build test on $(uname -s)."
  exit 0
fi

echo "=== Test 1: Verify AgentSoundsMenu compiles cleanly ==="
bash "${REPO_ROOT}/scripts/build-menu-bar-app.sh"
echo "PASS: AgentSoundsMenu compiled cleanly into build/AgentDashboard.app"

echo "=== Test 2: Verify binary exists and is executable ==="
APP_BIN="${REPO_ROOT}/build/AgentDashboard.app/Contents/MacOS/AgentSoundsMenu"
if [[ -x "${APP_BIN}" ]]; then
  echo "PASS: Compiled executable is present and executable"
else
  echo "FAIL: ${APP_BIN} is not executable" >&2
  exit 1
fi

echo "=== Test 3: Rank quota pools from the 29 Oct 2026 snapshot ==="
SWIFTC=$(command -v swiftc || echo "/usr/bin/swiftc")
SUGGESTION_SRC="${REPO_ROOT}/ui/QuotaPoolSuggestion.swift"
RANK_TEST_SRC="${REPO_ROOT}/tests/quota-pool-suggestion-test.swift"
RANK_TEST_BIN="${REPO_ROOT}/build/quota-pool-suggestion-test"
"${SWIFTC}" "${SUGGESTION_SRC}" "${RANK_TEST_SRC}" -o "${RANK_TEST_BIN}"
"${RANK_TEST_BIN}"
echo "PASS: quota pool ranking matches the snapshot"

echo "quota-manager-test: ALL PASS"
