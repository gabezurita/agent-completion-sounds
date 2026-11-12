#!/usr/bin/env bash
# Regression tests for Codex notify adapter session and thread-id handling.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

TEST_SOUNDS="${TEST_ROOT}/sounds"
TEST_SESSIONS="${TEST_ROOT}/agent-sound-sessions"
MOCK_BIN="${TEST_ROOT}/bin"
PLAY_LOG="${TEST_ROOT}/play.log"
PLAYER_INPUT_LOG="${TEST_ROOT}/player-stdin.log"

mkdir -p "${MOCK_BIN}" "${TEST_SESSIONS}" "${TEST_SOUNDS}/unit-a"
: > "${TEST_SOUNDS}/unit-a/clip.wav"
: > "${PLAY_LOG}"
: > "${PLAYER_INPUT_LOG}"

# Mock audio player so no actual sounds play, but record every playback call
cat > "${MOCK_BIN}/afplay" <<'SH'
#!/usr/bin/env bash
/bin/echo "played $*" >> "${TMP_PLAY_LOG}"
exit 0
SH
chmod +x "${MOCK_BIN}/afplay"

cat > "${TEST_SOUNDS}/favorites.txt" <<'EOF'
unit-a
EOF
printf 'session\n' > "${TEST_SOUNDS}/.mode"

count_plays() {
  if [[ -f "${PLAY_LOG}" ]]; then
    wc -l < "${PLAY_LOG}" | tr -d ' '
  else
    echo 0
  fi
}

wait_for_plays() {
  local target="$1"
  local timeout_ms="${2:-300}"
  local elapsed=0
  while ((elapsed < timeout_ms)); do
    local current
    current=$(count_plays)
    if [[ "${current}" -ge "${target}" ]]; then
      echo "${current}"
      return 0
    fi
    sleep 0.02
    elapsed=$((elapsed + 20))
  done
  count_plays
}

run_codex_notify() {
  local arg="${1:-}"
  local cooldown="${2:-15}"
  HOME="${TEST_ROOT}" \
  PATH="${MOCK_BIN}:${PATH}" \
  TMPDIR="${TEST_ROOT}" \
  TMP_PLAY_LOG="${PLAY_LOG}" \
  AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" \
  AGENT_SOUND_COOLDOWN_SECS="${cooldown}" \
    "${REPO_ROOT}/scripts/codex-notify.sh" ${arg:+"$arg"}
}

echo "=== Test 1: Adapter passes notification thread ID to the player ==="
# Test with a wrapper player script to inspect stdin payload passed by the adapter
TEST_MOCK_DIR=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}" "${TEST_MOCK_DIR}"' EXIT

MOCK_PLAYER_SCRIPT="${TEST_MOCK_DIR}/play-random-completion-sound.sh"
cat > "${MOCK_PLAYER_SCRIPT}" <<'SH'
#!/usr/bin/env bash
cat >> "${CAPTURED_STDIN_FILE}"
printf '%s\n' '{}'
SH
chmod +x "${MOCK_PLAYER_SCRIPT}"

# 1a. Argument with "thread-id"
CAPTURED_STDIN="${TEST_ROOT}/stdin-1a.log"
CAPTURED_STDIN_FILE="${CAPTURED_STDIN}" \
  AGENT_SOUND_PLAYER="${MOCK_PLAYER_SCRIPT}" \
  "${REPO_ROOT}/scripts/codex-notify.sh" '{"type":"agent-turn-complete","thread-id":"thread-alpha-123"}'

if ! grep -q '"session_id":"thread-alpha-123"' "${CAPTURED_STDIN}"; then
  echo "FAIL: Expected 'session_id':'thread-alpha-123' in player stdin, got: $(cat "${CAPTURED_STDIN}")" >&2
  exit 1
fi
echo "PASS: Adapter passed thread-id as session_id"

# 1b. Argument with "thread_id" underscore format
CAPTURED_STDIN="${TEST_ROOT}/stdin-1b.log"
CAPTURED_STDIN_FILE="${CAPTURED_STDIN}" \
  AGENT_SOUND_PLAYER="${MOCK_PLAYER_SCRIPT}" \
  "${REPO_ROOT}/scripts/codex-notify.sh" '{"type":"agent-turn-complete","thread_id":"thread_underscore_456"}'

if ! grep -q '"session_id":"thread_underscore_456"' "${CAPTURED_STDIN}"; then
  echo "FAIL: Expected 'session_id':'thread_underscore_456' in player stdin, got: $(cat "${CAPTURED_STDIN}")" >&2
  exit 1
fi
echo "PASS: Adapter handled thread_id format"

# 1c. Payload passed over stdin
CAPTURED_STDIN="${TEST_ROOT}/stdin-1c.log"
CAPTURED_STDIN_FILE="${CAPTURED_STDIN}" \
  AGENT_SOUND_PLAYER="${MOCK_PLAYER_SCRIPT}" \
  "${REPO_ROOT}/scripts/codex-notify.sh" <<< '{"thread-id":"thread-stdin-789"}'

if ! grep -q '"session_id":"thread-stdin-789"' "${CAPTURED_STDIN}"; then
  echo "FAIL: Expected 'session_id':'thread-stdin-789' in player stdin, got: $(cat "${CAPTURED_STDIN}")" >&2
  exit 1
