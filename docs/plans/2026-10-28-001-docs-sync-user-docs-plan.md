---
title: Sync User Docs to Current Behavior - Plan
type: docs
date: 2026-10-28
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# Sync User Docs to Current Behavior - Plan

## Goal Capsule

- **Objective:** Make `README.md`, `GETTING_STARTED.md`, and the Alfred workflow readme describe the player, menu, catalog, and install path as they work today.
- **Authority:** Requirements win on what a reader must be able to learn. Key technical decisions win on which file owns each claim. If a requirement disagrees with the code, stop and report it. Leave the code as it is.
- **Stop conditions:** Leave scripts, Swift, hooks, tests, and `.agents/skills/agent-completion-sounds/SKILL.md` unchanged. Do not publish a binary size, RAM figure, or CPU figure. Do not describe a host JSON payload that no in-repo fixture shows.
- **Execution:** Three prose units. `README.md` lands first. Getting Started and the Alfred readme follow it and use its headings.
- **Tail:** After the Definition of Done, the repo's usual commit and draft-PR flow applies. This plan does not choose commit text.

## Product Contract

### Summary

User docs will match the current player, `AgentDashboard.app`, the Kenney-only download catalog, and the real Alfred commands. Install docs will say what `scripts/setup.sh` changes, and what the optional menu app and Alfred workflow change.

### Problem Frame

Readers who follow the current pages get the wrong icon, the wrong mute gesture, the wrong downloads, and the wrong idea of when a sound plays. `README.md` was last aligned when the menu was documented as an SF Symbol that toggles mute, with a 160 KB binary and RTS sound packs to download. The code has since become a drawn-bot menu titled Agent Dashboard, a Kenney UI catalog, prompt-send hooks, and a cooldown classifier. `GETTING_STARTED.md` still describes setup as completion hooks only, and a Mixkit sentence is cut off by the soundfetch heading.

### Key Decisions

- Document current behavior. Leave the player, hooks, menu app, Alfred actions, and fetcher unchanged. (session-settled: user-directed. Chosen over changing behavior where the old docs promised something else, and over brainstorming the product first. The request was to correct documentation drift.)
  - **Governs:** R1 through R21.

### Requirements

#### Playback

- R1. The README opening, the player bullet, and the Why section describe one script on prompt-send and turn-complete hooks for Cursor, Claude Code, Gemini CLI, Google Antigravity, and Codex CLI, with `session` as the default mode.
- R2. The README states the event rules in `scripts/play-random-completion-sound.sh` as a first match. If the invocation number is greater than 1, play nothing, even when the command line passes `start` or `stop`. Else if the invocation number is 1 and the command line passes no event, it is a start. Else if the command line passes `start` or `stop`, that wins. Else a payload containing `terminationReason`, `executionNum`, `stop_reason`, or `stop` is a stop, then a payload containing `userPrompt`, `beforeSubmitPrompt`, `userPromptSubmit`, `beforeAgent`, or `prompt` is a start, and every other payload is a stop.
- R3. The README states the cooldown. While `AGENT_SOUND_COOLDOWN_SECS` is above 0 (default 15), a stop is skipped when that session played a start, or any sound, inside the window, and a second start inside 2 seconds is skipped. Setting the variable to 0 disables both skips. The 2-second start gap is not its own variable.
- R4. The README states playback order when `python3` is present. An `.ogg` clip uses `ffplay` when `ffplay` is on `PATH`, with volume scaled from the afplay range. Other clips use `afplay` with `AGENT_COMPLETION_SOUND_VOLUME` (default `0.45`), then `paplay`, then `aplay`. `paplay` and `aplay` ignore volume. Without `python3`, the `setsid` path tries `paplay` and then `aplay` with no volume. When the folders actually searched contain no audio, macOS plays `Glass.aiff` if that file exists, and stays silent when it does not.
- R5. The README states that `scripts/codex-notify.sh` drops Codex's argument and sends empty JSON. That turn has no session id, does not stick a unit, and shares the session-less cooldown with other session-less plays.

#### Modes and mute

