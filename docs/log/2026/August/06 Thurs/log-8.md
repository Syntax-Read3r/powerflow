# Log 8 — August 6, 2026 — PMX disk and clone output contracts

**Timestamp:** 2026-08-06 UTC

**Work performed:**
- Split exact virtual-disk modeling, clone planning, and disk-growth orchestration into dedicated
  PMX components while retaining the existing adapter and amber mutation safety boundaries.
- Added exact IEC size output, boot/data roles, strict concise growth syntax, fail-closed disk
  inference, per-storage clone placement/capacity, and clone plan-versus-result JSON.
- Updated all PMX help surfaces, public documentation, issue/solved-problem records, and v4.1.0
  release notes; added parser, model, table, ambiguity, planning, and JSON regressions.

**Files modified:**
- `components/proxmox/{shared,disk-model,vm-read,clone-plan,vm-change,disk-grow,help}.ps1`
- `Microsoft.PowerShell_profile.ps1`, `COMPONENTS.md`, `README.md`, `CHANGELOG.md`
- `tests/proxmox/{parser-routing,vm-model,help-surface,output-contracts,run}.ps1`
- PMX plan, feature, troubleshooting, instruction, issue, and solved-problem documentation

**Decisions:**
- Preserve existing disk JSON properties and add fields so v4.1.0 remains a compatible minor.
- Keep equal-size growth as an idempotent no-op for desired-state scripts; reject every shrink.
- Report same-as-source placement per disk because this command does not accept target storage.

**Verification:** PMX, SRV privacy, Windows prerequisite/uninstall, and Linux download suites pass
on Windows. PMX and SRV suites also pass in the Linux PowerShell container. Every PowerShell file
parses; architecture, automatic-variable, help registry (134 commands), integrated profile/help,
private-data review, and whitespace gates pass. Real Proxmox dry runs remain pending.

**Bug status:** Bug reported: PMX disk units and clone storage placement were ambiguous, and the
only disk-growth spelling was unnecessarily long.

**Commit message:** `feat(pmx): add exact disk and clone output contracts`
