# Current Issues

## Issue 18 — PMX has no detailed VM configuration view

**Files:** `components/proxmox/vm-read.ps1`, PMX model/view/help/tests
**Severity:** Low
**Description:** The compact `pmx vm show` summary now has correct IEC units but does not expose
sockets/total vCPUs, CPU type, agent, NIC model/bridge/MAC/firewall, disk placement, boot order,
firmware, or machine type. Output-mode overrides work but lack direct precedence coverage and help
that explains their relationship to `pmx config set output`.

**Status:** Open — component design now includes the required `-t`/`-j` convenience aliases and
`--full` view in `docs/plan/proxmox/pmx-full-vm-view-and-output-overrides.md`; awaiting approval.

## Issue 16 — SSH and PMX authentication disclose a saved endpoint

**Files:** platform SSH/PMX adapters, network/Proxmox privacy components and regressions
**Severity:** High
**Description:** OpenSSH's native password prompt printed the saved username/address during
`srv <name>`, and remote PMX propagated endpoint-bearing `Permission denied` diagnostics to the
bare dashboard. Both bypassed the alias-only privacy contract.

**Status:** Fix applied — awaiting user confirmation. `srv` now uses an alias-only platform
askpass boundary without persisting credentials; PMX categorizes remote failures and renders a
calm alias-only disconnected state with `srv <alias>` guidance.


## Issue 9 — PowerShell 5.1 compatibility claim is not currently testable

**Files:** `README.md`, `docs/installation.md`, repository PowerShell sources
**Severity:** Medium
**Description:** Documentation advertises Windows PowerShell 5.1, but the UTF-8-without-BOM
source tree is decoded as the legacy ANSI code page by 5.1 and produces widespread parse
errors around Unicode text. At least one existing adapter also uses PowerShell 7's null-
coalescing operator. The supported release workflows and Linux installer execute `pwsh`, so
this is pre-existing and separate from PMX, but the compatibility promise needs a dedicated
decision: restore/continuously test 5.1 or raise the documented runtime floor.

**Status:** Open — discovered during the v3.17.0 release-recovery audit; not expanded into
this PMX/Starship release fix.
