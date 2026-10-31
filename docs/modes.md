# Favorites and mode

`scripts/sound-mode.sh` (`soundmode`) sets sticky, random, mute, and locked-pack modes.

`favorites.txt` at the sounds root lists folder names, one per line. `#` starts a comment. `.mode` holds the playback mode and is read on every call.

`session` is the default. It sticks one favorites pack to each conversation. If `favorites.txt` is missing or contains only comments, that pool is every pack except `scratch` and folders whose names start with a dot. Setup appends `agent-completion-starter` only when `favorites.txt` already exists. `session-all` is its own sticky mode and draws from the full pool. `favorites` and `all` pick again on every play. A folder name in `.mode` locks every play to that pack.

A play with no session id does not stick a pack. In `session` mode the search is the whole sounds root. In `favorites` mode, when that file exists, the search is the favorites folders.

## Sound modes

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

## Mute

Playback stays quiet in three ways:

- `<sounds-root>/.disabled`. `soundmode mute` and the menu's Sounds Enabled item create or remove this file. They do not write `.mode`.
- `.mode` set to `mute`, `off`, or `disabled`. `soundmode unmute` leaves that value in place. Choosing `session`, `session-all`, `favorites`, `all`, or a folder name replaces the file and ends the latch. The menu's Playback Mode submenu can write the four named modes. It cannot write a folder lock.
- `AGENT_COMPLETION_SOUND_DISABLE=1` for the current process.

Preview (`AGENT_COMPLETION_SOUND_PREVIEW=1`) skips the sentinel and the environment variable. It still honors a mute value in `.mode`.

## Sticky packs

In `session` and `session-all`, a conversation id sticks one pack for later plays in that conversation. The cache lives in `${TMPDIR:-/tmp}/agent-sound-sessions`. On macOS that is the per-user temporary directory, unless `TMPDIR` is unset, in which case it is `/tmp`. `soundmode clear` and the menu's Reset Active Sessions delete that directory and leave `.mode` and `.disabled` alone.

A new sticky pick skips packs bound to other conversations inside `AGENT_SOUND_ACTIVE_WINDOW_SECS`. Each play refreshes that conversation's timestamp. If every favorite is already in use, the pick expands to the full pool. If every pack is in use, it picks the one whose other conversation was active least recently.

The agent skill `agent-completion-sounds` can suggest a theme name such as `sc1-medic`. Those names are not in the shipped `soundfetch` manifest, and setup does not install them. Setup does install `kenney-voice-female`, `kenney-voice-male`, `senfft-teuton`, and `senfft-germanic`.
