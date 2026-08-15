# Contributing

Small tool, low ceremony. A few ground rules:

## Before opening a PR

- `shellcheck scripts/*.sh` must pass clean.
- `bash -n scripts/*.sh` must pass (syntax check).
- JSON files under `hooks/` must parse (`python3 -m json.tool <file>`).
- Scripts must stay executable (`chmod +x`).

CI runs all of the above on every push and PR.

## Scope

This repo is the hook-wiring and playback logic only. Do not add:

- Bundled audio files (unlicensed or otherwise) — users bring their own clips.
- A new coding-agent integration without opening an issue first to confirm the
  hook/config shape that agent actually supports.

## Style

- Bash: `set -euo pipefail`, quote variable expansions, prefer `[[ ]]` over `[ ]`.
- Keep the sounds root configurable via `AGENT_SOUNDS_ROOT`; do not hardcode `~/sounds`.
- No comments that restate what the code does; comment only non-obvious WHY.
