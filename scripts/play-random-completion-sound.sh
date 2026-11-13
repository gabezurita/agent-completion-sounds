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
FALLBACK="${AGENT_SOUNDS_FALLBACK:-/System/Library/Sounds/Glass.aiff}"
VOLUME="${AGENT_COMPLETION_SOUND_VOLUME:-0.45}"
SESSION_CACHE_DIR="${TMPDIR:-/tmp}/agent-sound-sessions"
ACTIVE_WINDOW_SECS="${AGENT_SOUND_ACTIVE_WINDOW_SECS:-7200}"
COOLDOWN_FILE="${SOUNDS_ROOT}/.cooldown"
DEFAULT_COOLDOWN=2
if [[ -f "${COOLDOWN_FILE}" ]]; then
  file_cooldown=$(cat "${COOLDOWN_FILE}" 2>/dev/null || true)
  if [[ "${file_cooldown}" =~ ^[0-9]+$ ]]; then
    DEFAULT_COOLDOWN="${file_cooldown}"
  fi
fi
COOLDOWN_SECS="${AGENT_SOUND_COOLDOWN_SECS:-${DEFAULT_COOLDOWN}}"
if [[ ! "${COOLDOWN_SECS}" =~ ^[0-9]+$ ]]; then
  COOLDOWN_SECS=2
fi
DISABLE_FILE="${SOUNDS_ROOT}/.disabled"
LOG_FILE="${AGENT_SOUND_LOG_FILE:-/tmp/agent-sound.log}"

log_msg() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
  printf '[%s] [%s:%s] [player] %s\n' "${ts}" "$$" "${PPID:-0}" "$*" >> "${LOG_FILE}" 2>/dev/null || true
}

log_msg "entered: args='$*' payload_len=${#payload}"

if [[ "${AGENT_COMPLETION_SOUND_PREVIEW:-}" != "1" && ( -f "${DISABLE_FILE}" || "${AGENT_COMPLETION_SOUND_DISABLE:-}" == "1" ) ]]; then
  log_msg "suppressed: disabled (sentinel file '${DISABLE_FILE}' exists or AGENT_COMPLETION_SOUND_DISABLE=1)"
  printf '%s\n' '{}'
  exit 0
fi

# Parse explicit event argument (start vs stop)
event=""
for arg in "$@"; do
  case "${arg}" in
    start|--start|--event=start) event="start" ;;
    stop|--stop|--event=stop) event="stop" ;;
  esac
done

# Active mode: "session" (default: sticky unit from favorites per conversation),
# "favorites" / "turn-favorites" (randomize favorite unit every turn),
# "session-all" (sticky unit from full pool per conversation),
# "all" / "turn-all" (randomize full pool every turn),
# or a specific folder name (e.g. "sc1-valkyrie").
MODE=$(cat "${MODE_FILE}" 2>/dev/null || echo "session")

if [[ "${MODE}" == "off" || "${MODE}" == "mute" || "${MODE}" == "disabled" ]]; then
  log_msg "suppressed: mode is '${MODE}'"
  printf '%s\n' '{}'
  exit 0
fi