fi
echo "PASS: Adapter accepted payload via stdin"


echo "=== Test 2: Two different thread IDs receive independent session/cooldown state ==="
: > "${PLAY_LOG}"
# Cooldown set to 5 seconds
run_codex_notify '{"type":"agent-turn-complete","thread-id":"thread-A"}' 5
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected 1 play for thread-A, got ${plays}" >&2
  exit 1
fi

if [[ ! -f "${TEST_SESSIONS}/thread-A.time" ]]; then
  echo "FAIL: Expected session state file ${TEST_SESSIONS}/thread-A.time to exist" >&2
  exit 1
fi
echo "PASS: Thread-A played and created dedicated session state"

# Immediately notify for thread-B (< 5s cooldown). Because thread-B is an independent
# session, it must NOT be blocked by thread-A's cooldown window.
run_codex_notify '{"type":"agent-turn-complete","thread-id":"thread-B"}' 5
plays=$(wait_for_plays 2)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Expected 2 total plays (thread-B should not be blocked by thread-A), got ${plays}" >&2
  exit 1
fi

if [[ ! -f "${TEST_SESSIONS}/thread-B.time" ]]; then
  echo "FAIL: Expected session state file ${TEST_SESSIONS}/thread-B.time to exist" >&2
  exit 1
fi
echo "PASS: Thread-B played independently and created its own session state"

# Rapid successive notification for thread-A within cooldown MUST be throttled
run_codex_notify '{"type":"agent-turn-complete","thread-id":"thread-A"}' 5
sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Thread-A was not throttled by its own cooldown! Total plays: ${plays}" >&2
  exit 1
fi
echo "PASS: Thread-A was throttled by its own session cooldown"


echo "=== Test 3: Missing thread IDs remain safe and fall back to global state ==="
: > "${PLAY_LOG}"

# 3a. Payload without thread-id
run_codex_notify '{"type":"agent-turn-complete"}' 2
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected play on missing thread-id, got ${plays}" >&2
  exit 1
fi

if [[ ! -f "${TEST_SESSIONS}/global.time" ]]; then
  echo "FAIL: Expected global.time state file on missing thread-id" >&2
  exit 1
fi
echo "PASS: Missing thread-id fell back to global.time state"

# 3b. Empty payload / no argument
: > "${PLAY_LOG}"
run_codex_notify "" 0
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected play on empty argument, got ${plays}" >&2
  exit 1
fi
echo "PASS: Empty argument handled safely"


echo "=== Test 4: Muted and disabled playback remain safe ==="
: > "${PLAY_LOG}"

# 4a. AGENT_COMPLETION_SOUND_DISABLE=1
output=$(
  HOME="${TEST_ROOT}" \
  TMPDIR="${TEST_ROOT}" \
  AGENT_COMPLETION_SOUND_DISABLE=1 \
    "${REPO_ROOT}/scripts/codex-notify.sh" '{"type":"agent-turn-complete","thread-id":"thread-muted"}'
)
if [[ "${output}" != "{}" ]]; then
  echo "FAIL: Expected '{}' on AGENT_COMPLETION_SOUND_DISABLE=1, got '${output}'" >&2
  exit 1
fi
sleep 0.05
plays=$(count_plays)
if [[ "${plays}" -ne 0 ]]; then
  echo "FAIL: Sound played while AGENT_COMPLETION_SOUND_DISABLE=1" >&2
  exit 1
fi
echo "PASS: AGENT_COMPLETION_SOUND_DISABLE=1 suppresses playback and returns {}"

# 4b. .disabled file sentinel
touch "${TEST_SOUNDS}/.disabled"
output=$(
  HOME="${TEST_ROOT}" \
  TMPDIR="${TEST_ROOT}" \
  PATH="${MOCK_BIN}:${PATH}" \
  AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" \
    "${REPO_ROOT}/scripts/codex-notify.sh" '{"type":"agent-turn-complete","thread-id":"thread-disabled"}'
)
if [[ "${output}" != "{}" ]]; then
  echo "FAIL: Expected '{}' on .disabled, got '${output}'" >&2
  exit 1
fi
sleep 0.05
plays=$(count_plays)
if [[ "${plays}" -ne 0 ]]; then
  echo "FAIL: Sound played while .disabled exists" >&2
  exit 1
fi
rm -f "${TEST_SOUNDS}/.disabled"
echo "PASS: .disabled sentinel suppresses playback and returns {}"

# 4c. Mode set to 'mute'
printf 'mute\n' > "${TEST_SOUNDS}/.mode"
output=$(
  HOME="${TEST_ROOT}" \
  TMPDIR="${TEST_ROOT}" \
  PATH="${MOCK_BIN}:${PATH}" \
  AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" \
    "${REPO_ROOT}/scripts/codex-notify.sh" '{"type":"agent-turn-complete","thread-id":"thread-mode-mute"}'
)
if [[ "${output}" != "{}" ]]; then
  echo "FAIL: Expected '{}' on mode mute, got '${output}'" >&2
  exit 1
fi
sleep 0.05
plays=$(count_plays)
if [[ "${plays}" -ne 0 ]]; then
  echo "FAIL: Sound played while mode is mute" >&2
  exit 1
fi
echo "PASS: Mode 'mute' suppresses playback and returns {}"

printf '%s\n' 'codex notify adapter: ALL PASS'
