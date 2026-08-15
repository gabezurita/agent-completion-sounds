# Cross-agent Completion Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add supported Gemini CLI, Codex CLI, and Claude Code VS Code completion-sound wiring while accurately documenting unsupported VS Code surfaces.

**Architecture:** Preserve the shared playback script and its stdin/stdout hook contract. Gemini and Claude call it directly; a thin Codex adapter translates Codex's argument-based notification invocation into that contract.

**Tech Stack:** Bash, JSON, TOML, GitHub Actions, Python standard library.

## Global Constraints

- Keep audio selection and playback in `scripts/play-random-completion-sound.sh`.
- Add no bundled audio or new dependencies.
- Do not scrape VS Code UI state or use private extension APIs.
- Every supported claim must match an official product contract.

---

### Task 1: Codex notification adapter

**Files:**
- Create: `scripts/codex-notify.sh`
- Create: `tests/codex-notify-test.sh`

**Interfaces:**
- Consumes: Codex notification JSON as optional argument `$1` and `AGENT_COMPLETION_SOUND_DISABLE`.
- Produces: Delegation to the sibling `play-random-completion-sound.sh`, with `{}` on stdout and the delegated exit status.

- [ ] **Step 1: Write the failing adapter test**

Create an executable Bash test that runs `scripts/codex-notify.sh '{"type":"agent-turn-complete"}'` with `AGENT_COMPLETION_SOUND_DISABLE=1`, captures stdout, and fails unless stdout is exactly `{}`.

- [ ] **Step 2: Verify the test fails for the missing adapter**

Run: `bash tests/codex-notify-test.sh`

Expected: non-zero with `scripts/codex-notify.sh: No such file or directory`.

- [ ] **Step 3: Implement the minimal adapter**

Create an executable Bash script with `set -euo pipefail`, resolve its directory with `BASH_SOURCE[0]`, ignore the optional Codex payload, and pipe `{}` into the sibling shared player.

- [ ] **Step 4: Verify the adapter test passes**

Run: `bash tests/codex-notify-test.sh`

Expected: `codex notify adapter: PASS` and exit 0.

### Task 2: Configuration examples and documentation

**Files:**
- Create: `hooks/gemini-cli-hooks.json.snippet`
- Create: `hooks/codex-cli-config.toml.snippet`
- Modify: `README.md`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Gemini `AfterAgent`, Codex `notify`, and Claude Code shared settings contracts.
- Produces: Copyable JSON/TOML snippets and an explicit support matrix.

- [ ] **Step 1: Extend CI before adding examples**

Set up Python 3.11, add checks that require and parse `hooks/*.toml.snippet` with `tomllib`, execute every `tests/*.sh`, and include those test scripts in Bash syntax checking and executable-bit checks.

- [ ] **Step 2: Verify CI-equivalent checks fail**

Run the new TOML parser and `bash tests/codex-notify-test.sh` before creating the configuration files.

Expected: adapter test passes; a direct existence assertion for both planned hook files fails.

- [ ] **Step 3: Add the hook examples**

Add a Gemini settings fragment using `hooks.AfterAgent`, matcher `*`, type `command`, and the shared player path. Add a Codex user config fragment setting `notify = ["/absolute/path/to/agent-completion-sounds/scripts/codex-notify.sh"]`.

- [ ] **Step 4: Update README**

Describe the three supported integrations, add setup steps for Gemini and Codex, state that Claude CLI configuration also covers its VS Code extension, and add a support matrix marking Copilot VS Code and Codex VS Code unsupported because no documented user-scriptable completion hook exists.

- [ ] **Step 5: Run repository verification**

Run ShellCheck, `bash -n` over scripts and tests, JSON parsing, TOML parsing, shell tests, executable checks, and `git diff --check`.

Expected: all commands exit 0 with the adapter test reporting PASS.

### Task 3: Follow-up tracking and delivery

**Files:**
- No repository files.

**Interfaces:**
- Consumes: the support limitations documented in Task 2.
- Produces: a new GitHub issue and a pushed feature branch.

- [ ] **Step 1: Open the VS Code workaround issue**

Create an issue in `gabezurita/agent-completion-sounds` that scopes an upstream Copilot/VS Code contribution, a Codex app-server/public API investigation, a standalone companion-extension feasibility check, and an explicit ban on UI scraping/private APIs.

- [ ] **Step 2: Review the final diff**

Run `git status --short`, `git diff --check`, and inspect `git diff main...HEAD` plus uncommitted changes for scope and correctness.

- [ ] **Step 3: Commit and push**

Stage only the implementation, docs, config examples, tests, and CI files; commit with `feat: add cross-agent completion hooks`; then push `feat/cross-agent-hooks` to origin.
