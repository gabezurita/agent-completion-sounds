# Configuration

`scripts/play-random-completion-sound.sh` picks and plays one clip. These variables control that play.

- `AGENT_SOUNDS_ROOT` is the sounds root. The default is `~/sounds`.
- `AGENT_COMPLETION_SOUND_DISABLE=1` skips playback for that process. See [Mute](modes.md#mute).
- `AGENT_COMPLETION_SOUND_PREVIEW=1` is the preview flag. See [Mute](modes.md#mute).
- `AGENT_COMPLETION_SOUND_VOLUME` is the `afplay` volume from `0.0` to `1.0`. The default is `0.45`. `ffplay` uses the same value scaled to 0 through 100. `paplay` and `aplay` ignore it.
- `AGENT_SOUND_COOLDOWN_SECS` is the cooldown in seconds. The default is 15. `0` disables both skips described under [When a sound plays](#when-a-sound-plays).
- `AGENT_SOUND_ACTIVE_WINDOW_SECS` is how long a conversation counts as live when the player avoids a pack already in use. The default is 7200 seconds.
- `AGENT_SOUND_UNIT` forces one pack for the current process and does not write `.mode`.

## When a sound plays

The player classifies each call in this order:

1. An invocation number greater than 1 (`invocationNum` or `invocation_num`) plays nothing, even when the command line says start or stop.
2. Invocation number 1, with no start or stop argument, is a start.
3. A start or stop argument wins over the JSON.
4. Otherwise a stop token (`terminationReason`, `executionNum`, `stop_reason`, or `stop`) is a stop.
5. Otherwise a start token (`userPrompt`, `beforeSubmitPrompt`, `userPromptSubmit`, `beforeAgent`, or `prompt`) is a start.
6. Every other payload is a stop. Empty JSON is this case.

While the cooldown is greater than 0, a stop is skipped when that session played a start, or any sound, inside the window. A second start inside two seconds is also skipped. That gap is fixed. It is not its own variable.

A call with no session id (`conversationId`, `conversation_id`, `session_id`, or `sessionId`) uses the shared session-less clock. Codex always takes that path. Setup's test sound uses it too, so a verify command in the next 15 seconds can be silent.

## Playback

When `python3` is on `PATH`, an `.ogg` clip uses `ffplay` if `ffplay` is on `PATH`. Any other clip, including `.ogg` without `ffplay`, tries `afplay -v`, then `paplay`, then `aplay`. Without `python3`, `setsid` on `PATH` selects `paplay`, then `aplay`. When `setsid` is absent, the player tries `afplay -v`, then `paplay`, then `aplay`.

If the chosen folders contain no supported audio and `/System/Library/Sounds/Glass.aiff` exists, that file plays. If it does not exist, the call stays silent.

## Shell profiles

Export the variables above from a shell startup file when a profile needs its own sounds root, a mute, a root shared across accounts, or a different root per workspace. One pattern is [gabezurita/gab0-system#198](https://github.com/gabezurita/gab0-system/issues/198).

Modes, mute, and sticky packs are in [Modes](modes.md).
