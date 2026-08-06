# Current Issues


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
