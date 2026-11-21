#!/usr/bin/env bash
# Tests for persistent Unix socket playback fast-path, fallback behavior, and log capping.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PLAYER="${SCRIPT_DIR}/scripts/play-random-completion-sound.sh"

# Use a short /tmp path so Unix socket sun_path stays well under macOS's 104-byte limit.
TEST_ROOT=$(mktemp -d "/tmp/acs-sock.XXXXXX")
SOCK_PATH="${TEST_ROOT}/player.sock"
SOCK_LOG="${TEST_ROOT}/socket-requests.jsonl"
MOCK_BIN="${TEST_ROOT}/bin"
MOCK_SOUNDS="${TEST_ROOT}/sounds"
AFPLAY_LOG="${TEST_ROOT}/afplay.log"
FFPLAY_LOG="${TEST_ROOT}/ffplay.log"
LOG_FILE="${TEST_ROOT}/agent-sound.log"
SERVER_PID=""

mkdir -p "${MOCK_BIN}" "${MOCK_SOUNDS}/wav-unit" "${MOCK_SOUNDS}/ogg-unit"
touch "${MOCK_SOUNDS}/wav-unit/clip1.wav"
touch "${MOCK_SOUNDS}/ogg-unit/clip1.ogg"
printf 'wav-unit\n' > "${MOCK_SOUNDS}/favorites.txt"
printf 'session\n' > "${MOCK_SOUNDS}/.mode"

cat > "${MOCK_BIN}/afplay" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${AFPLAY_LOG}"
exit 0
SH
chmod +x "${MOCK_BIN}/afplay"

cat > "${MOCK_BIN}/ffplay" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${FFPLAY_LOG}"
exit 0
SH
chmod +x "${MOCK_BIN}/ffplay"

stop_server() {
  if [[ -n "${SERVER_PID}" ]]; then
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
    SERVER_PID=""
  fi
}

cleanup() {
  stop_server
  rm -rf "${TEST_ROOT}"
}
trap cleanup EXIT

start_mock_server() {
  local response="$1"
  stop_server
  rm -f "${SOCK_PATH}"
  python3 - "${SOCK_PATH}" "${SOCK_LOG}" "${response}" <<'PY' &
import os, socket, sys

sock_path, log_path, response = sys.argv[1], sys.argv[2], sys.argv[3]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sock_path)
s.listen(8)
while True:
    conn, _ = s.accept()
    with conn:
        data = conn.recv(4096).decode("utf-8", errors="replace").strip()
        with open(log_path, "a") as f:
            f.write(data + "\n")
        conn.sendall((response + "\n").encode("utf-8"))
PY
  SERVER_PID=$!
  local i=0
  while [[ ! -S "${SOCK_PATH}" && "${i}" -lt 50 ]]; do
    sleep 0.05
    i=$((i + 1))
  done
  [[ -S "${SOCK_PATH}" ]] || { echo "FAIL: mock socket did not appear at ${SOCK_PATH}"; exit 1; }
}

run_player() {
  local extra_env=("$@")
  env \
    PATH="${MOCK_BIN}:${PATH}" \
    TMPDIR="${TEST_ROOT}" \
    AGENT_SOUNDS_ROOT="${MOCK_SOUNDS}" \
    AGENT_SOUND_COOLDOWN_SECS=0 \
    AGENT_SOUND_LOG_FILE="${LOG_FILE}" \
    "${extra_env[@]}" \
    "${PLAYER}" stop >/dev/null <<<'{"conversationId":"sock-test"}'
}

echo "=== Test 1: Persistent socket fast-path avoids spawning afplay ==="
start_mock_server "OK"
: > "${AFPLAY_LOG}"
: > "${SOCK_LOG}"
run_player "AGENT_SOUND_SOCKET=${SOCK_PATH}" "AGENT_COMPLETION_SOUND_VOLUME=0.35"
sleep 0.2
[[ -s "${SOCK_LOG}" ]] || { echo "FAIL: expected request on persistent socket"; exit 1; }
grep -q '"clip": ".*clip1\.wav"' "${SOCK_LOG}" || { echo "FAIL: socket request missing clip"; cat "${SOCK_LOG}"; exit 1; }
grep -q '"volume": 0.35' "${SOCK_LOG}" || { echo "FAIL: socket request missing volume"; cat "${SOCK_LOG}"; exit 1; }
if [[ -s "${AFPLAY_LOG}" ]]; then
  echo "FAIL: afplay should not be called when persistent socket succeeds"
  cat "${AFPLAY_LOG}"
  exit 1
fi
grep -q "playback via persistent socket (${SOCK_PATH}): ok" "${LOG_FILE}" || {
  echo "FAIL: expected persistent socket log line"
  cat "${LOG_FILE}"
  exit 1
}
echo "PASS: persistent socket played clip without spawning afplay"

echo "=== Test 2: Socket ERR response falls back cleanly to afplay ==="
start_mock_server "ERR decode failed"
: > "${AFPLAY_LOG}"
run_player "AGENT_SOUND_SOCKET=${SOCK_PATH}"
sleep 0.3
grep -q "clip1.wav" "${AFPLAY_LOG}" || {
  echo "FAIL: expected afplay fallback after socket ERR"
  cat "${LOG_FILE}"
  exit 1
}
echo "PASS: socket ERR fell back to afplay"

