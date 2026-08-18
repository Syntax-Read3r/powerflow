# PMX Disk and Clone Output Contracts

**Status:** Implemented and locally verified; awaiting confirmation on a real Proxmox host before release.

## Goal

Make PMX disk sizes, disk roles, clone placement, and clone JSON precise enough to serve as stable
human and automation interfaces without weakening resize or clone safeguards.

## Scope

This release will:

- label binary byte values with IEC units (`KiB`, `MiB`, `GiB`, `TiB`) everywhere in PMX;
- preserve exact configured byte counts as the source for comparisons and resize calculations;
- introduce a dedicated virtual-disk model with additive machine-readable fields;
- derive boot participation from the Proxmox VM configuration instead of guessing from slot names;
- add concise positional disk-growth forms while retaining the explicit named form for scripts;
- infer a disk only when exactly one eligible growable disk exists and fail closed otherwise;
- include backing identity and current storage availability in every disk-growth preview;
- show full-clone placement and provisioned capacity per disk before confirmation;
- distinguish a requested clone plan from a verified clone result in JSON.

This release will not inspect guest partitions/filesystems, estimate actually allocated thin-pool
blocks, move disks to a different storage, add a clone `--storage` selector, or replace existing JSON
properties with incompatible names. The existing v4.0.1 privacy work remains intact in the working
tree and will be included in the eventual v4.1.0 release.

## Interface decisions

1. `SizeBytes` remains authoritative. Display text is always derived from it and never parsed back.
2. `Format-PmxBytes` retains its function name for compatibility but emits IEC labels because its
   PowerShell constants are binary.
3. Disk-list JSON remains an array and retains existing properties. New properties are additive:
   `Roles`, `BootOrder`, `SizeMiB`, `SizeGiB`, and `SizeDisplay`. This avoids a breaking wrapper or
   PascalCase-to-snake_case migration in a minor release.
4. `Roles` contains `boot` when the disk is enabled in Proxmox's configured boot order and `data`
   otherwise. `BootOrder` is the one-based configured priority or null. Legacy `bootdisk` is used
   only when the modern `boot: order=...` value is absent.
5. Clone placement is per disk. Because the current command supplies no target-storage option, the
   plan records `same-as-source` policy and maps each target disk to its source storage. It must not
   collapse a multi-storage VM into one misleading storage field.
6. Capacity is labelled `Provisioned capacity`, not `estimated data`. PMX knows configured virtual
   sizes but does not know how many thin-provisioned physical blocks the clone will allocate.
7. Clone `--json` emits one JSON document on the success stream. Prompts and status decoration remain
   on the information stream. Dry runs report `executed=false` and `verified=false`; completed clones
   report the original plan separately from the postcondition that PMX verified.
8. Disk growth accepts exactly three mutually exclusive grammars:
   - `pmx disk grow <vm> <target-size>` — infer the disk only when one is eligible;
   - `pmx disk grow <vm> <disk> <target-size>` — explicit positional selection;
   - `pmx disk grow --vm <vm> --disk <disk> --to <target-size>` — explicit named selection.
   Hybrid positional/named forms, missing values, and extra positionals are rejected.
9. Eligible inference includes only modeled `ideN`, `sataN`, `scsiN`, and `virtioN` disks with a
   trustworthy configured size/backing. CD/DVD, cloud-init, EFI, TPM-state, and unused volumes are
   excluded by type/config rather than by a preferred-slot guess.
10. Multiple eligible disks never trigger an interactive picker or a “main disk” guess. PMX prints
    their slot, role, size, storage, and backing, then returns without mutation and shows both the
    concise explicit and named-option commands.
11. A target equal to the configured size remains a successful idempotent no-op. Shrinks remain
    errors. This intentionally differs from the supplied brief: desired-state automation should be
    able to request an already-achieved size without failing.
12. Storage `avail` is displayed as the Proxmox storage API's current available capacity. It is not
    labelled as guaranteed allocatable thin-pool space. Inactive/unavailable storage fails closed;
    a capacity shortfall is shown before Proxmox receives a resize request.
13. The disk/clone renderers honor the existing PMX `Explain` policy and explicit `--explain` switch.
    Explanation states that the target is a final virtual size, calculations use configuration
    bytes, native growth is a delta, and guest partition/filesystem growth remains separate.

## Chunks

1. **IEC size formatter and numeric invariants**
   - Update `components/proxmox/shared.ps1` so `Format-PmxBytes` emits IEC unit labels while retaining
     exact numeric conversion behavior.
   - Audit PMX tables, warnings, mutation fields, verification messages, and capacity errors for
     assumptions about `GB`/`TB` labels.
   - Extend `tests/proxmox/parser-routing.ps1` with byte-to-display fixtures at KiB through TiB
     boundaries and non-integral GiB values.

