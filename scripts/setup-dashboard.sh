#!/usr/bin/env bash
# Build AgentDashboard.app, launch the menu, and start the local quota page.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
APP_BUNDLE="${REPO_ROOT}/build/AgentDashboard.app"
COLLECTOR="${APP_BUNDLE}/Contents/Resources/ai_quota_collector.py"
PORT=3333

# Tests set this to record the call without building, launching, or binding a port.
if [[ -n "${AGENT_DASHBOARD_STUB_LOG:-}" ]]; then
  printf '%s\n' "setup-dashboard" >> "${AGENT_DASHBOARD_STUB_LOG}"
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' "setup-dashboard requires macOS" >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || {
  printf '%s\n' "setup-dashboard requires python3" >&2
  exit 1
}

"${SCRIPT_DIR}/build-menu-bar-app.sh"

if [[ ! -f "${COLLECTOR}" ]]; then
  printf '%s\n' "collector missing from ${COLLECTOR}" >&2
  exit 1
fi

open "${APP_BUNDLE}"

if python3 -c 'import socket,sys; s=socket.socket(); s.settimeout(0.3); code=s.connect_ex(("127.0.0.1", 3333)); s.close(); sys.exit(0 if code == 0 else 1)'; then
  printf '%s\n' "Quota page already listening on 127.0.0.1:${PORT}"
else
  nohup python3 "${COLLECTOR}" --serve --port "${PORT}" >>/tmp/ai_quota_collector_serve.log 2>&1 &
  printf '%s\n' "Quota page starting at http://127.0.0.1:${PORT}"
fi
