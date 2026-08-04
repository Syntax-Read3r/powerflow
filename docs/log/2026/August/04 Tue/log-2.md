# Log 2 — August 4, 2026 — repairing Codex's Proxmox work, and making it prove a fake drive (v3.16.0)

**User:** "you can go into proxmox.md and see the full chat. you have permission to delete
everything codex wrote if its too costly to refactor. then create a plan and create a better
system that you then test before we release."

## The decision: keep and repair

Deleting was on the table and I did not take it. Roughly 700 lines of the Linux adapter are
genuinely good — the stable-identity resolution (`/dev/disk/by-id`, WWN, major:minor,
`diskseq`), the SMART decoding, and a multi-layer safety model that checks partition
signatures, config references, mount namespaces and open handles before allowing anything
destructive. That is the expensive part and it was done well. What was broken was the seam
between the component and the adapter, and it was broken in ways that were invisible until
you traced a call end to end.

## Five defects, and what each one actually did

**1. The capacity test could never run.** The component asked the user to type one phrase; the
adapter compared against a different one. The strings never matched, so the destructive probe
was unreachable — which reads as "safe" and is in fact a dead command. Both sides now build
`DESTROY <by-id-leaf>` from the same source.

**2. The identity guard always tripped.** `Invoke-ProxmoxCapacityProbe` takes an
`-ExpectedWwn` so it can re-verify the disk has not changed underneath the user between
confirmation and execution. The component never passed it. So the check compared the real WWN
against `$null`, concluded *identity changed*, and refused — permanently. A guard that always
fires is indistinguishable from a broken feature, and hides that the guard was never tested.

**3. `$matches` used as a local.** In `Resolve-PmxDisk` and `Show-PmxGuests`. `$matches` is a
PowerShell **automatic** variable that every subsequent `-match` overwrites — so these were
reading whatever the last unrelated regex had left behind. Renamed to `$hits`. (I then made
the same class of error with `$Pid` in my own team-room code the same day. Noted.)

**4. CI could not see any of it.** The adapter-parity gate matches contract names from a
**hardcoded** regex — it is not automatic. Thirteen Proxmox names were absent from it, so a
function present on only one platform would have passed CI and exploded at runtime on the
other. Added, along with the four team-room names.

**5.** Dead `$node` lookup in `Get-ProxmoxUpdates`.

Also: `pmx help` sat *behind* the "are we on Proxmox?" gate, so the help text was unreadable
on the machine you are most likely reading it from — the laptop you SSH to the host with.

## What I built on top: the report

`docs/proxmox.md` is a real session about a real counterfeit — a "4 TB SSD" whose model string
was literally `SSD 4TB`, whose serial was six digits, whose WWN was all zeros, and which
dropped off the bus twice. The existing code could *show* all of that. It could not **say what
it meant**.

`pmx disk <sel> report` does. Each signal is named, with what it indicates:

| Flag | What fired it |
|---|---|
| `zero-wwn` | WWN is all zeros — no real vendor ships that |
| `generic-model` | model string is a marketing size, not a product |
| `short-serial` / `no-serial` / `numeric-serial` | serial is not a manufacturer serial |
| `no-smart` | the drive refuses SMART entirely |
| `size-mismatch` | reported capacity disagrees with itself |
| `smart-failed`, `reallocated-sectors`, `pending-sectors`, `uncorrectable-sectors`, `media-errors` | genuine failure, separate from fraud |
| kernel I/O errors | from `journalctl -k`, matched against known patterns |

Authenticity and health are kept apart deliberately: a genuine drive can be dying, and a fake
can pass a short read test. Conflating them would produce a confident wrong answer in both
directions.

`-Write` saves the bundle — `report.md`, raw `smart.txt`, `kernel.txt`, `identity.json`, and a
tarball — under `Get-HomePath`/pmx-reports. A refund request should be a file you attach.

## Testing rule I set and kept

**The automated tests never invoke `f3probe --destructive`.** Not once, not on a spare device,
not behind a flag. The destructive path is verified by testing everything *around* it: that
the correct phrase is accepted, that a wrong phrase is refused, that each safety layer refuses
independently, and that the identity re-check fires when identity genuinely differs.

45 assertions pass, including the authenticity flags firing **exactly** on the real
counterfeit's recorded evidence: `zero-wwn`, `generic-model`, `short-serial` — and nothing
else. A flag set that fires on everything would be as useless as one that fires on nothing.

## Windows

Every Proxmox adapter function exists on Windows and returns empty. Proxmox VE is a
Debian-based hypervisor; there is nothing to implement. The stubs exist so the component
loads, parity holds, and `pmx help` works — and every other verb says plainly that this is not
a Proxmox node rather than rendering a dashboard full of zeros.
