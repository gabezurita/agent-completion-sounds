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
mkdir -p "${MOCK_BIN}" "${TEST_CACHE}" "${TEST_SOUNDS}"
: > "${PLAY_LOG}"

# Mock audio player so no actual sounds play, but record the played clip path
cat > "${MOCK_BIN}/afplay" <<SH
#!/usr/bin/env bash
for last; do true; done
echo "\${last}" >> "${PLAY_LOG}"
exit 0
SH
chmod +x "${MOCK_BIN}/afplay"

# Setup test units
mkdir -p "${TEST_SOUNDS}/unit-pair" "${TEST_SOUNDS}/unit-multi" "${TEST_SOUNDS}/unit-single"
: > "${TEST_SOUNDS}/unit-pair/clip-a.wav"
: > "${TEST_SOUNDS}/unit-pair/clip-b.wav"

: > "${TEST_SOUNDS}/unit-multi/clip-1.wav"
: > "${TEST_SOUNDS}/unit-multi/clip-2.wav"
: > "${TEST_SOUNDS}/unit-multi/clip-3.wav"
: > "${TEST_SOUNDS}/unit-multi/clip-4.wav"

: > "${TEST_SOUNDS}/unit-single/solo.wav"

cat > "${TEST_SOUNDS}/favorites.txt" <<'EOF'
unit-pair
unit-multi
unit-single
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
  local timeout_ms="${2:-1000}"
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
  local sess_id="${1:-}"
  local unit_override="${2:-}"
  local payload="{}"
  if [[ -n "${sess_id}" ]]; then
    payload="{\"conversationId\": \"${sess_id}\"}"
  fi

  local env_vars=(
    HOME="${TEST_ROOT}"
    PATH="${MOCK_BIN}:${PATH}"
    TMPDIR="${TEST_ROOT}"
    AGENT_SOUNDS_ROOT="${TEST_SOUNDS}"
    AGENT_SOUND_COOLDOWN_SECS=0
  )
  if [[ -n "${unit_override}" ]]; then
    env_vars+=(AGENT_SOUND_UNIT="${unit_override}")
  fi

  env "${env_vars[@]}" "${PLAYER}" "stop" <<<"${payload}" >/dev/null
}

echo "=== Test 1: Pair unit strictly alternates between the 2 clips ==="
: > "${PLAY_LOG}"
expected_plays=10
for ((i = 1; i <= expected_plays; i++)); do
  run_player "sess-pair" "unit-pair"
  wait_for_plays "$i" >/dev/null
done

plays=$(count_plays)
if [[ "${plays}" -lt "${expected_plays}" ]]; then
  echo "FAIL: Expected at least ${expected_plays} plays, got ${plays}" >&2
  exit 1
fi

