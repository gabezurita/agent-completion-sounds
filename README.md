# agent-completion-sounds

[![CI](https://github.com/gabezurita/agent-completion-sounds/actions/workflows/ci.yml/badge.svg)](https://github.com/gabezurita/agent-completion-sounds/actions/workflows/ci.yml)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-donate-yellow.svg)](https://buymeacoffee.com/gabezurita)

Play a random audio clip when a coding-agent turn ends, shared across Cursor and Claude
Code CLI from one script and one sound pool. Includes a favorites/all toggle so you can
narrow playback to a curated subset of your own clips.

This repo ships no audio. Bring your own short clips (voice lines, chimes, whatever) and
point the tool at them.

## What this is

- `scripts/play-random-completion-sound.sh` - picks and plays one random clip from your
  sounds root. Works as a Cursor `stop` hook and a Claude Code `Stop` hook at the same
  time, since both just run a shell command with JSON on stdin.
- `scripts/sound-mode.sh` - toggles between two modes:
  - `favorites` (default): only clips listed in `favorites.txt`
  - `all`: every clip under the sounds root
- Cross-platform playback: `afplay` (macOS), falling back to `paplay` or `aplay` (Linux).

## Why

Several projects already play a sound on agent completion for one tool or the other
(see Prior art below). None combine one script wired into both tools' hook systems at
once with a favorites/all toggle for curating subsets of a larger pool.

## Setup

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
4. Wire the hook:
   - Cursor: copy `hooks/cursor-hooks.json.example` to `~/.cursor/hooks.json`
     (merge if you already have one), and replace the placeholder path with the
     absolute path to `scripts/play-random-completion-sound.sh` in your clone.
   - Claude Code: merge the contents of `hooks/claude-code-stop-hook.json.snippet`
     into the `hooks` object in `~/.claude/settings.json` (create the file if it
     does not exist), same path substitution.
5. Make the scripts executable if they are not already: `chmod +x scripts/*.sh`.

## Configuration

- `AGENT_SOUNDS_ROOT` - sounds root directory (default `~/sounds`).
- `AGENT_COMPLETION_SOUND_DISABLE=1` - disable playback entirely.
- `AGENT_COMPLETION_SOUND_VOLUME=0.3` - volume for `afplay` (`0.0`-`1.0`, default `0.45`).
  Not used on the `paplay`/`aplay` fallback paths.

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

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: shellcheck clean, no bundled
audio.

## License

MIT. See [LICENSE](LICENSE).
