# Log 1 — August 6, 2026 — 10:22 UTC

**Work performed:**
- Read `docs/feature-pmx.md`, the delivered PMX code, repository rules, and release workflow.
- Recorded the user's requirement that substantial features remain component based.
- Created the v3.17.0 PMX VM-management plan and audited release prerequisites.
- Opened issues for two release inconsistencies and one descendant disk-use check gap.

**Files modified:**
- `docs/instructions.md` (architecture rules — added responsibility-based component splitting).
- `docs/plan/proxmox/pmx-vm-management.md` (created — scope, modular layout, chunks, rollback, tests).
- `docs/plan/issues/current-issues.md` (added Issues 3–5).
- `docs/log/2026/August/06 Thurs/log-1.md` (created).

**Decisions:**
- Target v3.17.0 because remote VM management is a backward-compatible user-facing feature.
- Use the specification's recommended first-release surface; defer red VM destruction and
  physical-disk preparation to separate safety work.
- Keep one thin `pmx` router and split implementations into ordered Proxmox components plus
  matching platform adapters.
- Do not run `git-rl`; project policy requires the human to initiate the interactive release.

**Bug status:** No bug reported by user.

**Commit message:** No commit — implementation plan is awaiting user approval.