played_lines=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -n "${line}" ]] && played_lines+=("${line}")
done < "${PLAY_LOG}"
for ((i = 1; i < ${#played_lines[@]}; i++)); do
  prev="${played_lines[i-1]}"
  curr="${played_lines[i]}"
  if [[ "${prev}" == "${curr}" ]]; then
    echo "FAIL: Turn $((i+1)) repeated the exact same sound: ${curr}" >&2
    exit 1
  fi
done
echo "PASS: 10 consecutive turns strictly alternated without repeating"

echo "=== Test 2: Multi-clip unit (4 clips) never repeats consecutively ==="
: > "${PLAY_LOG}"
expected_plays=30
for ((i = 1; i <= expected_plays; i++)); do
  run_player "sess-multi" "unit-multi"
  wait_for_plays "$i" >/dev/null
done

plays=$(count_plays)
if [[ "${plays}" -lt "${expected_plays}" ]]; then
  echo "FAIL: Expected at least ${expected_plays} plays, got ${plays}" >&2
  exit 1
fi

played_lines=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -n "${line}" ]] && played_lines+=("${line}")
done < "${PLAY_LOG}"
for ((i = 1; i < ${#played_lines[@]}; i++)); do
  prev="${played_lines[i-1]}"
  curr="${played_lines[i]}"
  if [[ "${prev}" == "${curr}" ]]; then
    echo "FAIL: Turn $((i+1)) repeated the exact same sound: ${curr}" >&2
    exit 1
  fi
done
echo "PASS: 30 consecutive turns never repeated a sound back-to-back"

echo "=== Test 3: Single-clip pool continues playing reliably ==="
: > "${PLAY_LOG}"
for ((i = 1; i <= 3; i++)); do
  run_player "sess-single" "unit-single"
  wait_for_plays "$i" >/dev/null
done

plays=$(count_plays)
if [[ "${plays}" -lt 3 ]]; then
  echo "FAIL: Single-clip unit failed to play repeatedly. Total plays: ${plays}" >&2
  exit 1
fi

played_lines=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -n "${line}" ]] && played_lines+=("${line}")
done < "${PLAY_LOG}"
for line in "${played_lines[@]}"; do
  if [[ "${line}" != *"solo.wav" ]]; then
    echo "FAIL: Expected solo.wav, got ${line}" >&2
    exit 1
  fi
done
echo "PASS: Single-clip unit plays reliably on all turns"

echo "=== Test 4: Global/standalone playback avoids back-to-back repeats ==="
: > "${PLAY_LOG}"
expected_plays=15
for ((i = 1; i <= expected_plays; i++)); do
  run_player "" "unit-multi"
  wait_for_plays "$i" >/dev/null
done

plays=$(count_plays)
if [[ "${plays}" -lt "${expected_plays}" ]]; then
  echo "FAIL: Expected at least ${expected_plays} global plays, got ${plays}" >&2
  exit 1
fi

played_lines=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -n "${line}" ]] && played_lines+=("${line}")
done < "${PLAY_LOG}"
for ((i = 1; i < ${#played_lines[@]}; i++)); do
  prev="${played_lines[i-1]}"
  curr="${played_lines[i]}"
  if [[ "${prev}" == "${curr}" ]]; then
    echo "FAIL: Global turn $((i+1)) repeated the exact same sound: ${curr}" >&2
    exit 1
  fi
done
echo "PASS: Global invocations never repeated a sound back-to-back"

echo "=== Test 5: Concurrent sessions preserve independent non-repetition ==="
: > "${PLAY_LOG}"
expected_count=0
for ((round = 1; round <= 5; round++)); do
  run_player "sess-A" "unit-multi"
  expected_count=$((expected_count + 1))
  wait_for_plays "${expected_count}" >/dev/null

  run_player "sess-B" "unit-pair"
  expected_count=$((expected_count + 1))
  wait_for_plays "${expected_count}" >/dev/null
done

plays=$(count_plays)
if [[ "${plays}" -lt 10 ]]; then
  echo "FAIL: Interleaved sessions did not produce 10 plays, got ${plays}" >&2
  exit 1
fi

played_lines=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -n "${line}" ]] && played_lines+=("${line}")
done < "${PLAY_LOG}"
# Even indices (0, 2, 4, 6, 8) belong to sess-A
sess_A_plays=()
sess_B_plays=()
for ((i = 0; i < ${#played_lines[@]}; i++)); do
  if ((i % 2 == 0)); then
    sess_A_plays+=("${played_lines[i]}")
  else
    sess_B_plays+=("${played_lines[i]}")
  fi
done

for ((i = 1; i < ${#sess_A_plays[@]}; i++)); do
  if [[ "${sess_A_plays[i]}" == "${sess_A_plays[i-1]}" ]]; then
    echo "FAIL: Session A repeated sound back-to-back within its session: ${sess_A_plays[i]}" >&2
    exit 1
  fi
done

for ((i = 1; i < ${#sess_B_plays[@]}; i++)); do
  if [[ "${sess_B_plays[i]}" == "${sess_B_plays[i-1]}" ]]; then
    echo "FAIL: Session B repeated sound back-to-back within its session: ${sess_B_plays[i]}" >&2
    exit 1
  fi
done
echo "PASS: Interleaved sessions each preserved non-repetition independently"

echo "=== Test 6: Empty unit safely reaches fallback without unbound variable error ==="
mkdir -p "${TEST_SOUNDS}/unit-empty"
: > "${PLAY_LOG}"
run_player "sess-empty" "unit-empty"
wait_for_plays 1 >/dev/null
plays=$(count_plays)
if [[ "${plays}" -lt 1 ]]; then
  echo "FAIL: Empty unit failed to trigger fallback playback" >&2
  exit 1
fi
echo "PASS: Empty unit safely fell back without unbound variable abort"

echo "duplicate-sound-prevention-test: ALL PASS"