echo "=== Test 3: Stale/missing socket falls back cleanly to afplay ==="
stop_server
: > "${AFPLAY_LOG}"
run_player "AGENT_SOUND_SOCKET=${SOCK_PATH}"
sleep 0.3
grep -q "clip1.wav" "${AFPLAY_LOG}" || {
  echo "FAIL: expected afplay fallback when socket is stale"
  exit 1
}
rm -f "${SOCK_PATH}"
: > "${AFPLAY_LOG}"
run_player "AGENT_SOUND_SOCKET=${SOCK_PATH}"
sleep 0.3
grep -q "clip1.wav" "${AFPLAY_LOG}" || {
  echo "FAIL: expected afplay fallback when socket is missing"
  exit 1
}
echo "PASS: stale and missing socket fell back to afplay"

echo "=== Test 4: .ogg clips bypass macOS socket and use ffplay ==="
start_mock_server "OK"
: > "${SOCK_LOG}"
: > "${FFPLAY_LOG}"
run_player "AGENT_SOUND_SOCKET=${SOCK_PATH}" "AGENT_SOUND_UNIT=ogg-unit"
sleep 0.3
if [[ -s "${SOCK_LOG}" ]]; then
  echo "FAIL: .ogg clip should bypass persistent socket"
  cat "${SOCK_LOG}"
  exit 1
fi
grep -q "clip1.ogg" "${FFPLAY_LOG}" || {
  echo "FAIL: expected ffplay for .ogg clip"
  cat "${LOG_FILE}"
  exit 1
}
echo "PASS: .ogg clip bypassed socket and used ffplay"

echo "=== Test 5: AGENT_SOUND_SOCKET=off disables socket routing ==="
: > "${SOCK_LOG}"
: > "${AFPLAY_LOG}"
run_player "AGENT_SOUND_SOCKET=off"
sleep 0.3
if [[ -s "${SOCK_LOG}" ]]; then
  echo "FAIL: AGENT_SOUND_SOCKET=off should not hit socket"
  exit 1
fi
grep -q "clip1.wav" "${AFPLAY_LOG}" || {
  echo "FAIL: expected afplay when socket disabled"
  exit 1
}
echo "PASS: AGENT_SOUND_SOCKET=off bypassed socket"

echo "=== Test 6: Intermediate invocations are quiet by default and log size is capped ==="
: > "${LOG_FILE}"
env \
  PATH="${MOCK_BIN}:${PATH}" \
  TMPDIR="${TEST_ROOT}" \
  AGENT_SOUNDS_ROOT="${MOCK_SOUNDS}" \
  AGENT_SOUND_LOG_FILE="${LOG_FILE}" \
  "${PLAYER}" >/dev/null <<<'{"conversationId":"quiet-test","invocationNum":2}'
if [[ -s "${LOG_FILE}" ]]; then
  echo "FAIL: intermediate invocation should not write to log without AGENT_SOUND_DEBUG=1"
  cat "${LOG_FILE}"
  exit 1
fi

env \
  PATH="${MOCK_BIN}:${PATH}" \
  TMPDIR="${TEST_ROOT}" \
  AGENT_SOUNDS_ROOT="${MOCK_SOUNDS}" \
  AGENT_SOUND_DEBUG=1 \
  AGENT_SOUND_LOG_FILE="${LOG_FILE}" \
  "${PLAYER}" >/dev/null <<<'{"conversationId":"quiet-test","invocationNum":2}'
grep -q "suppressed: intermediate tool invocation (2)" "${LOG_FILE}" || {
  echo "FAIL: AGENT_SOUND_DEBUG=1 should log intermediate invocation"
  cat "${LOG_FILE}"
  exit 1
}

# Seed an oversized log file and verify trim_log_if_needed caps it.
python3 - "${LOG_FILE}" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(200):
        f.write(f"[2026-11-21 00:00:00] [1:1] [player] filler line {i:04d} padding\n")
PY
run_player "AGENT_SOUND_SOCKET=${SOCK_PATH}" "AGENT_SOUND_LOG_MAX_BYTES=1024" "AGENT_SOUND_LOG_KEEP_LINES=10"
line_count=$(wc -l < "${LOG_FILE}" | tr -d ' ')
if ((line_count > 25)); then
  echo "FAIL: expected log to be trimmed near 10 lines, got ${line_count}"
  exit 1
fi
echo "PASS: intermediate noise gated and log size capped (${line_count} lines after trim)"

if [[ "$(uname -s)" == "Darwin" ]] && command -v swiftc >/dev/null 2>&1; then
  echo "=== Test 7: Swift SoundPlaybackServer socket & AVAudioPlayer integration (macOS) ==="
  SWIFT_TEST_BIN="${TEST_ROOT}/sound-playback-server-test"
  swiftc -O "${SCRIPT_DIR}/ui/SoundPlaybackServer.swift" "${SCRIPT_DIR}/tests/sound-playback-server-test.swift" -o "${SWIFT_TEST_BIN}"
  "${SWIFT_TEST_BIN}"
  echo "PASS: Swift SoundPlaybackServer integration passed"
fi

echo "persistent-player-socket: ALL PASS"