- R6. The README states that `clear`, `reset`, and `clear-sessions`, and the menu item Reset Active Sessions, delete `$TMPDIR/agent-sound-sessions` and leave `.mode` and `.disabled` unchanged. On macOS that directory is the per-user temporary directory, not a literal `/tmp` path, unless `TMPDIR` is unset.
- R7. The README states the toggle cycle `session`, then `favorites`, then `all`, then `session`. `session-all` and a locked unit name fall through to `session`. The menu cannot lock a unit. Locking is `soundmode` plus a folder name, or `AGENT_SOUND_UNIT`.
- R8. The README states the sticky pool. A missing or comment-only `favorites.txt` uses every pack directory except dot-directories and `scratch`. Setup appends `agent-completion-starter` only when `favorites.txt` already exists. A payload with no `conversationId`, `conversation_id`, `session_id`, or `sessionId` does not stick, and in `session` mode the search is the whole sounds root.
- R9. The README states the three mute latches. `soundmode mute` and the Sounds Enabled item only create or remove `<sounds-root>/.disabled`. They do not write `.mode`. A `.mode` value of `mute`, `off`, or `disabled` stays silent until a real mode is written, and the menu has no control for that file. `AGENT_COMPLETION_SOUND_DISABLE=1` is the third latch.

#### Catalog, menu, and Alfred

- R10. User docs name `kenney-ui` as the only set in `scripts/completion-sound-sets.default.txt`. RTS, builder, and shooter folder names are suggestions in the agent skill, not downloads and not files setup installs. The CLI uses `COMPLETION_SOUND_MANIFEST` when set, otherwise the gitignored `scripts/completion-sound-sets.txt` when that file is beside the script, otherwise the default file. Menu and Alfred set lists read the default file only. Alfred's list stops at the first set name.
- R11. The README names the bundle `AgentDashboard.app` and the menu title Agent Dashboard. The status icon is a drawn bot. The default style is sound-wave arcs. Icon Style can switch to bars. Mute keeps the bot and drops the sound marks. A click opens the menu. Mute is the Sounds Enabled item.
- R12. The README and Getting Started remove the 160 KB, 15 MB, and 0% CPU figures and do not replace them with a measurement.
- R13. The README lists the working menu controls: playback mode, icon style, favorites with select-all and clear-all, Finder, import, per-set download, Play Test Sound, and Reset Active Sessions. It states that Download All Curated Sets calls the fetcher with an empty name, downloads nothing, exits 0, and still shows a download-complete notification. Open in Finder opens `~/sounds` when that directory exists, and opens `AGENT_SOUNDS_ROOT` only when `~/sounds` is absent.
- R14. The README describes quota rows as optional. Setup does not install a collector or a web server. The menu reads `/tmp/ai_quota_collector_cache.json`. A provider block appears only when that provider's status is `ok`. Cursor, Antigravity, and Codex show remaining-percent meters. At or below 15% the meter is critical. At or below 40% it is a warning. Claude, GitHub Copilot, and OpenCode blocks are local counts. OpenRouter shows a credits meter when the cache has one, plus monthly spend, and a missing spend limit is shown as $10. Force Refresh runs `~/.agents/scripts/ai_quota_collector.py` only when that file exists. Open Web Dashboard opens `http://localhost:3333` and does not start a server. The menu bar icon stays image-only. The support table still says GitHub Copilot has no completion-sound hook.
- R15. Menu Play Test Sound sets `AGENT_COMPLETION_SOUND_PREVIEW=1` and `AGENT_SOUND_COOLDOWN_SECS=0`, plays while `.disabled` is set, does not remove that file, and sends conversation id `test-ui-ping`, which can stick a unit in `session` mode. It still honors a `.mode` mute latch and does not unmute agents. Alfred's test row sets `AGENT_COMPLETION_SOUND_DISABLE=0` only, so the sentinel and the cooldown still apply, and it sends conversation id `alfred-test`.
- R16. The README and the Alfred workflow readme list the real `snd` surface. The bare `snd` menu holds mute, test, mode, favorites, Finder, and fetch. Typed prefixes are `fav`, `mode` (including `session-all`), and `fetch`. They do not tell the reader to type `snd toggle`, `snd test`, or `snd open`. Alfred Download All runs the fetcher with no arguments and downloads every set in the active manifest. A per-set Alfred or menu row passes the name taken from the default file.

#### Install doc

