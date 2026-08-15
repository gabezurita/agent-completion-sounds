#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${TEST_ROOT}"' EXIT

TEST_HOME="${TEST_ROOT}/home"
TEST_BIN="${TEST_ROOT}/bin"
PLAY_LOG="${TEST_ROOT}/played.log"
mkdir -p "${TEST_HOME}/.cursor" "${TEST_HOME}/.claude" "${TEST_HOME}/.gemini/config" \
  "${TEST_HOME}/.codex" "${TEST_HOME}/sounds" "${TEST_BIN}"

cat > "${TEST_ROOT}/cursor-hooks-target.json" <<'JSON'
{"version":1,"preserved":"cursor","hooks":{"stop":[{"command":"/existing/cursor"}],"beforeSubmitPrompt":[{"command":"/existing/before"}]}}
JSON
ln -s "${TEST_ROOT}/cursor-hooks-target.json" "${TEST_HOME}/.cursor/hooks.json"
cat > "${TEST_HOME}/.claude/settings.json" <<'JSON'
{"preserved":"claude","hooks":{"Stop":[{"matcher":"existing","hooks":[{"type":"command","command":"/existing/claude"}]}],"PreToolUse":[]}}
JSON
cat > "${TEST_HOME}/.gemini/settings.json" <<'JSON'
{"preserved":"gemini","hooks":{"AfterAgent":[{"matcher":"existing","hooks":[{"type":"command","command":"/existing/gemini"}]}],"BeforeAgent":[]}}
JSON
cat > "${TEST_HOME}/.gemini/config/hooks.json" <<'JSON'
{"preserved":"antigravity","existing-hook":{"Stop":[{"type":"command","command":"/existing/antigravity"}]}}
JSON
cat > "${TEST_HOME}/.codex/config.toml" <<'TOML'
notify = [
  "/old/root-notifier",
]

[projects."/tmp/example"]
trust_level = "trusted"
notify = ["/old/notifier"]
TOML
printf '%s\n' 'existing-folder' > "${TEST_HOME}/sounds/favorites.txt"

cp "${TEST_HOME}/.cursor/hooks.json" "${TEST_ROOT}/original-cursor.json"
cp "${TEST_HOME}/.claude/settings.json" "${TEST_ROOT}/original-claude.json"
cp "${TEST_HOME}/.gemini/settings.json" "${TEST_ROOT}/original-gemini.json"
cp "${TEST_HOME}/.gemini/config/hooks.json" "${TEST_ROOT}/original-antigravity.json"
cp "${TEST_HOME}/.codex/config.toml" "${TEST_ROOT}/original-codex.toml"

cat > "${TEST_BIN}/afplay" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${*: -1}" >> "${PLAY_LOG:?}"
SH
chmod +x "${TEST_BIN}/afplay"
mkdir -p "${TEST_HOME}/sounds/agent-completion-starter"
: > "${TEST_HOME}/sounds/agent-completion-starter/complete-bright.wav"

run_setup() {
  HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:${PATH}" \
    PLAY_LOG="${PLAY_LOG}" \
    AGENT_SOUNDS_ROOT="${TEST_HOME}/sounds" \
    "${REPO_ROOT}/scripts/setup.sh"
}

run_setup
config_hashes() {
  shasum \
    "${TEST_HOME}/.cursor/hooks.json" \
    "${TEST_HOME}/.claude/settings.json" \
    "${TEST_HOME}/.gemini/settings.json" \
    "${TEST_HOME}/.gemini/config/hooks.json" \
    "${TEST_HOME}/.codex/config.toml" \
    "${TEST_HOME}/sounds/favorites.txt"
}

first_hashes=$(config_hashes)
run_setup
second_hashes=$(config_hashes)
if [[ "${first_hashes}" != "${second_hashes}" ]]; then
  printf '%s\n' 'Error: idempotent run altered config hashes!' >&2
  exit 1
fi
[[ -L "${TEST_HOME}/.cursor/hooks.json" ]]

cmp "${TEST_ROOT}/original-cursor.json" "${TEST_HOME}/.cursor/hooks.json.bak"
cmp "${TEST_ROOT}/original-claude.json" "${TEST_HOME}/.claude/settings.json.bak"
cmp "${TEST_ROOT}/original-gemini.json" "${TEST_HOME}/.gemini/settings.json.bak"
cmp "${TEST_ROOT}/original-antigravity.json" "${TEST_HOME}/.gemini/config/hooks.json.bak"
cmp "${TEST_ROOT}/original-codex.toml" "${TEST_HOME}/.codex/config.toml.bak"

python3 - "${TEST_HOME}" "${REPO_ROOT}" <<'PY'
import json
import pathlib
import sys
import wave

home = pathlib.Path(sys.argv[1])
repo = pathlib.Path(sys.argv[2])
player = str(repo / "scripts" / "play-random-completion-sound.sh")
notifier = str(repo / "scripts" / "codex-notify.sh")

cursor = json.loads((home / ".cursor/hooks.json").read_text())
assert cursor["preserved"] == "cursor"
commands = [entry["command"] for entry in cursor["hooks"]["stop"]]
assert commands.count(player) == 1
assert "/existing/cursor" in commands
assert cursor["hooks"]["beforeSubmitPrompt"] == [{"command": "/existing/before"}]

