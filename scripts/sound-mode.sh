#!/usr/bin/env bash
# Show or set the agent completion-sound mode: favorites (favorites.txt only) or all (full pool).
# Read by play-random-completion-sound.sh.

set -euo pipefail

SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"
MODE_FILE="${SOUNDS_ROOT}/.mode"
arg="${1:-}"

mkdir -p "$(dirname "${MODE_FILE}")"

case "$arg" in
  "")
    cat "${MODE_FILE}" 2>/dev/null || echo "favorites"
    ;;
  favorites | all)
    printf '%s\n' "$arg" > "${MODE_FILE}"
    echo "Sound mode: $arg"
    ;;
  toggle)
    current=$(cat "${MODE_FILE}" 2>/dev/null || echo "favorites")
    next="all"
    [[ "$current" == "all" ]] && next="favorites"
    printf '%s\n' "$next" > "${MODE_FILE}"
    echo "Sound mode: $next"
    ;;
  *)
    echo "Usage: sound-mode.sh [favorites|all|toggle]" >&2
    exit 1
    ;;
esac
