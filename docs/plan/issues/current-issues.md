# Current Issues

## Issue 8 — Tagged PMX feature omitted planned release closure

**Files:** `tests/proxmox/`, `README.md`, `docs/features.md`, `docs/troubleshooting.md`,
`COMPONENTS.md`, `CHANGELOG.md`, `.github/workflows/release-*.yml`
**Severity:** High
**Description:** The PMX management implementation was tagged as v3.16.2 before its approved
dedicated tests, CI wiring, canonical documentation, changelog/release notes, release-asset
correction, issue closure, and plan status were completed. The failed tag is not a published
release, but the next tag must not repeat the incomplete release preparation.

**Status:** Open — implementation and local release closure complete; v3.17.0 tag, CI, and
published-asset verification remain.

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
