# Plan — Version Display, Enhanced Update Prompt & `pwsh-reminders`

> **Status: Implemented** — Approved and completed 2026-05-24.

## Goal

Three related improvements shipped together:
1. Always show the current version on profile load.
2. Replace the bare `y/n/s` update prompt with a clear numbered 3-option menu; option 3 permanently disables reminders by writing to the settings file.
3. Add `pwsh-reminders` — a toggle command that lets users re-enable (or disable) update notifications at any time.
4. Fix `docs/instructions.md` §9 and `CHANGELOG.md` so release documentation never drifts out of sync with GitHub again (root cause of the old-version install bug).

---

## Root Cause Analysis — Old Version Installed

`irm .../releases/latest/download/install.ps1 | iex` resolves to the GitHub
*latest release* page. v1.0.5 is still the latest **GitHub release** because the
v2.0.0 / v2.0.1 / v2.1.0 commits were tagged and pushed, but the CI pipeline
was never verified to have completed and created the GitHub release objects.
Result: `releases/latest` still points to v1.0.5.

Fix: add a mandatory post-release verification step to `docs/instructions.md` §9,
and update the README installation command to use the `main`-branch script
(which always reflects the current codebase).

---

## Scope

**Changing:**
- `components/core/version.ps1` — enhanced `Check-PowerFlowUpdates` (numbered menu, option 3 writes settings); new `pwsh-reminders` function
- `Microsoft.PowerShell_profile.ps1` — bootloader final line includes version
- `components/help/menu.ps1` — add `pwsh-reminders` entry
- `COMPONENTS.md` — update `version.ps1` functions column
- `docs/instructions.md` — §9 release verification rule + CHANGELOG ordering clarification
- `README.md` — fix installation URL (releases/latest → main branch raw URL)

**Not changing:**
- `powerflow-update` function — the full zip-based download update is a separate task
- `config/PowerFlow.settings.ps1` — no structural change; `pwsh-reminders` writes to it at runtime
- All other component files

**Naming conflict note:** The future dev plan (`docs/future-dev-plan.md` Tier 1)
reserves `pwsh-r` for `reload-profile`. The user mentioned `pwsh-reminders` or
`pwsh-r` for this feature. To avoid the conflict, this plan uses `pwsh-reminders`
as the sole command name. If `pwsh-r` should point here instead, the future
`reload-profile` entry must be renamed (separate decision for user to make).

---

## Chunks

### Chunk 1 — `docs/instructions.md`: Release verification rule

Add to §9 after the existing release prompt block:

```markdown
### Post-release verification (mandatory)

After running `git-rl`, confirm the release was created before closing the session:

1. Open `https://github.com/Syntax-Read3r/powerflow/releases` — the new tag
   must appear as a **Release** (not just a tag) within ~3 minutes.
2. Confirm the release has the expected assets: `install.ps1`,
   `powerflow-vX.Y.Z.zip`, `RELEASE_NOTES.md`.
3. If the CI pipeline did not run or failed, do NOT mark the release complete.
   Investigate the Actions tab and re-trigger if needed.

**Never assume the tag alone is sufficient.** A git tag triggers CI; CI creates
the GitHub Release. If CI fails or does not run, `releases/latest` does not
advance and users will continue installing the previous version.
```

Also add a CHANGELOG ordering convention note:

```markdown
### CHANGELOG ordering rule

- Entries go newest-first: the in-progress version is always at the top.
- Use `## [X.Y.Z] - Unreleased` while the feature is being built.
- After post-release verification confirms the GitHub release exists, update
  the header to `## [X.Y.Z] - YYYY-MM-DD` (the actual release date).
- The generic `## [Unreleased]` section at the top is only for changes not yet
  assigned to a version number. Move its content into the versioned section
  before running `git-rl`.
