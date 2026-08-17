#!/usr/bin/env bash
# Install starter sounds and merge completion hooks into supported agent configs.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
PLAYER="${SCRIPT_DIR}/play-random-completion-sound.sh"
NOTIFIER="${SCRIPT_DIR}/codex-notify.sh"
SOUNDS_ROOT="${AGENT_SOUNDS_ROOT:-${HOME}/sounds}"

command -v python3 >/dev/null 2>&1 || {
  printf '%s\n' 'setup requires python3' >&2
  exit 1
}
if ! command -v afplay >/dev/null 2>&1 && \
  ! command -v paplay >/dev/null 2>&1 && \
  ! command -v aplay >/dev/null 2>&1; then
  printf '%s\n' 'setup requires afplay (macOS), paplay, or aplay (Linux)' >&2
  exit 1
fi

python3 - "${HOME}" "${SOUNDS_ROOT}" "${PLAYER}" "${NOTIFIER}" "${REPO_ROOT}" <<'PY'
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import tempfile
import wave

home = Path(sys.argv[1]).expanduser()
sounds_root = Path(sys.argv[2]).expanduser()
raw_player = Path(sys.argv[3]).resolve()
raw_notifier = Path(sys.argv[4]).resolve()
repo = Path(sys.argv[5])

bin_dir = home / ".local" / "bin"
bin_dir.mkdir(parents=True, exist_ok=True)


def link_binary(link_path, target_path):
    link_path.parent.mkdir(parents=True, exist_ok=True)
    if link_path.is_symlink() or link_path.exists():
        link_path.unlink()
    link_path.symlink_to(target_path)


bin_player = bin_dir / "play-random-completion-sound.sh"
bin_player_short = bin_dir / "play-random-completion-sound"
bin_soundmode = bin_dir / "sound-mode.sh"
bin_soundmode_short = bin_dir / "soundmode"
bin_notifier = bin_dir / "codex-notify.sh"
bin_fetch = bin_dir / "fetch-completion-sounds.sh"
bin_fetch_short = bin_dir / "soundfetch"

link_binary(bin_player, raw_player)
link_binary(bin_player_short, raw_player)
link_binary(bin_soundmode, (repo / "scripts" / "sound-mode.sh").resolve())
link_binary(bin_soundmode_short, (repo / "scripts" / "sound-mode.sh").resolve())
link_binary(bin_notifier, raw_notifier)
link_binary(bin_fetch, (repo / "scripts" / "fetch-completion-sounds.sh").resolve())
link_binary(bin_fetch_short, (repo / "scripts" / "fetch-completion-sounds.sh").resolve())

player = str(bin_player)
notifier = str(bin_notifier)


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return
    if path.exists():
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
    target = path.resolve() if path.is_symlink() else path
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=target.name + ".", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write(text)
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_json(path):
    if not path.exists():
        return {}
    try:
        value = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        raise SystemExit(f"cannot update invalid JSON in {path}: {error}")
    if not isinstance(value, dict):
        raise SystemExit(f"cannot update {path}: top-level JSON value must be an object")
    return value


def write_json(path, data):
    atomic_write(path, json.dumps(data, indent=2) + "\n")


def json_template(filename):
    text = (repo / "hooks" / filename).read_text().replace(
        "/absolute/path/to/agent-completion-sounds/scripts/play-random-completion-sound.sh",
        player,
    )
    return json.loads(text)


def is_sound_hook(command):
    if not isinstance(command, str):
        return False
    return (
        command == player
        or command.endswith("/play-random-completion-sound.sh")
        or command.endswith("/play-random-completion-sound")
    )


def merge_nested_hook(path, event, group, command):
    data = load_json(path)
    hooks = data.setdefault("hooks", {})
    groups = hooks.setdefault(event, [])
    updated = False
    for item in groups:
        if isinstance(item, dict):
            for hook in item.get("hooks", []):
                if isinstance(hook, dict) and is_sound_hook(hook.get("command")):
                    hook["command"] = command
                    updated = True
    if not updated:
        groups.append(group)
    return data


cursor_path = home / ".cursor" / "hooks.json"
cursor_template = json_template("cursor-hooks.json.example")
cursor = load_json(cursor_path)
cursor.setdefault("version", cursor_template["version"])
hooks = cursor.setdefault("hooks", {})
entries = hooks.setdefault("stop", [])
updated_cursor = False
for item in entries:
    if isinstance(item, dict) and is_sound_hook(item.get("command")):
        item["command"] = player
        updated_cursor = True
if not updated_cursor:
    entries.extend(cursor_template["hooks"]["stop"])

claude_template = json_template("claude-code-stop-hook.json.snippet")
claude_path = home / ".claude" / "settings.json"
claude = merge_nested_hook(
    claude_path,
    "Stop",
    claude_template["hooks"]["Stop"][0],
    player,
)
gemini_template = json_template("gemini-cli-hooks.json.snippet")
gemini_path = home / ".gemini" / "settings.json"
gemini = merge_nested_hook(
    gemini_path,
    "AfterAgent",
    gemini_template["hooks"]["AfterAgent"][0],
    player,
)

