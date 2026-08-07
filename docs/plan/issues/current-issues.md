# Current Issues

## Issue 18 — PMX has no detailed VM configuration view

**File:** `components/proxmox/vm-read.ps1`, PMX model/view/help/tests
**Severity:** Low
**Description:** The compact `pmx vm show` summary now has correct IEC units but does not expose
sockets/total vCPUs, CPU type, agent, NIC model/bridge/MAC/firewall, disk placement, boot order,
firmware, or machine type. Output-mode overrides work but lack direct precedence coverage and help
that explains their relationship to `pmx config set output`.

**Status:** Open — component design now includes the required `-t`/`-j` convenience aliases and
`--full` view in `docs/plan/proxmox/pmx-full-vm-view-and-output-overrides.md`; awaiting approval.

---

## Resolved

### Issue 16 — SSH and PMX authentication disclose a saved endpoint

**Files:** platform SSH/PMX adapters, network/Proxmox privacy components and regressions
**Severity:** High
**Description:** OpenSSH's native password prompt printed the saved username/address during
`srv <name>`, and remote PMX propagated endpoint-bearing `Permission denied` diagnostics to the
bare dashboard. Both bypassed the alias-only privacy contract.

**Status:** **RESOLVED — confirmed by test 2026-08-07 (v4.4.0).** 24 assertions, all green:

*The askpass boundary* — both platform SSH adapters force `SSH_ASKPASS` **and**
`SSH_ASKPASS_REQUIRE`, so OpenSSH cannot fall back to its own terminal prompt (which is what
printed the endpoint). Both helpers prompt with `Password for '<alias>':` and neither
interpolates a `user@host` anywhere. The Linux askpass cache is `chmod 700`. Nothing is
persisted.

*The disconnected state* — `Write-PmxDisconnectedState` categorises the failure, **validates the
alias against `^[a-z0-9][a-z0-9_-]{0,63}$` before printing it** (so a malformed alias degrades to
the literal "saved server" rather than leaking whatever it contained), and directs the user to
`srv <alias>`. It is now wired at all 17 session-failure sites — it was 1 of 17 until v4.2.0,
which is what let raw errors reach the dashboard in the first place.

*End to end* — a disconnected `pmx vm list` and `srv list` were both checked to contain **no
dotted-quad and no `user@host`** anywhere in their output.

*Standing regressions* — `tests/network/` covers the adapter contract, authenticated-info
disclosure, and public output, and runs on every release.

### Issue 9 — PowerShell 5.1 compatibility claim is not currently testable

**Files:** `README.md`, `docs/installation.md`, `install.ps1`
**Severity:** Medium
**Description:** Documentation advertised Windows PowerShell 5.1, but the UTF-8-without-BOM
source tree is decoded as the legacy ANSI code page by 5.1 and produces widespread parse errors
around Unicode text. At least one adapter also uses PowerShell 7's null-coalescing operator.

**Status:** **RESOLVED — floor raised to PowerShell 7.0 (v4.4.0), owner's decision.**

Raising the floor rather than restoring 5.1 is the honest fix: 5.1 support was **documented but
never exercised**. Every supported install path and both CI legs already run `pwsh`, so nothing
in the release pipeline ever proved the claim — and the tree would have to stop using non-ASCII
output (box-drawing, emoji) or gain BOMs everywhere to make it true.

Changed: the README badge (5.1+ → 7.0+), the README prerequisites row, the installation-doc
prerequisite, `#Requires -Version 5.1` → `7.0` in `install.ps1`, and the "installing into the
5.1 profile" section replaced with an explanation of why it is unsupported.

The bootloader's defensive 5.1 detection (`$PSEdition -eq 'Desktop'`) is **deliberately left in
place**: it costs nothing, and a clear failure on an unsupported host beats an obscure one.