2. **Component-based virtual-disk model**
   - Add `components/proxmox/disk-model.ps1` and load it between `shared.ps1` and `vm-read.ps1` in
     `Microsoft.PowerShell_profile.ps1`.
   - Move `Get-PmxVirtualDisksFromConfig` out of `vm-read.ps1` and split parsing into focused helpers
     for configured size, storage/backing identity, and modern/legacy boot order.
   - Produce additive disk fields: existing `Disk`, `Storage`, `Backing`, `Size`, `SizeBytes`, `Raw`
     plus `Roles`, `BootOrder`, `SizeMiB`, `SizeGiB`, and `SizeDisplay`.
   - Update `Show-PmxManagedVmDisks` in `components/proxmox/vm-read.ps1` to render
     `DISK ROLE SIZE STORAGE BACKING`, using only the modeled numeric/display fields.

3. **Disk-growth grammar and plan component**
   - Add `components/proxmox/disk-grow.ps1`, loaded after the shared VM-mutation helpers and before
     the command router, and move `Invoke-PmxVmDiskGrow` out of `vm-change.ps1`.
   - Add a strict parser for the two concise positional forms and the existing named form. Global
     switches may appear in normal supported positions, but selector grammars cannot be mixed.
   - Resolve VM names/VMIDs through the existing unique resolver, build the eligible disk set from
     `disk-model.ps1`, and select automatically only when the set has exactly one member.
   - For ambiguity, render an informational disk table and explicit retry commands, then stop before
     confirmation, audit execution, or native invocation.
   - Build one immutable growth plan containing VM name/VMID, node, disk slot/roles, backing,
     configured current bytes, target bytes, delta bytes, storage, storage available bytes, and the
     allow-listed native delta. Revalidation rebuilds and compares this plan before execution.
   - Render `VM`, `VMID`, disk, role, current, target, growth, storage, backing, available capacity,
     and native command. Honor `--explain` and retain the guest partition/filesystem warning.

4. **Clone planning component**
   - Add `components/proxmox/clone-plan.ps1`, loaded after `disk-model.ps1` and before
     `vm-change.ps1`.
   - Move and expand `Get-PmxCloneCapacityCheck` from `vm-change.ps1` into a plan builder that returns
     source/target nodes, placement policy, per-disk source/target storage, roles, configured bytes,
     total provisioned bytes, and storage availability.
   - Revalidation rebuilds the plan and rejects changed disk identity, size, placement, node, or
     available-capacity state before execution.
   - Add a clone-specific renderer that prints the per-disk placement table before the shared amber
     confirmation without duplicating mutation execution logic.

5. **Plan-versus-result JSON**
   - Extend the shared mutation result path in `components/proxmox/vm-change.ps1` only as needed to
     return structured plan and verification data instead of discarding it.
   - For clone JSON, emit stable top-level operation state (`operation`, `dry_run`, `executed`,
     `verified`), a `plan` object with source/target/placement/capacity, and a separate `result`
     object populated only after postcondition verification.
   - Preserve the existing interactive-confirmation requirement; `--json` is an output mode, not a
     force or non-interactive execution bypass.

6. **Regression and contract coverage**
   - Extend `tests/proxmox/vm-model.ps1` with modern boot order, legacy bootdisk, multi-disk,
     multi-storage, fractional-size, CD-ROM, cloud-init, and malformed-size fixtures.
   - Extend `tests/proxmox/mutation-safety.ps1` with immutable clone-plan/revalidation behavior.
   - Add `tests/proxmox/output-contracts.ps1` for exact table headings/IEC labels, additive disk JSON,
     concise/explicit growth previews, ambiguity output, multi-storage clone preview, dry-run JSON,
     and verified-result JSON.
   - Extend parser/help inventory tests with every accepted disk-growth grammar and rejected hybrid.
   - Ensure resize tests prove current, target, and delta are computed from bytes, equal targets are
     successful no-ops, and every shrink request remains rejected.

7. **Documentation and release preparation**
   - Update `components/proxmox/help.ps1` so the main `pmx help` command map shows all three
     disk-growth forms and `pmx help disk grow` explains automatic selection, ambiguity refusal,
     exact final-size semantics, IEC units, storage-capacity display, and native delta calculation.
   - Extend `tests/proxmox/help-surface.ps1` so every accepted concise/explicit grammar appears in
     rendered help and every documented form is accepted by the parser/router fixtures.
   - Update `COMPONENTS.md`, `README.md`, `docs/features.md`, `docs/troubleshooting.md`, and
     `docs/instructions.md` with the output-contract rules.
   - Add the issue/log/solved-problem records required by repository policy.
   - Replace the prepared v4.0.1 release section with v4.1.0 release notes because the privacy fix
     plus additive disk/clone contracts form a minor release. Do not hand-edit the settings version;
     `git-rl` owns that bump after confirmation and release gates.

## Expected table examples

