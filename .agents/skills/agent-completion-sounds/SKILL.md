---
name: agent-completion-sounds
description: >
  Allows the agent to manage, change, and suggest completion sound effects for their own active session. Includes a map of all available sound effects, their themes, and can suggest unique favorite sound effects not currently in use by other active sessions.
---

# Agent Completion Sounds Management

This skill instructs agents on how to autonomously query, suggest, and change the completion sound effect for their own active session.

Completion sounds are managed by the `agent-completion-sounds` project and are played upon the completion of every agent turn (when a hook executes). In `session` mode, the player binds a sticky favorite sound unit to each unique session/conversation using a cached file under `/tmp/agent-sound-sessions/<session_id>.unit`.

---

## How to Query and Modify Your Session Sound

To inspect or change the sound effect assigned to your active session, use the following procedures.

### 1. Identify Your Active Session File
Because multiple sessions may run concurrently, do not rely purely on file modification times. Instead, find the exact session file by matching the active chat transcript filename:
1. Locate the newest `.jsonl` transcript file under the chat folder (e.g. `/Users/gabrielzurita/.gemini/tmp/daily-feed/chats/`).
2. Extract the 8-character hash prefix at the end of the filename (before `.jsonl`).
3. Match it against the `.unit` files in the session cache directory (`/tmp/agent-sound-sessions/`).

You can find the path of your active session unit file using this Python command:
```python
import glob, os, re
latest_chat = max(glob.glob('/Users/gabrielzurita/.gemini/tmp/daily-feed/chats/*.jsonl'), key=os.path.getmtime)
prefix = re.search(r'([a-f0-9]{8})\.jsonl$', latest_chat).group(1)
unit_file = glob.glob(os.path.join(os.environ.get('TMPDIR', '/tmp'), 'agent-sound-sessions', prefix + '*.unit'))[0]
print(unit_file)
```

### 2. Read the Active Session Sound Unit
To read what sound unit is currently bound to your active session, print the contents of that unit file:
```python
import glob, os, re
latest_chat = max(glob.glob('/Users/gabrielzurita/.gemini/tmp/daily-feed/chats/*.jsonl'), key=os.path.getmtime)
prefix = re.search(r'([a-f0-9]{8})\.jsonl$', latest_chat).group(1)
unit_files = glob.glob(os.path.join(os.environ.get('TMPDIR', '/tmp'), 'agent-sound-sessions', prefix + '*.unit'))
if unit_files:
    print(open(unit_files[0]).read().strip())
else:
    print("No active session sound bound yet.")
```

### 3. Change Your Session's Sound Effect
To change your session's sound effect, write the name of the desired sound unit directory directly to your active session file:
```python
import glob, os, re
latest_chat = max(glob.glob('/Users/gabrielzurita/.gemini/tmp/daily-feed/chats/*.jsonl'), key=os.path.getmtime)
prefix = re.search(r'([a-f0-9]{8})\.jsonl$', latest_chat).group(1)
unit_files = glob.glob(os.path.join(os.environ.get('TMPDIR', '/tmp'), 'agent-sound-sessions', prefix + '*.unit'))
if unit_files:
    open(unit_files[0], 'w').write('sc1-valkyrie\n')
    print("Bound active session to sc1-valkyrie")
```

---

## Sound Effect Map & Thematic Suggestion Engine

When requested, you can suggest a fun and appropriate sound effect for the current task. To make the suggestion feel fresh and unique, **ensure the suggested unit is not currently bound to other active sessions**.

### Querying Active (In-Use) Units
Run this command to check which units are currently in use by other active sessions:
```bash
cat "${TMPDIR:-/tmp}/agent-sound-sessions/"*.unit 2>/dev/null | sort -u
```
Exclude these active units when making a new suggestion.

### Thematic Mapping

Use the following map to suggest a unit that fits the "vibe" or type of task you are performing:

| Sound Unit Folder | Game Source | Theme / Vibe | Suggested Tasks | Catchphrase / Dialogue Line |
| --- | --- | --- | --- | --- |
| `sc1-scv` | StarCraft I | Labor, Construction, Setup | Setting up packages, writing boilerplate, OS configuration | *"SCV good to go, sir!"*, *"Ah! You scared me!"* |
| `wc3-peasant` | WarCraft III | Steady Work, Refactoring | Labor-intensive refactoring, writing unit tests, cleaning code | *"Ready to work!"*, *"More work?"*, *"All right."* |
| `wc2-peon` | WarCraft II | Quick Fixes, Maintenance | Running linters, minor formatting fixes, doc updates | *"Work, work!"*, *"Jobs done!"* |
| `sc1-medic` | StarCraft I | Debugging, Repairs, Triage | Fixing test failures, troubleshooting crashes, bug hunting | *"Where does it hurt?"*, *"Stat!"*, *"Preparing medical prep."* |
| `sc1-ghost` | StarCraft I | Deletion, Security, Stealth | Deleting dead code, security reviews, git prune, secrets review | *"Somebody call for an exterminator?"*, *"Ghost reporting."* |
| `sc2-alarak` | StarCraft II | Sarcasm, Peer Review, Complexity | Code review drafts, complex planning, refactoring dirty code | *"Oh, is that what you call a plan?"*, *"Do not waste my time."* |
| `sc1-battlecruiser`| StarCraft I | Launching, Heavy Compilation | Heavy build processes, complex CI pipeline setup, massive merges | *"Battlecruiser operational."*, *"Set a course."* |
| `sc1-valkyrie` | StarCraft I | Direct Action, Automation | Script execution, batch renaming, automated deployment | *"Don't care, standard launch!"*, *"Blitzen!"* |
| `sc1-high-templar`| StarCraft I | Algorithms, Type Safety | Data structure optimization, TypeScript/Rust compiler cleanups | *"My life for Aiur!"*, *"We feel your presence."* |
| `wc3-arthas` | WarCraft III | Bold Features, Greenfield | Starting a new module, writing a feature spec, pioneering | *"For the King!"*, *"A noble cause."*, *"I will be done."* |
| `wc3-illidan` | WarCraft III | Dark Secrets, Deep Archaeology | Investigating legacy code, resolving merge conflicts | *"You are not prepared!"*, *"At last."* |
| `overwatch-ults` | Overwatch | Destruction, State Reset | Clearing caches, rebuilding DB, resetting virtualenvs | *"It's high noon!"*, *"Nerf this!"* |

---

## Workflow: How to Suggest and Apply a Sound

1. **Triage Active Sessions:** Run the check for in-use units.
2. **Context Matching:** Match your current task's focus (e.g., debugging vs. building vs. deleting) to one of the inactive candidate units.
3. **Draft the Suggestion:** Present the suggestion to the user with its associated catchphrase and explain how it matches the current workflow.
4. **Apply with Confirmation:** Ask if they'd like you to bind it. If they say yes, write that unit's folder name to the active session file!
