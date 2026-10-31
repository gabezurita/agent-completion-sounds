#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ "$(uname -s)" != "Darwin" ]]; then
  if "${REPO_ROOT}/scripts/setup-dashboard.sh" >/dev/null 2>&1; then
    printf '%s\n' "expected setup-dashboard.sh to fail off macOS" >&2
    exit 1
  fi
  printf '%s\n' "setup-dashboard-test: PASS (non-macOS refuses the dashboard install)"
  exit 0
fi

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT
STUB_BIN="${TEST_ROOT}/bin"
mkdir -p "${STUB_BIN}"
OPEN_LOG="${TEST_ROOT}/open.log"
PYTHON_LOG="${TEST_ROOT}/python.log"
: > "${OPEN_LOG}"
: > "${PYTHON_LOG}"

cat > "${STUB_BIN}/open" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${OPEN_LOG}"
EOF
cat > "${STUB_BIN}/python3" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${PYTHON_LOG}"
if [[ "\${1:-}" == "-c" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "${STUB_BIN}/open" "${STUB_BIN}/python3"

PATH="${STUB_BIN}:${PATH}" "${REPO_ROOT}/scripts/setup-dashboard.sh"

for _ in {1..20}; do
  grep -q -- '--serve' "${PYTHON_LOG}" && break
  sleep 0.05
done

COLLECTOR="${REPO_ROOT}/build/AgentDashboard.app/Contents/Resources/ai_quota_collector.py"
[[ -f "${COLLECTOR}" ]]
if grep -q '/Users/gabrielzurita' "${COLLECTOR}"; then
  printf '%s\n' "bundled collector still has a personal home path" >&2
  exit 1
fi
grep -q 'AgentDashboard.app' "${OPEN_LOG}"
grep -q -- '--serve' "${PYTHON_LOG}"
grep -q -- '--port' "${PYTHON_LOG}"
grep -q '3333' "${PYTHON_LOG}"
grep -q 'ai_quota_collector.py' "${PYTHON_LOG}"

printf '%s\n' "setup-dashboard-test: PASS"
