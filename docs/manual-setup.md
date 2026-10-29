# Manual setup

Use this when you are not running `scripts/setup.sh`. The one-command path is [GETTING_STARTED.md](../GETTING_STARTED.md).

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

Which surfaces can take a hook is in [Agents](agents.md).
