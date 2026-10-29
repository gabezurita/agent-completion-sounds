# Getting started

The one-command setup gives Cursor, Claude Code, Gemini CLI, Codex CLI, and Google
Antigravity one shared completion-sound pool. It generates the starter sounds locally;
it does not download audio or require an account with a sound library.

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

The command does not build Agent Dashboard, install its login agent, or package
the Alfred workflow.

1. Links `play-random-completion-sound.sh`, `play-random-completion-sound`,
   `sound-mode.sh`, `soundmode`, `codex-notify.sh`, `fetch-completion-sounds.sh`,
   and `soundfetch` into `~/.local/bin/`.
2. Generates three CC0 WAV chimes, `complete-bright.wav`, `complete-calm.wav`,
   and `complete-soft.wav`, in `~/sounds/agent-completion-starter/`. They are
   original project output under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
3. Adds the shared player to both hook edges:
   - Cursor `beforeSubmitPrompt` and `stop` in `~/.cursor/hooks.json`
   - Claude Code `UserPromptSubmit` and `Stop` in `~/.claude/settings.json`
   - Gemini CLI `BeforeAgent` and `AfterAgent` in `~/.gemini/settings.json`
   - Google Antigravity `PreInvocation` and `Stop` in `~/.gemini/config/hooks.json`
   Setup does not write a workspace `.agents/hooks.json`.
4. Sets Codex CLI's user-level `notify` command to `~/.local/bin/codex-notify.sh`.
5. Appends `agent-completion-starter` to an existing `~/sounds/favorites.txt` and
   plays a test sound. If that file does not exist, setup leaves it absent. With
   no favorites file, `session` mode searches every pack except `scratch` and
   folders whose names start with a dot.

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

The installer plays one chime. The empty-JSON command below is one session-less
play. That install chime starts the session-less cooldown, so the command can
stay silent for about 15 seconds afterward:

```bash
printf '{}\n' | ./scripts/play-random-completion-sound.sh
```

Restart agent sessions that were already open. Each agent loads its own hook
configuration.

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
[Mixkit Sound Effects](https://mixkit.co/free-sound-effects/). Read the license on
the Mixkit page before reuse.

### Curated sets (`soundfetch`)

The shipped manifest, `scripts/completion-sound-sets.default.txt`, contains one
set: `kenney-ui` (five Kenney CC0 clicks). Theme names in the agent skill are not
downloadable sets.

`soundfetch` reads `COMPLETION_SOUND_MANIFEST` when set, otherwise
`scripts/completion-sound-sets.txt` when that file exists, otherwise the default
manifest. The menu and the Alfred set list read the default file only. See
[Agent Dashboard and Alfred](README.md#agent-dashboard-and-alfred).

When `ffmpeg` is on `PATH`, `.ogg` downloads are converted to `.wav`.

```bash
soundfetch --list
soundfetch --list kenney-ui
soundfetch kenney-ui
soundfetch
```

## Customize

Use `favorites.txt` and the mode helper to select how sounds participate in your sessions. By default, the system runs in `session` mode which sticky-binds a single favorite unit per conversation.

You can customize the mode using:

```bash
./scripts/sound-mode.sh session      # bind 1 random favorite unit per conversation
./scripts/sound-mode.sh favorites    # randomize favorite units on every turn
./scripts/sound-mode.sh all          # randomize full pool on every turn
./scripts/sound-mode.sh kenney-ui    # lock all sessions to a specific unit (e.g. kenney-ui)
./scripts/sound-mode.sh toggle       # cycle through modes
./scripts/sound-mode.sh mute         # mute completion audio immediately
./scripts/sound-mode.sh unmute       # unmute completion audio
./scripts/sound-mode.sh toggle-mute  # flip mute state
./scripts/sound-mode.sh status       # show mode, mute status, and favorites count
./scripts/sound-mode.sh clear        # delete sticky session assignments
```

### macOS menu and Alfred

Build and launch for `AgentDashboard.app`, and the Alfred keyword, are in
[Agent Dashboard and Alfred](README.md#agent-dashboard-and-alfred).

See the [README configuration section](README.md#configuration) for volume,
cooldown, and the sounds-root variable.

## Uninstall

Remove the player command from these four hook files:

- `~/.cursor/hooks.json`
- `~/.claude/settings.json`
- `~/.gemini/settings.json`
- `~/.gemini/config/hooks.json`

Remove the top-level `notify` entry from `~/.codex/config.toml` when it points at
`codex-notify.sh`.

Remove the `~/.local/bin` links setup created: `play-random-completion-sound`,
`play-random-completion-sound.sh`, `soundmode`, `sound-mode.sh`, `codex-notify.sh`,
`soundfetch`, and `fetch-completion-sounds.sh`.

You can remove `~/sounds/agent-completion-starter` and its line in
`~/sounds/favorites.txt`.

Quit Agent Dashboard. If you installed login launch, remove
`~/Library/LaunchAgents/com.gabo.agent-sounds-menu.plist` and the
`~/.local/bin/agent-sounds-menu` symlink. Remove the workflow from Alfred.

The `.bak` files from the latest setup are references. Restoring one wholesale
can discard newer unrelated configuration.
