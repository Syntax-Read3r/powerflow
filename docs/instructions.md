# AI Agent Behavioral Instructions — PowerFlow

## Purpose

This document defines how the AI agent must behave when working on this project.
It ensures consistent documentation, logging, and maintainability across sessions
and different agents.

**These instructions are mandatory.** The agent must follow them without exception
unless explicitly overridden by a human.

---

## 1. Daily Activity Logging

### Location

```
docs/log/<YEAR>/<MONTH>/<DD DayAbbrev>/
```

- Example: `docs/log/2026/May/19 Tue/`
- The folder name is **date first, then day abbreviation** — `DD DayAbbrev`.
- Create year, month, and day subdirectories as needed.
- Each day gets its own **folder** (not a single file).

### Day Name Reference

Always compute the day of the week from the actual calendar date. **Never copy
the day abbreviation from an adjacent existing folder.** Use the table below:

| Day       | Abbreviation |
|-----------|-------------|
| Sunday    | Sun         |
| Monday    | Mon         |
| Tuesday   | Tue         |
| Wednesday | Wed         |
| Thursday  | Thurs       |
| Friday    | Fri         |
| Saturday  | Sat         |

> **Why date-first:** sorting alphabetically inside the month folder produces
> correct chronological order even when multiple different days share the same
> day-of-week abbreviation (e.g. two different Saturdays sort as `09 Sat`
> before `16 Sat`).

### Log File Naming

Inside the day folder, create a separate file for each session or task, named sequentially:

- `log-1.md`
- `log-2.md`
- `log-3.md`
- …

### Required Content per Log File

Each log file must contain:

1. **Timestamp** — start of session or task (UTC)
2. **Work performed** — what was done, files created or modified, decisions made
3. **Files modified** — list with file paths and relevant line ranges
4. **Decisions** — any non-obvious choices made and why
5. **Bug status** — must explicitly state one of:
   - `No bug reported by user`
   - `Bug reported: [brief description]`
6. **Commit message** — the conventional-commit message for this session's changes, or
   `No commit — <reason>` if no commit was made (e.g., read-only session).

### Example Log File

```markdown
# Log 1 — May 19, 2026 — 14:30 UTC

**Work performed:**
- Fixed bootloader scoping bug in `Microsoft.PowerShell_profile.ps1`.
- Added `-ErrorAction SilentlyContinue` to alias removals in `operations.ps1`.

**Files modified:**
- `Microsoft.PowerShell_profile.ps1` (lines 14–20 — `_pf_source` replaced with `_pf_path`)
- `components/files/operations.ps1` (lines 11–13 — guarded alias removals)
- `docs/log/2026/May/19 Tue/log-1.md` (created)

**Decisions:**
- Renamed `_pf_source` to `_pf_path` so dot-sourcing stays in bootloader scope.

**Bug status:** Bug reported: profile functions not visible after load.

**Commit message:** `fix: correct bootloader scoping so component functions survive load`
```

### After each interaction, update the log immediately after completing the action — do not wait for the user to ask.

---

## 2. Rule Updates (Project Memory)

### Location

`docs/instructions.md` — this file. It is the single source of truth for all agent rules.

### Rule

Every time a human gives a new rule (about behaviour, coding standards,
testing, naming, etc.), the agent must **immediately** update `docs/instructions.md`.

- Add the rule to the most relevant existing section, or create a new numbered section.
- Include the meta-rule: *"This file must be updated whenever a new rule is given."*
- Do not duplicate existing rules — check before adding.

### Example Entry

```markdown
## 8. Component Naming

- New component files must follow the kebab-case naming pattern: `my-feature.ps1`.
- Update `COMPONENTS.md` and `components/help/menu.ps1` in the same response.
```

---

## 3. Scoop Package & Dependency Tracking

### Location

`docs/installed-packages.md`

### When to Update

Every time a Scoop package, PowerShell module, or other tool dependency is added or removed.

### Required Format

