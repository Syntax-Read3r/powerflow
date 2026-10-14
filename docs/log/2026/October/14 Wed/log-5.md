# Log 5 — GitHub command family and stale repository review

**Timestamp:** 2026-10-14 18:43 UTC (implementation start, approximate); completed 18:59 UTC.

**Work performed:** Implemented the approved `github` family with recent/oldest browsing, `stale` review, organization browsing, token status/reset, and executable help. Added shared pagination, UTC age filtering, stable repository-ID selection, Pages enrichment for account/project/custom-domain sites, and readable reports without a picker. Kept legacy commands with once-per-session migration hints, ordinary browsing's three deletion confirmations, and organization clone-all confirmation. Extracted existing Windows credential storage into a platform adapter and added the matching Linux contract without adding persistent storage.

**Files modified:**
- `components/github/repositories.ps1` (created: authentication, data/model, date filtering, Pages evidence).
- `components/github/browser.ps1` (browser/actions and organization implementation refactored; legacy public definitions moved to the dispatcher).
- `components/github/review.ps1` (created: review entry point).
- `components/github/command.ps1` (created: dispatcher, canonical flags, command collision check, help registration, legacy wrappers).
- `platform/windows/adapters/github.ps1`, `platform/linux/adapters/github.ps1` (created: matching saved-token contracts).
- `Microsoft.PowerShell_profile.ps1` (ordered GitHub source entries).
- `tests/github/repository-review.ps1`, `tests/github/run.ps1` (created: mocked regression suite).
- `.github/workflows/release-validate.yml` (GitHub regression step).
- `README.md`, `COMPONENTS.md`, `IMPORT_ORDER.md`, `docs/features.md`, `docs/troubleshooting.md` (command, module, and behavior documentation).
- `CHANGELOG.md` (5.2.0 Unreleased feature entry; configured version unchanged at 5.1.0).
- `docs/plan/github/stale-repository-review.md` (approved names consolidated; implementation and verification status recorded).
- `docs/log/2026/October/14 Wed/log-5.md` (created: this record).

**Decisions:** Age means last push, not proven redundancy or lack of site usage. Preserve known Pages-enabled state through permission/rate-limit/network failures; never infer hosting solely from names or homepages. Review has no deletion/archive action. Reuse the browser renderer/action flow while keeping the root router and review entry point thin. Keep `gh` unchanged and preserve a pre-existing `github` command. Organization public-only fallback is explicitly incomplete. A test caught local-time month subtraction across daylight saving; normalize the reference time to UTC before calendar subtraction.

**Validation:** GitHub suite: 124 assertions passed. Flag convention suite: 111 assertions passed. Local release gates: eight passed, zero failed, five requiring GitHub tag context skipped. Parsed all nine changed/new executable files in the GitHub domain, adapters, tests, and profile with no syntax errors. Verified `pwsh-h github` with the real registry and Windows adapter loaded. `git diff --check` passed. Tests used mocked requests/actions and did not inspect or modify the live account. No profile installation, release, or version bump performed.

**Bug status:** No bug reported by user.

**Commit message:** No commit — implementation is available in the working tree for review; suggested message: `feat: add github command family and Pages-aware stale repository review`.
