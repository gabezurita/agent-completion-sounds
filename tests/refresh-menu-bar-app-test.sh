#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="${REPO_ROOT}/scripts/refresh-menu-bar-app.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

BARE="${TEST_ROOT}/origin.git"
USER_REPO="${TEST_ROOT}/user"
RELEASE="${TEST_ROOT}/release"
APP="${USER_REPO}/build/AgentDashboard.app"
BIN="${TEST_ROOT}/bin"
PIDFILE="${TEST_ROOT}/pids"
OPEN_LOG="${TEST_ROOT}/open.log"
BUILD_LOG="${TEST_ROOT}/build.log"

mkdir -p "${USER_REPO}"
git init -b main "${USER_REPO}" >/dev/null
printf 'one\n' > "${USER_REPO}/README"
git -C "${USER_REPO}" add README
git -C "${USER_REPO}" -c user.email=test@example.com -c user.name=test commit -m "init" >/dev/null
git init --bare -b main "${BARE}" >/dev/null
git -C "${USER_REPO}" remote add origin "${BARE}"
git -C "${USER_REPO}" push -u origin main >/dev/null
git -C "${USER_REPO}" checkout -b feature >/dev/null
printf 'feature\n' > "${USER_REPO}/FEATURE"
git -C "${USER_REPO}" add FEATURE
git -C "${USER_REPO}" -c user.email=test@example.com -c user.name=test commit -m "feature" >/dev/null

mkdir -p "${BIN}"
cat > "${BIN}/pgrep" <<'SH'
#!/usr/bin/env bash
if [[ -s "${REFRESH_TEST_DIR}/pids" ]]; then
  cat "${REFRESH_TEST_DIR}/pids"
  exit 0
fi
exit 1
SH
cat > "${BIN}/kill" <<'SH'
#!/usr/bin/env bash
: > "${REFRESH_TEST_DIR}/pids"
exit 0
SH
cat > "${BIN}/open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${REFRESH_TEST_DIR}/open.log"
exit 0
SH
cat > "${BIN}/build-ok" <<'SH'
#!/usr/bin/env bash
if [[ "${REFRESH_FAIL_BUILD:-0}" -eq 1 ]]; then
  printf 'fail\n' >> "${REFRESH_TEST_DIR}/build.log"
  exit 1
fi
mkdir -p build/AgentDashboard.app/Contents/MacOS
printf '#!/bin/sh\nexit 0\n' > build/AgentDashboard.app/Contents/MacOS/AgentSoundsMenu
chmod +x build/AgentDashboard.app/Contents/MacOS/AgentSoundsMenu
printf 'ok\n' >> "${REFRESH_TEST_DIR}/build.log"
SH
chmod +x "${BIN}/pgrep" "${BIN}/kill" "${BIN}/open" "${BIN}/build-ok"

export REFRESH_TEST_DIR="${TEST_ROOT}"
export PATH="${BIN}:${PATH}"
export REFRESH_BUILD_CMD="${BIN}/build-ok"

refresh() {
  bash "${SCRIPT}" \
    --repo "${USER_REPO}" \
    --release-root "${RELEASE}" \
    --app "${APP}"
}

build_count() {
  if [[ -f "${BUILD_LOG}" ]]; then
    wc -l < "${BUILD_LOG}" | tr -d ' '
  else
    echo 0
  fi
}

printf '4242\n' > "${PIDFILE}"
refresh
test "$(build_count)" -eq 1
test -x "${APP}/Contents/MacOS/AgentSoundsMenu"
test "$(cat "${RELEASE}/installed-sha")" = "$(git -C "${BARE}" rev-parse main)"
test "$(cat "${OPEN_LOG}")" = "${APP}"
test ! -s "${PIDFILE}"
test "$(git -C "${USER_REPO}" rev-parse --abbrev-ref HEAD)" = "feature"
test "$(cat "${USER_REPO}/FEATURE")" = "feature"

: > "${OPEN_LOG}"
printf '4242\n' > "${PIDFILE}"
refresh
test "$(build_count)" -eq 1
test -s "${PIDFILE}"
test ! -s "${OPEN_LOG}"

: > "${PIDFILE}"
: > "${OPEN_LOG}"
SEED=$(mktemp -d)
git clone "${BARE}" "${SEED}" >/dev/null
printf 'two\n' >> "${SEED}/README"
git -C "${SEED}" add README
git -C "${SEED}" -c user.email=test@example.com -c user.name=test commit -m "two" >/dev/null
git -C "${SEED}" push origin main >/dev/null
rm -rf "${SEED}"
refresh
test "$(build_count)" -eq 2
test "$(cat "${RELEASE}/installed-sha")" = "$(git -C "${BARE}" rev-parse main)"
test ! -s "${OPEN_LOG}"

printf '4242\n' > "${PIDFILE}"
: > "${OPEN_LOG}"
rm -f "${RELEASE}/installed-sha"
export REFRESH_FAIL_BUILD=1
set +e
refresh
status=$?
set -e
test "${status}" -ne 0
test "$(cat "${PIDFILE}")" = "4242"
test ! -s "${OPEN_LOG}"
unset REFRESH_FAIL_BUILD

git -C "${RELEASE}/src" remote set-url origin "${TEST_ROOT}/missing.git"
printf '9999\n' > "${PIDFILE}"
refresh
test "$(cat "${PIDFILE}")" = "9999"

LAUNCHD="${TEST_ROOT}/LaunchAgents"
LIB="${TEST_ROOT}/lib"
bash "${SCRIPT}" --install --no-load \
  --repo "${USER_REPO}" \
  --release-root "${RELEASE}" \
  --app "${APP}" \
  --lib-dir "${LIB}" \
  --launchd-dir "${LAUNCHD}"
PLIST="${LAUNCHD}/com.gabo.agent-sounds-menu.refresh.plist"
test -f "${PLIST}"
test -x "${LIB}/refresh-menu-bar-app.sh"
grep -q "<string>com.gabo.agent-sounds-menu.refresh</string>" "${PLIST}"
grep -q "<integer>60</integer>" "${PLIST}"
grep -q -- "--installed" "${PLIST}"

echo "refresh-menu-bar-app-test: ALL PASS"
