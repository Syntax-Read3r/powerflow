---
name: project-architecture
description: "PowerFlow component architecture after the May 2026 refactor — 28 component files, bootloader pattern, domain-organized folders"
metadata: 
  node_type: memory
  type: project
  originSessionId: <archived>
---

The 7726-line `Microsoft.PowerShell_profile.ps1` was refactored into a component architecture on 2026-05-19.

**Why:** maintainability, discoverability, React-style feature organization.

**How to apply:** When adding new functions, place them in the correct domain folder. When debugging load issues, check `IMPORT_ORDER.md` for load-order rationale.

## Structure

```
Microsoft.PowerShell_profile.ps1   ← thin 109-line bootloader (_pf_source helper)
config/
  PowerFlow.settings.ps1           ← version, flags, DB creds, $ProgressPreference
  PowerFlow.paths.ps1              ← Scoop PATH, Starship, Zoxide, auto-navigate
components/
  core/          version.ps1, dependencies.ps1, recovery.ps1
  shared/        strings.ps1 (case converters), aliases.ps1
  navigation/    bookmarks.ps1, projects.ps1, nav.ps1, directory.ps1
  files/         listing.ps1, operations.ps1, rename.ps1, clipboard.ps1
  git/           remote.ps1, commit.ps1, branches.ps1, rollback.ps1, interactive.ps1, release.ps1, reset.ps1
  github/        browser.ps1
  terminal/      tabs.ps1, wsl.ps1
  projects/      create-next.ps1 (1395 lines — large Next.js scaffold)
  system/        config-files.ps1, shutdown.ps1
  diagnostics/   (empty — reserved)
  help/          menu.ps1
docs/            commands/, architecture/, migration/ (all empty, reserved)
tests/           smoke/, manual/ (all empty, reserved)
COMPONENTS.md    ← table of all files, domains, and exported functions
IMPORT_ORDER.md  ← rationale for load order at each stage
```

## Key patterns
- Bootloader uses `$script:PowerFlowRoot = Split-Path -Parent $MyInvocation.MyCommand.Path` for portability
- `_pf_source` helper warns on missing components instead of hard-failing
- Every component file has a documentation header: Domain, File, Purpose, Functions, Depends
- `config/PowerFlow.paths.ps1` loads early (before nav) so it can remove zoxide's `z` alias before nav.ps1 redefines it
- `components/git/remote.ps1` loads before `commit.ps1` because `git-a` calls `Create-RemoteRepository`
- Startup checks (`Check-PowerFlowUpdates`, `Initialize-Dependencies`, `Check-PowerShellUpdates`) run at end of bootloader, guarded by `$script:CHECK_*` flags
