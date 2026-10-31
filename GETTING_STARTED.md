# Getting started

One command gives Cursor, Claude Code, Gemini CLI, Codex CLI, and Google Antigravity one shared completion-sound pool. It writes the starter sounds on this machine and downloads the CC0 voice sets from the default catalog. It does not require a sound-library account.

## Requirements

- macOS or Linux
- Bash 3.2 or newer
- Python 3
- A supported audio player: `afplay` on macOS, or `paplay` and `aplay` on Linux
- `curl`, so setup can download the CC0 voice sets
- `ffmpeg`, so setup can convert the Kenney voice clips from OGG to WAV. `afplay` cannot play OGG

## Install

Keep the clone in a permanent location. Agent configurations point at its absolute path.

```bash
git clone https://github.com/gabezurita/agent-completion-sounds.git
cd agent-completion-sounds
./scripts/setup.sh
```

On macOS, setup then runs `scripts/setup-dashboard.sh`. That builds `AgentDashboard.app` with the quota collector inside, launches the menu, and starts the quota page at `http://127.0.0.1:3333`. On Linux, setup stops after the sounds install. Setup does not load a login agent or package the Alfred workflow.

1. Links `play-random-completion-sound.sh`, `play-random-completion-sound`, `sound-mode.sh`, `soundmode`, `codex-notify.sh`, `fetch-completion-sounds.sh`, and `soundfetch` into `~/.local/bin/`.
2. Writes three CC0 WAV chimes, `complete-bright.wav`, `complete-calm.wav`, and `complete-soft.wav`, in `~/sounds/agent-completion-starter/`. They are original project output under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
3. Adds the shared player to both hook edges:
   - Cursor `beforeSubmitPrompt` and `stop` in `~/.cursor/hooks.json`
   - Claude Code `UserPromptSubmit` and `Stop` in `~/.claude/settings.json`
   - Gemini CLI `BeforeAgent` and `AfterAgent` in `~/.gemini/settings.json`
   - Google Antigravity `PreInvocation` and `Stop` in `~/.gemini/config/hooks.json`
   Setup writes that user Antigravity file only. A workspace `.agents/hooks.json` is a manual merge.
4. Sets Codex CLI's user-level `notify` command to `~/.local/bin/codex-notify.sh`.
5. Appends `agent-completion-starter` to an existing `~/sounds/favorites.txt` and plays a test sound. If that file does not exist, setup leaves it absent. With no favorites file, `session` mode searches every pack except `scratch` and folders whose names start with a dot.
6. Downloads `kenney-voice-female`, `kenney-voice-male`, `senfft-teuton`, and `senfft-germanic` from the default manifest. When `favorites.txt` exists, setup appends those folder names once.

Existing JSON settings and unrelated hooks stay intact. Before changing an existing configuration file, setup writes a sibling `.bak` copy. Running setup again is safe and does not duplicate hooks or favorites.

To use a different sounds directory:

```bash
AGENT_SOUNDS_ROOT=/absolute/path/to/sounds ./scripts/setup.sh
```

Set `AGENT_SOUNDS_ROOT` in the environment that launches your agents, so their hooks read the same directory.

## Verify

Setup's test sound is one session-less play, and it starts the session-less cooldown. The command below is the same kind of play, so it can stay silent for about 15 seconds afterward:

```bash
printf '{}\n' | ./scripts/play-random-completion-sound.sh
```

Restart agent sessions that were already open. Each agent loads its own hook configuration.

## Add your own sounds

