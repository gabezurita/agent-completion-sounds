# agent-completion-sounds

[![CI](https://github.com/gabezurita/agent-completion-sounds/actions/workflows/ci.yml/badge.svg)](https://github.com/gabezurita/agent-completion-sounds/actions/workflows/ci.yml)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-donate-yellow.svg)](https://buymeacoffee.com/gabezurita)

One script plays a sound when you send a prompt and when a turn ends. It runs universally across Cursor, Claude Code, Gemini CLI, Google Antigravity, and Codex CLI.

## Quick start

Clone the repository somewhere permanent, then run:

```bash
./scripts/setup.sh
```

Setup writes three original CC0 WAV chimes, merges the five supported hook configurations, and plays a test sound. Existing configuration files are kept and backed up before a change. Restart any open agent sessions afterward.

## Guides

| Guide | What it covers |
| --- | --- |
| [Getting started](GETTING_STARTED.md) | Requirements, what setup changes, verify, add sounds, uninstall |
| [Manual setup](docs/manual-setup.md) | Hook files and script links without running setup |
| [Agents](docs/agents.md) | Which surfaces can play a sound |
| [Configuration](docs/configuration.md) | When a sound plays, volume, playback |
| [Modes](docs/modes.md) | Favorites, mute, sticky packs |
| [Agent Dashboard and Alfred](docs/menu-and-alfred.md) | Menu bar, quotas, `snd` workflow |

The docs index and the engineering taxonomy are in [docs/README.md](docs/README.md).

## Prior art

These projects play a completion sound for a single agent.

- Claude Code: [daveschumaker/homebrew-claude-sounds](https://github.com/daveschumaker/homebrew-claude-sounds), [dgilperez/claude-sounds](https://github.com/dgilperez/claude-sounds), [alwa97/claude-code-stop-sound](https://github.com/alwa97/claude-code-stop-sound), [etr/bells-and-whistles](https://github.com/etr/bells-and-whistles)
- Cursor: [hamzafer/cursor-hooks](https://github.com/hamzafer/cursor-hooks), [bcharleson/sound-mcp](https://github.com/bcharleson/sound-mcp), [hgbdev/cursor-agent-notifier](https://github.com/hgbdev/cursor-agent-notifier)
- Curated list: [varun86/awesome-claude-code-sounds](https://github.com/varun86/awesome-claude-code-sounds)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: shellcheck clean, and no third-party audio committed to the repository.

## License

MIT. See [LICENSE](LICENSE).
