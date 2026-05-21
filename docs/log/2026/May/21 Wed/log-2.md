# Log 2 — May 21, 2026

**Work performed:**
- Investigated nav bug 2 (nav games failing from ~\Code but succeeding from ~\Code\Projects).
- Determined bug 2 does not exist in the current code — it was a limitation of the old monolithic
  nav implementation which had hardcoded subdirectory names (Applications, Learning Area, etc.) as
  search areas. The current Search-Projects BFS traverses all directories up to MaxDepth 4, so
  Projects\Games at depth 2 is found correctly regardless of CWD.
- Added [2.0.1] entry to CHANGELOG.md with the nav multi-word query fix.
- Bumped $script:POWERFLOW_VERSION to "2.0.1" in config/PowerFlow.settings.ps1, then reverted
  it back to "2.0.0" after identifying that git-release (git-rl) owns the version bump — leaving
  it at 2.0.0 lets git-rl do a clean patch bump as part of the release commit.
- Diagnosed why git-a -vr did not work: the -vr / -VersionRelease switch was removed from
  git-a during the v2.0.0 modular refactor. Release workflow now lives in
  components/git/release.ps1 as git-release / git-rl.

**Files modified:**
- `CHANGELOG.md` (added [2.0.1] - 2026-05-21 section)
- `config/PowerFlow.settings.ps1` (bumped to 2.0.1 then reverted to 2.0.0 — net no change)
- `docs/log/2026/May/21 Wed/log-2.md` (created)

**Decisions:**
- Reverted the manual settings.ps1 bump so git-rl can own the version increment atomically
  as part of the release commit, rather than having it pre-bumped in a separate edit.

**Bug status:** No new bug reported. Confirmed bug 2 (nav depth from parent dir) is not present
in current code.

**Commit message:** `No commit — documentation and release prep only`
