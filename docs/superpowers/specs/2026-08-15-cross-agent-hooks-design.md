# Cross-agent completion hooks design

## Goal

Extend completion sounds to every requested agent surface that exposes a supported command hook, and clearly document the surfaces that do not. Keep audio selection and playback in the existing shared script.

## Supported integrations

- Gemini CLI uses its `AfterAgent` hook. Its JSON stdin and JSON stdout contract is compatible with the shared player.
- Codex CLI uses the user-level `notify` command. Codex passes its JSON notification payload as a command-line argument, so a thin adapter will supply JSON on stdin to the shared player.
- The Claude Code VS Code extension shares `~/.claude/settings.json` with the CLI, so the existing `Stop` hook config covers both surfaces.

GitHub Copilot in VS Code and the Codex VS Code extension have no documented user-scriptable completion hook. The README will list them as unsupported rather than imply that their CLI hooks cover them.

## Repository changes

- Add a Gemini CLI JSON settings snippet under `hooks/`.
- Add a Codex CLI TOML config snippet under `hooks/`.
- Add a Codex notification adapter under `scripts/`; it ignores Codex-specific payload contents and delegates playback to the shared script.
- Update the README introduction, setup instructions, support matrix, and limitations.
- Extend CI to parse TOML snippets and exercise the adapter without playing audio.
- Open a separate repository issue for a VS Code workaround or upstream contribution.

## Error handling

The adapter resolves the shared player relative to itself, so moving the cloned repository does not break internal delegation. It forwards the shared script's exit status. The existing disable environment variable provides a deterministic, side-effect-free verification path.

## Testing

Add a shell test that invokes the adapter with a representative Codex JSON argument while playback is disabled and asserts that it emits the shared hook's `{}` response. CI will continue shell syntax and ShellCheck validation, validate every JSON example/snippet, parse TOML snippets with Python's standard `tomllib`, run the adapter test, and verify executable bits.

## Follow-up issue

The follow-up will investigate an open-source VS Code workaround. It will distinguish two paths:

- Copilot Chat is open source in VS Code, so propose or contribute an upstream completion event/hook.
- The Codex CLI/app-server is open source, but the Codex VS Code extension is not currently open source; investigate an app-server event or public VS Code API and track the upstream extension-source request rather than promising a direct extension PR.

The companion extension must not scrape UI state or depend on private extension APIs.
