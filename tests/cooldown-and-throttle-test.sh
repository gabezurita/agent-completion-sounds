#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

TEST_SOUNDS="${TEST_ROOT}/sounds"
TEST_CACHE="${TEST_ROOT}/sessions"
PLAYER="${REPO_ROOT}/scripts/play-random-completion-sound.sh"

MOCK_BIN="${TEST_ROOT}/bin"
PLAY_LOG="${TEST_ROOT}/play.log"
mkdir -p "${MOCK_BIN}" "${TEST_CACHE}" "${TEST_SOUNDS}/unit-a"
: > "${TEST_SOUNDS}/unit-a/clip.wav"
: > "${PLAY_LOG}"

# Mock audio player so no actual sounds play, but record every playback call
cat > "${MOCK_BIN}/afplay" <<SH
#!/usr/bin/env bash
/bin/echo "played \$*" >> "${PLAY_LOG}"
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

run_player() {
  local sess_id="${1:-test-session}"
  local event_arg="${2:-}"
  local payload="${3:-}"
  local cooldown="${4:-2}"

  if [[ -z "${payload}" ]]; then
    payload="{\"conversationId\": \"${sess_id}\"}"
  fi

  local cmd=("${PLAYER}")
  [[ -n "${event_arg}" ]] && cmd+=("${event_arg}")
  HOME="${TEST_ROOT}" \
  PATH="${MOCK_BIN}:${PATH}" \
  TMPDIR="${TEST_ROOT}" \
  AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" \
  AGENT_SOUND_COOLDOWN_SECS="${cooldown}" \
  "${cmd[@]}" <<<"${payload}"
}

echo "=== Test 1: Intermediate invocations (invocationNum > 1) are suppressed ==="
: > "${PLAY_LOG}"

# First invocation (turn start): should play
run_player "sess-1" "start" '{"conversationId": "sess-1", "invocationNum": 1}'
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected 1 sound on invocationNum: 1, got ${plays}" >&2
  exit 1
fi
echo "PASS: Sound played on invocationNum: 1"

# Second invocation (intermediate tool step): MUST BE SILENT
run_player "sess-1" "start" '{"conversationId": "sess-1", "invocationNum": 2}'
sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Intermediate invocation (invocationNum: 2) played sound! Total plays: ${plays}" >&2
  exit 1
fi
echo "PASS: Intermediate invocation (invocationNum: 2) was suppressed"

# Third invocation without explicit 'start' arg (payload-only detection): MUST BE SILENT
run_player "sess-1" "" '{"conversationId": "sess-1", "invocationNum": 3}'
sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Intermediate invocation without event arg played sound! Total plays: ${plays}" >&2
  exit 1
fi
echo "PASS: Intermediate invocation without event arg was suppressed"


echo "=== Test 2: Short turns within cooldown suppress end sound ==="
: > "${PLAY_LOG}"
# Cooldown set to 2 seconds
run_player "sess-short" "start" '{"conversationId": "sess-short", "invocationNum": 1}' 2
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected 1 play on start, got ${plays}" >&2
  exit 1
fi

# Stop called immediately (< 2s cooldown)
run_player "sess-short" "stop" '{"conversationId": "sess-short"}' 2
sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Stop hook within cooldown played sound! Expected 1, got ${plays}" >&2
  exit 1
fi
echo "PASS: Stop hook within cooldown window was suppressed"


echo "=== Test 3: Long turns (elapsed >= cooldown) play end sound ==="
: > "${PLAY_LOG}"
# Cooldown set to 1 second
run_player "sess-long" "start" '{"conversationId": "sess-long", "invocationNum": 1}' 1
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected 1 play on start, got ${plays}" >&2
  exit 1
fi

# Sleep past the 1-second cooldown
sleep 1.2

run_player "sess-long" "stop" '{"conversationId": "sess-long"}' 1
plays=$(wait_for_plays 2)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Expected end sound after cooldown expired, got ${plays} plays" >&2
  exit 1
