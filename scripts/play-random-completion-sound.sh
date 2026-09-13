#!/usr/bin/env bash
# Play a random clip from ~/sounds/ when an agent turn ends.
# Supports session-scoped unit binding (sticky unit per conversation) or per-turn random.
# Shared Stop hook: wired from ~/.cursor/hooks.json (Cursor), ~/.claude/settings.json (Claude Code),
# and Antigravity hooks. Documented in ~/sounds/README.md.

set -euo pipefail

# Hosts send JSON on stdin; capture it to extract session/conversation ID.
payload=$(cat 2>/dev/null || true)

SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"
FAVORITES_FILE="${SOUNDS_ROOT}/favorites.txt"
MODE_FILE="${SOUNDS_ROOT}/.mode"
FALLBACK="/System/Library/Sounds/Glass.aiff"
VOLUME="${AGENT_COMPLETION_SOUND_VOLUME:-0.45}"
SESSION_CACHE_DIR="${TMPDIR:-/tmp}/agent-sound-sessions"
ACTIVE_WINDOW_SECS="${AGENT_SOUND_ACTIVE_WINDOW_SECS:-7200}"

if [[ "${AGENT_COMPLETION_SOUND_DISABLE:-}" == "1" ]]; then
  printf '%s\n' '{}'
  exit 0
fi

# Active mode: "session" (default: sticky unit from favorites per conversation),
# "favorites" / "turn-favorites" (randomize favorite unit every turn),
# "session-all" (sticky unit from full pool per conversation),
# "all" / "turn-all" (randomize full pool every turn),
# or a specific folder name (e.g. "sc1-valkyrie").
MODE=$(cat "${MODE_FILE}" 2>/dev/null || echo "session")

