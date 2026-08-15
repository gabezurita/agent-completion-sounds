# Getting started

The one-command setup gives Cursor, Claude Code, Gemini CLI, and Codex CLI one shared
completion-sound pool. It generates the starter sounds locally; it does not download
audio or require an account with a sound library.

## Requirements

- macOS or Linux
- Bash 3.2 or newer
- Python 3
- A supported audio player: `afplay` on macOS, or `paplay`/`aplay` on Linux

## Install

Keep the clone in a permanent location because agent configurations point to its
absolute path.

```bash
git clone https://github.com/gabezurita/agent-completion-sounds.git
cd agent-completion-sounds
./scripts/setup.sh
```

The command:

1. Generates three short synthesized WAV chimes in
   `~/sounds/agent-completion-starter/`. They are original project output dedicated to
   the public domain under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
2. Adds the shared player to Cursor's `stop`, Claude Code's `Stop`, and Gemini CLI's
   `AfterAgent` hooks.
3. Sets Codex CLI's user-level `notify` command.
4. Adds the starter folder to an existing `~/sounds/favorites.txt` and plays a test
   sound. If that file does not exist, it remains absent and the default full-pool
   behavior includes both existing clips and the starter sounds.

Existing JSON settings and unrelated hooks remain intact. Before changing an existing
configuration file, setup writes a sibling `.bak` copy. Running setup again is safe and
does not duplicate hooks or favorites.

To use a different sounds directory:

```bash
AGENT_SOUNDS_ROOT=/absolute/path/to/sounds ./scripts/setup.sh
```

Set `AGENT_SOUNDS_ROOT` in the environment used to launch your agents as well, so their
hooks read the same directory.

## Verify

The installer plays one chime immediately. To exercise the same shared player again:

```bash
printf '{}\n' | ./scripts/play-random-completion-sound.sh
```

Restart agent sessions that were open during installation, then complete a short turn
in each agent you use. Hook configuration is loaded by the agent, not by this project.

## Add your own sounds

Copy supported `.mp3`, `.wav`, `.aiff`, `.aif`, `.m4a`, or `.ogg` files anywhere under
`~/sounds`. This repository does not include third-party audio files. Find reusable
notification sounds on [Freesound](https://freesound.org/), preferably under CC0, or
use sounds you created or otherwise have permission to use. Check each file's license
and provide attribution when required. Avoid redistributing copyrighted game audio.

Freesound files carry individual licenses. Its
[license guide](https://freesound.org/help/faq/#licenses) explains CC0, CC BY, and CC
BY-NC; CC BY requires attribution and CC BY-NC limits commercial use. A file being
downloadable does not by itself make it safe to reuse.

Other general-purpose sources include [Pixabay Sound Effects](https://pixabay.com/sound-effects/)
under the [Pixabay Content License](https://pixabay.com/service/license-summary/) and
[Mixkit Sound Effects](https://mixkit.co/free-sound-effects/) under the
[Mixkit license](https://mixkit.co/license/). Review the applicable terms for the
specific file and your intended use.

## Customize

Use `favorites.txt` and the mode helper to select which folders participate:

```bash
./scripts/sound-mode.sh favorites
./scripts/sound-mode.sh all
./scripts/sound-mode.sh toggle
```

See the [README configuration section](README.md#configuration) for volume, disabling
playback, and the sounds-root environment variable.

## Uninstall

Remove the entries whose command points into this clone from:

- `~/.cursor/hooks.json`
- `~/.claude/settings.json`
- `~/.gemini/settings.json`
- the top-level `notify` setting in `~/.codex/config.toml`

You can then remove `~/sounds/agent-completion-starter` and its line from
`~/sounds/favorites.txt`. The `.bak` files created during the most recent setup are
available as references, but restoring one wholesale may discard newer unrelated
configuration changes.
