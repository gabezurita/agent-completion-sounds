#!/usr/bin/env bash
# Adapt Codex's JSON command argument to the shared hook's JSON stdin contract.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Codex appends its notification payload as argv[1]. Playback does not need it.
: "${1:-}"

printf '%s\n' '{}' | "${SCRIPT_DIR}/play-random-completion-sound.sh"
