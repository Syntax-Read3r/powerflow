# Log 4 — May 21, 2026

**Work performed:**
- Read all 6 GitHub Actions workflow files to understand the full release pipeline before writing docs.
- Created docs/git-rl-project-setup.md — a self-contained reference for setting up any project to
  work with git-rl, covering both the local command and the CI/CD pipeline it triggers.
- Document covers: version resolution priority, the minimum settings file, what git-rl does
  step-by-step, the 6-workflow pipeline diagram, per-workflow adaptation notes, a full AI checklist,
  and code snippets for syncing non-PowerShell version files (package.json, pyproject.toml, VERSION).

**Files modified:**
- `docs/git-rl-project-setup.md` (created)
- `docs/log/2026/May/21 Wed/log-4.md` (created)

**Decisions:**
- Documented what to keep unchanged (artifact names, version-match regex, RELEASE_NOTES.md logic)
  vs what to adapt (required files list, install scripts, zip contents, release assets) so an AI
  knows which parts are load-bearing and which are project-specific.

**Bug status:** No bug reported by user.

**Commit message:** `No commit — documentation only`
