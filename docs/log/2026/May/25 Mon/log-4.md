# Log 4 — May 25, 2026 — 09:24 UTC

**Work performed:**
- Updated `CHANGELOG.md` with a new `## [2.2.1] - Unreleased` release-note entry for the `gh-l-org` organisation selection parser bug fix.
- Confirmed the current source version remains `2.2.0`; `git-rl` should perform the patch bump to `2.2.1` during release.

**Files modified:**
- `CHANGELOG.md` (added [2.2.1] Unreleased bug-fix entry)
- `docs/log/2026/May/25 Mon/log-4.md` (created)

**Decisions:**
- Classified this as a patch release because it fixes existing `gh-l-org` behaviour without adding a new feature or breaking compatibility.
- Did not edit `config/PowerFlow.settings.ps1`; release version changes are owned by `git-rl`.

**Bug status:** Bug reported: `gh-l-org` fetches organisations but fails with `Could not parse organisation name from selection` after selecting one.

**Commit message:** `fix(github): parse gh-l-org selection from stable hidden field`
