# Log 11 — August 6, 2026 — 15:54 UTC

**Work performed:**
- Implemented the approved read-only PMX VM network layer with goal-based canonical commands,
  `net`/`nic`/`ip` conveniences, strict short options, source-separated table/JSON output, traffic
  stats, agent-state handling, MAC-only matching, and inferred primary-address selection.
- Added the fixed VM-agent query to both platform management adapters, complete PMX help/registry
  coverage, documentation, v4.1.0 changelog notes, issue closure, and a reusable solved-problem note.
- Verified the PMX, SRV privacy, and Windows prerequisite suites on Windows; PMX regressions and
  all-PowerShell parsing in a Linux PowerShell container; profile/registry/help integration; and
  the repository's platform-separation, automatic-variable, and help-registration gates.

**Files modified:**
- `components/proxmox/network-config-model.ps1` (lines 1–111 — configured adapters and agent state)
- `components/proxmox/guest-network-model.ps1` (lines 1–222 — addresses, stats, matching, ranking)
- `components/proxmox/network-view.ps1` (lines 1–261 — tables and stable JSON contracts)
- `components/proxmox/network-read.ps1` (lines 1–291 — parser, reads, failure states, aliases, registry)
- `components/proxmox/command.ps1` and `Microsoft.PowerShell_profile.ps1` (VM routes and load order)
- `platform/windows/adapters/proxmox-management.ps1` and
  `platform/linux/adapters/proxmox-management.ps1` (allow-listed query and safe failure categories)
- `components/proxmox/help.ps1` (lines 82–132, 228–239, 334–344 — network topics and overview)
- `tests/proxmox/network-contracts.ps1`, `adapter-contract.ps1`, `parser-routing.ps1`,
  `help-surface.ps1`, and `run.ps1` (models, JSON purity, runtime gates, routing, help, adapter parity)
- `README.md`, `docs/features.md`, `docs/troubleshooting.md`, `COMPONENTS.md`, and `CHANGELOG.md`
  (public syntax, architecture, troubleshooting, and v4.1.0 release notes)
- `docs/instructions.md`, `docs/plan/proxmox/pmx-vm-network-inspection.md`, issue trackers, and
  `docs/solved-problems/proxmox-vm-network-source-confusion.md` (project rules and implementation record)
- `docs/log/2026/August/06 Thurs/log-11.md` (created)

**Decisions:**
- Public PMX vocabulary is `network`, `adapters`, `addresses`, and `stats`; the underlying native
  VM-agent command is emitted only for explicit `--show-native` requests.
- Configuration and VM-reported facts stay separate and join only through one valid MAC on each
  side. A primary address is an inference, never an SSH or reachability claim.
- A stopped/template/disabled/unavailable VM preserves configured output, and one failed VM remains
  visible rather than aborting the all-VM inventory.

**Bug status:** No bug reported by user

**Commit message:** No commit — implementation awaits real-host acceptance and the user-initiated release workflow.
