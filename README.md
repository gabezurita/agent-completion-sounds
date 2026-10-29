# agent-completion-sounds

[![CI](https://github.com/gabezurita/agent-completion-sounds/actions/workflows/ci.yml/badge.svg)](https://github.com/gabezurita/agent-completion-sounds/actions/workflows/ci.yml)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-donate-yellow.svg)](https://buymeacoffee.com/gabezurita)

One script plays a sound when you send a prompt and when a turn ends. Cursor, Claude Code, Gemini CLI, and Google Antigravity call that script. Codex CLI uses the same player through its `notify` command. The default mode, `session`, keeps each conversation on one sound pack. Setup writes three CC0 starter sounds and does not download a catalog.

## Quick start

Clone the repository somewhere permanent, then run:

```bash
./scripts/setup.sh
```

Setup writes three original CC0 WAV chimes, merges the five supported hook configurations, and plays a test sound. Existing configuration files are kept and backed up before a change. Restart any open agent sessions afterward.

See [GETTING_STARTED.md](GETTING_STARTED.md) for requirements, the exact file changes, verification, customization, and uninstall steps.

## What this is

- `scripts/play-random-completion-sound.sh` picks and plays one clip. Cursor, Claude Code, Gemini CLI, and Antigravity call it on both the prompt-send hook and the turn-complete hook. Event rules and playback order are under [Configuration](#configuration).
- `scripts/codex-notify.sh` drops Codex's notification argument and sends `{}` to the player. See [When a sound plays](#when-a-sound-plays).
- `scripts/sound-mode.sh` (`soundmode`) sets sticky, random, mute, and locked-pack modes. See [Favorites and mode](#favorites-and-mode).
- `ui/AgentSoundsMenu.swift` is the macOS menu-bar app. The bundle is `AgentDashboard.app` and the menu title is Agent Dashboard. See [Agent Dashboard and Alfred](#agent-dashboard-and-alfred).
- `integrations/alfred/` is an Alfred 5 workflow opened with the `snd` keyword.
- `scripts/fetch-completion-sounds.sh` (`soundfetch`) downloads sets from a manifest into the sounds root. The committed manifest contains only `kenney-ui`.

## Manual setup

1. Clone this repo somewhere permanent, for example `~/code/agent-completion-sounds`.
2. Create a sounds root and drop audio files into subfolders, or use `soundfetch` to download curated packs:

   ```bash
   mkdir -p ~/sounds/my-favorite-clips
   cp /path/to/some/*.wav ~/sounds/my-favorite-clips/
   ```

   Supported extensions: `.mp3`, `.wav`, `.aiff`, `.aif`, `.m4a`, `.ogg`. Any subfolder works. Every supported file under the sounds root is in the pool.

3. Optional: copy `sounds/favorites.txt.example` to `<sounds-root>/favorites.txt` and list the subfolder names you want in the favorites rotation.
4. Recommended: link the scripts into `~/.local/bin/` so hooks use stable paths:

   ```bash
   mkdir -p ~/.local/bin
   ln -sf "$(pwd)/scripts/play-random-completion-sound.sh" ~/.local/bin/
   ln -sf "$(pwd)/scripts/play-random-completion-sound.sh" ~/.local/bin/play-random-completion-sound
   ln -sf "$(pwd)/scripts/sound-mode.sh" ~/.local/bin/
   ln -sf "$(pwd)/scripts/sound-mode.sh" ~/.local/bin/soundmode
   ln -sf "$(pwd)/scripts/codex-notify.sh" ~/.local/bin/
   ln -sf "$(pwd)/scripts/fetch-completion-sounds.sh" ~/.local/bin/
   ln -sf "$(pwd)/scripts/fetch-completion-sounds.sh" ~/.local/bin/soundfetch
   ```

5. Point one or more hooks at `~/.local/bin/play-random-completion-sound.sh`, or at the absolute script path:

   - Cursor: copy `hooks/cursor-hooks.json.example` to `~/.cursor/hooks.json` (merge if you already have one). This sets `beforeSubmitPrompt` (when you send a request) and `stop` (when the turn completes).
   - Claude Code: merge `hooks/claude-code-stop-hook.json.snippet` into `~/.claude/settings.json` (create the file if it does not exist). This sets `UserPromptSubmit` (when you submit a prompt) and `Stop` (when the turn ends). The Claude Code VS Code extension shares this settings file, so the same hooks cover its graphical panel.
   - Gemini CLI: merge `hooks/gemini-cli-hooks.json.snippet` into `~/.gemini/settings.json`. This sets `BeforeAgent` (before the agent starts) and `AfterAgent` (once after each completed turn).
   - Google Antigravity: merge `hooks/antigravity-hooks.json.snippet` into `~/.gemini/config/hooks.json`, or into `.agents/hooks.json` in a workspace. This sets `PreInvocation` (before model execution) and `Stop` (when the execution loop ends).
   - Codex CLI: add `hooks/codex-cli-config.toml.snippet` to the user-level `~/.codex/config.toml`, pointing at `~/.local/bin/codex-notify.sh`. Put the `notify` line before the first TOML table header (any line beginning with `[`), so it stays a top-level setting rather than landing inside `[projects."..."]`, `[mcp_servers....]`, or another table. Project config cannot override notification settings.
6. Make the scripts executable if they are not already: `chmod +x scripts/*.sh`.

## Supported agent surfaces

| Surface | Status | Wiring |
| --- | --- | --- |
| Cursor | Supported | `beforeSubmitPrompt` (prompt send) and `stop` (turn complete) hooks |
| Claude Code CLI | Supported | `UserPromptSubmit` (prompt send) and `Stop` (turn complete) hooks |
| Claude Code VS Code extension | Supported | Shares the CLI's `~/.claude/settings.json` hooks |
| Gemini CLI | Supported | `BeforeAgent` (prompt send) and `AfterAgent` (turn complete) hooks |
| Google Antigravity | Supported | `PreInvocation` (prompt send) and `Stop` (turn complete) hooks in `~/.gemini/config/hooks.json` |
| Codex CLI | Supported | User-level `notify` command via adapter |
| GitHub Copilot in VS Code | Not currently supported | No documented user-scriptable completion hook |
| Codex VS Code extension | Not currently supported | No documented user-scriptable completion hook |

VS Code has no generic public event for another extension's completed agent turn. This project does not scrape extension UI state or call private APIs. See the [Gemini hooks reference](https://geminicli.com/docs/hooks/reference/), the [Codex configuration reference](https://developers.openai.com/codex/config-reference/), the [Claude Code VS Code guide](https://code.claude.com/docs/en/ide-integrations), and the [VS Code API reference](https://code.visualstudio.com/api/references/vscode-api).

## Configuration

- `AGENT_SOUNDS_ROOT` is the sounds root. The default is `~/sounds`.
- `AGENT_COMPLETION_SOUND_DISABLE=1` skips playback for that process. See [Mute](#mute).
- `AGENT_COMPLETION_SOUND_PREVIEW=1` is the preview flag. See [Mute](#mute).
- `AGENT_COMPLETION_SOUND_VOLUME` is the `afplay` volume from `0.0` to `1.0`. The default is `0.45`. `ffplay` uses the same value scaled to 0 through 100. `paplay` and `aplay` ignore it.
- `AGENT_SOUND_COOLDOWN_SECS` is the cooldown in seconds. The default is 15. `0` disables both skips described under [When a sound plays](#when-a-sound-plays).
- `AGENT_SOUND_ACTIVE_WINDOW_SECS` is how long a conversation counts as live when the player avoids a pack already in use. The default is 7200 seconds.
- `AGENT_SOUND_UNIT` forces one pack for the current process and does not write `.mode`.

### When a sound plays

The player classifies each call in this order:

1. An invocation number greater than 1 (`invocationNum` or `invocation_num`) plays nothing, even when the command line says start or stop.
2. Invocation number 1, with no start or stop argument, is a start.
3. A start or stop argument wins over the JSON.
4. Otherwise a stop token (`terminationReason`, `executionNum`, `stop_reason`, or `stop`) is a stop.
5. Otherwise a start token (`userPrompt`, `beforeSubmitPrompt`, `userPromptSubmit`, `beforeAgent`, or `prompt`) is a start.
6. Every other payload is a stop. Empty JSON is this case.

While the cooldown is greater than 0, a stop is skipped when that session played a start, or any sound, inside the window. A second start inside two seconds is also skipped. That gap is fixed. It is not its own variable.

A call with no session id (`conversationId`, `conversation_id`, `session_id`, or `sessionId`) uses the shared session-less clock. Codex always takes that path. Setup's test sound uses it too, so a verify command in the next 15 seconds can be silent.

### Playback

When `python3` is on `PATH`, an `.ogg` clip uses `ffplay` if `ffplay` is on `PATH`. Any other clip, including `.ogg` without `ffplay`, tries `afplay -v`, then `paplay`, then `aplay`. Without `python3`, `setsid` on `PATH` selects `paplay`, then `aplay`. When `setsid` is absent, the player tries `afplay -v`, then `paplay`, then `aplay`.

If the chosen folders contain no supported audio and `/System/Library/Sounds/Glass.aiff` exists, that file plays. If it does not exist, the call stays silent.

### Shell profiles

Export the variables above from a shell startup file when a profile needs its own sounds root, a mute, a root shared across accounts, or a different root per workspace. One pattern is [gabezurita/gab0-system#198](https://github.com/gabezurita/gab0-system/issues/198).

## Additional sounds

This repository does not include third-party audio. Find reusable notification sounds on [Freesound](https://freesound.org/), preferably under CC0, or use sounds you created or have permission to use. Check each file's license and give attribution when the license requires it. Do not redistribute copyrighted game audio. See [Freesound's licensing guide](https://freesound.org/help/faq/#licenses) before using a download. [GETTING_STARTED.md](GETTING_STARTED.md) also covers Pixabay and Mixkit.

## Favorites and mode

`favorites.txt` at the sounds root lists folder names, one per line. `#` starts a comment. `.mode` holds the playback mode and is read on every call.

`session` is the default. It sticks one favorites pack to each conversation. If `favorites.txt` is missing or contains only comments, that pool is every pack except `scratch` and folders whose names start with a dot. Setup appends `agent-completion-starter` only when `favorites.txt` already exists. `session-all` is its own sticky mode and draws from the full pool. `favorites` and `all` pick again on every play. A folder name in `.mode` locks every play to that pack.

A play with no session id does not stick a pack. In `session` mode the search is the whole sounds root. In `favorites` mode, when that file exists, the search is the favorites folders.

### Sound modes

| Command | What it writes |
| --- | --- |
| `soundmode` | Prints `.mode`, or `session` when the file is missing |
| `soundmode session` | `session`. Also accepts `session-favorites` and `sticky` |
| `soundmode session-all` | `session-all` |
| `soundmode favorites` | `favorites`. Also accepts `turn-favorites` |
| `soundmode all` | `all`. Also accepts `turn-all` |
| `soundmode mute` | Creates `<sounds-root>/.disabled`. Also accepts `off` and `disable`. Does not change `.mode` |
| `soundmode unmute` | Removes `.disabled`. Also accepts `on` and `enable`. Does not change `.mode` |
| `soundmode toggle-mute` | Flips `.disabled`. Also accepts `toggle-sound` |
| `soundmode status` | Prints mode, mute state, and favorites count |
| `soundmode <folder>` | Writes that folder name into `.mode` when the folder exists |
| `soundmode clear` | Deletes the session cache only. Also accepts `reset` and `clear-sessions` |
| `soundmode toggle` | `session`, then `favorites`, then `all`, then `session`. From `session-all` or a locked folder, toggle writes `session` |

```bash
alias soundmode="/absolute/path/to/agent-completion-sounds/scripts/sound-mode.sh"
```

### Mute

Playback stays quiet in three ways:

- `<sounds-root>/.disabled`. `soundmode mute` and the menu's Sounds Enabled item create or remove this file. They do not write `.mode`.
- `.mode` set to `mute`, `off`, or `disabled`. `soundmode unmute` leaves that value in place. Choosing `session`, `session-all`, `favorites`, `all`, or a folder name replaces the file and ends the latch. The menu's Playback Mode submenu can write the four named modes. It cannot write a folder lock.
- `AGENT_COMPLETION_SOUND_DISABLE=1` for the current process.

Preview (`AGENT_COMPLETION_SOUND_PREVIEW=1`) skips the sentinel and the environment variable. It still honors a mute value in `.mode`.

### Sticky packs

In `session` and `session-all`, a conversation id sticks one pack for later plays in that conversation. The cache lives in `${TMPDIR:-/tmp}/agent-sound-sessions`. On macOS that is the per-user temporary directory, unless `TMPDIR` is unset, in which case it is `/tmp`. `soundmode clear` and the menu's Reset Active Sessions delete that directory and leave `.mode` and `.disabled` alone.

A new sticky pick skips packs bound to other conversations inside `AGENT_SOUND_ACTIVE_WINDOW_SECS`. Each play refreshes that conversation's timestamp. If every favorite is already in use, the pick expands to the full pool. If every pack is in use, it picks the one whose other conversation was active least recently.

The agent skill `agent-completion-sounds` can suggest a theme name such as `sc1-medic`. Those names are not in the shipped `soundfetch` manifest, and setup does not install them.

## Agent Dashboard and Alfred

A click opens the menu. Sounds Enabled is the mute control. Setup does not build this app, install its login agent, or package the Alfred workflow.

### Menu bar

The icon is a drawn talking bot, image only, with no SF Symbol. The default style is `bot` (sound-wave arcs). Icon Style can switch to `bot-wave` (bars). Muting keeps the bot and drops the sound marks. Sounds Enabled toggles the `.disabled` sentinel.

The menu can switch among `session`, `session-all`, `favorites`, and `all`. Favorites lists Select All as Favorites, Clear All Favorites, and one item per pack. It can import a folder or audio files. Reset Active Sessions clears the sticky cache.

Play Test Sound (`Cmd+T`) sets `AGENT_COMPLETION_SOUND_PREVIEW=1`, `AGENT_COMPLETION_SOUND_DISABLE=0`, and cooldown `0`, then plays a stop for conversation id `test-ui-ping`. The preview plays while `.disabled` exists, can stick `test-ui-ping`, and leaves `.disabled` in place, so later agent turns stay silent. If the player script is missing, the menu falls back to `afplay` on a random clip and does not set those variables.

Open in Finder (`Cmd+O`) opens `~/sounds` when that directory exists. Otherwise it opens `AGENT_SOUNDS_ROOT`.

Download Curated Packs lists sets from `scripts/completion-sound-sets.default.txt` only. A named item passes that name to the fetcher. Download All Curated Sets calls the fetcher with an empty name, downloads nothing, and exits 0. The menu still shows a download-complete notification.

Build and launch:

```bash
./scripts/build-menu-bar-app.sh --link --start
```

That writes `build/AgentDashboard.app` and can link `~/.local/bin/agent-sounds-menu`. Add `--install-launchd` to write `~/Library/LaunchAgents/com.gabo.agent-sounds-menu.plist`. The bundle display name is Agent Dashboard.

### Quotas

Quota rows are optional. The menu reads `/tmp/ai_quota_collector_cache.json`. A provider block appears only when that provider's status is `ok`. Setup does not install `~/.agents/scripts/ai_quota_collector.py` or a dashboard server. Force Refresh runs that script only when the file exists. Open Web Dashboard opens `http://localhost:3333` and does not start a server.

Cursor, Antigravity, and Codex show percent meters. At or below 15% the meter is critical. Above 15% and at or below 40% it is a warning. Claude, Copilot, and OpenCode show local telemetry counts. OpenRouter shows a credits meter when the cache has one, plus monthly spend. A missing spend limit is displayed as $10. Copilot in this menu is telemetry. The support table above is the hook status for Copilot and the Codex VS Code extension.

### Alfred

Keep the workflow files at `integrations/alfred/` inside the clone when you need mute, test, mode, or fetch. After Alfred imports the packaged workflow, those actions look for this repository two directories above the workflow, which is not the clone. Favorites edits and Finder still use the sounds directory. Alfred's Finder action opens `AGENT_SOUNDS_ROOT` or `~/sounds`. The menu's Finder action prefers a literal `~/sounds` when that directory exists.

Type `snd` and pick a row. The typed prefixes are `snd fav`, `snd mode`, and `snd fetch`. The bare `snd` list includes mute, a test sound, mode, favorites, Finder, and download. `snd mode` offers `session`, `session-all`, `favorites`, and `all`.

The fetch list reads `scripts/completion-sound-sets.default.txt` and stops after the first set name. Download All runs `soundfetch` with no arguments, so it downloads every set in the manifest that command resolves: `COMPLETION_SOUND_MANIFEST`, else `scripts/completion-sound-sets.txt` when that file exists, else the default manifest.

The Alfred test row sets only `AGENT_COMPLETION_SOUND_DISABLE=0` and plays a stop for conversation id `alfred-test`. The `.disabled` sentinel and the cooldown still apply. The play can stick `alfred-test`.

Package and open the workflow:

```bash
./scripts/package-alfred-workflow.sh
open "build/Agent-Completion-Sounds.alfredworkflow"
```

## Prior art

These projects play a completion sound for a single agent.

- Claude Code: [daveschumaker/homebrew-claude-sounds](https://github.com/daveschumaker/homebrew-claude-sounds), [dgilperez/claude-sounds](https://github.com/dgilperez/claude-sounds), [alwa97/claude-code-stop-sound](https://github.com/alwa97/claude-code-stop-sound), [etr/bells-and-whistles](https://github.com/etr/bells-and-whistles)
- Cursor: [hamzafer/cursor-hooks](https://github.com/hamzafer/cursor-hooks), [bcharleson/sound-mcp](https://github.com/bcharleson/sound-mcp), [hgbdev/cursor-agent-notifier](https://github.com/hgbdev/cursor-agent-notifier)
- Curated list: [varun86/awesome-claude-code-sounds](https://github.com/varun86/awesome-claude-code-sounds)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: shellcheck clean, and no third-party audio committed to the repository.

## License

MIT. See [LICENSE](LICENSE).