```

---

### Chunk 2 — `README.md`: Fix installation URL

Change the Quick Installation one-liner from:
```
irm https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install.ps1 | iex
```
to:
```
irm https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.ps1 | iex
```

The `raw.githubusercontent.com/main` URL always reflects the current codebase and
doesn't depend on a GitHub release object existing. Apply to every occurrence in
`README.md`.

---

### Chunk 3 — `Microsoft.PowerShell_profile.ps1`: Version on startup

Change the final `Write-Host` block from:
```powershell
Write-Host "✅ PowerFlow profile loaded! Type " -NoNewline -ForegroundColor Green
Write-Host "pwsh-h" -NoNewline -ForegroundColor Yellow
Write-Host " for help" -ForegroundColor Green
```
to:
```powershell
Write-Host "✅ PowerFlow v${script:POWERFLOW_VERSION} loaded. Type " -NoNewline -ForegroundColor Green
Write-Host "pwsh-h" -NoNewline -ForegroundColor Yellow
Write-Host " for help" -ForegroundColor Green
```

This always shows the running version regardless of whether update reminders are
on or off.

---

### Chunk 4 — `components/core/version.ps1`: Enhanced update prompt

Replace the current `Read-Host "🔄 Update now? (y/n/s=skip today)"` block with
a numbered 3-option menu:

```
┌─ 🚀 PowerFlow Update Available ──────────────────────────────┐
│  v2.1.0  →  v2.2.0                                           │
│  Release notes: https://github.com/…/releases/tag/v2.2.0    │
├───────────────────────────────────────────────────────────────┤
│  1) Install now                                               │
│  2) Skip today                                               │
│  3) Turn off update reminders                                │
└───────────────────────────────────────────────────────────────┘
```

- Option `1` → calls `powerflow-update` (unchanged)
- Option `2` → writes today's date to `$updateCheckFile` (same as current `s`)
- Option `3` → permanently writes `$script:CHECK_PROFILE_UPDATES = $false` to
  `config/PowerFlow.settings.ps1` using a regex replace on the file content, then
  sets `$script:CHECK_PROFILE_UPDATES = $false` in the current session; also writes
  today's date to `$updateCheckFile` to prevent a second prompt before the profile
  is reloaded

The regex replace pattern (same one used by `git-release` for the version line):
```powershell
$settingsPath = Join-Path $script:PowerFlowRoot "config\PowerFlow.settings.ps1"
$raw = Get-Content $settingsPath -Raw
$raw = $raw -replace '\$script:CHECK_PROFILE_UPDATES\s*=\s*\$true', '$script:CHECK_PROFILE_UPDATES = $false'
Set-Content $settingsPath $raw -Encoding UTF8
```

---

### Chunk 5 — `components/core/version.ps1`: `pwsh-reminders` function

New function placed after `powerflow-version`. Behaviour:

```
pwsh-reminders         → shows current status, asks to toggle
```

Logic:
1. Read current value of `$script:CHECK_PROFILE_UPDATES`
2. Display status: `🔔 Update reminders: ON` or `🔕 Update reminders: OFF`
3. Ask: `Toggle to <opposite>? (y/n)`
4. If `y`: write the opposite value to `config/PowerFlow.settings.ps1` (same
   regex-replace as Chunk 4), update `$script:CHECK_PROFILE_UPDATES` in session
5. If turning ON: also delete `$env:TEMP\.powerflow_update_check` so the update
   check runs on next profile load (rather than waiting until tomorrow)
6. Confirm with a short success message

---

### Chunk 6 — `components/help/menu.ps1`: Add `pwsh-reminders`

Add one line to the `⚙️ CONFIGURATION & SETTINGS` block under VERSION MANAGEMENT:

```
│  pwsh-reminders          → toggle update reminder notifications on/off        │
```

---

### Chunk 7 — `COMPONENTS.md`: Update version.ps1 row

Add `pwsh-reminders` to the Functions column for `components/core/version.ps1`:

```
`components/core/version.ps1` | Core | `Check-PowerFlowUpdates`, `powerflow-update`, `Get-PowerFlowVersion`, `powerflow-version`, `pwsh-reminders`
```

---

### Chunk 8 — Log

Create `docs/log/2026/May/24 Sun/log-4.md`.

---

## Rollback

All changes are contained to source files with no external state side effects:
- `Microsoft.PowerShell_profile.ps1`: revert the `Write-Host` one-liner
- `components/core/version.ps1`: revert the prompt block; remove `pwsh-reminders`
- `components/help/menu.ps1`: remove the `pwsh-reminders` line
- `COMPONENTS.md`: revert the functions column
- `docs/instructions.md`: remove the two new sub-sections from §9

If `pwsh-reminders` has already written `CHECK_PROFILE_UPDATES = $false` to the
settings file, restore it manually or run `pwsh-reminders` again to toggle back.

---

## Testing

1. Reload profile → final line shows `✅ PowerFlow v2.1.0 loaded. Type pwsh-h for help`
2. Mock an update (temporarily set `$script:POWERFLOW_VERSION = "0.0.1"` in session, run
   `Check-PowerFlowUpdates` manually) → 3-option box appears; each option behaves correctly:
   - `1` → `powerflow-update` runs
   - `2` → daily skip file written; re-running `Check-PowerFlowUpdates` in same session exits silently
   - `3` → `config/PowerFlow.settings.ps1` now contains `$false`; re-running check exits silently
3. Run `pwsh-reminders` with reminders OFF → shows OFF status, toggle to ON → settings file has `$true`; daily skip file deleted
4. Run `pwsh-reminders` with reminders ON → shows ON status, toggle to OFF → settings file has `$false`
5. `pwsh-h` shows `pwsh-reminders` in the CONFIGURATION section
6. Verify `README.md` install URL no longer references `releases/latest/download`
