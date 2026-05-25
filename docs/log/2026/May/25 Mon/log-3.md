# Log 3 — May 25, 2026 — 09:18 UTC

**Work performed:**
- Implemented the approved `gh-l-org` organisation selection parser fix.
- Changed organisation picker rows in `components/github/browser.ps1` from emoji-prefixed display-only strings to `login<TAB>display` rows.
- Updated the fzf invocation to show only the display column via `--with-nth=2..` and `--delimiter`.
- Parsed the selected organisation from the stable hidden login column and validated it against the fetched `$orgs.login` values.
- Moved Issue 1 from current issues to resolved issues.
- Created a solved-problems note for the general fzf decorated-row parsing pattern.
- Verified `components/github/browser.ps1` parses successfully with the PowerShell parser.
- Verified the new tab-delimited selection parser with a local simulated fzf result.

**Files modified:**
- `components/github/browser.ps1` (org picker row format and parser block)
- `docs/plan/issues/current-issues.md` (Issue 1 removed)
- `docs/plan/issues/resolved-issues.md` (Issue 1 marked resolved)
- `docs/plan/github/gh-l-org-selection-parser.md` (status set to Implemented)
- `docs/solved-problems/powershell-fzf-decorated-row-parsing.md` (created)
- `docs/log/2026/May/25 Mon/log-3.md` (created)

**Decisions:**
- Used a tab-delimited hidden value instead of a regex against display text so UI decoration cannot break parsing.
- Added validation against `$orgs.login` to avoid using malformed or unexpected fzf output.

**Bug status:** Bug reported: `gh-l-org` fetches organisations but fails with `Could not parse organisation name from selection` after selecting one.

**Commit message:** `fix(github): parse gh-l-org selection from stable hidden field`