```text
DISK   ROLE   SIZE      STORAGE      BACKING
scsi0  boot   32 GiB    local-zfs    local-zfs:vm-102-disk-1
scsi1  data   100 GiB   bulk-zfs     bulk-zfs:vm-102-disk-2
```

```text
⚠️  GROW VM DISK
──────────────────────────────────────────────────────────────
VM             docker-host
VMID           102
Disk           scsi0
Role           boot
Current        32 GiB
Target         100 GiB
Growth         68 GiB
Storage        local-zfs
Backing        local-zfs:vm-102-disk-1
Available      1.2 TiB
Native         qm disk resize 102 scsi0 +68G --digest <sha1>
```

For an ambiguous VM, PMX stops and prints:

```text
VM 102 has more than one eligible growable disk.

DISK   ROLE   SIZE      STORAGE      BACKING
scsi0  boot   100 GiB   local-zfs    local-zfs:vm-102-disk-1
scsi1  data   2 TiB     bulk-zfs     bulk-zfs:vm-102-disk-2

Specify one:
pmx disk grow 102 scsi1 3TiB
pmx disk grow --vm 102 --disk scsi1 --to 3TiB
```

```text
SOURCE DISK   ROLE   SOURCE STORAGE   TARGET STORAGE   PROVISIONED
scsi0         boot   local-zfs        local-zfs        32 GiB
scsi1         data   bulk-zfs         bulk-zfs         100 GiB

Placement policy       same-as-source
Provisioned capacity   132 GiB
```

## Expected clone JSON shape

```json
{
  "operation": "clone",
  "dry_run": true,
  "executed": false,
  "verified": false,
  "plan": {
    "source": { "vmid": 100, "name": "debian13-base", "node": "pve" },
    "target": { "vmid": 102, "name": "docker-host", "node": "pve" },
    "clone_type": "full",
    "placement_policy": "same-as-source",
    "provisioned_bytes": 141733920768,
    "disks": [
      {
        "slot": "scsi0",
        "roles": ["boot"],
        "source_storage": "local-zfs",
        "target_storage": "local-zfs",
        "size_bytes": 34359738368,
        "size_display": "32 GiB"
      }
    ]
  },
  "result": null
}
```

The public clone contract may use the repository's established PowerShell/PascalCase property names
internally; tests will pin the serialized JSON names deliberately so casing cannot drift accidentally.

## Rollback

Revert the formatter, remove the two new model/plan components from the loader, restore the disk
parser and capacity checker to their original files, and remove the additive output tests/docs. No
saved PMX configuration, VM configuration, or Proxmox state requires migration.

## Testing

- `size=32G` produces `34359738368` bytes and displays `32 GiB` everywhere.
- `pmx disk grow --vm 102 --disk scsi0 --to 100GiB --dry-run` reports exactly 32 GiB current,
  100 GiB target, and 68 GiB growth while emitting native `+68G`.
- `pmx disk grow 102 100GiB --dry-run` selects `scsi0` only when it is the single eligible disk.
- `pmx disk grow docker-host 100GiB` resolves the unique name and displays both name and VMID.
- `pmx disk grow 102 scsi1 3TiB --dry-run` selects the exact positional disk.
- A two-disk `pmx disk grow 102 3TiB` lists both eligible disks and performs no mutation.
- Concise/named hybrid syntax is rejected rather than interpreted heuristically.
- EFI, TPM-state, cloud-init, CD/DVD, and unused volumes never enter automatic selection.
- The preview includes storage availability from the API without describing it as guaranteed thin
  allocation, and `--explain` describes byte/delta/guest-filesystem semantics.
- Disk JSON exposes exact integer bytes and derived fields without removing existing properties.
- Boot role/order comes only from modern `boot` or legacy `bootdisk` configuration.
- Multi-storage clones show every disk mapping and validate capacity on every target storage.
- Clone dry-run JSON has a populated plan and null result; a completed verified clone retains that
  plan and adds a distinct verified result.
- Redirected input cannot execute a clone, including with `--json`.
- PMX, SRV, Windows prerequisite, parse, architecture, adapter, help, YAML, privacy, and whitespace
  release gates all pass before release preparation is declared complete.

## Implementation outcome

- Added the planned `disk-model.ps1`, `clone-plan.ps1`, and `disk-grow.ps1` components in the
  documented load order; the router remains unchanged except for calling the moved handler.
- Preserved the disk JSON array and all existing properties while adding exact/derived fields.
- Kept equal targets as idempotent no-ops and used `qm disk resize`, as decided in this plan.
- The clone plan reports same-as-source placement because no target-storage selector was added.
- Local Windows suites and Linux-container PMX/SRV suites pass, as do parse, architecture,
  automatic-variable, help-registry, whitespace, and integrated profile/help checks.
- Real-host resize/clone dry runs and the previously prepared private SSH prompt still require
  owner confirmation before `git-rl` cuts v4.1.0.