Copy supported `.mp3`, `.wav`, `.aiff`, `.aif`, `.m4a`, or `.ogg` files anywhere under `~/sounds`. This repository does not include third-party audio. Find reusable notification sounds on [Freesound](https://freesound.org/), preferably under CC0, or use sounds you created or have permission to use. Check each file's license and give attribution when the license requires it. Do not redistribute copyrighted game audio.

The app plays whatever is in a folder under `~/sounds`. Setup only downloads the CC0 sets in the manifest. If you already have unit voices you are allowed to use, such as StarCraft, Warcraft, Dune, or Red Alert recordings, copy them into a folder there and add that folder name to `favorites.txt`.

Freesound files carry individual licenses. Its [license guide](https://freesound.org/help/faq/#licenses) explains CC0, CC BY, and CC BY-NC. CC BY requires attribution. CC BY-NC limits commercial use. A file being downloadable does not by itself make it safe to reuse.

Other general-purpose sources include [Pixabay Sound Effects](https://pixabay.com/sound-effects/) under the [Pixabay Content License](https://pixabay.com/service/license-summary/) and [Mixkit Sound Effects](https://mixkit.co/free-sound-effects/). Read the license on the Mixkit page before reuse.

### Curated sets (`soundfetch`)

The shipped manifest, `scripts/completion-sound-sets.default.txt`, contains five sets:

- `kenney-ui`: five Kenney CC0 clicks
- `kenney-voice-female` and `kenney-voice-male`: positive lines from Kenney's CC0 Voiceover Pack. Failure lines such as "you lose" and "mission failed" are left out
- `senfft-teuton` and `senfft-germanic`: Manuel Senfft's CC0 Wyrmsun unit responses (selected, acknowledge, ready, work complete, annoyed)

Theme names in the agent skill, including Blizzard folder names, are suggestions. They are not downloadable sets, and setup does not install them. Setup does install the five sets above.

`soundfetch` reads `COMPLETION_SOUND_MANIFEST` when set, otherwise `scripts/completion-sound-sets.txt` when that file exists, otherwise the default manifest. The menu and the Alfred set list read the default file only. See [Agent Dashboard and Alfred](docs/menu-and-alfred.md).

Kenney voice clips are downloaded as `.ogg`. `soundfetch` converts them to `.wav` and does not keep the `.ogg` file, because `afplay` cannot play it. Without `ffmpeg`, those clips fail to install.

```bash
soundfetch --list
soundfetch --list kenney-ui
soundfetch kenney-ui
soundfetch
```

## Customize

`session` is the default: one favorite pack per conversation. Mode, mute, and sticky-pack rules are in [Modes](docs/modes.md).

```bash
./scripts/sound-mode.sh session      # bind one random favorite pack per conversation
./scripts/sound-mode.sh favorites    # pick a favorite pack on every turn
./scripts/sound-mode.sh all          # pick from the full pool on every turn
./scripts/sound-mode.sh kenney-ui    # lock every session to one pack
./scripts/sound-mode.sh toggle       # cycle session, favorites, all
./scripts/sound-mode.sh mute         # mute
./scripts/sound-mode.sh unmute       # unmute
./scripts/sound-mode.sh toggle-mute  # flip mute
./scripts/sound-mode.sh status       # show mode, mute, and favorites count
./scripts/sound-mode.sh clear        # delete sticky session assignments
```

### macOS menu and Alfred

On a Mac, `./scripts/setup.sh` continues into the dashboard. `./scripts/setup-dashboard.sh` does that step on its own. Alfred stays in [Agent Dashboard and Alfred](docs/menu-and-alfred.md).

Volume, cooldown, and the sounds root are in [Configuration](docs/configuration.md).

## Uninstall

Remove the player command from these four hook files:

- `~/.cursor/hooks.json`
- `~/.claude/settings.json`
- `~/.gemini/settings.json`
- `~/.gemini/config/hooks.json`

Remove the top-level `notify` entry from `~/.codex/config.toml` when it points at `codex-notify.sh`.

Remove the `~/.local/bin` links setup created: `play-random-completion-sound`, `play-random-completion-sound.sh`, `soundmode`, `sound-mode.sh`, `codex-notify.sh`, `soundfetch`, and `fetch-completion-sounds.sh`.

You can remove `~/sounds/agent-completion-starter`, `kenney-voice-female`, `kenney-voice-male`, `senfft-teuton`, and `senfft-germanic`, and their lines in `~/sounds/favorites.txt`.

Quit Agent Dashboard. On macOS, stop the quota page setup started on `127.0.0.1:3333`. If you installed login launch, remove `~/Library/LaunchAgents/com.gabo.agent-sounds-menu.plist` and the `~/.local/bin/agent-sounds-menu` symlink. If you installed the main-branch refresh, remove `~/Library/LaunchAgents/com.gabo.agent-sounds-menu.refresh.plist` and `~/.local/share/agent-completion-sounds`. Remove the workflow from Alfred.

The `.bak` files from the latest setup are references. Restoring one wholesale can discard newer unrelated configuration.
