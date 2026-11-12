#!/usr/bin/env bash
# Tests for diagnostic logging in codex-notify.sh, play-random-completion-sound.sh, and sound-mode.sh.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sound-diag-test.XXXXXX")
LOG_FILE="${TMP_ROOT}/test-agent-sound.log"
SESSION_DIR="${TMP_ROOT}/sessions"
MOCK_SOUNDS="${TMP_ROOT}/sounds"
mkdir -p "${MOCK_SOUNDS}/test-unit" "${SESSION_DIR}"
touch "${MOCK_SOUNDS}/test-unit/test-clip.wav"
printf 'test-unit\n' > "${MOCK_SOUNDS}/favorites.txt"
printf 'session\n' > "${MOCK_SOUNDS}/.mode"

# Mock afplay that succeeds quickly
MOCK_BIN="${TMP_ROOT}/bin"
mkdir -p "${MOCK_BIN}"
cat <<'SH' > "${MOCK_BIN}/afplay"
#!/usr/bin/env bash
exit 0
SH
chmod +x "${MOCK_BIN}/afplay"

export PATH="${MOCK_BIN}:${PATH}"
export AGENT_SOUND_LOG_FILE="${LOG_FILE}"
export AGENT_SOUNDS_ROOT="${MOCK_SOUNDS}"
export TMPDIR="${TMP_ROOT}/"
export AGENT_SOUND_COOLDOWN_SECS=10

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

echo "=== Test 1: codex-notify logs incoming calls and extracts thread_id ==="
"${SCRIPT_DIR}/scripts/codex-notify.sh" '{"thread-id":"test-diag-thread-1"}'
sleep 0.5
grep -q "\[codex-notify\] invoked: thread_id='test-diag-thread-1'" "${LOG_FILE}" || {
  echo "FAIL: codex-notify invocation was not logged properly"
  cat "${LOG_FILE}"
  exit 1
}
echo "PASS: codex-notify logged invocation and extracted thread-id"

echo "=== Test 2: play-random-completion-sound logs dispatch and player execution ==="
grep -q "\[player\] dispatch: event=stop session=test-diag-thread-1" "${LOG_FILE}" || {
  echo "FAIL: player dispatch was not logged"
  cat "${LOG_FILE}"
  exit 1
}
grep -q "\[player\] executing: afplay -v" "${LOG_FILE}" || {
  echo "FAIL: player execution was not logged"
  cat "${LOG_FILE}"
  exit 1
}
grep -q "\[player\] playback complete (code=0)" "${LOG_FILE}" || {
  echo "FAIL: player completion was not logged"
  cat "${LOG_FILE}"
  exit 1
}
echo "PASS: player dispatch and completion were logged"

echo "=== Test 3: Cooldown suppression is logged with elapsed time ==="
# Immediate second call on same thread should be throttled
"${SCRIPT_DIR}/scripts/codex-notify.sh" '{"thread-id":"test-diag-thread-1"}'
grep -q "\[player\] suppressed: cooldown active" "${LOG_FILE}" || {
  echo "FAIL: cooldown suppression was not logged"
  cat "${LOG_FILE}"
  exit 1
}
echo "PASS: cooldown suppression was logged"

echo "=== Test 4: Mute / disabled suppression is logged ==="
"${SCRIPT_DIR}/scripts/sound-mode.sh" mute
"${SCRIPT_DIR}/scripts/codex-notify.sh" '{"thread-id":"test-diag-thread-2"}'
grep -q "\[player\] suppressed: disabled" "${LOG_FILE}" || {
  echo "FAIL: disabled suppression was not logged"
  cat "${LOG_FILE}"
  exit 1
}
"${SCRIPT_DIR}/scripts/sound-mode.sh" unmute
echo "PASS: disabled suppression was logged"

echo "=== Test 5: soundmode log outputs recent log lines ==="
log_output=$("${SCRIPT_DIR}/scripts/sound-mode.sh" log 5)
[[ "${log_output}" =~ \[player\] ]] || {
  echo "FAIL: soundmode log did not print log content"
  echo "${log_output}"
  exit 1
}
echo "PASS: soundmode log prints diagnostic log output"

echo "=== Test 6: soundmode status displays log file path ==="
status_output=$("${SCRIPT_DIR}/scripts/sound-mode.sh" status)
[[ "${status_output}" =~ "Log: ${LOG_FILE}" ]] || {
  echo "FAIL: soundmode status did not display log path"
  echo "${status_output}"
  exit 1
}
echo "PASS: soundmode status displays log path"

echo "diagnostic-logging: ALL PASS"