- R17. Getting Started says `scripts/setup.sh` links the player, `soundmode`, `codex-notify`, and `soundfetch` into `~/.local/bin`, writes both the prompt-send and turn-complete hooks, sets the Codex `notify` line, generates the three CC0 starter wavs, and plays one test sound. The setup list names the prompt-send events `beforeSubmitPrompt`, `UserPromptSubmit`, `BeforeAgent`, and `PreInvocation`, as well as the completion events. It does not build `AgentDashboard.app`, load the launch agent, or install the Alfred workflow. Antigravity setup writes `~/.gemini/config/hooks.json` only. A workspace `.agents/hooks.json` is a manual merge.
- R18. Getting Started says the empty-JSON verify command is one session-less play, and that agent sessions open during install must be restarted before the new hooks load.
- R19. Getting Started ends the Mixkit license sentence, then starts the soundfetch section as its own heading. That section documents the CLI, including `.ogg` to `.wav` when `ffmpeg` is on `PATH`, and follows R10 for which sets exist.
- R20. Getting Started uninstall covers the player command in the five hook files, the top-level Codex `notify` assignment, the `~/.local/bin` links setup created, and the starter directory plus its `favorites.txt` line. It also says to quit Agent Dashboard, remove launch agent `com.gabo.agent-sounds-menu` and `~/Library/LaunchAgents/com.gabo.agent-sounds-menu.plist`, remove `~/.local/bin/agent-sounds-menu`, and remove the Alfred workflow from Alfred's workflow list.
- R21. This work does not change scripts, Swift, hooks, tests, or the agent skill.

### Scope Boundaries

In scope: the three user-facing texts named in the objective, including the claim fixes from the docs audit and the later Agent Dashboard, Copilot, OpenRouter, and OpenCode menu behavior.

#### Deferred to Follow-Up Work

- Make menu Download All call the fetcher with no arguments, so the success notification matches a download.
- Forward the Codex notify payload so Codex turns can stick a voice.
- Give Alfred's test row the same preview flag as the menu.
- Make Open in Finder honor `AGENT_SOUNDS_ROOT` when `~/sounds` also exists.
- Rewrite `.agents/skills/agent-completion-sounds/SKILL.md` so it does not tell an agent to bind packs that are not installed, and so it does not depend on one machine's Gemini transcript path.
- Add a fixture before documenting Gemini `AfterAgent` or Antigravity invocation `0` as a specific event class.
- Publish a measured memory or CPU figure after a repeatable measurement exists.
- Edit `docs/superpowers/` historical plans.

### Acceptance Examples

- AE1. Covers R2, R3.
  - **Given:** a Cursor or Claude turn whose prompt-send payload classified as start.
  - **When:** the turn-complete hook runs 10 seconds later and cooldown is 15.
  - **Then:** the README says the completion sound is skipped.
- AE2. Covers R10, R13, R16.
  - **Given:** a stock clone and no local manifest override.
  - **When:** the reader compares soundfetch, the menu's Download All item, and Alfred's Download All row.
  - **Then:** the docs say the CLI and Alfred's all-row download `kenney-ui`, and the menu item downloads nothing and still shows success.
- AE3. Covers R9, R11, R15.
  - **Given:** Sounds Enabled is off, so `.disabled` exists, and `.mode` is `session`.
  - **When:** the reader uses Play Test Sound, then an agent turn ends.
  - **Then:** the docs say the preview can play, the agent turn stays silent, and the icon click was never the mute control.
- AE4. Covers R17, R20.
  - **Given:** the reader ran setup and also built the menu app with `--link --install-launchd`.
  - **When:** they follow Getting Started uninstall.
  - **Then:** the page names both the hook files and launch agent `com.gabo.agent-sounds-menu`.

## Planning Contract

### Key Technical Decisions

- KTD1. `README.md` owns runtime behavior, modes, the menu, the quota menu, and the Alfred command summary. `GETTING_STARTED.md` owns install, verify, the soundfetch CLI, and uninstall, and links to the README instead of restating the menu, the size claim, or `snd` syntax. `integrations/alfred/info.plist` owns the in-Alfred readme and matches R16.
  - **Rationale:** The same claim in two pages is how the icon, the catalog, and the hook list drifted. One page states each rule.
  - **Governs:** the file split for R1 through R20. Applies the key decision above.
