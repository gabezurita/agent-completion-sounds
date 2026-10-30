# Agent Dashboard and Alfred

A click opens the menu. Sounds Enabled is the mute control. Setup does not build this app, install its login agent, or package the Alfred workflow.

## Menu bar

`ui/AgentSoundsMenu.swift` is the macOS menu-bar app. The bundle is `AgentDashboard.app` and the menu title is Agent Dashboard.

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

To keep that local app on `origin/main`, install the refresh agent:

```bash
./scripts/refresh-menu-bar-app.sh --install
```

Every 60 seconds it fetches `origin/main` in a side clone at `~/.local/share/agent-completion-sounds/src`. When `main` has moved, it rebuilds `AgentDashboard.app` into this checkout's `build/` directory. If Agent Dashboard is running, the agent quits it and opens the new bundle. If it is not running, the bundle is replaced and left quit. The checkout's branch stays as it is. A failed fetch or a failed build leaves the running app in place. GitHub Actions cannot do this step, because CI runs on Ubuntu and cannot quit the Mac app.

Remove `~/Library/LaunchAgents/com.gabo.agent-sounds-menu.refresh.plist` to stop the refresh. The side clone is `~/.local/share/agent-completion-sounds`.

## Quotas

Quota rows are optional. The menu reads `/tmp/ai_quota_collector_cache.json`. A provider block appears only when that provider's status is `ok`. Setup does not install `~/.agents/scripts/ai_quota_collector.py` or a dashboard server. Force Refresh runs that script only when the file exists. Open Web Dashboard opens `http://localhost:3333` and does not start a server.

Cursor, Antigravity, and Codex show percent meters. At or below 15% the meter is critical. Above 15% and at or below 40% it is a warning. Claude, Copilot, and OpenCode show local telemetry counts. OpenRouter shows a credits meter when the cache has one, plus monthly spend. A missing spend limit is displayed as $10. Copilot in this menu is telemetry. Hook support for Copilot and the Codex VS Code extension is in [Agents](agents.md).

Under the quota header, the menu suggests one pool among Antigravity Gemini, Antigravity Claude & GPT, Antigravity Argon, and Codex. The score is the lower of the weekly percent and the 5-hour percent. When the 5-hour window resets within 30 minutes and the week is above 40%, the score uses the week alone. A pool at 0% is skipped. A tie goes to the pool whose week resets sooner. Cursor joins that rank only when its percent is measured. A 100% bar with no recorded use stays out, because the collector writes that same shape when Cursor sends no plan usage. Claude, Copilot, OpenCode, and OpenRouter stay out of the rank.

## Alfred

`integrations/alfred/` is an Alfred 5 workflow opened with the `snd` keyword.

Keep the workflow files at `integrations/alfred/` inside the clone when you need mute, test, mode, or fetch. After Alfred imports the packaged workflow, those actions look for this repository two directories above the workflow, which is not the clone. Favorites edits and Finder still use the sounds directory. Alfred's Finder action opens `AGENT_SOUNDS_ROOT` or `~/sounds`. The menu's Finder action prefers a literal `~/sounds` when that directory exists.

Type `snd` and pick a row. The typed prefixes are `snd fav`, `snd mode`, and `snd fetch`. The bare `snd` list includes mute, a test sound, mode, favorites, Finder, and download. `snd mode` offers `session`, `session-all`, `favorites`, and `all`.

The fetch list reads `scripts/completion-sound-sets.default.txt` and stops after the first set name. Download All runs `soundfetch` with no arguments, so it downloads every set in the manifest that command resolves: `COMPLETION_SOUND_MANIFEST`, else `scripts/completion-sound-sets.txt` when that file exists, else the default manifest.

The Alfred test row sets only `AGENT_COMPLETION_SOUND_DISABLE=0` and plays a stop for conversation id `alfred-test`. The `.disabled` sentinel and the cooldown still apply. The play can stick `alfred-test`.

Package and open the workflow:

```bash
./scripts/package-alfred-workflow.sh
open "build/Agent-Completion-Sounds.alfredworkflow"
```
