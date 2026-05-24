# Log 1 — May 24, 2026

**Work performed:**
- Read all project documentation at user's request.
- Designed plan for new `gh-l-org` feature (GitHub organisation browser + bulk clone).
- Created `docs/plan/github/org-clone.md` with full plan: goal, scope, 4 implementation
  chunks, rollback steps, and 8 test cases.

**Files modified:**
- `docs/plan/github/org-clone.md` (created)
- `docs/log/2026/May/24 Sun/log-1.md` (created)

**Decisions:**
- Chose a separate `gh-l-org` function over a `-Organisation` switch on `gh-l` to keep
  the two workflows independent and consistent with the existing helper-function pattern.
- Planned extraction of `Set-GitHubToken`, `Get-GitHubToken`, `Get-CommitCount` from
  inside `gh-l` to module-level `_GhL-*` helpers so `gh-l-org` can share them without
  duplication.
- Used `Push-Location`/`Pop-Location` for the clone-all directory change (PowerShell
  idiom; restores CWD on error).

**Bug status:** No bug reported by user.

**Commit message:** No commit — planning session only.
