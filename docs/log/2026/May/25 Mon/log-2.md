# Log 2 — May 25, 2026 — 09:10 UTC

**Work performed:**
- Troubleshot user-reported `gh-l-org` failure after organisation selection.
- Identified root cause: organisation parsing depends on a literal decorative `🏢` emoji in the fzf-selected row.
- Created issue-tracking files and recorded the bug as Issue 1.
- Created `docs/plan/github/gh-l-org-selection-parser.md` with a scoped fix plan and stopped before implementation pending approval.

**Files modified:**
- `docs/plan/issues/current-issues.md` (created — Issue 1 added)
- `docs/plan/issues/resolved-issues.md` (created)
- `docs/plan/github/gh-l-org-selection-parser.md` (created)
- `docs/log/2026/May/25 Mon/log-2.md` (created)

**Decisions:**
- Proposed tab-delimited hidden data for the fzf picker so UI decoration can change without breaking data extraction.
- Classified the bug as Medium because it blocks a newly added command path but does not break profile load or core command availability.

**Bug status:** Bug reported: `gh-l-org` fetches organisations but fails with `Could not parse organisation name from selection` after selecting one.

**Commit message:** No commit — troubleshooting and plan only.