claude = json.loads((home / ".claude/settings.json").read_text())
assert claude["preserved"] == "claude"
commands = [hook["command"] for group in claude["hooks"]["Stop"] for hook in group["hooks"]]
assert commands.count(player) == 1
assert "/existing/claude" in commands
assert claude["hooks"]["PreToolUse"] == []

gemini = json.loads((home / ".gemini/settings.json").read_text())
assert gemini["preserved"] == "gemini"
commands = [hook["command"] for group in gemini["hooks"]["AfterAgent"] for hook in group["hooks"]]
assert commands.count(player) == 1
assert "/existing/gemini" in commands
assert gemini["hooks"]["BeforeAgent"] == []

antigravity = json.loads((home / ".gemini/config/hooks.json").read_text())
assert antigravity["preserved"] == "antigravity"
commands = [
    entry["command"]
    for spec in antigravity.values() if isinstance(spec, dict)
    for entry in spec.get("Stop", []) if isinstance(entry, dict)
]
assert commands.count(player) == 1
assert "/existing/antigravity" in commands

codex_text = (home / ".codex/config.toml").read_text()
preamble = "\n".join(
    line for line in codex_text.splitlines() if not line.lstrip().startswith("[")
)
assert f'notify = ["{notifier}"]' in preamble
assert 'trust_level = "trusted"' in codex_text
assert 'notify = ["/old/notifier"]' in codex_text
assert codex_text.count("notify =") == 2

sounds = sorted((home / "sounds/agent-completion-starter").glob("*.wav"))
assert len(sounds) == 3
for sound in sounds:
    with wave.open(str(sound)) as wav:
        assert wav.getnchannels() == 1
        assert wav.getsampwidth() == 2
        assert wav.getframerate() == 44_100
        assert wav.getnframes() > 0

favorites = (home / "sounds/favorites.txt").read_text().splitlines()
assert favorites.count("agent-completion-starter") == 1
assert favorites.count("existing-folder") == 1
PY

TOML_PY=""
for candidate in python3.11 python3; do
  if command -v "${candidate}" >/dev/null 2>&1 && "${candidate}" -c 'import tomllib' >/dev/null 2>&1; then
    TOML_PY="${candidate}"
    break
  fi
done
[[ -n "${TOML_PY}" ]]
"${TOML_PY}" - "${TEST_HOME}/.codex/config.toml" "${REPO_ROOT}/scripts/codex-notify.sh" <<'PY'
import pathlib
import sys
import tomllib

config = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
assert config["notify"] == [sys.argv[2]]
assert config["projects"]["/tmp/example"]["notify"] == ["/old/notifier"]
PY

for _ in {1..20}; do
  [[ -s "${PLAY_LOG}" ]] && break
  sleep 0.05
done

[[ -s "${PLAY_LOG}" ]]
grep -q '/agent-completion-starter/.*\.wav$' "${PLAY_LOG}"

FRESH_HOME="${TEST_ROOT}/fresh-home"
HOME="${FRESH_HOME}" PATH="${TEST_BIN}:${PATH}" PLAY_LOG="${PLAY_LOG}" \
  "${REPO_ROOT}/scripts/setup.sh" >/dev/null
[[ -f "${FRESH_HOME}/.cursor/hooks.json" ]]
[[ -f "${FRESH_HOME}/.claude/settings.json" ]]
[[ -f "${FRESH_HOME}/.gemini/settings.json" ]]
[[ -f "${FRESH_HOME}/.gemini/config/hooks.json" ]]
[[ -f "${FRESH_HOME}/.codex/config.toml" ]]
[[ -f "${FRESH_HOME}/sounds/agent-completion-starter/complete-bright.wav" ]]
[[ ! -e "${FRESH_HOME}/sounds/favorites.txt" ]]

INVALID_HOME="${TEST_ROOT}/invalid-home"
mkdir -p "${INVALID_HOME}/.cursor" "${INVALID_HOME}/.gemini"
printf '%s\n' '{"preserved":"before"}' > "${INVALID_HOME}/.cursor/hooks.json"
printf '%s\n' '{invalid' > "${INVALID_HOME}/.gemini/settings.json"
if HOME="${INVALID_HOME}" PATH="${TEST_BIN}:${PATH}" PLAY_LOG="${PLAY_LOG}" \
  "${REPO_ROOT}/scripts/setup.sh" >/dev/null 2>&1; then
  printf '%s\n' 'expected invalid JSON setup to fail' >&2
  exit 1
fi
[[ "$(cat "${INVALID_HOME}/.cursor/hooks.json")" == '{"preserved":"before"}' ]]

NO_PLAYER_BIN="${TEST_ROOT}/no-player-bin"
mkdir -p "${NO_PLAYER_BIN}"
ln -s "$(command -v python3)" "${NO_PLAYER_BIN}/python3"
ln -s "$(command -v dirname)" "${NO_PLAYER_BIN}/dirname"
if HOME="${TEST_ROOT}/no-player-home" PATH="${NO_PLAYER_BIN}" \
  /bin/bash "${REPO_ROOT}/scripts/setup.sh" >/dev/null 2>&1; then
  printf '%s\n' 'expected setup without an audio player to fail' >&2
  exit 1
fi
[[ ! -e "${TEST_ROOT}/no-player-home/.cursor/hooks.json" ]]

printf '%s\n' 'one-command setup: PASS'
