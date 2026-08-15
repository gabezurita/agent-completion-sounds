#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

output=$(
  AGENT_COMPLETION_SOUND_DISABLE=1 \
    "${REPO_ROOT}/scripts/codex-notify.sh" '{"type":"agent-turn-complete"}'
)

if [[ "${output}" != "{}" ]]; then
  printf 'expected {}, got %s\n' "${output}" >&2
  exit 1
fi

printf '%s\n' 'codex notify adapter: PASS'
