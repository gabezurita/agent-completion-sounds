#!/usr/bin/env bash
# Show or set the agent completion-sound mode.
# Read by ~/.agents/scripts/play-random-completion-sound.sh. Documented in ~/sounds/README.md.

set -euo pipefail

SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"
MODE_FILE="${SOUNDS_ROOT}/.mode"
SESSION_CACHE_DIR="${TMPDIR:-/tmp}/agent-sound-sessions"
arg="${1:-}"

mkdir -p "$(dirname "${MODE_FILE}")"

case "$arg" in
  "")
    cat "${MODE_FILE}" 2>/dev/null || echo "session"
    ;;
  session | session-favorites | sticky)
    printf 'session\n' > "${MODE_FILE}"
    echo "Sound mode: session (sticky favorite unit per conversation)"
    ;;
  session-all)
    printf 'session-all\n' > "${MODE_FILE}"
    echo "Sound mode: session-all (sticky unit from full pool per conversation)"
    ;;
  favorites | turn-favorites)
    printf 'favorites\n' > "${MODE_FILE}"
    echo "Sound mode: favorites (random favorite unit every turn)"
    ;;
  all | turn-all)
    printf 'all\n' > "${MODE_FILE}"
    echo "Sound mode: all (random unit from full pool every turn)"
    ;;
  clear | reset | clear-sessions)
    rm -rf "${SESSION_CACHE_DIR}"
    echo "Cleared active session sound bindings in ${SESSION_CACHE_DIR}"
    ;;
  toggle)
    current=$(cat "${MODE_FILE}" 2>/dev/null || echo "session")
    case "$current" in
      session | session-favorites | sticky) next="favorites" ;;
      favorites | turn-favorites) next="all" ;;
      *) next="session" ;;
    esac
    printf '%s\n' "$next" > "${MODE_FILE}"
    echo "Sound mode: $next"
    ;;
  mute | off | disable)
    touch "${SOUNDS_ROOT}/.disabled"
    echo "Sound mode: muted (.disabled sentinel set)"
    ;;
  unmute | on | enable)
    rm -f "${SOUNDS_ROOT}/.disabled"
    echo "Sound mode: unmuted (.disabled sentinel removed)"
    ;;
  toggle-mute | toggle-sound)
    if [[ -f "${SOUNDS_ROOT}/.disabled" ]]; then
      rm -f "${SOUNDS_ROOT}/.disabled"
      echo "Sound mode: unmuted (.disabled sentinel removed)"
    else
      touch "${SOUNDS_ROOT}/.disabled"
      echo "Sound mode: muted (.disabled sentinel set)"
    fi
    ;;
  status)
    curr_mode=$(cat "${MODE_FILE}" 2>/dev/null || echo "session")
    if [[ -f "${SOUNDS_ROOT}/.disabled" ]]; then
      sound_state="muted (.disabled)"
    else
      sound_state="active"
    fi
    fav_count=0
    if [[ -f "${SOUNDS_ROOT}/favorites.txt" ]]; then
      fav_count=$(grep -c -vE '^[[:space:]]*(#|$)' "${SOUNDS_ROOT}/favorites.txt" 2>/dev/null || echo 0)
    fi
    total_units=0
    for d in "${SOUNDS_ROOT}"/*/; do
      [[ -d "$d" ]] || continue
      b=$(basename "$d")
      [[ "$b" == .* || "$b" == "scratch" ]] && continue
      total_units=$((total_units + 1))
    done
    echo "Sound Mode: ${curr_mode}"
    echo "Sound State: ${sound_state}"
    echo "Favorites: ${fav_count} of ${total_units} unit packs"
    ;;
  *)
    if [[ -d "${SOUNDS_ROOT}/${arg}" ]]; then
      printf '%s\n' "$arg" > "${MODE_FILE}"
      echo "Sound mode: locked to unit '$arg'"
    else
      echo "Usage: soundmode [session|favorites|all|session-all|mute|unmute|toggle-mute|status|<unit-folder>|toggle|clear]" >&2
      exit 1
    fi
    ;;
esac
