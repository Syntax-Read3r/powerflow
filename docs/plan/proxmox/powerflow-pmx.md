# PowerFlow Proxmox Commands

> **SUPERSEDED — historical record.** This is the original plan as written. The delivered
> design is [powerflow-pmx-v2.md](powerflow-pmx-v2.md), which records what changed and why.
> One item below is now wrong on purpose: the destructive gate does **not** take a "typed
> serial confirmation". A serial names a *product* and is easy to paste from the wrong row
> of a disk list, so the phrase is `DESTROY <by-id leaf>`, which names *this device*.

**Status:** Approved — implementation in progress (approved by the user on 2026-08-03)

## Goal

Provide a compact, safe `pmx` command family inside PowerFlow that replaces long Proxmox
inspection pipelines with readable summaries while keeping destructive disk operations behind
strict, re-checked safeguards.

## Scope

- Fix PowerFlow's Linux `ls` so its output remains attractive at a terminal and clean in a
  pipeline.
- Add `pmx`, `pmx disks`, `pmx disk [selector]`, `pmx pools`, `pmx guests`, and `pmx updates`.
- Add compact SMART summaries, full SMART output, and SMART short/long test launchers.
- Add an F3 capacity probe only behind explicit destructive intent, stable device identity,
  in-use checks, and typed serial confirmation.
- Use structured Proxmox, `lsblk`, and `smartctl` output where available.
- Keep shared rendering and command routing in `components/`; keep OS and Proxmox calls in
  matching platform adapters.
- Do not automate VM/container lifecycle changes, pool creation, disk wiping, or package
  upgrades in this slice.

## Chunks

1. **Pipeline correctness**
   - Update `components/files/listing.ps1` to let `lsd` automatically suppress decoration when
     its output is captured or piped.
   - Add a Linux workflow regression for an end-anchored `ls | grep` symlink lookup.
2. **Adapter contract**
   - Add `platform/linux/adapters/proxmox.ps1` for detection and structured node, disk, storage,
     guest, update, SMART, and disk-safety data.
   - Add `platform/windows/adapters/proxmox.ps1` as the same safe unsupported contract.
   - Extend the hardcoded adapter contract gate in `.github/workflows/release-validate.yml`.
3. **PowerFlow command surface**
   - Add `components/system/proxmox.ps1` with the `pmx` dispatcher, compact renderers, selector
     resolution, optional fzf disk selection, and clear degradation messages.
   - Load it from `Microsoft.PowerShell_profile.ps1` and register it in generated help.
4. **Destructive boundary**
   - Resolve every disk action to `/dev/disk/by-id` and display model plus serial.
   - Re-check partitions, mounts, holders, swap, ZFS, LVM, and Ceph immediately before F3.
   - Refuse redirected input and require the exact serial; provide no force bypass.
   - Never execute an F3 probe in automated tests.
5. **Documentation and release metadata**
   - Update `README.md`, `docs/features.md`, `docs/troubleshooting.md`, `COMPONENTS.md`,
     `CHANGELOG.md`, dependency tracking, issue tracking, and the session log.

## Rollback

Remove the Proxmox component and its two adapters, remove its bootloader/help/contract entries,
and revert the `lsd` decoration mode plus its regression step. No persistent Proxmox state is
created by the read-only commands; SMART tests already launched must be allowed to finish or be
stopped with `smartctl`.

## Testing

- Parse every PowerShell file.
- Run the exact platform-separation and help-registration gates.
- Verify every new adapter call exists on Windows and Linux.
- Load the profile in a clean Windows shell and confirm `pmx` degrades honestly.
- Test renderers and routing with fixture adapter functions, including missing tools and empty
  results.
- On Linux, test the `ls | grep` regression and mock Proxmox JSON parsing.
- Exercise every F3 refusal path using fixtures/mocks; never invoke `f3probe --destructive`.
- Verify redirected input cannot reach a prompt or destructive invocation.