# Extract conversation/session ID from stdin payload if present.
session_id=""
if [[ -n "${payload}" ]]; then
  session_id=$(printf '%s' "${payload}" | grep -oE '"(conversationId|conversation_id|session_id|sessionId)":[[:space:]]*"[^"]+"' | head -n 1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/' || true)
  session_id="${session_id//[^a-zA-Z0-9_.-]/_}"
fi

# Helper: load valid candidate unit folders for the current mode
get_candidate_units() {
  local pool_type="$1"
  local units=()
  if [[ "${pool_type}" == "favorites" && -f "${FAVORITES_FILE}" ]]; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%$'\r'}"
      line="${line%%#*}"
      [[ -z "${line// /}" ]] && continue
      [[ -d "${SOUNDS_ROOT}/${line}" ]] && units+=("${line}")
    done < "${FAVORITES_FILE}"
  fi

  if ((${#units[@]} == 0)); then
    for d in "${SOUNDS_ROOT}"/*/; do
      [[ -d "$d" ]] || continue
      local b
      b=$(basename "$d")
      [[ "$b" == .* || "$b" == "scratch" ]] && continue
      units+=("$b")
    done
  fi
  printf '%s\n' "${units[@]}"
}

# Helper: inspect session cache and return units actively bound to other concurrent sessions
get_active_units() {
  local exclude_file="${1:-}"
  local now cutoff
  now=$(date +%s)
  cutoff=$((now - ACTIVE_WINDOW_SECS))
  local active=()

  if [[ -d "${SESSION_CACHE_DIR}" ]]; then
    for sf in "${SESSION_CACHE_DIR}"/*.unit; do
      [[ -f "${sf}" ]] || continue
      [[ -n "${exclude_file}" && "${sf}" == "${exclude_file}" ]] && continue

      local smtime=0
      smtime=$(stat -f %m "${sf}" 2>/dev/null || stat -c %Y "${sf}" 2>/dev/null || echo 0)

      if ((smtime >= cutoff)); then
        local u
        u=$(cat "${sf}" 2>/dev/null || true)
        [[ -n "${u}" ]] && active+=("${u}")
      fi
    done
  fi
  ((${#active[@]} > 0)) && printf '%s\n' "${active[@]}"
}

selected_unit=""

# 1. Explicit unit override from environment or mode setting
if [[ -n "${AGENT_SOUND_UNIT:-}" && -d "${SOUNDS_ROOT}/${AGENT_SOUND_UNIT}" ]]; then
  selected_unit="${AGENT_SOUND_UNIT}"
elif [[ -d "${SOUNDS_ROOT}/${MODE}" ]]; then
  selected_unit="${MODE}"
elif [[ -n "${session_id}" && ("${MODE}" == "session" || "${MODE}" == "session-favorites" || "${MODE}" == "session-all" || "${MODE}" == "sticky") ]]; then
  # 2. Session-scoped binding: check or initialize session cache
  session_file="${SESSION_CACHE_DIR}/${session_id}.unit"
  if [[ -f "${session_file}" ]]; then
    cached_unit=$(cat "${session_file}" 2>/dev/null || true)
    if [[ -n "${cached_unit}" && -d "${SOUNDS_ROOT}/${cached_unit}" ]]; then
      selected_unit="${cached_unit}"
      touch "${session_file}" 2>/dev/null || true
    fi
  fi

  if [[ -z "${selected_unit}" ]]; then
    pool="favorites"
    [[ "${MODE}" == "session-all" ]] && pool="all"
    candidate_units=()
    while IFS= read -r u; do
      [[ -n "$u" ]] && candidate_units+=("$u")
    done < <(get_candidate_units "${pool}")

    if ((${#candidate_units[@]} > 0)); then
      # Collect units actively in use by other recent sessions
      active_units=()
      while IFS= read -r au; do
        [[ -n "$au" ]] && active_units+=("$au")
      done < <(get_active_units "${session_file}")

      # Filter candidate units to those not currently in use
      available_units=()
      for cu in "${candidate_units[@]}"; do
        in_use=0
        if ((${#active_units[@]} > 0)); then
          for au in "${active_units[@]}"; do
            if [[ "${cu}" == "${au}" ]]; then
              in_use=1
              break
            fi
          done
        fi
        if ((in_use == 0)); then
          available_units+=("${cu}")
        fi
      done

      # If favorites pool is exhausted by active sessions, expand to full pool
      all_units=()
      if ((${#available_units[@]} == 0)) && [[ "${pool}" == "favorites" ]]; then
        while IFS= read -r u; do
          [[ -n "$u" ]] && all_units+=("$u")
        done < <(get_candidate_units "all")

        for cu in "${all_units[@]}"; do
          in_use=0
          if ((${#active_units[@]} > 0)); then
            for au in "${active_units[@]}"; do
              if [[ "${cu}" == "${au}" ]]; then
                in_use=1
                break
              fi
            done
          fi
          if ((in_use == 0)); then
            available_units+=("${cu}")
          fi
        done
      fi

      if ((${#available_units[@]} > 0)); then
        selected_unit="${available_units[RANDOM % ${#available_units[@]}]}"
      else
        # When all units are active, pick the candidate whose session was least recently active
        search_pool=("${candidate_units[@]}")
        if ((${#all_units[@]} > 0)); then
          search_pool=("${all_units[@]}")
        fi
        now_ts=$(date +%s)
        oldest_time=$((now_ts + 1000))
        oldest_candidate="${search_pool[0]}"
        for cu in "${search_pool[@]}"; do
          unit_last_seen=0
          if [[ -d "${SESSION_CACHE_DIR}" ]]; then
            for sf in "${SESSION_CACHE_DIR}"/*.unit; do
              [[ -f "${sf}" ]] || continue
              if [[ "$(cat "${sf}" 2>/dev/null || true)" == "${cu}" ]]; then
                smtime=$(stat -f %m "${sf}" 2>/dev/null || stat -c %Y "${sf}" 2>/dev/null || echo 0)
                ((smtime > unit_last_seen)) && unit_last_seen="${smtime}"
              fi
            done
          fi
          if ((unit_last_seen < oldest_time)); then
            oldest_time="${unit_last_seen}"
            oldest_candidate="${cu}"
          fi
        done
        selected_unit="${oldest_candidate}"
      fi

      mkdir -p "${SESSION_CACHE_DIR}"
      printf '%s\n' "${selected_unit}" > "${session_file}"
      touch "${session_file}" 2>/dev/null || true
    fi
  fi
fi

# 3. Determine search roots
search_roots=()
if [[ -n "${selected_unit}" && -d "${SOUNDS_ROOT}/${selected_unit}" ]]; then
  search_roots=("${SOUNDS_ROOT}/${selected_unit}")
elif [[ ("${MODE}" == "favorites" || "${MODE}" == "turn-favorites") && -f "${FAVORITES_FILE}" ]]; then
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    line="${line%%#*}"
    [[ -z "${line// /}" ]] && continue
    [[ -d "${SOUNDS_ROOT}/${line}" ]] && search_roots+=("${SOUNDS_ROOT}/${line}")
  done < "${FAVORITES_FILE}"
fi

((${#search_roots[@]} == 0)) && search_roots=("${SOUNDS_ROOT}")

# 4. Gather matching audio clips
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

# 5. Play detached
if [[ -n "${clip}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    # Double-fork daemon with setsid to completely decouple from hook runner process group and controlling TTY (e.g. iTerm/VS Code)
    python3 - "${clip}" "${VOLUME}" <<'PY'
import os, sys, shutil

clip = sys.argv[1]
volume = sys.argv[2]

player_cmd = []
if clip.lower().endswith(".ogg") and shutil.which("ffplay"):
    vol = max(0, min(100, int(float(volume) * 100)))
    player_cmd = ["ffplay", "-nodisp", "-autoexit", "-loglevel", "error", "-volume", str(vol), clip]
elif shutil.which("afplay"):
    player_cmd = ["afplay", "-v", str(volume), clip]
elif shutil.which("paplay"):
    player_cmd = ["paplay", clip]
elif shutil.which("aplay"):
    player_cmd = ["aplay", "-q", clip]

if player_cmd:
    if os.fork() > 0:
        sys.exit(0)
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    devnull = os.open(os.devnull, os.O_RDWR)
    os.dup2(devnull, 0)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    if devnull > 2:
        os.close(devnull)
    os.execvp(player_cmd[0], player_cmd)
PY
  elif command -v setsid >/dev/null 2>&1; then
    # On Linux, run in a new process group so it survives hook process group reaping
    (setsid paplay "${clip}" >/dev/null 2>&1 &) || (setsid aplay -q "${clip}" >/dev/null 2>&1 &) || (paplay "${clip}" >/dev/null 2>&1 &)
  elif command -v afplay >/dev/null 2>&1; then
    (afplay -v "${VOLUME}" "${clip}" >/dev/null 2>&1 &)
  elif command -v paplay >/dev/null 2>&1; then
    (paplay "${clip}" >/dev/null 2>&1 &)
  elif command -v aplay >/dev/null 2>&1; then
    (aplay -q "${clip}" >/dev/null 2>&1 &)
  fi
fi

printf '%s\n' '{}'
exit 0
