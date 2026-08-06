# Log 4 — August 6, 2026 — 12:16 UTC

**Work performed:**
- Audited every `srv` output path after the user reported saved SSH usernames and addresses
  appearing during normal connection and picker use.
- Identified endpoint disclosure in connect, list, picker, add, duplicate, rename and delete
  output, then implemented the approved alias-only/authenticated-info plan.
- Split endpoint construction, native SSH invocation and authenticated detail rendering into a
  focused privacy component rather than expanding the existing command router.
- Added mocked privacy regressions and wired them into Windows and Linux release validation.
- Folded the uncut Windows prerequisite patch into v3.18.0 because authenticated `srv info` is
  a new backward-compatible command surface and therefore requires a minor release.
- Recorded the native OpenSSH prompt boundary without copying the reported private endpoint.

**Files modified:**
- `components/network/server-privacy.ps1` (created — endpoint privacy and SSH boundary)
- `components/network/servers.ps1`, `Microsoft.PowerShell_profile.ps1` (private UI and load order)
- `tests/network/`, `.github/workflows/release-validate*.yml` (regressions and CI)
- `docs/plan/network/srv-private-display.md` (created and completed)
- `docs/plan/issues/current-issues.md`, `docs/plan/issues/resolved-issues.md` (Issue 13 closed)
- `docs/solved-problems/ssh-saved-endpoint-preauth-display.md` (created)
- `docs/instructions.md` (saved SSH endpoint display-privacy rule added)
- `README.md`, `docs/features.md`, `COMPONENTS.md`, `IMPORT_ORDER.md`, `CHANGELOG.md` (docs)
- `docs/log/2026/August/06 Thurs/log-4.md` (created)

**Decisions:**
- Ordinary `srv` output will identify saved connections by alias and reachability only.
- `srv <name> info` will gate endpoint display on successful SSH authentication while leaving
  password handling entirely with OpenSSH.
- The persisted schema stays unchanged; this is display minimization, not credential storage.

**Bug status:** Fix applied — awaiting user confirmation.

**Verification:** The focused SRV privacy suite, PMX suite, GitHub-download regression, and all
three Windows prerequisite regressions pass. Every PowerShell file parses; component
architecture, automatic-variable, help registry (134 commands), adapter parity (84 calls),
repository-profile load, workflow YAML, v3.18.0 changelog extraction, private-endpoint scrub,
and whitespace gates pass.

**Commit message:** `feat(network): protect saved SSH endpoint display`
