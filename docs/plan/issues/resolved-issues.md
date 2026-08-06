# Resolved Issues

## Issue 15 — `pmx help` omits required arguments and routed commands

**Files:** `components/proxmox/help.ps1`, `components/proxmox/vm-read.ps1`,
`components/proxmox/vm-change.ps1`, PMX regressions, README and release notes
**Severity:** Medium
**Description:** The hand-written overview listed operation names such as
`pmx vm start|shutdown` without the required VM selector. Detailed help also omitted accepted
forms and entire router families, so users had to inspect source or guess how to execute PMX.

**Status:** Resolved — a table-driven overview now covers every management and local route with
executable syntax, complete family/action topics resolve, and a regression pins the inventory.
Commands already under `pmx vm` use a direct positional VM selector and reject redundant `--vm`;
disk and snapshot commands retain `--vm` to identify their owning VM.

## Issue 14 — `srv` password succeeds but the remote shell disappears

**Files:** `components/network/server-privacy.ps1`, `components/network/servers.ps1`,
`tests/network/public-output.ps1`
**Severity:** High
**Description:** The normal interactive SSH helper returned through a PowerShell pipeline so
`Connect-PFServer` could discard its numeric exit code with `Out-Null`. That also redirected the
native process streams, leaving password authentication with no visible or usable remote shell.
The compact fzf window could additionally wrap its decorated controls into the server rows.

**Status:** Resolved — the normal SSH invocation is terminal-attached and emits no synthetic
exit-code object; only the no-shell authentication probe captures output. A regression now
requires mock remote-session output to reach the caller. The picker uses a larger minimum height
and a short ASCII header/prompt.

## Issue 13 — `srv` exposes saved SSH endpoints before authentication

**Files:** `components/network/server-privacy.ps1`, `components/network/servers.ps1`, network
regressions, help registry, public documentation and release notes
**Severity:** Medium
**Description:** Saved usernames, hosts, addresses and ports were repeated in ordinary connect,
list, picker, save, rename and removal output even though the operator had already supplied them
when creating the alias.

**Status:** Resolved — ordinary `srv` views now show alias and reachability only. The new
`srv <name> info` path performs a non-mutating native SSH authentication probe and reveals the
stored endpoint only after success; failed, cancelled and non-interactive probes fail closed.
PowerFlow never reads or stores the password.

## Issue 1 — `gh-l-org` cannot parse selected organisation

**File:** `components/github/browser.ps1`
**Severity:** Medium
**Description:** `gh-l-org` successfully fetches organisations and shows the fzf picker, but after selecting an organisation it can fail with `Could not parse organisation name from selection.` The parser depends on the selected display line containing the exact `🏢` emoji prefix. If fzf, the terminal, font fallback, encoding, or copied output changes that decorative glyph, the org login is no longer extracted even though the selected row is valid.

**Status:** Resolved — organisation picker now stores the login in a tab-delimited hidden field and validates it against the fetched API results.

## Issue 2 — PowerFlow `ls` decoration breaks end-anchored Linux pipelines

**File:** `components/files/listing.ps1`
**Severity:** Medium
**Description:** Forced `lsd` colour reset bytes broke end-anchored Linux pipelines.

**Status:** Resolved in v3.16.0 — both listing paths use automatic icon/colour detection and
the Linux release workflow pins piped directory output.

## Issue 3 — Release notes are not attached to GitHub releases

**File:** `.github/workflows/release-publish.yml`
**Severity:** Medium
**Description:** Release notes were used as the body but omitted from downloadable assets.

**Status:** Resolved — `RELEASE_NOTES.md` is now explicitly included in the published files
list and the release contract is checked locally.

## Issue 4 — README understates what `git-rl` commits

**File:** `README.md`
**Severity:** Medium
**Description:** Documentation said staged changes even though `git-rl` runs `git add .`.

**Status:** Resolved — the release guide now warns that the complete working tree is staged
and tells maintainers to inspect `git status --short` first.

## Issue 5 — Proxmox disk-use checks do not inspect descendant device identities

