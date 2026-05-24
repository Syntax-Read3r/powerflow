# Log 3 — May 24, 2026

**Work performed:**
- Determined gh-l-org warrants a minor release (new feature → v2.0.1 → v2.1.0).
- Read `components/git/release.ps1` to understand git-rl is fully interactive (fzf,
  no CLI flags for bump type). Confirmed version source is `config/PowerFlow.settings.ps1`.
- Added `## [2.1.0] - Unreleased` section to `CHANGELOG.md` with full feature description.
- Added Section 9 (Release Prompt After New Features) to `docs/instructions.md` —
  rule requiring the agent to read the current version, calculate the correct semver bump,
  update CHANGELOG.md, and prompt the user with the release block at the end of every
  feature implementation response.
- Updated `docs/plan/github/org-clone.md` status to Implemented.

**Files modified:**
- `CHANGELOG.md` (added [2.1.0] Unreleased section)
- `docs/instructions.md` (Section 9 added — release prompt rule)
- `docs/plan/github/org-clone.md` (Status: Implemented added)
- `docs/log/2026/May/24 Sun/log-3.md` (created)

**Decisions:**
- Classified gh-l-org as a minor bump (not patch) because it introduces new user-facing
  functionality, not a fix. Semver is unambiguous: new backward-compatible feature = minor.
- Noted in the rule that git-rl is interactive and the agent must tell the user which
  fzf option to pick rather than trying to automate the selection.

**Bug status:** No bug reported by user.

**Commit message:** No commit — documentation and rule update only.
