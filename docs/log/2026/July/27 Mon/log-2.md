# Log 2 — July 27, 2026 — pc-whoami learns the hardware: GPU, RAM spec, motherboard (v3.11.0)

**User:** "pc-whoami does not display gpu, we need to add that too. also if we could extract
the type of RAM and its speed, that would be great instead of just displaying ram." Then,
mid-build: "we need the name of the gpu, not just nvidia 4090", "We also need to display
motherboard. thats a crucial too", and "you can display integrated gpu and the proper gpu on
different rows."

Result:

```
🖥️  MACHINE
   CPU      12th Gen Intel Core i9-12900K · 16c/24t
   GPU      NVIDIA GeForce RTX 4080 · 16 GB
   iGPU     Intel UHD Graphics 770
   RAM      32 GB · DDR4-3600 · 4x8GB
   Board    ASUS ROG STRIX Z690-A GAMING WIFI D4
   BIOS     1720 (2022-08-12)   ⚠️ over 3 years old
   Up       0d 0h
```

All of it lives in `platform/*/adapters/health.ps1` — `Get-CimInstance` is on the
architecture gate's forbidden list for `components/`, so the component only renders.
`Get-MachineInfo` gained `Gpus` and `Memory` rather than adding new contract functions, which
keeps the CI parity regex untouched.

## What real hardware taught us (none of it guessable)

**`AdapterRAM` is a uint32 and wraps above 4 GB.** The 16 GB RTX 4080 in this machine reports
4293918720 (~4.29 GB). VRAM therefore comes from the display-class registry key's
`HardwareInformation.qwMemorySize`, which is 64-bit.

**On an integrated chip, `AdapterRAM` reports SHARED system memory.** The first working build
showed "Intel UHD Graphics 770 · 2 GB · discrete" — inventing VRAM the chip doesn't have and
misclassifying it. Only dedicated memory counts now; an iGPU shows no VRAM, which the `iGPU`
label explains.

**`Win32_PhysicalMemory.MemoryType` is 0/"Unknown"** on this DDR4 board, so the type comes
from `SMBIOSMemoryType` (26 = DDR4, 34 = DDR5, …).

**Configured ≠ rated speed.** Reporting the rated figure would hide XMP/EXPO being off, so
the row shows what the sticks actually run at and warns when the two differ.

**There were three video controllers**, one a dead "Virtual Desktop Monitor". Streaming and
virtual display drivers are filtered; a real card with an unhealthy driver is kept and
flagged, since that is exactly what a health command is for.

**The motherboard needed no new plumbing at all** — `Get-FirmwareInfo` has returned
`BoardVendor`/`BoardName` since v3.4.0 and nothing ever rendered them.

## Two bugs my own tests caught

**`"Intel Corporation" -match 'ATI'` is TRUE.** `-match` is case-insensitive and
substring-based, and "Corpor**ati**on" contains "ati" — so the discrete-brand check labelled
every Intel iGPU as a discrete AMD card. That is why the row still read `GPU` after the
"fix". Now `\bATI\b`, in the vendor formatter too.

**I deleted the uptime row.** The motherboard edit's replaced region swallowed the two
uptime lines, and `pc-whoami` silently lost a row it has always had. The assertion for it
failed; uptime is back, now on its own line since RAM no longer has room to share.

## Linux: same three rows, different mechanisms

GPU from `nvidia-smi` first (authoritative marketing name *and* true VRAM), then `lspci -mm`,
preferring the bracketed product name — `Navi 31 [Radeon RX 7900 XTX]` → "AMD Radeon
RX 7900 XTX", which is precisely the "name of the GPU, not just the chip" ask.

Integrated vs discrete is decided by **PCI topology, not vendor**. Two rejected heuristics:
"AMD ⇒ discrete" mislabels every Ryzen APU, and "no VRAM figure ⇒ integrated" mislabels a
discrete card whose amdgpu driver isn't bound (live USB, container) — the first version had
exactly that bug, calling an RX 7900 XTX integrated. Bus 00 is the root complex where
integrated graphics live; a card sits behind a PCIe bridge on a higher bus. VRAM is keyed by
PCI slot, because taking the largest `mem_info_vram_total` across cards would credit the
discrete card's memory to the iGPU.

RAM type/speed needs SMBIOS, which on Linux means `dmidecode` and therefore root
(`/sys/firmware/dmi/tables/DMI` is 0400). Attempted as root or via `sudo -n` — non-interactive
so a status command can never block on a password — otherwise the size is shown with a plain
reason. Motherboard needs no root at all.

## Verified

**Windows, live hardware:** 38 assertions — virtual adapter excluded, full product name,
16 GB (not the 4 GB wrap), iGPU integrated with no VRAM, discrete sorted first, DDR4/3600/
4x8GB/32 GB/slots, `(R)`/`(TM)` stripped, board shortened to ASUS, **no serial number
exposed**, and every rendered row present including `Up`.

**Linux, container:** honest degradation with no tooling (no invented GPU; size from
/proc/meminfo with a note naming dmidecode). Then the parsers driven with realistic output
via PATH shims: `dmidecode -t 17` → DDR5, running 4800 vs rated 5600, 2 populated of 4 slots,
2x16GB, vendor and part number; `lspci -mm` → bracketed names, non-GPU PCI devices ignored,
discrete-first ordering, and an AMD-APU-on-bus-00 case confirming it is not called discrete.

Gates: parse, architecture (no OS API in `components/`), parity, help registry, privacy.
