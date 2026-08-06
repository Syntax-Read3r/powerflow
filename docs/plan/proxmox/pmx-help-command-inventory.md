# PMX Help Command Inventory

**Status:** Implemented and locally verified.

## Goal

Make `pmx help` a complete, executable command map. Every routed PMX operation must show the
arguments needed to run it, including VM selectors, mutation values, output modes, physical-disk
actions, compatibility forms, and discoverable detailed-help families.

## Findings

The router and parsers support more than the hand-written overview advertises. The most visible
gap is lifecycle syntax: the overview says only `pmx vm start|shutdown`, hiding the required VM
selector. The same shorthand affects clone, CPU, memory, snapshots, and virtual disks. Detailed
topics also omit accepted named/positional forms; `config discover` has no matching help alias;
and local commands such as `pmx guest` and physical-disk action aliases are absent.

## Implementation

1. Add a table-driven overview catalog to the PMX help component and render the overview from it.
2. Show complete canonical syntax for every management and local/physical route.
3. Expand detailed topics with all supported selector forms and add missing family/action topics.
4. Add a help-inventory regression that asserts every router surface and required argument appears
   in both overview and detailed help without contacting Proxmox.
5. Update public docs, issue records, session log, and major-version release notes; run all
   release gates.

## Syntax decision

The audit exposed a redundant selector spelling in commands already nested under `pmx vm`.
Per the user's direction, `vm show`, `vm status`, CPU, memory, start, and shutdown now take the
VM name/VMID directly after the action and reject `--vm`. Cross-resource `pmx disk` and
`pmx snapshot` commands retain `--vm` because it names which VM owns a separate disk/snapshot
resource. Removing an accepted option is a breaking change and therefore requires v4.0.0.

## Non-goals

This audit does not add Proxmox operations, change parser behavior, contact a node, or weaken any
mutation confirmation. Compatibility spellings remain documented as aliases, not preferred forms.

## Rollback

Revert the help catalog/renderer, detailed-topic additions, regression, and documentation. PMX
runtime behavior is unchanged.

## Result

The overview is rendered from `Get-PmxHelpOverview` and contains all 31 executable syntax rows
across the router's configuration/discovery, VM, disk, snapshot, and local-host surfaces.
Detailed help now resolves family, action, and compatibility topics. VM-prefixed commands use a
direct selector, while disk/snapshot ownership retains `--vm`. The audit also confirmed that
profiles/deploy, reboot, snapshot rollback/delete, destroy, networking, autostart/startup,
protection, tags, and notes in `feature-pmx.md` are future designs, not routed commands; they are
therefore not advertised as runnable help.
