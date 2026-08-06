# PMX disk sizes and clone placement are ambiguous

## Problem

Virtual-disk tables labelled PowerShell's binary arithmetic as `GB`/`TB`, and clone previews
showed source/target VMIDs without showing which storage pool would receive each cloned disk.
The long named disk-growth form was also unnecessarily cumbersome for a VM with one disk.

**Status:** Implemented — awaiting confirmation on a real Proxmox host.

## Root cause

The original shared formatter used PowerShell's 1024-based constants with decimal-looking unit
labels. Disk parsing, listing, growth, and clone capacity also lived in broad VM files, which made
it easy for exact model data and presentation contracts to drift apart. Clone validation grouped
storage correctly but discarded that information before rendering the preview.

## Solution

Create a virtual-disk model whose authoritative field is integer bytes and derive IEC display,
boot role/order, storage, and backing from the Proxmox configuration. Build disk-growth and clone
plans as separate components. Automatic disk selection succeeds only for one trustworthy eligible
disk; ambiguity lists choices and stops. Clone plans retain a same-as-source mapping and available
capacity for each disk, then serialize the requested plan separately from the verified result.

## Notes

- Never parse human table text to calculate growth.
- A full clone may span several storage pools; placement is a per-disk property.
- Provisioned virtual capacity is not the same as allocated thin-pool blocks.
- An equal growth target remains a successful idempotent no-op; shrinking remains forbidden.
- Guest partition and filesystem expansion is still a separate in-guest operation.
