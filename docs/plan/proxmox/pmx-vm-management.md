# PowerFlow PMX — modular VM management

**Status:** Implemented and locally verified — v3.17.0 release verification pending
**Target release:** v3.17.0 (minor, from current v3.16.2; v3.16.2 tag failed and was not published)
**Source:** `docs/feature-pmx.md`, layered onto the delivered v3.16.x host/disk `pmx`

## Goal

Extend `pmx` into a safe, educational Proxmox VM-management command that works locally on a
Proxmox node or through a saved SSH target, without regressing the existing dashboard,
physical-disk, SMART, evidence, or capacity-test workflows.

## Scope

### Included in v3.17.0

- Preserve all existing commands: bare `pmx`, physical `pmx disk <selector>`, `pmx disks`,
  pools/storage, guests, updates, SMART tests, evidence bundles, and the F3 safety gate.
- Split the 640-line Proxmox component into small responsibility-based components. The final
  `pmx` dispatcher only parses and routes; it does not contain implementations.
- Add strict GNU-style argument parsing with exact long option names, no abbreviation, no
  duplicate option ambiguity, and a hard error for unknown or missing values.
- Add configuration and discovery:
  - `pmx config show|set|reset|validate|discover`
  - `pmx discover`, `pmx node status`, `pmx storage list`
  - local transport on a Proxmox node and SSH transport elsewhere through a saved `srv` alias
- Add the specification's recommended first-release VM surface:
  - `pmx vm list|show|status|next-id`
  - `pmx vm clone`
  - `pmx vm cpu set`, `pmx vm memory set`
  - `pmx disk list|grow --vm <id-or-name>`
  - `pmx vm start|shutdown`
  - `pmx snapshot list|create`
- Resolve a friendly VM name uniquely, then display and execute the authoritative VMID.
- Support `--help`, topic help, `--explain`, `--dry-run`, `--show-native`, `--json`, and
  human-readable table output where the command supports them.
- Classify reads as green and mutations as amber. Amber operations show a complete plan,
  refuse redirected confirmation, re-read authoritative state after confirmation, execute an
  allow-listed operation, and verify the postcondition.
- Write a secret-free JSONL audit record for attempted mutations and their outcomes.
- Fix release hygiene discovered during planning: attach `RELEASE_NOTES.md`, document that
  `git-rl` stages the full working tree, and resolve the matching issue entries.

### Explicitly deferred

- VM destroy/stop/reset, snapshot rollback/delete, network/VLAN mutation, tags/notes,
  autostart/protection, and profile/deploy orchestration. These are later phases in the source
  document and should not be smuggled into the first safe release.
- An unrestricted `pmx exec` or any raw remote-command escape hatch.
- Automating the supplied `wipefs`/`parted` sequence. It is a separate red-risk physical-disk
  workflow, not VM management. The disk now has a partition, so the current F3 capacity gate
  must continue to refuse it; there will be no force bypass. A future `pmx disk prepare` plan
  must preflight every tool before the first write and use a separate typed erase confirmation.
- Hard-coded hostnames, addresses, node names, storage IDs, bridges, VMIDs, or templates.

## Component layout

The existing `components/system/proxmox.ps1` will be replaced by this ordered domain:

| File | Responsibility |
|---|---|
| `components/proxmox/shared.ps1` | formatting, safe display text, size conversion, result shapes, strict token parser |
| `components/proxmox/config.ps1` | defaults, config persistence, validation, target resolution, audit-log path |
| `components/proxmox/host.ps1` | existing dashboard/pools/guests/updates plus node/storage/discovery rendering |
| `components/proxmox/physical-disks.ps1` | existing physical disk selection, SMART, tests, and capacity-test UI |
| `components/proxmox/evidence.ps1` | existing authenticity report and evidence bundle |
| `components/proxmox/vm-read.ps1` | VM resolution, list/show/status/next-id and VM-disk inspection |
| `components/proxmox/vm-change.ps1` | clone, CPU, memory, disk growth, start, and shutdown plans |
| `components/proxmox/snapshots.ps1` | snapshot list/create plans |
| `components/proxmox/help.ps1` | table-driven overview and topic help |
| `components/proxmox/command.ps1` | thin `pmx` router and adjacent help registrations |

New OS execution stays separate in:

- `platform/windows/adapters/proxmox-management.ps1` — SSH management implementation.
- `platform/linux/adapters/proxmox-management.ps1` — local management on Proxmox, SSH
  management elsewhere.

Both adapters expose the same small operation contract and return a consistent result with
`Success`, `Data`, `Error`, `ExitCode`, and `NativeCommand`. Operations are enum-like and
allow-listed; the adapter validates every value again before constructing native arguments.

## Chunks

1. **Mechanical modular split with zero intended behaviour change**
   - Create the ten `components/proxmox/*.ps1` files above by moving existing functions by
     responsibility.
   - Remove `components/system/proxmox.ps1` only after the new ordered load list works.
   - Update `Microsoft.PowerShell_profile.ps1`, `COMPONENTS.md`, and command registrations.
   - Expand descendant mount/open-handle inspection in
     `platform/linux/adapters/proxmox.ps1`, then resolve Issue 5.
   - Run all current PMX regressions before adding management commands.