| Package | Date Added | Use Case | Status |
|---------|-----------|----------|--------|
| `lsd` | 2026-05-19 | Enhanced directory listing (`ls` function) | Active |
| `fzf` | 2026-05-19 | Interactive fuzzy-search pickers throughout | Active |
| `zoxide` | 2026-05-19 | Smart directory navigation (`nav`/`z`) | Active |
| `starship` | 2026-05-19 | Cross-shell prompt with Git integration | Active |

### Status Options

| Status | Meaning |
|--------|---------|
| `Active` | Still in use |
| `Deprecated` | Installed but no longer used — document reason |
| `Removed` | Uninstalled from the project |

---

## 4. Issue Tracking

### Location

```
docs/plan/issues/
├── current-issues.md    — open and blocked issues
└── resolved-issues.md   — issues that have been fixed
```

### When to Create an Issue

Create a new entry in `current-issues.md` immediately when any of the following occur:

- A user reports a bug
- An implementation is known to be incomplete
- A directive rule cannot yet be satisfied and the reason is known

Do not wait for the user to ask. Create the issue as soon as the gap is identified.

### Required Format per Issue

```markdown
## Issue N — <short title>

**File:** `path/to/file.ps1`
**Severity:** High / Medium / Low
**Description:** What is missing or broken and why it matters.
**Blocked reason:** Why it cannot be resolved yet (omit if not blocked).

**Status:** Open | Blocked — <specific reason> | Resolved — <what was done>
```

### Auto-Move to Resolved

The moment an issue is fixed, the agent must:

1. Copy the full issue entry into `resolved-issues.md` and update its `**Status:**` line
   to `Resolved — <brief description of the fix>`.
2. Delete the entry from `current-issues.md`.
3. Do both in the same response — never leave a resolved issue in `current-issues.md`.

### Severity Guide

| Severity | Meaning |
|----------|---------|
| `High` | Breaks profile load or makes core commands unavailable |
| `Medium` | Required by convention; must be fixed before next release |
| `Low` | Quality or consistency improvement; does not block progress |

---

## 5. Behaviour Rules for the Agent

- **Check the current date** before writing to `docs/log/`. Compute the day-of-week
  abbreviation from the actual date — never copy it from an existing folder name.
  Create new folders as needed.
- **Do not overwrite existing logs.** Always create a new numbered log file.
- **Before fixing a bug**, check `docs/log/` for recent activity in that area.
  If a prior bug was reported for the same area, reference that log entry.
- **When unsure about a rule**, ask the human for clarification — do not assume.
- **Keep log reflections concise** — one or two sentences per item is sufficient.

### CLAUDE.md rules take precedence

The `CLAUDE.md` file at the repo root contains hard rules that override anything
in this document. Always read `CLAUDE.md` first. Key standing rules:

- Adding any function to `components/` → update `components/help/menu.ps1` **in the same response**.
- Also update `COMPONENTS.md` in the same response.

### 5b. Check `dependencies.ps1` Before Proposing Tools

**Before recommending or adding any new CLI tool, PowerShell module, or external
dependency, read `components/core/dependencies.ps1` first.**

- The `$requiredTools` array lists every tool PowerFlow already installs (Starship,
  fzf, zoxide, lsd, git). Do not suggest re-implementing functionality these tools
  already provide.
- If a new tool is genuinely needed, add it to `$requiredTools` in `dependencies.ps1`
  AND to `install.ps1` so it is installed immediately on fresh install — not deferred
  to the first profile load.
- Update `docs/installed-packages.md` in the same response whenever a tool is added
  or removed.

### 5a. Automatic Planning for Comprehensive Tasks

**When asked to perform a comprehensive task:**

1. **Create the plan document** in `docs/plan/<area>/<descriptive-name>.md`.
2. **Output the plan to the user** so they can read it.
3. **State clearly:** *"Plan is ready — awaiting your approval to proceed."*
4. **Stop.** Do not write any implementation code, create component files, or make
   any functional change until the human replies with explicit approval
   (e.g. "looks good", "proceed", "approved").

This is a hard stop — not a suggestion. Skipping it and implementing immediately
is a violation of this rule, even if the implementation looks correct.

