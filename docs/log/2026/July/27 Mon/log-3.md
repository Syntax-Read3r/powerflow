# Log 3 — July 27, 2026 — storage and upgrade headroom in pc-whoami (v3.12.0)

**User:** "We need to include HDD or SDD and how much each holds." Then: "also the type of
HDD or SDD it is, meaning is it a 2.5 SATA or older versions. Also we need to add, if there
are free ports, i.e. 2 free ports or some better wording." And when the first answer on ports
was thin: **"you could get this data from the motherboard."**

That last remark was the right call and changed the design.

```
   Disk     Samsung SSD 970 EVO Plus 1TB · 932 GB · M.2 NVMe SSD · 131 GB free on C:
   Disk     Samsung SSD 970 EVO Plus 1TB · 932 GB · M.2 NVMe SSD · 206 GB free on D:
   Disk     WD My Passport 25E1 · 1.8 TB · USB HDD · 686 GB free on E: · external
   Bays     M.2 2 of 4 free · SATA 6 of 6 free
   Slots    PCIe 2 of 3 free · RAM 0 of 4 slots free (max 128 GB)
```

## Form factor: what the API actually knows, and what it doesn't

The ask was "is it a 2.5 SATA or older versions". `Get-PhysicalDisk` has a `FormFactor`
property — and on real hardware it is **blank** (NVMe reports nothing, the USB drive reports
"Unknown"). So there is no API answer to read, and reporting "2.5-inch" as fact would be
invention.

What the OS *does* know is authoritative and answers the same question:

- **`MediaType`** — SSD vs HDD, the kernel's own answer (Linux: the rotational flag).
- **Interface** — NVMe / SATA / USB. This is the real discriminator: NVMe *is* the modern
  drive, SATA SSD *is* the 2.5" generation, and a SATA HDD is the old one.
- **`SpindleSpeed`** — a real RPM when the platter actually spins; 0 on SSDs, "Unknown"
  behind a USB bridge.

So form factor is *inferred from the bus and only where the bus makes it certain* — NVMe ⇒
M.2, SATA SSD ⇒ 2.5" — and a spinning SATA disk gets its RPM rather than a guessed size,
because 3.5" and 2.5" are indistinguishable from here. The inference is commented as an
inference in both adapters.

## Free ports: the motherboard really does publish them

The user's suggestion paid off. SMBIOS carries it, and Windows exposes it directly:

- **Type 8 port connectors** (`Win32_PortConnector`): this board declares
  `M.2_1..M.2_4(SOCKET3)` plus `M.2(WIFI)`, and `SATA6G_12`, `SATA6G_34`, `SATA6G_E12`.
  Two details that matter — the **Wi-Fi M.2 key is excluded** (it takes a radio, not a
  drive), and SATA connectors are labelled in **pairs**, so `SATA6G_12` is ports 1 *and* 2;
  counting records would have reported 3 ports where there are 6, so the trailing digit run
  is counted instead.
- **Type 9 system slots** (`Win32_SystemSlot`): carries a genuine used/free flag
  (CurrentUsage 3 = Available, 4 = In Use) — 2 of 3 free here, no inference at all.
- **Type 16/17**: declared memory slots vs populated, plus the board's 128 GB maximum.

Occupancy for M.2/SATA is counted from the drives actually attached by bus, because SMBIOS
describes the *board*, not what is plugged into it. No hardcoded database of board models —
that would be unmaintainable and wrong for everyone else's machine.

**What is deliberately not claimed:** SATA *port* usage beyond counting attached SATA drives,
and drive health on Linux (SMART needs root; asserting health we cannot see would lie).

## Details that came from running it, not reasoning about it

- **Two identically-named NVMe drives.** Keying or grouping by `FriendlyName` would have
  silently merged them into one row. Everything is keyed by device ID.
- **Free space belongs to volumes, capacity to disks.** Partitions are the join; a drive's
  free figure is the sum of its own mounted partitions, not a machine-wide total. On Linux
  the same job is done by `PKNAME` (a partition's parent disk).
- **The external USB drive** is marked and sorted last — it is storage you can unplug.
- **The boot drive leads.** First sort attempt put a 4 TB data HDD above the NVMe the machine
  boots from; now the drive holding `C:` (Linux: `/`) comes first.
- **`Format-Size` was reused, then wasn't.** apps.ps1 already had a byte formatter, but at
  drive scale "931.51 GB" is noise where "932 GB" is the fact, so the component got a small
  `Format-DriveSize` for whole-drive presentation — leaving installed-apps' 2-decimal output
  untouched.

## Verified

**Windows, live hardware — 60 assertions:** 3 drives found, the two same-named NVMe kept
separate, NVMe⇒SSD⇒M.2, USB flagged external, internal-first ordering, free space per drive
with letters mapped, SSDs at 0 rpm; from SMBIOS: 4 M.2 sockets with 2 used, 6 SATA ports,
3 PCIe with 2 free, 4 memory slots all used, 128 GB max, and used never exceeding total.
Rendered rows checked including "no 2-decimal drive sizes".

**Linux, container with PATH shims:** `lsblk -b -P` parsing — loop/optical devices excluded,
ROTA→SSD/HDD, NVMe⇒M.2, SATA SSD⇒2.5", SATA HDD given no guessed form factor, model names
read, free space summed per parent disk, mountpoints listed, boot drive (`/`) first with a
bigger data HDD sorting after it. `dmidecode -t 8 -t 9` parsing — M.2 sockets counted with
the Wi-Fi key excluded, SATA paired designators totalling 6, PCIe In-Use/Available split.
Plus the no-tooling path: no invented drives, and a note naming what is missing.

Gates: parse, architecture (all CIM/lsblk confined to adapters), parity (`Get-DiskInfo` and
`Get-SlotInfo` on both platforms; neither called from `components/`, so the CI contract regex
is unchanged), help registry, privacy.
