# Log 1 — July 17, 2026 — pc-whoami / pc-cap built; v3.3.2 rescued

**Two jobs this session: build the machine-health feature from `docs/plan/pc-whoami/`, and —
discovered mid-way — rescue v3.3.2, whose release had silently failed three days ago.**

## v3.3.2 was never published, and nobody noticed

While dating the CHANGELOG I found v3.3.2 tagged (Jul 14) with **no GitHub release**. Its
release run failed on exactly one leg: Arch, where the installer's anonymous
`api.github.com` call for the latest PowerShell release got a **403 rate limit** (shared CI
runner IPs). Seven other distros passed; the same leg had passed 30 minutes earlier on
v3.3.1. A transient infrastructure failure, mistaken for nothing because no one was looking.

- **Immediate:** re-ran the failed jobs on the same tag — passed, **v3.3.2 published Jul 17**.
- **Durable:** the installer now resolves the latest pwsh in three layers: the
  `releases/latest` **redirect** on github.com (not the API — no meaningful rate limit),
  then the API **with `GITHUB_TOKEN`** when present (CI passes it now), then a pinned
  known-good version with a loud warning. Verified all three layers on Arch.
- **Lesson recorded:** a release pipeline that can fail without anyone noticing is a
  pipeline that HAS failed without anyone noticing — twice now (3.2.0, 3.3.2).

## pc-whoami / pc-cap (staged for v3.4.0)

Built to the plan doc; scope and platform decisions were pre-agreed (dashboard + pc-cap,
both platforms via adapters). Files:

- `platform/windows/adapters/health.ps1` — powercfg (hex decoded, stock plans matched by
  **GUID** because names are localised), WHEA/WER via Get-WinEvent (which THROWS on zero
  events — try/caught so an empty week isn't an error), CIM firmware, minidumps.
- `platform/linux/adapters/health.ps1` — cpufreq governor + scaling_max_freq as the cap,
  kernel MCE via journalctl ("cannot read" ≠ "zero errors"), `/sys/class/dmi/id` for
  firmware (readable without root), `/var/crash`.
- `components/system/health.ps1` — rendering only. `pc-whoami` (+ `-power`, `-crashes
  [-export]`, `-bios`, `-days`), `pc-cap N|restore`.

**Validated against the machine that motivated the feature.** The dashboard reproduced the
entire manual diagnosis session in one command: the live 85% AC cap (correctly attributed
as *not* PowerFlow's), GameTurbo flagged custom/OEM by GUID, BIOS 3.9 years old, 4 WHEA
errors — and surfaced something new: **two bugchecks that same morning** (0x7f, 0x20001),
plus the fact that `C:\Windows\Minidump` lists as empty without elevation, which the
adapter now states rather than implying "0 dumps".

**pc-cap's restoration guarantee, tested with mocked adapters (21 assertions):** the record
hits disk *before* the change (the mock asserts the file exists when the setter runs); a
second cap refuses while a record exists; restore targets the *recorded* plan, verifies by
re-query, deletes the record only on verified success and keeps it on failure; bad input
writes nothing; not-admin refuses before writing anything.

**Bugs caught during the build, before ship:**

- `Assert-Admin` **returns** `$false` — it does not throw. The component originally piped
  it to `Out-Null`, discarding the answer, so `pc-cap` would have proceeded unelevated.
  The mocked not-admin test exists because of this.
- The strengthened architecture gate (`powercfg`, `Get-CimInstance`, `Get-WinEvent`,
  `$env:SystemRoot` now forbidden in `components/`) is why the teaching line ("real
  command: powercfg …") lives in the adapter's `RealCommand` field rather than the
  component — the component may not even *name* powercfg.

**CI:** six new contract functions added to the parity regex in `release-validate.yml`
(the list is hardcoded — new adapter calls are NOT picked up automatically, whatever the
plan doc hoped); forbidden-pattern strengthened; `GITHUB_TOKEN` passed to the distro
matrix. All gates green on Windows (real machine) and Linux (container, honest-degradation
paths exercised: no cpufreq, no journalctl, no DMI).

## The startup update check (audited on request — and it was a landmine)

The requested behaviour already existed: daily check, version shown, install-or-defer
offered. But the audit found **"Install now" was a pre-2.0 relic that downloaded ONLY the
bootloader and overwrote `$PROFILE`** — new bootloader + old components, version file
untouched, so the "updated" install kept reporting the old version and re-prompted daily,
forever. It had presumably never been exercised on the component layout.

Rewritten:

- `powerflow-update` now downloads `install.ps1` and runs it in a **child `pwsh
  -NoProfile`** (the installer must not run inside the session whose files it replaces).
  Full tree, manifest respected — the 3.3.2 upgrade fixes made this possible.
- Found and fixed in the process: **`-NoDeps` erased dependency ownership** (it skipped
  the whole deps section, so the manifest was rewritten with an empty list — uninstall
  would then keep every tool forever). `-NoDeps` now carries the previous records
  forward; verified in Docker: install → `-NoDeps` re-install → ownership intact →
  uninstall still removes owned deps and keeps pre-existing git.
- Version discovery via the **`releases/latest` redirect** (no API quota — the same 403
  class that killed v3.3.2), API as fallback with the existing 3-day cooldown.
- Defer became real: **tomorrow / a week / off**, marker holds a date, corrupt or legacy
  markers degrade to "check again".
- Redirected-stdin loads announce on one line and snooze — no Read-Host against EOF, and
  the fall-through now writes the marker (it previously didn't, so non-interactive loads
  re-checked every single time).

14 harness assertions (run with stdin genuinely redirected), plus the real-repo redirect
resolving v3.3.2 and a no-op `powerflow-update` against the live release.
