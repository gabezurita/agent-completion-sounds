# agent-completion-sounds

[![CI](https://github.com/gabezurita/agent-completion-sounds/actions/workflows/ci.yml/badge.svg)](https://github.com/gabezurita/agent-completion-sounds/actions/workflows/ci.yml)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-donate-yellow.svg)](https://buymeacoffee.com/gabezurita)

Play a random audio clip when a coding-agent turn ends, shared across Cursor, Claude
Code, Gemini CLI, and Codex CLI from one script and one sound pool. Includes three
locally generated CC0 starter sounds and a favorites/all toggle.

## Quick start

Clone the repository somewhere permanent, then run:

```bash
./scripts/setup.sh
```

The setup script generates three original CC0 WAV chimes, safely merges all four
supported hook configurations, and plays a test sound. Existing configuration files
are preserved and backed up before a change. Restart any open agent sessions afterward.

See [GETTING_STARTED.md](GETTING_STARTED.md) for requirements, exactly what changes,
verification, customization, and uninstall instructions.

## What this is

- `scripts/play-random-completion-sound.sh` - picks and plays one random clip from your
  sounds root. Works directly with Cursor `stop`, Claude Code `Stop`, and Gemini CLI
  `AfterAgent` hooks, which run a shell command with JSON on stdin.
- `scripts/codex-notify.sh` - adapts Codex CLI's argument-based `notify` command to the
  shared player's stdin contract.
- `scripts/sound-mode.sh` - toggles between two modes:
  - `favorites` (default): only clips listed in `favorites.txt`
  - `all`: every clip under the sounds root
- Cross-platform playback: `afplay` (macOS), falling back to `paplay` or `aplay` (Linux).

## Why

Several projects already play a sound on agent completion for one tool or the other
(see Prior art below). None combine one script wired into both tools' hook systems at
once with a favorites/all toggle for curating subsets of a larger pool.

## Manual setup

1. Clone this repo somewhere permanent, e.g. `~/code/agent-completion-sounds`.
2. Create a sounds root and drop audio files into subfolders:

   ```bash
   mkdir -p ~/sounds/my-favorite-clips
   cp /path/to/some/*.wav ~/sounds/my-favorite-clips/
   ```

   Supported extensions: `.mp3`, `.wav`, `.aiff`, `.aif`, `.m4a`, `.ogg`. Any subfolder
   works; every supported file under the sounds root is in the pool.

3. (Optional) Copy `sounds/favorites.txt.example` to `<sounds-root>/favorites.txt` and
   list the subfolder names you want in the favorites rotation.
4. Wire one or more hooks, replacing each placeholder with the absolute path to this
   clone:

   - Cursor: copy `hooks/cursor-hooks.json.example` to `~/.cursor/hooks.json`
     (merge if you already have one).
   - Claude Code: merge the contents of `hooks/claude-code-stop-hook.json.snippet`
     into `~/.claude/settings.json` (create the file if it does not exist). The Claude
     Code VS Code extension shares this settings file, so this also enables sounds in
     its graphical panel.
   - Gemini CLI: merge `hooks/gemini-cli-hooks.json.snippet` into
     `~/.gemini/settings.json`. The `AfterAgent` event fires once after each completed
     turn.
   - Codex CLI: add `hooks/codex-cli-config.toml.snippet` to the user-level
     `~/.codex/config.toml`. Insert the `notify` line before the first TOML table header
     (any line beginning with `[`), so it remains a top-level setting rather than becoming
     part of a `[projects."..."]`, `[mcp_servers....]`, or other table. Keep `notify` in
     the user-level config; project config cannot override notification settings.
5. Make the scripts executable if they are not already: `chmod +x scripts/*.sh`.

## Supported agent surfaces

| Surface | Status | Wiring |
| --- | --- | --- |
| Cursor | Supported | `stop` hook |
| Claude Code CLI | Supported | `Stop` hook |
| Claude Code VS Code extension | Supported | Shares the CLI's `~/.claude/settings.json` hooks |
| Gemini CLI | Supported | `AfterAgent` hook |
| Codex CLI | Supported | User-level `notify` command via adapter |
| GitHub Copilot in VS Code | Not currently supported | No documented user-scriptable completion hook |
| Codex VS Code extension | Not currently supported | No documented user-scriptable completion hook |

The unsupported VS Code rows are deliberate: VS Code does not expose a generic public
event for observing another extension's completed agent turn. This project will not
scrape extension UI state or depend on private APIs. See the upstream contracts in the
[Gemini hooks reference](https://geminicli.com/docs/hooks/reference/),
[Codex configuration reference](https://developers.openai.com/codex/config-reference/),
[Claude Code VS Code guide](https://code.claude.com/docs/en/ide-integrations), and
[VS Code API reference](https://code.visualstudio.com/api/references/vscode-api).

## Configuration

- `AGENT_SOUNDS_ROOT` - sounds root directory (default `~/sounds`).
- `AGENT_COMPLETION_SOUND_DISABLE=1` - disable playback entirely.
- `AGENT_COMPLETION_SOUND_VOLUME=0.3` - volume for `afplay` (`0.0`-`1.0`, default `0.45`).
  Not used on the `paplay`/`aplay` fallback paths.

## Additional sounds

This repository does not include third-party audio files. Find reusable notification
sounds on [Freesound](https://freesound.org/), preferably under CC0, or use sounds you
created or otherwise have permission to use. Check each file's license and provide
attribution when required. Avoid redistributing copyrighted game audio. See
[Freesound's licensing guide](https://freesound.org/help/faq/#licenses) before using a
download.

## Favorites and mode

`favorites.txt` at the root of your sounds directory lists folder names, one per line;
`#` starts a comment. `.mode` (also at the sounds root) holds `favorites` or `all`, read
fresh on every hook call, so switching takes effect immediately with no app restart:

```bash
scripts/sound-mode.sh            # show current mode
scripts/sound-mode.sh favorites  # cycle only the favorites.txt folders
scripts/sound-mode.sh all        # cycle the full sounds root
scripts/sound-mode.sh toggle     # flip between the two
```

Add a shell alias for convenience:

```bash
alias soundmode="/absolute/path/to/agent-completion-sounds/scripts/sound-mode.sh"
```

## Prior art

- Claude Code: [daveschumaker/homebrew-claude-sounds](https://github.com/daveschumaker/homebrew-claude-sounds), [dgilperez/claude-sounds](https://github.com/dgilperez/claude-sounds), [alwa97/claude-code-stop-sound](https://github.com/alwa97/claude-code-stop-sound), [etr/bells-and-whistles](https://github.com/etr/bells-and-whistles)
- Cursor: [hamzafer/cursor-hooks](https://github.com/hamzafer/cursor-hooks), [bcharleson/sound-mcp](https://github.com/bcharleson/sound-mcp), [hgbdev/cursor-agent-notifier](https://github.com/hgbdev/cursor-agent-notifier)
- Curated list: [varun86/awesome-claude-code-sounds](https://github.com/varun86/awesome-claude-code-sounds)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: shellcheck clean and no
third-party audio committed to the repository.

## License

MIT. See [LICENSE](LICENSE).
