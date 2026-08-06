# Log 3 — August 6, 2026 — 12:04 UTC

**Work performed:**
- Investigated the Windows installer and `pwsh-font` report that FiraCode Nerd Font Mono could
  not be installed automatically.
- Confirmed Scoop, its nerd-fonts bucket, the `FiraCode-NF-Mono` package directory, six font
  files, and six HKCU font registrations are present.
- Reproduced the detector mismatch and wrote the implementation plan.
- Closed the v3.17.0 release-verification issue after CI and asset verification succeeded.
- Made Scoop an explicit Windows prerequisite, including under `-NoDeps`, and activated a
  newly installed shim in the current process.
- Corrected Nerd Font registry detection and retained actionable Scoop command failures.
- Added the separately warned/double-confirmed interactive Scoop removal choice; `-Yes` and
  redirected uninstall always keep Scoop.
- Added three componentized Windows regressions and wired their runner into release CI.
- Prepared the Windows patch release documentation, later folded into v3.18.0 when the same
  working tree gained the new authenticated `srv info` feature. Verified the generated body and
  versioned installer URLs, dated the completed v3.17.0 entry, and removed stale non-Mono font
  names plus the obsolete `ls -t` tree example from shipped documentation.

**Files modified:**
- `docs/plan/core/windows-nerd-font-bootstrap.md` (created — implementation plan)
- `docs/plan/issues/current-issues.md` (Issue 12 added; resolved Issue 8 removed)
- `docs/plan/issues/resolved-issues.md` (Issue 8 release closure recorded)
- `docs/log/2026/August/06 Thurs/log-3.md` (created)
- `platform/windows/adapters/packages.ps1` (Scoop prerequisite, shim, and removal helpers)
- `platform/windows/adapters/fonts.ps1` (normalized detection and truthful failures)
- `install.ps1`, `uninstall.ps1` (prerequisite enforcement and safe Scoop opt-in)
- `tests/windows/` and `.github/workflows/release-validate.yml` (regressions and CI)
- `README.md`, `COMPONENTS.md`, `CHANGELOG.md`, `docs/installation.md`,
  `docs/troubleshooting.md`, `docs/installed-packages.md`, `docs/instructions.md` (docs)
- `docs/solved-problems/windows-scoop-font-registration-detection.md` (knowledge base)
- `README.md`, `docs/installation.md`, `docs/troubleshooting.md`, `CHANGELOG.md` (next-release
  release-document consistency pass and generated-note source)

**Decisions:**
- Treat Scoop as an automatically bootstrapped prerequisite, not a removable owned dependency,
  because a package manager can contain unrelated user packages.
- Fix the false-negative registry detector before changing installation strategy: the requested
  font is already installed and only PowerFlow's success check is wrong.
- Keep Scoop by default because it is shared infrastructure. Only an interactive, separately
  warned choice may hand off to Scoop's own final confirmation; automation cannot remove it.

**Bug status:** Bug reported: Windows font installation reports failure after Scoop has
successfully installed and registered FiraCode Nerd Font Mono.

**Verification:** Every PowerShell file parses; architecture, help registry (134 commands),
adapter parity (84 calls), privacy and whitespace gates pass. PMX, Linux download, and Windows
prerequisite suites pass. The actual Scoop/font registration is detected, and an isolated
`-NoDeps` install/uninstall round trip verifies the prerequisite while keeping Scoop.
The next-release changelog section extracts into a complete generated release body with the patch
details and Scoop-removal safety guarantee. It was subsequently promoted to v3.18.0 when the
authenticated `srv info` feature was added.

**Commit message:** `fix(windows): require Scoop and correct Nerd Font installation detection`
