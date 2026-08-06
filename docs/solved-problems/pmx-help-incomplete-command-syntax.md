# PMX help listed actions without executable syntax

**Status:** Fix applied — awaiting user confirmation.

## Symptom

`pmx help` named operations such as `pmx vm start|shutdown` but did not show the required VM
selector. Other routes, compatibility aliases, physical-disk actions, and detailed help families
were missing entirely.

## Cause

The PMX router and argument parsers evolved while the top-level help remained a separate set of
hand-written `Write-Host` lines. Nothing compared those lines with the actual command surface.

## Fix

`Get-PmxHelpOverview` now owns a structured catalog rendered by `Show-PmxHelp`. It contains every
routed configuration, discovery, VM, disk, snapshot, local host, guest, and update command with
the values needed to run it. `Get-PmxHelpTopics` now covers command families, actions, aliases,
named/positional forms, native equivalents, and safety notes.

The command language was also simplified: operations already below `pmx vm` take the VM name or
VMID directly. For example, use `pmx vm start debian13-lab` and
`pmx vm cpu set debian13-lab --cores 4`. Redundant `--vm` is rejected there. It remains valid for
`pmx disk` and `pmx snapshot`, where it identifies the VM that owns a separate resource.

## Regression protection

`tests/proxmox/help-surface.ps1` pins the complete overview inventory, required detailed topics,
rendered output, VM-first parser behavior, compatibility positionals, and rejection of the old
redundant flag. It runs inside the existing PMX suite on Windows and Linux CI.
