# pc-whoami — the machine's vital signs, one screen

**Status: IMPLEMENTED (2026-07-17, staged for v3.4.0).** This document is the design it
was built from. Deviations from plan, decided at build time:

- Open Q1 (name): `pc-whoami` / `pc-cap` kept as drafted.
- Open Q2 (window): `-days N`, default 7.
- Open Q3 (BIOS latest-check): search string only, as drafted.
- Open Q4 (DC on desktops): hidden when no battery is present, on both platforms.
- Open Q5 (Linux cap persistence): reboot-reset kept, as drafted.
- Added beyond plan: unelevated Windows sessions cannot LIST `C:\Windows\Minidump`, so
  "0 dumps" beside bugcheck records naming dump files would be a lie of omission — the
  dashboard now says the folder needs elevation to read.
- The architecture gate gained `powercfg` / `Get-CimInstance` / `Get-WinEvent` /
  `$env:SystemRoot` as forbidden in `components/`, making the adapter boundary here
  CI-enforced like the rest.

---

## Why this exists

A real diagnosis session (CPU throttling + WHEA crashes on the author's 12700K desktop)
took a wall of hand-typed incantations:

```powershell
powercfg /getactivescheme
powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX     # answer arrives as 0x55
powercfg /query SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE
Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; Id=1 }
Get-WinEvent -FilterHashtable @{ LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; Id=1001 }
Get-ChildItem 'C:\Windows\Minidump\*.dmp'
Get-CimInstance Win32_BIOS        # BIOS from 2022, ~20 revisions behind — nobody knew
```

Every one of those answers had to be decoded by a human (or an AI): `0x55` is hex for 85,
`GameTurbo` is not a stock Windows plan so *something* installed it, a 2022 BIOS date means
"seriously outdated". The question being asked the whole time was simple:

> **"Is something throttling or destabilising this machine?"**

That is one command's job.

### The trigger incident, and the rule it produces

During that session, a previous assistant script capped the CPU at 85% "temporarily" and
its restoration never happened. The machine was left throttled with no record of what the
original values were. The session's own conclusion:

> *"Do not let [the assistant] silently modify global power settings without guaranteed
> restoration. It has currently left your machine at 85%, which demonstrates that its
> cleanup mechanism is not dependable."*

**Rule for this feature: any command that changes machine state must write the prior state
to disk BEFORE changing anything, and the dashboard must show a banner for as long as the
change is active.** This is the same philosophy as the install manifest: record what you
changed, or you cannot undo it — and "I'll restore it afterward" is a promise, not a
mechanism.

---

## Command surface

### `pc-whoami` — the dashboard

```
🖥️  MACHINE
   CPU      12th Gen Intel i7-12700K · 12c/20t
   RAM      32 GB · uptime 2d 4h
   BIOS     1720 (2022-08-16)   ⚠️ over 3 years old

🔌 POWER
   Plan     GameTurbo (High Performance)   ⚠️ custom/OEM plan — not a Windows default
   CPU cap  85% on AC · 100% on DC         ⚠️ full speed is being withheld
            └─ details:  pc-whoami --power

💥 STABILITY (last 7 days)
   WHEA errors   3    ⚠️  └─ details:  pc-whoami --crashes
   Crash dumps   2 minidumps · newest Jul 12
```

Design rules:

- **Green stays silent.** A healthy machine prints short, calm lines. Warnings are the
  only thing that get a ⚠️ and every ⚠️ names the flag that drills in.
- **No hex, no GUIDs, no provider names.** `0x55` renders as `85%`. Plans are compared
  against the stock set (Balanced / High performance / Power saver / Ultimate) and
  anything else is flagged as custom/OEM — that is how the GameTurbo discovery happened.
- **BIOS age is computed**, because "1720, 16 Aug 2022" means nothing until someone tells
  you it's three years and ~20 revisions old.
- If a `pc-cap` record exists (see below), a permanent banner:
  `⚠️ CPU capped at 85% by pc-cap on Jul 14 — undo:  pc-cap restore`

### Flags

| Flag | Shows |
|---|---|
| `pc-whoami --power` | every power plan (active one marked), AC/DC caps decoded, boost mode, min/max processor state |
| `pc-whoami --crashes` | WHEA events with plain-language summaries · bugcheck 1001 messages · minidump list with dates/sizes |
| `pc-whoami --crashes --export` | the above, plus raw WHEA XML + minidump inventory written to `~/Desktop/pc-crash-report/` — the bundle you hand to an AI or a forum |
| `pc-whoami --bios` | firmware version/date/vendor, board model — and the exact string to search for updates ("ASUS PRIME Z690-A BIOS") |

Windows-style single-dash flags are correct here — these are PowerFlow's own commands, not
GNU twins, so the single-dash-is-Linux rule does not apply.

### `pc-cap` — state change with guaranteed restoration

```
pc-cap 85          cap the CPU at 85% (AC + DC) — records prior state FIRST
pc-cap             show the current cap and whether a restore record exists
pc-cap restore     put back exactly what was recorded, then delete the record
```

Mechanics:

1. **Before** touching anything, write `~/.powerflow-power-state.json`:
   ```json
   {
     "savedAt":   "2026-07-14T15:32:00Z",
     "plan":      "381b4222-...-df2e",
     "planName":  "Balanced",
     "acMax":     100,
     "dcMax":     100,
     "reason":    "pc-cap 85"
   }
   ```
2. If a record **already exists**, `pc-cap 85` refuses to overwrite it (the record holds
   the true original; capping 100→85→70 must not make "restore" mean 85). It says so and
   points at `restore`.
3. `pc-cap restore` re-applies plan + values from the record, **verifies** by re-querying
   (`powercfg` exit codes lie by omission — read the value back), and only then deletes
   the record.
4. `pc-whoami` shows the banner for as long as the record exists. An abandoned cap is
   therefore impossible to *not* notice — which is precisely what went wrong in the
   trigger incident.

Out of scope, deliberately: BIOS flashing, plan creation/deletion, undervolting, anything
Armoury-Crate-shaped. This is a thermometer and one clearly-labelled dial, not a tuning
suite.

---

## Architecture

`powercfg`, WHEA, CIM and minidumps are OS APIs — banned in `components/`. Adapter
contract, per the standard pattern:

| Contract | Windows backend | Linux backend |
|---|---|---|
| `Get-PowerSnapshot` | `powercfg /getactivescheme`, `/query SUB_PROCESSOR` (PROCTHROTTLEMAX, PERFBOOSTMODE); decode hex; stock-plan detection | cpufreq: `scaling_governor`, `scaling_max_freq` vs `cpuinfo_max_freq` per core (a governor of `powersave` or a pinned max ≈ the "cap") |
| `Get-StabilityEvents` | `Get-WinEvent` WHEA-Logger Id 1 + WER 1001; `C:\Windows\Minidump\*.dmp` | `journalctl -k` MCE / `mce:` lines; previous-boot errors via `journalctl -b -1 -p err`; kdump if present, else "no dump facility" |
| `Get-FirmwareInfo` | `Win32_BIOS` + `Win32_BaseBoard` CIM | `/sys/class/dmi/id/{bios_version,bios_date,board_name,board_vendor}` — **readable without root**; fall back to `dmidecode` hints if the sysfs nodes are absent (some VMs) |
| `Set-CpuCap` / `Restore-CpuCap` | `powercfg /setacvalueindex` + `/setdcvalueindex` + `/setactive`, then re-query to verify | write `scaling_max_freq` (needs root → route through `Invoke-Elevated`); restore likewise |

Degradation is honest, in the `perms.ps1` style: a VM with no DMI data says *"firmware
info not exposed by this hypervisor"*, not a fabricated version. A Linux box without
kdump says there is no dump facility rather than pretending zero crashes means health.

Both adapter files ship together (`platform/windows/adapters/health.ps1`,
`platform/linux/adapters/health.ps1`) or CI's parity gate fails the release — this is a
feature, not a chore: it forces the Linux side to exist on day one instead of rotting as
a TODO.

### File plan

```
components/system/health.ps1              pc-whoami, pc-cap  (rendering + logic, no OS calls)
platform/windows/adapters/health.ps1      the four contract functions, Windows
platform/linux/adapters/health.ps1        the four contract functions, Linux
```

Help menu: `components/system/` → **⚙️ CONFIGURATION & SETTINGS** section of `pwsh-h`,
plus COMPONENTS.md rows for all three files (Platform column: Both).

### Elevation

Reading is unprivileged on both platforms (nice surprise: `/sys/class/dmi/id` needs no
root). Writing (`pc-cap`) needs admin on Windows and root on Linux → `Assert-Admin` at
the top of the set/restore paths, never for the dashboard. The dashboard must always work
without elevation — a triage tool you need admin to *open* is a triage tool nobody runs.

---

## Teaching layer tie-in (cheap wins, same session)

The lesson library already covers `journalctl`. Two additions fit naturally:

- `lesson powercfg` — Windows-only concepts explained the way `lesson chmod` explains
  mode bits: what a plan is, what PROCTHROTTLEMAX means, why `0x55` is 85.
- The brother pattern in reverse: `pc-whoami --power` can print
  `🐧 real windows command: powercfg /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX`
  in `full` lesson mode — same muscle-memory trick as `changemode` → `chmod`, so the tool
  teaches the raw command it wraps.

---

## Open questions (decide at build time)

1. **Name.** `pc-whoami` (chosen working name — memorable, matches `whoami`'s "identity"
   framing). Alternatives considered: `pc-h` (collides with help-menu naming convention),
   `sys-check` (vague). A `pc` alias could front all of it later (`pc power`, `pc crashes`)
   if the flag list grows past comfort.
2. **Stability window.** 7 days is the draft default for the WHEA/dump summary. Flag to
   widen: `-days 30`?
3. **BIOS latest-version check.** The diagnosis session found the BIOS 20 revisions behind
   by *searching the vendor site*. Automating that means scraping ASUS/MSI/Gigabyte pages —
   fragile, vendor-specific, and a network call in a diagnostic tool. Draft position: print
   the exact search string and stop. Revisit only if it hurts.
4. **DC vs AC on desktops.** A desktop has no battery; DC values are noise there. Detect
   (`Win32_Battery` empty / no `/sys/class/power_supply/BAT*`) and hide the DC column?
5. **`pc-cap` on Linux.** Frequency pinning via `scaling_max_freq` is per-core and resets
   on reboot. Is reboot-reset acceptable (it self-heals, which suits a "temporary safety
   measure") or does the record need a systemd unit to reapply? Draft: reboot-reset is a
   feature, keep it.

## Release sizing

New user-facing commands → **minor** bump per the release rules. Estimated as one focused
session: two adapters (~150 lines each), one component (~250), help/docs/CHANGELOG, and a
Docker + local verification pass. No installer changes, no CI changes beyond the parity
list picking up the four new contract names automatically.