fi
echo "PASS: End sound played after cooldown expired"


echo "=== Test 4: Legacy stop-only hooks still play sound ==="
: > "${PLAY_LOG}"
# Stop hook called with no preceding start sound
run_player "sess-legacy" "stop" '{"conversationId": "sess-legacy"}' 2
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected legacy stop hook to play sound, got ${plays}" >&2
  exit 1
fi

# Rapid second stop hook within cooldown should be throttled
run_player "sess-legacy" "stop" '{"conversationId": "sess-legacy"}' 2
sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Rapid second stop hook was not throttled! Got ${plays}" >&2
  exit 1
fi
echo "PASS: Legacy stop hook works and throttles rapid duplicates"


echo "=== Test 5: Cooldown of 0 allows rapid successive playbacks (manual test sounds) ==="
: > "${PLAY_LOG}"
run_player "sess-manual-test" "stop" '{"conversationId": "sess-manual-test"}' 0
run_player "sess-manual-test" "stop" '{"conversationId": "sess-manual-test"}' 0
plays=$(wait_for_plays 2)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Expected 2 plays with cooldown=0, got ${plays}" >&2
  exit 1
fi
echo "PASS: Cooldown=0 allows immediate successive playbacks"

echo "=== Test 6: Default cooldown is 2 seconds without AGENT_SOUND_COOLDOWN_SECS ==="
: > "${PLAY_LOG}"
rm -f "${TEST_SOUNDS}/.cooldown"
run_player_default() {
  local sess_id="${1:-test-default}"
  HOME="${TEST_ROOT}" \
  PATH="${MOCK_BIN}:${PATH}" \
  TMPDIR="${TEST_ROOT}" \
  AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" \
  "${PLAYER}" stop <<<"{\"conversationId\": \"${sess_id}\"}"
}

run_player_default "sess-def"
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected initial play, got ${plays}" >&2
  exit 1
fi

# Immediate stop should be throttled by default 2s cooldown
run_player_default "sess-def"
sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Rapid stop was not throttled by default 2s cooldown, got ${plays}" >&2
  exit 1
fi

# After 2.1 seconds, stop should play
sleep 2.1
run_player_default "sess-def"
plays=$(wait_for_plays 2)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Expected play after 2s default cooldown expired, got ${plays}" >&2
  exit 1
fi
echo "PASS: Default 2s cooldown throttles rapid calls and permits play after 2 seconds"

echo "=== Test 7: soundmode cooldown command and file configuration ==="
SOUNDMODE="${REPO_ROOT}/scripts/sound-mode.sh"
out=$(AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" cooldown)
if [[ "${out}" != *"Sound cooldown: 2s"* ]]; then
  echo "FAIL: Expected default cooldown 2s, got: ${out}" >&2
  exit 1
fi

set_out=$(AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" cooldown 5)
if [[ "${set_out}" != *"Sound cooldown: set to 5s"* ]]; then
  echo "FAIL: Expected cooldown set to 5s, got: ${set_out}" >&2
  exit 1
fi
read_val=$(cat "${TEST_SOUNDS}/.cooldown")
if [[ "${read_val}" != "5" ]]; then
  echo "FAIL: .cooldown file expected 5, got: ${read_val}" >&2
  exit 1
fi

status_out=$(AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" status)
if [[ "${status_out}" != *"Cooldown: 5s"* ]]; then
  echo "FAIL: Expected status to include 'Cooldown: 5s', got: ${status_out}" >&2
  exit 1
fi

# Set back to 0 and verify instant playback via .cooldown file
AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" cooldown 0
: > "${PLAY_LOG}"
run_player_default "sess-zero"
run_player_default "sess-zero"
plays=$(wait_for_plays 2)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Expected 2 plays with .cooldown=0, got ${plays}" >&2
  exit 1
fi
echo "PASS: soundmode cooldown command and persistent configuration verified"

echo "cooldown-and-throttle-test: ALL PASS"

