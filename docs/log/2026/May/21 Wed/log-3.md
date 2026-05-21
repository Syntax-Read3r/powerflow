# Log 3 — May 21, 2026

**Work performed:**
- Updated README.md to remove all references to git-a -vr and replace with git-rl / git-release.
- Rewrote the "Version Control Setup" section to describe the git-rl fzf workflow instead of the
  old git-a -vr flag.
- Updated the development environment setup to note that Microsoft.PowerShell_profile.ps1 is now
  a bootloader and component edits happen under components/ and config/.
- Updated the "Disable Features" subsection to reference config/PowerFlow.settings.ps1 instead of
  "top of the profile".
- Updated both code example blocks and the Enhanced Git Workflow command table.

**Files modified:**
- `README.md` (lines 74, 168, 209–325, 344–351, 409–414 — git-rl migration and architecture fixes)
- `docs/log/2026/May/21 Wed/log-3.md` (created)

**Decisions:**
- Kept the "Manual Version Control" subsection but removed the git tag creation example since
  git-rl now owns tag creation. Only the delete/view examples remain, which are still relevant.

**Bug status:** No bug reported by user.

**Commit message:** `No commit — README update only`