- KTD2. Delete the footprint numbers. Do not write a new kilobyte, megabyte, or CPU figure.
  - **Rationale:** Nothing in source or CI records 160 KB, 15 MB, or 0% CPU. `build/` is gitignored, and `swiftc -O` output moves. A local binary size would become the next stale number.
- KTD3. State the classifier as R2, using the keys the script matches. Do not add a sentence that Gemini `AfterAgent` is a second start, or that Antigravity invocation `0` is a stop, unless a fixture under `tests/` or `hooks/` shows that payload.
  - **Rationale:** Those host shapes were inferred from the matcher. No in-repo payload confirms them. Documenting them would replace one drift with another.
- KTD4. Describe menu Download All as a no-op that still notifies success. Do not change `ui/AgentSoundsMenu.swift` or the fetcher in this work.
  - **Rationale:** The product decision leaves behavior alone. A sentence that says the menu item downloads every pack would be false.

### Sequencing

U1 edits `README.md` and leaves the headings Getting Started will link to. U2 and U3 start after U1. U2 and U3 edit different files and do not depend on each other.

### Risks

- A second copy of a rule in Getting Started will drift again. KTD1 is the control. U2 links out.
- R2 is easy to over-explain into host payload folklore. KTD3 is the control. The implementer quotes the script's keys and stops there.

### Sources

Behavior was checked in `scripts/play-random-completion-sound.sh`, `scripts/codex-notify.sh`, `scripts/sound-mode.sh`, `scripts/setup.sh`, `scripts/fetch-completion-sounds.sh`, `scripts/completion-sound-sets.default.txt`, `scripts/build-menu-bar-app.sh`, `ui/AgentSoundsMenu.swift`, `integrations/alfred/sound-alfred-filter.sh`, `integrations/alfred/sound-alfred-action.sh`, and `integrations/alfred/info.plist`. `tests/setup-test.sh`, `tests/cooldown-and-throttle-test.sh`, and `tests/fetch-completion-sounds-test.sh` lock the hook pairs, the invocation-number silence, and the default `kenney-ui` set. `docs/solutions/` does not exist, and `.agents/LEARNING_LOG.md` has no entries. `docs/superpowers/` is historical and is not a source for this text. No external research was used.

## Implementation Units

### U1. README matches the player, menu, and catalog

- **Goal:** Replace the stale README claims with R1 through R16, leaving headings that U2 can link to.
- **Requirements:** R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15, R16, R21. Decisions: KTD1, KTD2, KTD3, KTD4.
- **Dependencies:** none.
- **Files:** `README.md`
- **Approach:**
  1. Rewrite the opening, the Why paragraph, and the player bullet so they follow R1.
  2. Add the event and cooldown rules in the configuration section, following R2 and R3. Keep the heading text `Configuration` so the existing Getting Started link still resolves.
  3. Extend the playback sentence to R4 and the Codex bullet to R5.
  4. Correct the mode table so `clear` / `reset` are commands, not mode names, and add R6, R7, and R8 beside the existing session section.
  5. State the three mute latches from R9 next to the mute commands.
  6. Replace the soundfetch examples with R10. Keep the skill section as a description of the skill's suggestions, and say those names are not the shipped catalog.
  7. Replace the menu-bar subsection with R11 through R15. Use the heading `Agent Dashboard and Alfred` so U2 has a stable link. Remove every footprint number.
  8. Replace the Alfred command list with R16.
- **Patterns to follow:** The current README's H2 and H3 headings, pipe tables, and fenced shell. No emoji. `.editorconfig` is UTF-8, LF, and a final newline.
- **Test scenarios:**
  - A reader of the mode table sees `clear` delete the session cache and leave `.mode` unchanged.
  - A reader of the cooldown text sees a completion 10 seconds after a start skipped at the default of 15, and sees invocation number 2 stay silent even if the hook passed `stop`.
  - A reader of the catalog sentence sees `kenney-ui` as the shipped set and does not see RTS packs offered as `soundfetch` downloads.
  - A reader of the menu section sees a drawn bot, a click that opens the menu, no kilobyte or CPU figure, and Download All described as a success notification with no download.
  - A reader of the Alfred list does not see `snd toggle` as a typed command, and can tell the menu preview apart from the Alfred test row.