2. **Strict command grammar, configuration, and help**
   - Implement the parser and table-driven command schema in `shared.ps1` and `help.ps1`.
   - Persist non-secret settings beneath `Get-PowerFlowConfigPath` in `config.ps1`; reuse
     `Get-PFServers` for saved SSH endpoints rather than duplicating credentials or addresses.
   - Keep existing positional physical-disk syntax. Route reserved VM-disk actions
     (`list`, `grow`) before physical selector resolution so the two meanings cannot collide.
   - Make `pmx help` work without a configured or reachable Proxmox host.

3. **Allow-listed local/SSH management adapter**
   - Add the matching Windows/Linux management adapters.
   - Use structured `pvesh --output-format json` for queries and exact `qm` operations for
     approved mutations.
   - Apply strict VMID/name/disk/snapshot validation, fixed native argument arrays, connection
     timeout, SSH batch mode, safe remote quoting, and terminal-control sanitization.
   - Expose no method that accepts an arbitrary native command string.
   - Extend the hard-coded adapter parity list in `.github/workflows/release-validate.yml`.

4. **Read-only discovery and VM inspection**
   - Implement config validation/discovery, node status, storage list, VM list/show/status,
     next free VMID, VM-disk list, name-to-VMID resolution, table output, and JSON output.
   - Do not assume a storage pool, bridge, node, template, or next VMID.

5. **Guarded VM changes**
   - Implement clone, CPU, memory, disk grow-to-target, start, shutdown, and snapshot create.
   - Validate source/template/target state, active storage and capacity where applicable,
     final disk size, and snapshot uniqueness.
   - Make same-state operations no-ops; refuse shrink, target reuse, hostile values, and
     changed state after confirmation.
   - `--dry-run` performs every validation and prints the exact plan but invokes no mutation.
   - Verify each mutation by querying Proxmox afterward; partial multi-step work is reported
     precisely and never auto-destroyed.

6. **Dedicated tests and CI wiring**
   - Add dependency-free test scripts under `tests/proxmox/` for parser, routing, rendering,
     local/SSH adapter arguments, state revalidation, and idempotency.
   - Use function shims and recorded JSON. CI must never run real `qm`, destructive
     `f3probe`, `wipefs`, `parted`, `mkfs`, or mount commands.
   - Update `.github/workflows/release-validate.yml` and
     `.github/workflows/release-validate-linux.yml` to run the tests on both platforms.

7. **Documentation and release preparation**
   - Update `README.md`, `docs/features.md`, `docs/troubleshooting.md`, `COMPONENTS.md`, and
     generated help metadata with the canonical syntax and safety model.
   - Add `## [3.17.0] - Unreleased` to `CHANGELOG.md`; CI will generate release notes from it.
   - Add `RELEASE_NOTES.md` to `.github/workflows/release-publish.yml` assets and correct the
     `git-rl` staging description in `README.md`, then move Issues 3 and 4 to resolved.
   - Complete `docs/release-checklist.md` top to bottom and record the session log.
   - Protect unrelated untracked user files from `git-rl`'s `git add .`; do not delete or edit
     them. The release cannot be cut until its staged set contains only intended files.
   - The human runs interactive `git-rl` and selects **minor**. Afterward, verify v3.17.0 CI,
     the published GitHub release, required assets, and a clean-container installation.

## Rollback

- Revert the new Proxmox domain files and restore `components/system/proxmox.ps1` plus its
  original bootloader entry.
- Remove both management adapters and their parity entries.
- Remove v3.17.0-only tests/docs/changelog content.
- Configuration and audit files are user data outside the repository; rollback leaves them in
  place but the old version ignores them. No remote state changes occur during installation or
  profile load.
- Every supported mutation has a dry run, confirmation boundary, pre-execution revalidation,
  and post-read; rollback never guesses how to undo a partially completed Proxmox operation.

## Testing

- Parse every `.ps1` under Windows PowerShell-compatible syntax and Linux `pwsh`.
- Run the exact architecture, automatic-variable, help-registry, adapter-parity, and Linux
  native-command shadowing gates from the release workflow.
- Load the working-tree profile on Windows and in a clean Linux container; confirm help and
  remote configuration work, while local-only disk commands degrade honestly off Proxmox.
- Re-run every existing PMX SMART/lsblk/evidence/capacity refusal fixture after the file split.
- Parser matrix: reordered options, `--option=value`, missing values, duplicates, unknown and
  abbreviated flags, leading-dash values, metacharacters, newlines, and zero-width characters.
- Assert hostile values, cancellation, redirected input/output, and `--dry-run` produce zero
  mutation adapter calls.
- Capture exact local/SSH argument arrays for every allowed operation; assert no arbitrary
  command text can reach the adapter.
- Mutate one VM identity/state field at a time between preview and execution and assert the
  operation refuses. Verify start-running, shutdown-stopped, and same CPU/memory/disk size are
  no-ops; disk shrink, occupied VMID, duplicate snapshot, and ambiguous name refuse.
- Exercise read-only discovery against a real configured Proxmox target before release. Run
  mutation verification only with the user's explicit confirmation and a disposable test VM;
  mocks/dry-runs do not pretend to prove a real mutation.
- Privacy-scan the complete staged diff. Do not publish source notes containing a private
  hostname, address, username, serial number, or local path.
