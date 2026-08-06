# Log 6 — August 6, 2026 — PMX help completeness audit

**Work performed:**
- Compared the complete PMX router with every management, VM mutation, snapshot, virtual-disk,
  local-host, and physical-disk argument parser.
- Confirmed that the overview omitted required selectors and values, while detailed topics missed
  several accepted named/positional forms and whole help families.
- Accepted the follow-up syntax decision: commands already under `pmx vm` take the VM selector
  directly and reject redundant `--vm`; disk/snapshot commands retain it for ownership clarity.
- Replaced the hand-written overview with a 31-row executable catalog, added complete detailed
  family/action/alias topics, and pinned both rendered output and parser behavior in regression.
- Distinguished the implemented first-release surface from later `feature-pmx.md` designs so
  unimplemented profile, reboot, rollback/delete, network, autostart, protection, tag, and note
  commands are not falsely advertised.
- Prepared v4.0.0 release notes because removing an accepted option is a breaking change.
- Created the approved implementation plan and recorded the executable-help rule.

**Files modified:**
- `docs/plan/proxmox/pmx-help-command-inventory.md` (created)
- `docs/plan/issues/current-issues.md` (Issue 15 added)
- `docs/instructions.md` (executable PMX help rule)
- `docs/log/2026/August/06 Thurs/log-6.md` (created)
- `components/proxmox/vm-read.ps1`, `components/proxmox/vm-change.ps1`,
  `components/proxmox/command.ps1` (VM-first syntax)
- `components/proxmox/help.ps1`, `tests/proxmox/help-surface.ps1` (complete help inventory)
- `README.md`, `docs/feature-pmx.md`, `CHANGELOG.md` (syntax and v4.0.0 release docs)

**Bug status:** Fix applied — awaiting user confirmation.

**Verification:** PMX, SRV, Linux GitHub-download, and Windows prerequisite suites pass. Every
PowerShell file parses; architecture, automatic-variable, help registry (134 commands), adapter
parity (84 calls), rendered help, redundant-option scrub, v4.0.0 changelog extraction, workflow
YAML, and whitespace gates pass.

**Commit message:** `feat(pmx)!: make help complete and simplify VM selectors`
