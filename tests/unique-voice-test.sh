#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

TEST_SOUNDS="${TEST_ROOT}/sounds"
TEST_CACHE="${TEST_ROOT}/sessions"
PLAYER="${REPO_ROOT}/scripts/play-random-completion-sound.sh"

# Mock audio player so no actual sounds play
MOCK_BIN="${TEST_ROOT}/bin"
mkdir -p "${MOCK_BIN}" "${TEST_CACHE}"
cat > "${MOCK_BIN}/afplay" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "${MOCK_BIN}/afplay"

# Create test units
mkdir -p "${TEST_SOUNDS}/unit-a" "${TEST_SOUNDS}/unit-b" "${TEST_SOUNDS}/unit-c" "${TEST_SOUNDS}/unit-d"
: > "${TEST_SOUNDS}/unit-a/clip.wav"
: > "${TEST_SOUNDS}/unit-b/clip.wav"
: > "${TEST_SOUNDS}/unit-c/clip.wav"
: > "${TEST_SOUNDS}/unit-d/clip.wav"

# Favorites has unit-a and unit-b
cat > "${TEST_SOUNDS}/favorites.txt" <<'EOF'
unit-a
unit-b
EOF

printf 'session\n' > "${TEST_SOUNDS}/.mode"

run_player() {
  local sess_id="$1"
  HOME="${TEST_ROOT}" \
  PATH="${MOCK_BIN}:${PATH}" \
  TMPDIR="${TEST_ROOT}" \
  AGENT_SOUNDS_ROOT="${TEST_SOUNDS}" \
  AGENT_SOUND_ACTIVE_WINDOW_SECS="${2:-7200}" \
  "${PLAYER}" <<<"{\"conversationId\": \"${sess_id}\"}"
}

echo "=== Test 1: Unique voices for concurrent sessions ==="
run_player "session-1"
run_player "session-2"

unit_1=$(cat "${TEST_ROOT}/agent-sound-sessions/session-1.unit")
unit_2=$(cat "${TEST_ROOT}/agent-sound-sessions/session-2.unit")

if [[ "${unit_1}" == "${unit_2}" ]]; then
  echo "FAIL: Expected session-1 and session-2 to have distinct units, got ${unit_1} for both" >&2
  exit 1
fi
echo "PASS: session-1 got '${unit_1}' and session-2 got '${unit_2}' (distinct)"

echo "=== Test 2: Fallback to full pool when favorites exhausted ==="
# Both favorites (unit-a and unit-b) are now in use by session-1 and session-2.
# session-3 should pick from remaining units in full pool (unit-c or unit-d)
run_player "session-3"
unit_3=$(cat "${TEST_ROOT}/agent-sound-sessions/session-3.unit")

if [[ "${unit_3}" == "${unit_1}" || "${unit_3}" == "${unit_2}" ]]; then
  echo "FAIL: session-3 collided with active favorite unit: ${unit_3}" >&2
  exit 1
fi
if [[ "${unit_3}" != "unit-c" && "${unit_3}" != "unit-d" ]]; then
  echo "FAIL: session-3 did not pick from remaining full pool: ${unit_3}" >&2
  exit 1
fi
echo "PASS: session-3 picked '${unit_3}' from full pool when favorites were exhausted"

echo "=== Test 3: Session stickiness preserved on repeated turns ==="
run_player "session-1"
unit_1_turn2=$(cat "${TEST_ROOT}/agent-sound-sessions/session-1.unit")
if [[ "${unit_1_turn2}" != "${unit_1}" ]]; then
  echo "FAIL: session-1 changed unit on turn 2: ${unit_1} -> ${unit_1_turn2}" >&2
  exit 1
fi
echo "PASS: session-1 unit remained sticky on turn 2"

echo "=== Test 4: Stale sessions allow unit re-use ==="
# Set a tiny active window of 1 second and sleep 2 seconds
sleep 2
# With active window of 1 second, session-1 and session-2 are now considered inactive
run_player "session-stale-test" 1
unit_stale=$(cat "${TEST_ROOT}/agent-sound-sessions/session-stale-test.unit")
if [[ "${unit_stale}" != "unit-a" && "${unit_stale}" != "unit-b" ]]; then
  echo "FAIL: Expected stale-test session to pick a favorite unit again, got ${unit_stale}" >&2
  exit 1
fi
echo "PASS: Stale session units were reclaimed by new session ('${unit_stale}')"

echo "=== Test 5: Fallback when all units in pool are active ==="
# Clear sessions so Test 5 starts clean
rm -rf "${TEST_ROOT}/agent-sound-sessions"
# Active window 7200s, fill s-1, s-2, s-3, s-4
run_player "s-1"
run_player "s-2"
run_player "s-3"
run_player "s-4"

# Touch s-2, s-3, s-4 so s-1 is the oldest
sleep 1
run_player "s-2"
run_player "s-3"
run_player "s-4"

oldest_unit=$(cat "${TEST_ROOT}/agent-sound-sessions/s-1.unit")

# s-5 must now choose even though all 4 units are active; it should pick oldest_unit
run_player "s-5"
unit_5=$(cat "${TEST_ROOT}/agent-sound-sessions/s-5.unit")
if [[ "${unit_5}" != "${oldest_unit}" ]]; then
  echo "FAIL: Expected s-5 to pick least recently active unit '${oldest_unit}', got '${unit_5}'" >&2
  exit 1
fi
echo "PASS: Over-capacity session picked least recently active unit '${unit_5}'"

echo "unique-voice-test: ALL PASS"
