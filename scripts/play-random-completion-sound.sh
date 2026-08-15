#!/usr/bin/env bash
# Play a random clip from AGENT_SOUNDS_ROOT when an agent turn ends.
# Wire this as a Cursor, Claude Code, Gemini CLI, or Google Antigravity hook (see hooks/).

set -euo pipefail

# Hosts send JSON on stdin; consume it so the pipe does not stall.
cat >/dev/null

SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"
FAVORITES_FILE="${SOUNDS_ROOT}/favorites.txt"
MODE_FILE="${SOUNDS_ROOT}/.mode"
FALLBACK="/System/Library/Sounds/Glass.aiff"
VOLUME="${AGENT_COMPLETION_SOUND_VOLUME:-0.45}"

if [[ "${AGENT_COMPLETION_SOUND_DISABLE:-}" == "1" ]]; then
  printf '%s\n' '{}'
  exit 0
fi

# Mode is "favorites" (default) or "all"; toggle with sound-mode.sh.
MODE=$(cat "${MODE_FILE}" 2>/dev/null || echo "favorites")

# In favorites mode, favorites.txt (one folder name per line, relative to
# SOUNDS_ROOT) narrows the pool to those folders only. Any other mode, or an
# absent/empty favorites file, falls back to the full tree.
search_roots=()
if [[ "${MODE}" == "favorites" && -f "${FAVORITES_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    line="${line%%#*}"
    [[ -z "${line// /}" ]] && continue
    search_roots+=("${SOUNDS_ROOT}/${line}")
  done < "${FAVORITES_FILE}"
fi
((${#search_roots[@]} == 0)) && search_roots=("${SOUNDS_ROOT}")

clips=()
while IFS= read -r -d '' f; do
  clips+=("$f")
done < <(
  find "${search_roots[@]}" \
    \( -iname '*.mp3' -o -iname '*.wav' -o -iname '*.aiff' -o -iname '*.aif' -o -iname '*.m4a' -o -iname '*.ogg' \) \
    -type f -print0 2>/dev/null
)

clip=""
count=${#clips[@]}
if ((count > 0)); then
  clip="${clips[RANDOM % count]}"
elif [[ -f "${FALLBACK}" ]]; then
  clip="${FALLBACK}"
fi

if [[ -n "${clip}" ]]; then
  # Detach so the hook returns immediately and does not block the agent UI.
  if command -v afplay >/dev/null 2>&1; then
    (afplay -v "${VOLUME}" "${clip}" >/dev/null 2>&1 &)
  elif command -v paplay >/dev/null 2>&1; then
    (paplay "${clip}" >/dev/null 2>&1 &)
  elif command -v aplay >/dev/null 2>&1; then
    (aplay -q "${clip}" >/dev/null 2>&1 &)
  fi
fi

printf '%s\n' '{}'
exit 0
