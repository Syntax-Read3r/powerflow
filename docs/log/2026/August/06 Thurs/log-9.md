# Log 9 — August 6, 2026 — detailed PMX VM view feedback

**Timestamp:** 2026-08-06 UTC

**Work performed:**
- Audited every documented PMX read handler and confirmed it already uses the shared output-mode
  resolver with explicit option precedence over configured output.
- Confirmed the pending v4.1.0 disk work already changes the reported `8.0 GB`/`100G` examples to
  exact `8 GiB`/`100 GiB` displays.
- Planned a component-based `pmx vm show <vm> --full` model/renderer, real `-t`/`-j` convenience
  aliases, and output-mode contract tests.

**Files modified:**
- `docs/plan/proxmox/pmx-full-vm-view-and-output-overrides.md` (created)
- `docs/plan/issues/current-issues.md` (Issue 18 added)
- `docs/log/2026/August/06 Thurs/log-9.md` (created)

**Decisions:**
- Treat `-t`/`-j` as required conveniences across PMX reads, implemented through an explicit
  one-letter allow-list; continue rejecting `-table`, `-json`, bundles, and unknown shorts.
- Keep `--full` presentation-only so JSON retains one stable complete detail schema.
- Keep the compact summary and place expanded configuration in a separate full renderer.

**Bug status:** Bug reported: PMX output overrides need an explicit contract and `vm show` lacks a
detailed configuration view.

**Commit message:** No commit — implementation plan awaiting approval.
