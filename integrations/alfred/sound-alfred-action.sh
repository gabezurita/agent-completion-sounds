#!/usr/bin/env bash
# Alfred 5 Action Dispatcher for agent-completion-sounds.
# Takes an argument string and performs the action.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"
MODE_SCRIPT="${REPO_ROOT}/scripts/sound-mode.sh"
PLAYER_SCRIPT="${REPO_ROOT}/scripts/play-random-completion-sound.sh"
FETCH_SCRIPT="${REPO_ROOT}/scripts/fetch-completion-sounds.sh"
FAVORITES_FILE="${SOUNDS_ROOT}/favorites.txt"

arg="${1:-}"

case "${arg}" in
  toggle-mute)
    "${MODE_SCRIPT}" toggle-mute
    ;;
  test)
    AGENT_COMPLETION_SOUND_DISABLE=0 "${PLAYER_SCRIPT}" stop <<< '{"conversationId":"alfred-test","executionNum":1}' >/dev/null 2>&1 || true
    echo "Played test sound"
    ;;
  open)
    mkdir -p "${SOUNDS_ROOT}"
    open "${SOUNDS_ROOT}"
    echo "Opened ${SOUNDS_ROOT}"
    ;;
  mode\ *)
    target_mode="${arg#mode }"
    "${MODE_SCRIPT}" "${target_mode}"
    ;;
  fav\ *)
    unit="${arg#fav }"
    mkdir -p "${SOUNDS_ROOT}"
    touch "${FAVORITES_FILE}"

    # Check if unit is in favorites
    is_present=0
    temp_fav=$(mktemp)
    while IFS= read -r line || [[ -n "${line}" ]]; do
      clean_line="${line%$'\r'}"
      clean_line="${clean_line%%#*}"
      clean_line="${clean_line## }"
      clean_line="${clean_line%% }"
      if [[ "${clean_line}" == "${unit}" ]]; then
        is_present=1
      else
        echo "${line}" >> "${temp_fav}"
      fi
    done < "${FAVORITES_FILE}"

    if [[ "${is_present}" -eq 1 ]]; then
      mv -f "${temp_fav}" "${FAVORITES_FILE}"
      echo "Removed '${unit}' from favorites"
    else
      rm -f "${temp_fav}"
      echo "${unit}" >> "${FAVORITES_FILE}"
      echo "Added '${unit}' to favorites"
    fi
    ;;
  fetch\ all)
    "${FETCH_SCRIPT}"
    echo "Curated sounds downloaded"
    ;;
  fetch\ *)
    set_name="${arg#fetch }"
    "${FETCH_SCRIPT}" "${set_name}"
    echo "Sound set '${set_name}' downloaded"
    ;;
  *)
    echo "No action for: ${arg}"
    ;;
esac