antigravity_template = json_template("antigravity-hooks.json.snippet")
antigravity_path = home / ".gemini" / "config" / "hooks.json"
antigravity = load_json(antigravity_path)
updated_antigravity = False
for spec in antigravity.values():
    if isinstance(spec, dict):
        for entry in spec.get("Stop", []):
            if isinstance(entry, dict) and is_sound_hook(entry.get("command")):
                entry["command"] = player
                updated_antigravity = True
if not updated_antigravity:
    hook_entry = antigravity.setdefault("completion-sound", {})
    stop_list = hook_entry.setdefault("Stop", [])
    stop_list.extend(antigravity_template["completion-sound"]["Stop"])

codex_path = home / ".codex" / "config.toml"
codex_text = codex_path.read_text() if codex_path.exists() else ""
codex_template = (repo / "hooks" / "codex-cli-config.toml.snippet").read_text()
notify_line = next(line for line in codex_template.splitlines() if line.startswith("notify ="))
notify_line = notify_line.replace(
    "/absolute/path/to/agent-completion-sounds/scripts/codex-notify.sh", notifier
)
table_match = re.search(r"(?m)^\s*\[", codex_text)
table_start = table_match.start() if table_match else len(codex_text)
preamble = codex_text[:table_start]
notify_match = re.search(r"(?m)^notify\s*=", preamble)
if notify_match:
    value_start = preamble.find("[", notify_match.end())
    if value_start < 0:
        raise SystemExit("cannot update Codex notify: expected an array value")
    depth = 0
    quote = None
    escaped = False
    value_end = None
    for position in range(value_start, len(preamble)):
        character = preamble[position]
        if quote:
            if quote == '"' and character == "\\" and not escaped:
                escaped = True
                continue
            if character == quote and not escaped:
                quote = None
            escaped = False
            continue
        if character in ("'", '"'):
            quote = character
        elif character == "[":
            depth += 1
        elif character == "]":
            depth -= 1
            if depth == 0:
                value_end = position + 1
                break
    if value_end is None:
        raise SystemExit("cannot update Codex notify: unterminated array value")
    line_end = preamble.find("\n", value_end)
    value_end = len(preamble) if line_end < 0 else line_end + 1
    preamble = preamble[: notify_match.start()] + preamble[value_end:]
preamble = preamble.rstrip()
tables = codex_text[table_start:].lstrip("\n")
codex_text = notify_line + "\n"
if preamble:
    codex_text += preamble + "\n"
if tables:
    codex_text += "\n" + tables

write_json(cursor_path, cursor)
write_json(claude_path, claude)
write_json(gemini_path, gemini)
write_json(antigravity_path, antigravity)
atomic_write(codex_path, codex_text)

starter = sounds_root / "agent-completion-starter"
starter.mkdir(parents=True, exist_ok=True)
sample_rate = 44_100
tones = {
    "complete-bright.wav": (523.25, 659.25, 783.99),
    "complete-calm.wav": (392.00, 493.88, 587.33),
    "complete-soft.wav": (329.63, 415.30, 523.25),
}
for filename, frequencies in tones.items():
    destination = starter / filename
    try:
        with wave.open(str(destination)) as existing:
            if (
                existing.getnchannels() == 1
                and existing.getsampwidth() == 2
                and existing.getframerate() == sample_rate
                and existing.getnframes() > 0
            ):
                continue
    except (FileNotFoundError, EOFError, wave.Error):
        pass
    duration = 0.48
    frames = []
    for index in range(int(sample_rate * duration)):
        elapsed = index / sample_rate
        fade_in = min(1.0, elapsed / 0.025)
        fade_out = min(1.0, (duration - elapsed) / 0.14)
        envelope = max(0.0, min(fade_in, fade_out))
        value = sum(math.sin(2 * math.pi * frequency * elapsed) for frequency in frequencies)
        frames.append(struct.pack("<h", int(6_500 * envelope * value / len(frequencies))))
    fd, temporary = tempfile.mkstemp(prefix=filename + ".", dir=starter)
    os.close(fd)
    try:
        with wave.open(temporary, "wb") as output:
            output.setparams((1, 2, sample_rate, len(frames), "NONE", "not compressed"))
            output.writeframes(b"".join(frames))
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

atomic_write(
    starter / "LICENSE.txt",
    "The synthesized tones in this directory were generated locally by "
    "agent-completion-sounds and are dedicated to the public domain under CC0 1.0.\n"
    "https://creativecommons.org/publicdomain/zero/1.0/\n",
)

favorites_path = sounds_root / "favorites.txt"
favorite = "agent-completion-starter"
if favorites_path.exists():
    favorites = favorites_path.read_text().splitlines()
    if favorite not in favorites:
        favorites.append(favorite)
    atomic_write(favorites_path, "\n".join(favorites) + "\n")
PY

printf '%s\n' '{}' | "${PLAYER}" >/dev/null

printf 'Installed three CC0 starter sounds in %s\n' "${SOUNDS_ROOT}/agent-completion-starter"
printf '%s\n' 'Configured Cursor, Claude Code, Gemini CLI, Codex CLI, and Google Antigravity.'
printf '%s\n' 'Played a completion sound. Restart open agent sessions to load the new hooks.'