A task is **comprehensive** if it meets any of the following criteria:
- Involves **3 or more files** being created or materially changed
- Spans **multiple distinct phases or chunks** of work
- Introduces or removes a **feature, integration, or system component**
- Could **break existing functionality** if any step is done in the wrong order

A task is **simple** (no plan needed) if it is:
- A rename, move, or deletion of files/folders
- A single-file config value change
- A typo or formatting fix
- A log or documentation update only

#### Plan Document Location and Format

```
docs/plan/<area>/<descriptive-name>.md
```

Examples: `docs/plan/git/rollback-ux-rework.md`, `docs/plan/navigation/fuzzy-search.md`

The plan must contain:
1. **Goal** — one-sentence description of the end state
2. **Scope** — what is changing and what is not
3. **Chunks** — numbered, ordered phases of work, each listing exact files and changes
4. **Rollback** — how to undo the change if something goes wrong
5. **Testing** — how to verify the change worked

---

## 6. Solved Problems Knowledge Base

### Location

```
docs/solved-problems/<problem-name>.md
```

### Rule

**Every time a problem reported by the user is fully resolved, the agent must
immediately create a file in `docs/solved-problems/`.** Do not wait for the user to ask.

### Requirements for each file

- **Self-contained** — a future agent reading only that file must understand the
  problem, root cause, and fix without needing project context.
- **Generic naming** — use the technology and symptom, not version numbers.
  Use `powershell-dot-source-function-scope.md`, not `v2.0.0-fix.md`.
- **No session-specific identifiers** — use generic names in code examples.

### Required file structure

```markdown
# <Technology> — <symptom in one line>

## Problem
<exact error or symptom the developer sees>

## Root cause
<why it happens — specific enough to apply to other projects>

## Solution
<exact code or config change, with generic names>

## Notes
<edge cases, caveats, or related things to watch for>
```

### Status discipline

Never write `Confirmed resolved` or `Resolved` in a solved-problems file until
the **user explicitly confirms** the issue no longer occurs. Until then, use
`Fix applied — awaiting confirmation`.

After applying a fix, ask the user: "Can you confirm whether [specific problem]
is no longer occurring?"

### Check before investigating

**Before spending any tokens diagnosing a problem, scan `docs/solved-problems/`
first.** If a matching file exists, apply the documented solution directly without
re-investigating.

---

## 7. Example Workflow

**Human says:** "Add a new `git-tag` command to list and filter tags interactively."

**Agent:**

1. Reads `docs/instructions.md` (this file) to confirm logging requirements.
2. Reads `CLAUDE.md` for standing rules (help menu and COMPONENTS.md updates).
3. Writes the code in the correct component file (`components/git/`).
4. Updates `components/help/menu.ps1` and `COMPONENTS.md` in the same response.
5. Creates `docs/log/2026/May/19 Tue/log-1.md` with a reflection.
6. Adds `No bug reported by user` to the log.

**If the human later reports a bug:**

1. Agent creates `log-2.md` in the same day folder.
2. Records `Bug reported: <brief description>`.
3. Fixes the bug and notes the fix in the same log file.
4. If the fix is non-obvious, creates `docs/solved-problems/<name>.md`.

---

## 8. Architecture Documentation

### Location

```
docs/
├── features.md           — full feature catalogue (one section per domain)
├── installation.md       — install / uninstall instructions
├── troubleshooting.md    — common issues and fixes
└── claude.integration.md — Claude Code–specific conventions for this repo
```

Component registry lives in `COMPONENTS.md` at the repo root.

### When to Update

Update the relevant doc **on the same response** as the code change that triggered it.

| If you change…                              | Update this file              |
|---------------------------------------------|-------------------------------|
| New function in any `components/` domain     | `COMPONENTS.md`, `components/help/menu.ps1` |
| Install/uninstall steps change               | `docs/installation.md`        |
| New known issue or workaround                | `docs/troubleshooting.md`     |
| New Claude Code convention for this repo     | `docs/claude.integration.md`  |
| New major feature or domain                  | `docs/features.md`            |

