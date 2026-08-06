# PowerFlow Proxmox — v2 plan (acceptance testing and evidence)

**Status:** **Delivered in v3.16.0 (2026-08-04).** Supersedes `powerflow-pmx.md`, which is kept
for history and marked superseded.
**Author:** Claude, after reading `docs/proxmox.md` (the real session) and reviewing Codex's build.

## Deviations from this plan, as delivered

- **`pmx disk <sel> verify`** — the destructive acceptance test that folds evidence collection
  into the F3 run — is **deferred**, as scoped. `Invoke-ProxmoxCapacityProbe` now *returns* its
  f3probe output, which is the enabling half; wiring that into the evidence bundle is the
  remaining work.
- **Six defects were found by executing the code**, not by review, after this plan was written.
  Two were total failures of the whole subsystem on a real host (`$matches` used as a local in
  `Get-PmxStableIds`; infinite recursion in `Get-PmxBlockDescendants`). See
  `docs/log/2026/August/04 Tue/log-3.md`. Both are now pinned by a CI step that runs the
  adapter parsers against recorded `smartctl`/`lsblk` output.
- **The destructive confirmation is `DESTROY <by-id leaf>`, not the serial** the v1 plan
  specified. A serial names a product; the by-id leaf names *this device*. All comparisons on
  that path are `[StringComparison]::Ordinal` — `-cne` is culture-sensitive and accepted
  zero-width characters.
- **`Health`/`Wearout` were removed** from the disk record: the list request passes
  `--skipsmart 1`, so Proxmox returns `UNKNOWN`/`N/A` for them permanently.

## Why v2

The v1 slice built a Proxmox *inspection dashboard*: node, disks, pools, guests, updates, SMART.
That is useful, and most of its adapter is good. But `docs/proxmox.md` records what the owner
actually did on the night that mattered, and **none of v1 would have helped**:

1. Identify a new disk and its stable `/dev/disk/by-id` name — the very command that failed
   because PowerFlow's `ls` emitted ANSI colour into a pipe.
2. Read its identity and notice the counterfeit tells: model literally `SSD 4TB`, a six-digit
   serial, and an **all-zero WWN**.
3. Run an F3 capacity probe.
4. Run a sustained write, then a read-back verify.
5. When it failed, hand-collect `journalctl -k`, SMART after, `e2fsck` output and the f3read
   log; hand-write a summary; `tar` it; `scp` it to Windows.
6. Write a seller-facing explanation for a refund.

Steps 1–2 are seconds of work that a tool should do perfectly. Steps 5–6 are a half hour of
error-prone copy-paste, done under stress, *after* a disk has already corrupted a filesystem.
That is the gap v2 fills.

## Decision on the v1 code

**Keep and repair.** A rewrite would discard a working structured disk model, correct
ATA+NVMe SMART parsing, and a genuinely thorough fail-closed safety gate, only to re-derive
them. The defects are contained and specific.

### Defects to fix first (all confirmed by execution)

| # | Defect | Effect |
|---|---|---|
| 1 | Component prompts for the **serial**; adapter requires `DESTROY <by-id leaf>` | Capacity test can never run. Fails closed, so it is dead rather than dangerous |
| 2 | Component never passes `-ExpectedWwn`; adapter compares `$d.Wwn -cne ''` | "Identity changed" always fires — blocks it a second time |
| 3 | `$matches` used as a local in `Resolve-PmxDisk` / `Show-PmxGuests` | `$matches` is an automatic variable; any `-match` in scope clobbers it |
| 4 | The 12 Proxmox contract names are absent from the CI parity regex | The adapter-parity gate silently checks nothing for this feature |
| 5 | `$node = Get-PmxNodeName` assigned and unused in two functions | Dead code plus a wasted `pvesh` call each |

Resolution for #1: keep **`DESTROY <by-id-leaf>`** as the phrase. It names the device being
destroyed; a serial names a product and is easy to paste from the wrong row. Fix the prompt to
ask for what the adapter actually checks, and show both serial and by-id in the banner.

## What v2 adds

### `pmx disk <selector> report` — non-destructive evidence bundle

Reads nothing but SMART, kernel log and device metadata. Writes a folder, never the disk.

```
pmx disk sdg report            # writes ~/pmx-reports/<serial>-<timestamp>/
```

Produces:

- `report.md` — identity, capacity, **authenticity flags**, SMART summary, kernel I/O errors
  found in the window, and a plain-English verdict
- `smart.json` / `smart.txt` — the raw `smartctl -j -x` and human forms
- `kernel.txt` — `journalctl -k` filtered to this device, plus the decisive patterns
  (`DID_BAD_TARGET`, `device offline`, `I/O error`, `Synchronize Cache.*failed`,
  `aborted journal`, `Remounting filesystem read-only`)
- `lsblk.json`, `by-id.txt` — the structured device view and every stable identity
- `evidence.tar.gz` — all of the above, ready to attach to a refund claim

### Authenticity flags — the tells, checked automatically

Derived directly from what the counterfeit drive showed:

| Flag | Trigger | Why it matters |
|---|---|---|
| `zero-wwn` | WWN absent or all zeros | Genuine drives carry a real IEEE identifier |
| `generic-model` | Model matches `^SSD ?\d+ ?TB$`-style generic strings | Real vendors name their products |
| `short-serial` | Serial shorter than 8 chars or all digits | Vendor serials are long and mixed |
| `no-smart` | SMART unavailable on a SATA/SAS device | Counterfeit controllers often fake or omit it |
| `size-mismatch` | Reported size disagrees with F3's usable size | The classic fake-capacity signature |
| `slow-sustained` | Sustained write below a floor during a test | 18 MB/s is not an SSD |

Flags are **reported, never decisive on their own** — the report says what was observed and
what it suggests, not "this is a fake". `docs/proxmox.md` makes exactly that distinction, and
it is the difference between evidence and an accusation.

### `pmx disk <selector> verify` — the destructive acceptance test

Behind the existing safety gate, plus the corrected confirmation. Runs the sequence the owner
ran by hand, and **collects evidence as it goes** rather than after the damage:

1. pre-flight safety gate (unchanged, already thorough)
2. SMART before
3. `f3probe --destructive` — capacity truth
4. optional sustained `f3write` / `f3read` on a temporary filesystem
5. kernel-log watch throughout, so a mid-test disappearance is captured with its timestamp
6. SMART after
7. the same evidence bundle as `report`, with the test results folded in

Rules kept from v1: never in a pipe, no force bypass, re-check identity after the prompt,
per-disk lock, `udevadm settle`. Automated tests never invoke `f3probe --destructive`.

## Non-goals

VM/container lifecycle, pool creation, `zpool` mutation, package upgrades, and any automatic
"this is counterfeit" verdict.

## Testing

- Parse; architecture gate; help-registry gate; **contract parity with the regex extended**.
- Renderers and flag logic against fixtures, including the exact identity of the drive in
  `docs/proxmox.md` (`SSD 4TB` / short numeric serial / zero WWN) — the flags must fire on it.
- Every refusal path of the destructive gate, by fixture. Never a real probe.
- Confirm the corrected phrase is the one the adapter checks, and that a wrong phrase refuses.
- Windows: the whole surface degrades honestly.
