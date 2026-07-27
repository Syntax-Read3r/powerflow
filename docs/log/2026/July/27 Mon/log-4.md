# Log 4 — July 27, 2026 — "6 of 6 free" wasn't clear, and Linux found two bugs (v3.12.1)

**User:** "you mentioned sata 6 of 6 free, are you saying there are 6 slots that are free for
HHD or SSD?" — then, on being told the label was being fixed: "I take it you have verified for
linux too, if you have not, now is the time."

Both remarks landed on something real.

## The question exposed a wording bug

The row was labelled **`Bays`**. A *bay* is a mounting position in the **case**; that row
counts connectors on the **motherboard**. So "Bays … SATA 6 of 6 free" read as "six places I
can put a drive" — which the board cannot promise. Renamed to `Ports`.

The answer to the question itself: 6 is real. The board declares `SATA6G_12` (ports 1+2) and
`SATA6G_34` (3+4) on the Intel chipset plus `SATA6G_E12` (E1+E2) on an ASMedia controller —
the `E` meaning "extra" — and no SATA drive is attached, so all six are free electrically.

What that does NOT promise, now documented beside the code instead of implied away:

- **Ports are not bays and not power.** Mounting a drive also needs a free bay in the chassis
  and a spare PSU lead. SMBIOS knows nothing about either.
- **Many boards mux M.2 against SATA.** Populating certain M.2 sockets switches specific SATA
  ports off, because they share chipset lanes. With two M.2 drives installed, one or two of
  those six may already be dead. SMBIOS declares connectors that physically *exist*, not what
  is currently *enabled*, and there is no API that reports the muxing — the board manual's
  storage table is the authority. Deliberately no hardcoded per-board rules: correct for this
  machine, wrong for everyone else's.

## Then Linux verification found two genuine bugs

The prompt to verify on Linux was well placed — the previous release's Linux checking used
tool shims, and running the real thing in a container immediately produced:

**1. `Virtual Disk · 0 GB · HDD`.** Docker's VM exposes zero-size placeholder block devices,
and they were being listed as drives. Empty card readers do the same on real hardware. Now
skipped on both platforms — a device that holds nothing is not a drive worth a row.

**2. `Virtual Disk · 0 GB`, again — for a device that was not empty.** `Format-DriveSize` had
only TB and GB branches, so a 107 MB volume formatted as "0 GB". Added the MB branch rather
than filtering small drives out: someone's 512 MB USB stick is a real drive and should appear,
correctly sized. It now reads `388 MB`.

Neither was reachable from the Windows box — this machine has no sub-GB or zero-size devices.
Two of my own test assertions were also wrong (I had assumed the container had no `lsblk`, and
asserted the `Ports` row must appear when it is correctly *omitted* without `dmidecode`); those
were fixed rather than worked around.

## Verified

**Linux (container, real `lsblk`):** profile loads, `pc-whoami`/`Format-DriveSize`/
`start-folder`/`pwsh-config` resolve, coreutils still native; no zero-byte drives, real devices
still listed, loop devices excluded, sub-GB drives shown in MB, no `0 GB` row, no stale `Bays`
label; and with no `dmidecode` the slot data reports unsupported with all counts zero and the
`Ports` row correctly omitted rather than faked. Shimmed parser suite re-run with a zero-size
"Empty Card Reader" added to the fixture — correctly excluded, still 3 real drives, boot drive
first, M.2 Wi-Fi key excluded, SATA paired designators totalling 6.

**Windows (live hardware):** full suite green, drives unaffected by the zero-size filter, row
label asserted as `Ports` with `Bays` asserted absent.

Gates: parse, architecture, parity, help registry, privacy.

**Still not verified on live Linux silicon** — the container has no PCI graphics, no SMBIOS
slot records and only virtual block devices, so the `lspci`/`dmidecode` paths remain
shim-verified. Stated here rather than glossed.
