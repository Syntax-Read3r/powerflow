# Resolved Issues

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
