# Log 2 — May 24, 2026

**Work performed:**
- Implemented `gh-l-org` feature per approved plan `docs/plan/github/org-clone.md`.
- Chunk 1: Extracted `Set-GitHubToken`, `Get-GitHubToken`, `Get-CommitCount` from
  inside `gh-l` to module-level helpers `_GhL-SetToken`, `_GhL-GetToken`,
  `_GhL-CommitCount`. Added `Add-Type` guard in `_GhL-GetToken` so the CredentialManager
  class is only compiled once per session. Updated three call sites in `gh-l`.
- Chunk 2: Added `gh-l-org` function — org fzf picker, repo fzf picker (matching
  `gh-l` column layout), 5-option action menu including single-clone and
  bulk clone-all with `Push-Location`/`Pop-Location` and per-repo error counting.
  403 fallback retries with `type=public` when token lacks `read:org` scope.
- Chunk 3: Added `gh-l-org` entry to `components/help/menu.ps1` in the
  🐙 GITHUB INTEGRATION subsection.
- Chunk 4: Updated `COMPONENTS.md` registry row for `browser.ps1`.

**Files modified:**
- `components/github/browser.ps1` (full rewrite — helpers extracted, `gh-l-org` added)
- `components/help/menu.ps1` (line 170 — `gh-l-org` entry added)
- `COMPONENTS.md` (browser.ps1 registry row updated)
- `docs/log/2026/May/24 Sun/log-2.md` (created)

**Decisions:**
- Guarded `Add-Type` with `([System.Management.Automation.PSTypeName]'CredentialManager').Type`
  check so calling `_GhL-GetToken` from both `gh-l` and `gh-l-org` in the same session
  does not throw a "type already exists" error.
- Used `Push-Location`/`Pop-Location` for clone-all so the caller's CWD is restored
  even if an individual clone throws.
- `$repoTypes = @("all", "public")` foreach loop for 403 fallback — avoids nested
  do-while blocks and keeps the retry logic readable.

**Bug status:** No bug reported by user.

**Commit message:** `feat(github): add gh-l-org — organisation browser and bulk clone`
