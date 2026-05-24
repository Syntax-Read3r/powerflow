# Log 4 — May 24, 2026

**Work performed:**
- Read all project docs at user request.
- Diagnosed root cause of old v1.0.5 being installed: `releases/latest` still points to v1.0.5 because v2.x tags were pushed but the CI pipeline was never verified to have created GitHub Release objects.
- Created comprehensive plan `docs/plan/core/update-reminders.md` covering 8 chunks across 6 files:
  - `docs/instructions.md` §9 — release verification rule + CHANGELOG ordering convention
  - `README.md` — fix install URL from releases/latest to raw main branch
  - `Microsoft.PowerShell_profile.ps1` — version on startup
  - `components/core/version.ps1` — 3-option update menu + `pwsh-reminders` function
  - `components/help/menu.ps1` — add `pwsh-reminders` entry
  - `COMPONENTS.md` — update version.ps1 functions column

**Files modified:**
- `docs/plan/core/update-reminders.md` (created)
- `docs/log/2026/May/24 Sun/log-4.md` (created)

**Decisions:**
- `pwsh-reminders` chosen over `pwsh-r` to avoid conflict with the future `reload-profile` command reserved in `docs/future-dev-plan.md` Tier 1. Flagged in plan for user to decide.
- Install URL fix targets `README.md` only (not `docs/installation.md`, which already uses the correct raw URL).
- Option 3 "turn off reminders" writes directly to `config/PowerFlow.settings.ps1` via regex replace — same pattern already used by `git-release` for the version line.

**Bug status:** Bug reported: installing via `releases/latest` delivers v1.0.5 instead of current version because no GitHub Release object was created for v2.x.

**Commit message:** No commit — planning session only.
