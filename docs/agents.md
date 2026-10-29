# Agents

Cursor, Claude Code, Gemini CLI, and Google Antigravity call `scripts/play-random-completion-sound.sh` on both the prompt-send hook and the turn-complete hook. Codex CLI uses `scripts/codex-notify.sh`, which drops Codex's notification argument and sends `{}` to the same player. Event rules are in [Configuration](configuration.md#when-a-sound-plays).

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

Hand-merging those hooks is in [Manual setup](manual-setup.md). `scripts/setup.sh` writes them for you. See [GETTING_STARTED.md](../GETTING_STARTED.md).
