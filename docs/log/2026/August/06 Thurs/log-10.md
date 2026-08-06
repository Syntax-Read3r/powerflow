# Log 10 — August 6, 2026 — PMX VM network layer specification

**Timestamp:** 2026-08-06 UTC

**Work performed:**
- Audited the proposed VM network layer against existing PMX VM/config/status queries, router
  collisions, bridge discovery, adapters, strict output parser, and pending detailed VM view.
- Planned separate configured-NIC, guest-runtime, rendering, and orchestration components plus one
  fixed allow-listed guest-agent read operation on both platforms.
- Recorded canonical subject-first commands, full/root convenience aliases, address/MAC policies,
  schema-versioned JSON, failure handling, help, tests, and real-host acceptance gates.

**Files modified:**
- `docs/plan/proxmox/pmx-vm-network-inspection.md` (created)
- `docs/plan/proxmox/pmx-full-vm-view-and-output-overrides.md` (shared NIC-model dependency)
- `docs/plan/issues/current-issues.md` (Issue 19 added)
- `docs/instructions.md` (VM network source-separation rules)
- `docs/log/2026/August/06 Thurs/log-10.md` (created)

**Decisions:**
- Preserve configured and guest-observed records separately and match only by normalized MAC.
- Make root `pmx net` forms conveniences while canonical help remains `pmx vm net`/`pmx guest net`.
- Define `--all` as including all valid guest addresses, including normally hidden loopback and
  unspecified rows; never use it to trigger an undocumented fallback source.
- Emit one all-VM row per configured NIC and continue past individual agent failures.

**Bug status:** Bug reported: PMX lacks a source-separated read-only VM networking layer.

**Commit message:** No commit — implementation plan awaiting approval.