**File:** `platform/linux/adapters/proxmox.ps1`
**Severity:** Medium
**Description:** Mount-namespace and open-handle checks covered only the selected whole disk.

**Status:** Resolved — disk inventory retains every descendant path and major:minor identity;
namespace/handle checks receive the complete set and missing/malformed identities fail closed.
The PMX safety-model regression pins partitions and mapped descendants without touching disks.

## Issue 6 — Linux dependency downloads ignore the CI GitHub token

**File:** `platform/linux/adapters/packages.ps1`
**Severity:** High
**Description:** Parallel CI installs queried GitHub anonymously and hid request failures,
causing the v3.16.2 Ubuntu 24.04 Starship failure.

**Status:** Resolved — GitHub API requests send `GITHUB_TOKEN` when available, retry bounded
transient failures, omit empty authorization for users without a token, and report actionable
errors. A dependency-free regression pins authentication and retry behavior.

## Issue 7 — PMX parser accepts short-option-shaped values

**File:** `components/proxmox/shared.ps1`
**Severity:** Medium
**Description:** `--vm -x` was accepted as data despite the exact-long-option grammar.

**Status:** Resolved — separated and inline values beginning with `-` are rejected unless a
literal positional follows the explicit `--` end-of-options marker.

## Issue 10 — PMX one-token router tails collapse into strings

**File:** `components/proxmox/command.ps1`
**Severity:** Medium
**Description:** PowerShell enumerated a one-item array returned by `Get-PmxCommandTail`, so a
nested router could index the first character of `set` instead of the token.

**Status:** Resolved — the helper returns a non-enumerated array and the parser/router suite
pins one-token tails plus VM, snapshot, help, and virtual/physical disk collision routes.

## Issue 11 — PMX component accepts VMIDs the adapter rejects

**File:** `components/proxmox/shared.ps1`
**Severity:** Low
**Description:** `Test-PmxVmId` accepted leading-zero text such as `0101`; the adapter's strict
VMID grammar rejected it later, producing inconsistent selection behavior.

**Status:** Resolved — component and adapter now share the canonical 100–999999999 form with
no leading zeroes, covered by the parser regression suite.

## Issue 8 — Tagged PMX feature omitted planned release closure

**Files:** `tests/proxmox/`, `README.md`, `docs/features.md`, `docs/troubleshooting.md`,
`COMPONENTS.md`, `CHANGELOG.md`, `.github/workflows/release-*.yml`
**Severity:** High
**Description:** The PMX management implementation was tagged as v3.16.2 before its approved
dedicated tests, CI wiring, canonical documentation, changelog/release notes, release-asset
correction, issue closure, and plan status were completed. The failed tag was not published.

**Status:** Resolved — v3.17.0 completed every Windows/Linux validation leg, including the
previously failing Ubuntu 24.04 dependency path; the GitHub release was published with the
complete generated notes and all six expected assets.

## Issue 12 — Windows Nerd Font installation reports failure after succeeding

**Files:** `platform/windows/adapters/fonts.ps1`, `platform/windows/adapters/packages.ps1`,
`install.ps1`, `uninstall.ps1`, `tests/windows/`, Windows installation/troubleshooting docs
**Severity:** Medium
**Description:** Scoop installed and registered `FiraCode-NF-Mono`, but `Test-NerdFont`
searched only for a spaced family label while Scoop uses filename-derived registry properties
such as `FiraCodeNerdFontMono-Regular (TrueType)`. The false negative made the installer and
`pwsh-font` claim installation failed; every failure hint also incorrectly blamed absent Scoop.

**Status:** Resolved — detection normalizes both registry shapes; Scoop is an explicit,
immediately activated Windows prerequisite; real command failures are retained; and interactive
uninstall offers a separately warned/double-confirmed Scoop choice while `-Yes` always keeps it.
Three responsibility-focused Windows regressions cover font/bootstrap behavior, uninstall
safety, and an isolated `-NoDeps` install/uninstall round trip.
