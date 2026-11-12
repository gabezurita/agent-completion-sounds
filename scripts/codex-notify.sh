#!/usr/bin/env bash
# Adapt Codex's JSON command argument to the shared hook's JSON stdin contract.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLAYER_SCRIPT="${AGENT_SOUND_PLAYER:-${SCRIPT_DIR}/play-random-completion-sound.sh}"
LOG_FILE="${AGENT_SOUND_LOG_FILE:-/tmp/agent-sound.log}"

log_msg() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
  printf '[%s] [%s:%s] [codex-notify] %s\n' "${ts}" "$$" "${PPID:-0}" "$*" >> "${LOG_FILE}" 2>/dev/null || true
}

# Codex passes its notification payload as an argument (typically argv[1]).
# Allow stdin as a fallback when argv is omitted or non-interactive.
payload=""
pass_args=()
for arg in "$@"; do
  if [[ "${arg}" =~ ^\{.*\}$ ]]; then
    payload="${arg}"
  else
    pass_args+=("${arg}")
  fi
done

if [[ -z "${payload}" && -n "${1:-}" ]]; then
  payload="${1}"
elif [[ -z "${payload}" && ! -t 0 ]]; then
  payload=$(cat 2>/dev/null || true)
fi

thread_id=""
if [[ -n "${payload}" ]]; then
  thread_id=$(printf '%s' "${payload}" | grep -oE '"(thread-id|thread_id|threadId|conversationId|conversation_id|session_id|sessionId)"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n 1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/' || true)
  thread_id="${thread_id//[^a-zA-Z0-9_.-]/_}"
fi

if [[ -n "${thread_id}" ]]; then
  out_payload=$(printf '{"session_id":"%s"}' "${thread_id}")
else
  out_payload='{}'
fi

log_msg "invoked: thread_id='${thread_id:-<none>}' args='$*' payload_len=${#payload}"
log_msg "executing player: PLAYER_SCRIPT='${PLAYER_SCRIPT}' payload='${out_payload}' pass_args='${pass_args[*]:-}'"

if ((${#pass_args[@]} > 0)); then
  printf '%s\n' "${out_payload}" | "${PLAYER_SCRIPT}" "${pass_args[@]}"
  res=$?
else
  printf '%s\n' "${out_payload}" | "${PLAYER_SCRIPT}"
  res=$?
fi

log_msg "player exited with status ${res}"
