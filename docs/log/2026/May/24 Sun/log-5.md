# Log 5 — May 24, 2026

**Work performed:**
- Implemented all 8 chunks from `docs/plan/core/update-reminders.md`.

1. `docs/instructions.md` §9 — added post-release verification rule (mandatory
   GitHub Release check after git-rl) and CHANGELOG ordering convention.
2. `README.md` — replaced `releases/latest/download/install.ps1` URL with
   `raw.githubusercontent.com/main/install.ps1` so installs always resolve to the
   current codebase regardless of whether a GitHub Release exists.
3. `Microsoft.PowerShell_profile.ps1` — bootloader final line now reads
   `✅ PowerFlow v{VERSION} loaded.` instead of the generic "profile loaded" message.
4. `components/core/version.ps1` — `Check-PowerFlowUpdates`: replaced bare `y/n/s`
   Read-Host with a numbered 3-option menu; option 3 writes
   `CHECK_PROFILE_UPDATES = $false` to `config/PowerFlow.settings.ps1` via regex
   replace and sets the session variable immediately.
5. `components/core/version.ps1` — added `pwsh-reminders` function: shows current
   ON/OFF status, toggles by rewriting the settings file, clears the daily check
   marker when re-enabling so the update check fires on the very next load.
6. `components/help/menu.ps1` — added `pwsh-reminders` line in VERSION MANAGEMENT.
7. `COMPONENTS.md` — added `pwsh-reminders` to `version.ps1` functions column.
8. `docs/plan/core/update-reminders.md` — status updated to Implemented.

**Files modified:**
- `docs/instructions.md` (§9 — two new sub-sections appended)
- `README.md` (one URL replaced)
- `Microsoft.PowerShell_profile.ps1` (line 115 — version in loaded message)
- `components/core/version.ps1` (update prompt block replaced; `pwsh-reminders` added)
- `components/help/menu.ps1` (one line added under VERSION MANAGEMENT)
- `COMPONENTS.md` (`version.ps1` row updated)
- `docs/plan/core/update-reminders.md` (status set to Implemented)
- `docs/log/2026/May/24 Sun/log-5.md` (created)

**Decisions:**
- Used a plain styled list for the update menu rather than a rigid box to avoid
  alignment breakage when version strings or release URLs vary in length.
- `pwsh-reminders` deletes `$env:TEMP\.powerflow_update_check` on enable so that
  users who just re-enabled reminders are not forced to wait until tomorrow for
  the first check.
- README URL fix uses `raw.githubusercontent.com/main` — the same URL already used
  in `docs/installation.md`, making both documents consistent.

**Bug status:** Bug reported: installing via `releases/latest` delivers v1.0.5.
Fix: README URL corrected; `docs/instructions.md` now requires post-release
verification before marking a release complete.

**Commit message:** `feat(core): version on startup, 3-option update prompt, pwsh-reminders toggle`