- **Verification:** `git diff` for this unit touches only `README.md`. Each scenario above is true of the new text. No script or Swift line changes.

### U2. Getting Started matches setup and uninstall

- **Goal:** Make install, verify, soundfetch, and uninstall true, and stop restating the menu and Alfred syntax.
- **Requirements:** R10, R12, R17, R18, R19, R20, R21. Decisions: KTD1, KTD2.
- **Dependencies:** U1
- **Files:** `GETTING_STARTED.md`
- **Approach:**
  1. Replace the setup step that names only completion hooks with R17.
  2. Add the R18 note beside the empty-JSON verify command.
  3. Finish the Mixkit sentence, then give soundfetch its own heading that follows R10 and R19.
  4. Replace the menu blurb with one sentence that points at the README heading `Agent Dashboard and Alfred`, names `AgentDashboard.app`, and includes no size, icon, or `snd` syntax.
  5. Extend uninstall to R20.
- **Patterns to follow:** Keep Getting Started as the short install page. Link to `README.md` anchors instead of copying tables.
- **Test scenarios:**
  - A reader of the setup list sees `beforeSubmitPrompt`, `UserPromptSubmit`, `BeforeAgent`, and `PreInvocation` as well as the completion events, and does not see the menu app or Alfred marked as installed by setup.
  - The Mixkit license sentence is complete, and the next heading is the soundfetch section.
  - The soundfetch section names `kenney-ui` and the local manifest override, and does not name RTS packs as shipped sets.
  - The uninstall list includes `~/Library/LaunchAgents/com.gabo.agent-sounds-menu.plist` and the `~/.local/bin` links from R20.
  - The page contains no `160 KB`, `15 MB`, or `0% CPU` text, and no `snd toggle` command.
- **Verification:** `git diff` for this unit touches only `GETTING_STARTED.md`. The Configuration link and the Agent Dashboard link both resolve to headings left by U1.

### U3. Alfred workflow readme matches the filter

- **Goal:** Make the in-Alfred help string follow R16.
- **Requirements:** R16, R21. Decisions: KTD1.
- **Dependencies:** U1
- **Files:** `integrations/alfred/info.plist`
- **Approach:**
  1. Replace the `readme` string so it matches the README's Alfred list from U1.
  2. Keep the string valid XML. Escape `<` in placeholders the way the current string escapes them.
  3. Leave keyword `snd`, bundle id, and script paths unchanged.
- **Patterns to follow:** The existing `readme` key is a single string of short lines inside the plist.
- **Test scenarios:**
  - The readme names `fav`, `mode` with `session-all`, and `fetch`.
  - The readme does not tell the user to type `snd toggle`, `snd test`, or `snd open`.
  - The readme says the bare `snd` menu is where mute, test, and Finder live.
  - `python3 -m plistlib` can load the file, or an equivalent XML well-formedness check succeeds. The `keyword` string remains `snd`.
- **Verification:** `git diff` for this unit touches only `integrations/alfred/info.plist`. The command list matches the README list from U1 word for word on the prefix names.

## Verification Contract

| Gate | What proves it | Expected result |
| --- | --- | --- |
| Claim check | Read U1, U2, and U3 scenarios against the edited files | Each scenario holds |
| Regression | `for f in tests/*.sh; do bash "$f"; done` from the repo root, the same loop as `.github/workflows/ci.yml` | Pass, with no test file changed |
| Scope | `git diff --stat` against the branch point | Only `README.md`, `GETTING_STARTED.md`, and `integrations/alfred/info.plist` |
| ShellCheck | Not a new gate for this work | No shell file in the diff, so the existing CI shellcheck step is unchanged |

## Definition of Done

- R1 through R20 are true of the owning file named by KTD1.
- R21 holds: the diff has no script, Swift, hook, test, or skill changes.
- AE1 through AE4 can be checked by reading the docs, without running a hook.
- The Mixkit sentence is a finished sentence, and the soundfetch heading is not inside it.
- Footprint numbers are gone and no replacement measurement was added.
- Menu Download All is described as a notification without a download.
- Temporary wording from abandoned phrasings is not left in the three files.