### PowerFlow Component Structure

```
Microsoft.PowerShell_profile.ps1   ← bootloader (_pf_path + inline dot-source)
config/
  PowerFlow.settings.ps1           ← version, flags, $script:* variables
  PowerFlow.paths.ps1              ← PATH, Starship, Zoxide, auto-navigate
components/
  core/        version, dependencies, recovery
  shared/      string helpers, shell aliases
  navigation/  bookmarks, projects search, nav/z, directory shortcuts
  files/       listing (lsd), operations, rename, clipboard
  git/         remote, commit, branches, rollback, interactive, release, reset
  github/      repo browser (gh-l)
  terminal/    tab management, WSL launchers
  projects/    Next.js scaffold (create-next)
  system/      config-file editors, shutdown timer
  help/        pwsh-h (the full command reference)
```

### Rules

- Every component file must have the standard header block: Domain, File, Purpose, Functions, Depends.
- Functions use kebab-case: `git-release`, `nav`, `copy-pwd`.
- All cross-component variables use `$script:` scope prefix.
- Do not add a new top-level component folder without updating the bootloader load order.

---

## 9. Release Prompt After New Features

### Rule

**Whenever a new user-facing feature is fully implemented** (new function, new command,
new integration), the agent must, at the end of that response:

1. **State whether the change warrants a release** — new features always do.
2. **Read `config/PowerFlow.settings.ps1`** to get the current `$script:POWERFLOW_VERSION`.
3. **Calculate the correct next version** using semver:
   - Bug fix only → **patch** bump (X.Y.Z → X.Y.Z+1)
   - New backward-compatible feature → **minor** bump (X.Y.Z → X.Y+1.0)
   - Breaking change → **major** bump (X.Y.Z → X+1.0.0)
4. **Update `CHANGELOG.md`** — add a new `## [X.Y.Z] - Unreleased` section above the
   previous latest release with bullet points describing the feature. Do this in the
   same response as the feature implementation.
5. **Prompt the user** with this exact block:

```
---
📦 Release ready — this is a <patch|minor|major> change.

Current version : vX.Y.Z
Next version    : vA.B.C

Before releasing:
  1. Review the [A.B.C] entry in CHANGELOG.md and adjust wording if needed.
  2. Run: git-rl
  3. In the fzf picker, select: <patch|minor|major>
     → git-rl will update config/PowerFlow.settings.ps1, commit, tag vA.B.C, push, and trigger CI.
---
```

### Notes

- `git-rl` is **fully interactive** — there is no CLI flag for bump type. The agent
  cannot pre-select the option. Always tell the user which option to pick.
- The agent must NOT run `git-rl` itself. Release commits must be initiated by the human.
- If a session contains both a bug fix and a new feature, use the higher bump (minor).
- The release prompt is **in addition to** the normal session log — do not skip the log.

### Post-release verification (mandatory)

After the human runs `git-rl`, the release is NOT complete until the following
is confirmed — do not close the session without verifying:

1. Open `https://github.com/Syntax-Read3r/powerflow/releases` — the new version
   must appear as a **Release** (not just a tag) within ~3 minutes.
2. Confirm the release has the expected assets attached: `install.ps1`,
   `powerflow-vX.Y.Z.zip`, `RELEASE_NOTES.md`.
3. If the CI pipeline did not run or failed, investigate the Actions tab and
   re-trigger if needed. Do NOT mark the release complete until assets exist.

**Never assume the tag push alone is sufficient.** A git tag triggers CI; CI
creates the GitHub Release object. If CI fails, `releases/latest` does not
advance and users will continue installing the previous version.

### CHANGELOG ordering rule

- Entries are **newest-first** — the in-progress version is always at the top.
- Use `## [X.Y.Z] - Unreleased` while the feature is being built.
- After post-release verification confirms the GitHub release exists, update
  the header to `## [X.Y.Z] - YYYY-MM-DD` (actual release date).
- The generic `## [Unreleased]` section at the top is only for changes not yet
  assigned to a version number. Move its contents into the versioned section
  before running `git-rl`.
