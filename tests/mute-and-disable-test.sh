#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

TEST_SOUNDS="${TEST_ROOT}/sounds"
TEST_CACHE="${TEST_ROOT}/sessions"
PLAYER="${REPO_ROOT}/scripts/play-random-completion-sound.sh"
SOUNDMODE="${REPO_ROOT}/scripts/sound-mode.sh"

MOCK_BIN="${TEST_ROOT}/bin"
PLAY_LOG="${TEST_ROOT}/play.log"
mkdir -p "${MOCK_BIN}" "${TEST_CACHE}" "${TEST_SOUNDS}/unit-a"
: > "${TEST_SOUNDS}/unit-a/clip.wav"
: > "${PLAY_LOG}"

# Mock audio player so no actual audio is emitted during tests
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
  local timeout_ms="${2:-400}"
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
  HOME="${TEST_ROOT}" \
  PATH="${MOCK_BIN}:${PATH}" \
  AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" \
  AGENT_SOUND_COOLDOWN_SECS=0 \
  TMPDIR="${TEST_ROOT}" \
  "${PLAYER}" stop <<< '{"conversationId":"test-conv","executionNum":1}' >/dev/null 2>&1 || true
}

echo "=== Test 1: Active mode plays sound ==="
run_player
plays=$(wait_for_plays 1)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Expected 1 play, got ${plays}" >&2
  exit 1
fi
echo "PASS: Normal turn played sound"

echo "=== Test 2: soundmode mute sets .disabled and suppresses playback ==="
AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" mute >/dev/null
if [[ ! -f "${TEST_SOUNDS}/.disabled" ]]; then
  echo "FAIL: .disabled file was not created by soundmode mute" >&2
  exit 1
fi
run_player
sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 1 ]]; then
  echo "FAIL: Play count increased while muted; expected 1, got ${plays}" >&2
  exit 1
fi
echo "PASS: Playback suppressed by .disabled sentinel file"

echo "=== Test 3: soundmode unmute removes .disabled and restores playback ==="
AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" unmute >/dev/null
if [[ -f "${TEST_SOUNDS}/.disabled" ]]; then
  echo "FAIL: .disabled file still exists after soundmode unmute" >&2
  exit 1
fi
run_player
plays=$(wait_for_plays 2)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Play count did not increase after unmute; expected 2, got ${plays}" >&2
  exit 1
fi
echo "PASS: Playback restored after unmute"

echo "=== Test 4: soundmode toggle-mute flips .disabled state ==="
AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" toggle-mute >/dev/null
if [[ ! -f "${TEST_SOUNDS}/.disabled" ]]; then
  echo "FAIL: Expected .disabled after first toggle-mute" >&2
  exit 1
fi
AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" toggle-mute >/dev/null
if [[ -f "${TEST_SOUNDS}/.disabled" ]]; then
  echo "FAIL: Expected .disabled removed after second toggle-mute" >&2
  exit 1
fi
echo "PASS: toggle-mute cleanly flips mute state"

echo "=== Test 5: Mode set to 'disabled' suppresses playback ==="
printf 'disabled\n' > "${TEST_SOUNDS}/.mode"
run_player
sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Playback occurred when mode was 'disabled'; expected 2, got ${plays}" >&2
  exit 1
fi
printf 'session\n' > "${TEST_SOUNDS}/.mode"
echo "PASS: 'disabled' mode suppresses playback"

echo "=== Test 6: AGENT_COMPLETION_SOUND_DISABLE=1 suppresses playback ==="
HOME="${TEST_ROOT}" \
PATH="${MOCK_BIN}:${PATH}" \
AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" \
AGENT_SOUND_COOLDOWN_SECS=0 \
AGENT_COMPLETION_SOUND_DISABLE=1 \
TMPDIR="${TEST_ROOT}" \
"${PLAYER}" stop <<< '{"conversationId":"test-conv","executionNum":1}' >/dev/null 2>&1 || true

sleep 0.1
plays=$(count_plays)
if [[ "${plays}" -ne 2 ]]; then
  echo "FAIL: Playback occurred when AGENT_COMPLETION_SOUND_DISABLE=1; expected 2, got ${plays}" >&2
  exit 1
fi
echo "PASS: AGENT_COMPLETION_SOUND_DISABLE=1 suppresses playback"

echo "=== Test 7: soundmode status output ==="
status_out=$(AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" "${SOUNDMODE}" status)
if [[ "${status_out}" != *"Sound Mode: session"* ]] || [[ "${status_out}" != *"Sound State: active"* ]] || [[ "${status_out}" != *"Favorites: 1 of 1"* ]]; then
  echo "FAIL: Unexpected status output: ${status_out}" >&2
  exit 1
fi
echo "PASS: soundmode status reports accurate state"

echo "mute-and-disable-test: ALL PASS"
