# Log 1 — May 19, 2026 — Session start UTC

**Work performed:**
- Diagnosed broken profile after v2.0.0 component refactor.
- Fixed root-cause scoping bug in bootloader: `_pf_source` was a function that dot-sourced component files in its own local scope, destroying every function definition when the function returned. Replaced with `_pf_path` (path resolver only) + inline dot-source at bootloader scope.
- Guarded alias removals in `operations.ps1` with `-ErrorAction SilentlyContinue` so reload does not error when aliases were already removed by a prior load.
- Rewrote `docs/instructions.md` to remove all clinician-app / mojula references and centre on PowerFlow.

**Files modified:**
- `Microsoft.PowerShell_profile.ps1` — replaced `_pf_source` function with `_pf_path` resolver; all dot-sourcing moved to bootloader scope (lines 14–20 rewritten, all 29 sourcing calls updated)
- `components/files/operations.ps1` — lines 11–13: added `-ErrorAction SilentlyContinue` to `Remove-Item Alias:rm/rmdir/mv`
- `docs/instructions.md` — full rewrite: removed clinician-app content, adapted to PowerFlow
- `docs/log/2026/May/19 Tue/log-1.md` — created (this file)

**Decisions:**
- Chose `_pf_path` (returns path, never dot-sources) over inlining path logic at every call site — keeps the missing-file warning in one place without reintroducing the scope trap.
- Kept `_pf_path` as a function (rather than a script block) because it reads more clearly and PowerShell functions don't create a child scope for their *caller's* dot-source.

**Bug status:** Bug reported: profile functions (`Check-PowerFlowUpdates`, `op`, and all others) not visible after `_pf_source`-based load due to dot-source-in-function scoping.

**Commit message:** `fix: correct bootloader scoping bug so component functions survive profile load`