# Extract conversation/session ID and invocation number from stdin payload if present.
session_id=""
invocation_num=""
if [[ -n "${payload}" ]]; then
  session_id=$(printf '%s' "${payload}" | grep -oE '"(conversationId|conversation_id|session_id|sessionId)":[[:space:]]*"[^"]+"' | head -n 1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/' || true)
  session_id="${session_id//[^a-zA-Z0-9_.-]/_}"

  inv_match=$(printf '%s' "${payload}" | grep -oE '"(invocationNum|invocation_num)":[[:space:]]*[0-9]+' | head -n 1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/' || true)
  if [[ -n "${inv_match}" ]]; then
    invocation_num="${inv_match}"
  fi
fi

# In multi-step agent runs (e.g. Antigravity PreInvocation), suppress intermediate tool steps
if [[ -n "${invocation_num}" && "${invocation_num}" -gt 1 ]]; then
  log_msg "suppressed: intermediate tool invocation (${invocation_num}) for session '${session_id:-global}'"
  printf '%s\n' '{}'
  exit 0
fi

# Infer event type if not explicitly supplied via CLI argument
if [[ -z "${event}" ]]; then
  if [[ -n "${invocation_num}" && "${invocation_num}" -eq 1 ]]; then
    event="start"
  elif printf '%s' "${payload}" | grep -qiE '"(terminationReason|executionNum|stop_reason|stop)"'; then
    event="stop"
  elif printf '%s' "${payload}" | grep -qiE '"(userPrompt|beforeSubmitPrompt|userPromptSubmit|beforeAgent|prompt)"'; then
    event="start"
  else
    event="stop"
  fi
fi

# Check session cooldown state
state_file=""
if [[ -n "${session_id}" ]]; then
  state_file="${SESSION_CACHE_DIR}/${session_id}.time"
else
  state_file="${SESSION_CACHE_DIR}/global.time"
fi

now=$(date +%s)
last_start_ts=0
last_sound_ts=0

if [[ -f "${state_file}" ]]; then
  read -r last_start_ts last_sound_ts < "${state_file}" 2>/dev/null || true
  last_start_ts="${last_start_ts:-0}"
  last_sound_ts="${last_sound_ts:-0}"
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

# Helper: safely get file modification timestamp as an integer across GNU (Linux) and BSD (macOS)
get_file_mtime() {
  local target="$1"
  local mt
  if mt=$(stat -c %Y "${target}" 2>/dev/null) && [[ "${mt}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${mt}"
    return 0
  fi
  if mt=$(stat -f %m "${target}" 2>/dev/null) && [[ "${mt}" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "${mt}"
    return 0
  fi
  echo 0
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

      local smtime
      smtime=$(get_file_mtime "${sf}")

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
                smtime=$(get_file_mtime "${sf}")
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

if ((COOLDOWN_SECS > 0)); then
  if [[ "${event}" == "stop" ]]; then
    # Suppress end sound if turn finished too quickly after start sound (short turn)
    if ((last_start_ts > 0 && (now - last_start_ts < COOLDOWN_SECS))); then
      log_msg "suppressed: short turn (elapsed $((now - last_start_ts))s < cooldown ${COOLDOWN_SECS}s, session='${session_id:-global}')"
      printf '%s\n' '{}'
      exit 0
    fi
    # Suppress end sound if any sound was played too recently (duplicate stop hooks)
    if ((last_sound_ts > 0 && (now - last_sound_ts < COOLDOWN_SECS))); then
      log_msg "suppressed: cooldown active (elapsed $((now - last_sound_ts))s < cooldown ${COOLDOWN_SECS}s, session='${session_id:-global}')"
      printf '%s\n' '{}'
      exit 0
    fi
  elif [[ "${event}" == "start" ]]; then
    # Throttle duplicate start hooks within 2 seconds
    if ((last_start_ts > 0 && (now - last_start_ts < 2))); then
      log_msg "suppressed: duplicate start hook (elapsed $((now - last_start_ts))s < 2s, session='${session_id:-global}')"
      printf '%s\n' '{}'
      exit 0
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

# Read the last played clip to avoid playing the exact same sound consecutively
last_clip=""
if [[ -n "${session_id}" && -f "${SESSION_CACHE_DIR}/${session_id}.last" ]]; then
  last_clip=$(cat "${SESSION_CACHE_DIR}/${session_id}.last" 2>/dev/null || true)
fi
if [[ -z "${last_clip}" && -f "${SESSION_CACHE_DIR}/global.last" ]]; then
  last_clip=$(cat "${SESSION_CACHE_DIR}/global.last" 2>/dev/null || true)
fi

candidate_clips=()
if ((${#clips[@]} > 0)); then
  for c in "${clips[@]}"; do
    [[ -n "${last_clip}" && "${c}" == "${last_clip}" ]] && continue
    candidate_clips+=("${c}")
  done
fi

clip=""
count=${#clips[@]}
if ((${#candidate_clips[@]} > 0)); then
  clip="${candidate_clips[RANDOM % ${#candidate_clips[@]}]}"
elif ((count > 0)); then
  clip="${clips[RANDOM % count]}"
elif [[ -f "${FALLBACK}" ]]; then
  clip="${FALLBACK}"
fi

# 5. Play detached
if [[ -n "${clip}" ]]; then
  log_msg "dispatch: event=${event} session=${session_id:-global} unit=${selected_unit:-<none>} volume=${VOLUME} clip=${clip}"
  mkdir -p "${SESSION_CACHE_DIR}"
  if [[ "${event}" == "start" ]]; then
    printf '%s %s\n' "${now}" "${now}" > "${state_file}"
  else
    printf '%s %s\n' "${last_start_ts}" "${now}" > "${state_file}"
  fi
  printf '%s\n' "${clip}" > "${SESSION_CACHE_DIR}/global.last"
  if [[ -n "${session_id}" ]]; then
    printf '%s\n' "${clip}" > "${SESSION_CACHE_DIR}/${session_id}.last"
  fi

  if command -v python3 >/dev/null 2>&1; then
    log_msg "launching python background player"
    if ! python3 - "${clip}" "${VOLUME}" "${LOG_FILE}" <<'PY'
import os, sys, shutil, subprocess, datetime

clip = sys.argv[1]
volume = sys.argv[2]
log_file = sys.argv[3] if len(sys.argv) > 3 else ""

def log(msg):
    if not log_file:
        return
    try:
        ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(log_file, "a") as f:
            f.write(f"[{ts}] [{os.getpid()}] [player] {msg}\n")
    except Exception:
        pass

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
    log(f"spawn: player_cmd={' '.join(player_cmd)}")
    try:
        if os.fork() > 0:
            sys.exit(0)
        try:
            os.setsid()
        except Exception as se:
            log(f"setsid warning: {se}")
        if os.fork() > 0:
            os._exit(0)
    except Exception as fe:
        log(f"fork fallback (executing directly): {fe}")

    log(f"executing: {' '.join(player_cmd)}")
    try:
        res = subprocess.run(player_cmd, capture_output=True, text=True)
        if res.returncode == 0:
            log("playback complete (code=0)")
        else:
            log(f"playback error (code={res.returncode}): {res.stderr.strip() or res.stdout.strip()}")
            fallbacks = []
            if shutil.which("ffplay"):
                vol = max(0, min(100, int(float(volume) * 100)))
                fallbacks.append(["ffplay", "-nodisp", "-autoexit", "-loglevel", "error", "-volume", str(vol), clip])
            if shutil.which("play"):
                fallbacks.append(["play", "-q", "-v", str(volume), clip])
            for fb in fallbacks:
                log(f"trying fallback player: {' '.join(fb)}")
                fb_res = subprocess.run(fb, capture_output=True, text=True)
                if fb_res.returncode == 0:
                    log("fallback playback complete (code=0)")
                    break
                else:
                    log(f"fallback error (code={fb_res.returncode}): {fb_res.stderr.strip() or fb_res.stdout.strip()}")
    except Exception as e:
        log(f"playback exception: {e}")
    sys.exit(0)
PY
    then
      log_msg "python background player launch failed"
    fi
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
else
  log_msg "suppressed: no matching audio clip found (session='${session_id:-global}')"
fi

printf '%s\n' '{}'
exit 0
