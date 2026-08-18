# PMX Full VM View and Output Overrides

**Status:** Ready for approval; implementation has not started.

## Goal

Make PMX output-mode precedence explicit and tested, and add a detailed component-based VM view
without crowding or changing the existing `pmx vm show <vm>` summary.

## Audit result

The output overrides are already functional across all documented PMX reads. Each command calls
`Get-PmxOutputMode`, whose precedence is:

1. explicit `--json` or `--table`;
2. the configured `output` setting;
3. the built-in configuration default, `table`.

The strict parser already rejects `--table --json`, `-table`, and `-json`. This work will pin that
existing behavior, add the requested real single-letter conveniences `-t` and `-j`, and document
the relationship between explicit output choices and the configured default.

The pending v4.1.0 implementation also already corrects the reported unit examples: PowerShell's
binary constants now display IEC labels, and the summary uses modeled `SizeDisplay`, so the expected
values are `8 GiB` and `scsi0 100 GiB` rather than `8.0 GB` and raw `100G`.

## Interface decisions

1. `pmx vm show <name|vmid>` remains a compact summary.
2. `pmx vm show <name|vmid> --full` adds GENERAL, COMPUTE, DISKS, NETWORK, and GUEST sections.
3. `--full` is accepted only by `vm show`, not `vm status` or other read commands.
4. `--full --json` returns the same complete structured VM detail document as `--json`; `--full`
   controls human rendering and does not invent a second JSON schema.
5. `-t` is an exact alias for `--table`, and `-j` is an exact alias for `--json`, across every PMX
   read command that accepts the long forms. The parser continues rejecting `-table`, `-json`,
   bundled forms such as `-tj`, attached values, and unknown short options.
6. Repeating the same output choice through two spellings (`--table -t`, `--json -j`) is a
   duplicate-option error. Selecting both modes (`-t -j`, `--table -j`, and equivalent mixes) is
   a mutually-exclusive-output error.
7. A stopped VM displays uptime as `—`; JSON retains the authoritative numeric status value.
8. Total vCPUs are derived from configured sockets multiplied by cores per socket.
9. Firmware mode is derived from `bios` (`ovmf` = UEFI, otherwise SeaBIOS), with the raw value
   retained in the model.
10. Network rows are parsed from exact `netN` configuration entries. Model, MAC address, bridge,
   firewall state, and raw configuration are retained; terminal rendering is sanitized.
11. Missing optional fields display `default`, `disabled`, or `—` only when that is an honest
    interpretation of Proxmox defaults. Unknown/unparseable values remain `unknown`; the renderer
    must not fabricate configuration.

## Component design

1. Add `components/proxmox/vm-model.ps1` after the approved network configuration model.
   - Build a stable VM view model from the existing config/status/VM objects.
   - Reuse `Get-PmxConfiguredNics`; do not create a second `netN` parser.
   - Derive sockets, cores/socket, total vCPUs, CPU type, memory bytes/display, ballooning, agent,
     autostart, boot order, firmware, machine type, protection, and display uptime.
   - Keep source config/status objects available for JSON compatibility.
2. Add `components/proxmox/vm-view.ps1` after `vm-read.ps1`.
   - Render the existing compact summary from the model.
   - Render `--full` as sectioned tables and reuse `Show-PmxVirtualDiskTable` for disks.
   - Never query Proxmox or parse command arguments; rendering remains presentation-only.
3. Keep `components/proxmox/vm-read.ps1` responsible for resolution and the two existing
   allow-listed API queries. Extend its invocation parser with a `Full` switch only for `vm show`,
   then delegate rendering.
4. Update the ordered profile loader and `COMPONENTS.md` with both components.

The network layer is designed separately in `pmx-vm-network-inspection.md`. Only its configured
NIC model is a dependency of `--full`; the full VM view must not invoke QEMU Guest Agent.

## Output-mode contract work

- Extend the strict shared parser with an explicit short-switch map rather than treating arbitrary
  single-dash words as long options. Only allow-listed one-letter switches are accepted.
- Add `t -> Table` and `j -> Json` to the PMX global short-switch contract and pass that map only
  to command parsers that already accept the corresponding global long output switches.
- Add table-driven tests for explicit option > configured default > built-in default precedence.
- Assert explicit `--table` overrides configured JSON and explicit `--json` overrides configured
  table output.
- Assert `-t` and `-j` produce byte-for-byte equivalent mode selection to their long forms across
  every documented read handler.
- Assert `--table --json` fails before rendering.
- Assert mixed long/short conflicts and duplicate aliases fail before rendering.
- Assert `-table`, `-json`, `-tj`, and unknown short options remain rejected with useful guidance.
- Statistically inventory every documented read handler and require it to call
  `Get-PmxOutputMode`, preventing one command from silently ignoring the shared contract.
- Update `pmx help`, every relevant detailed topic, README, features, and troubleshooting text with
  `[--table|-t] [--json|-j]` plus the configured-default explanation.

## Expected full view

```text
🧱 VM 102 — docker-host
──────────────────────────────────────────────────────────────
GENERAL
  Node          pve
  Status        stopped
  Type          Virtual machine
  Template      no
  Protection    disabled

COMPUTE
  Sockets       1
  Cores/socket  4
  Total vCPUs   4
  CPU type      host
  Memory        8 GiB
  Ballooning    disabled

DISKS
  DISK      ROLE       SIZE  STORAGE       BACKING
  scsi0     boot    100 GiB  local-zfs     local-zfs:vm-102-disk-1

NETWORK
  NIC       MODEL     BRIDGE   MAC                  FIREWALL
  net0      virtio    vmbr0    BC:24:11:00:00:00    enabled

GUEST
  QEMU agent    enabled
  Autostart     disabled
  Boot order    scsi0;net0
  Firmware      UEFI (ovmf)
  Machine       q35
  Uptime        —
```

## Testing

- Summary and full views both use exact IEC memory/disk fields.
- A stopped VM displays `—`; a running VM displays the formatted positive uptime.
- Modern and legacy boot configuration remain modeled without slot guessing.
- NIC fixtures cover virtio/e1000, bridge, MAC, firewall on/off, missing fields, hostile terminal
  controls, and more than one NIC.
- Compute fixtures cover multiple sockets, CPU type, ballooning, agent, firmware, and machine.
- `--full` works with explicit/default table mode, is harmless with JSON, and is rejected for
  `vm status`.
- Every documented PMX read accepts `-t` and `-j`; mutations do not accidentally inherit output
  aliases unless their documented output contract supports them.
- All existing PMX, SRV privacy, platform, help, parse, and release gates remain green.

## Release impact

This remains v4.1.0 while unreleased: the detailed read view and output-contract tests complement
the already prepared additive PMX disk/clone work. `git-rl` continues to own the version bump.

## Rollback

Remove the two new components from the loader, return compact rendering to `vm-read.ps1`, remove
the `Full` switch from its parser, and remove the additive tests/help/docs. No saved configuration
or Proxmox state requires migration.
