# Log 6 — May 24, 2026

**Work performed:**
- Diagnosed why v2.2.0 release notes had no install URL: the CI extracts release
  notes from CHANGELOG.md, and CHANGELOG entries never contained install commands.
- Updated `.github/workflows/release-generate-scripts.yml` to always append a
  `## 📦 Installation` block with the versioned `irm` and `curl` one-liners to
  every RELEASE_NOTES.md it generates, unconditionally — regardless of CHANGELOG
  content. This makes every future release self-documenting on the GitHub release page.
- Updated `docs/instructions.md` §9 CHANGELOG ordering rule to document that install
  commands are auto-appended by CI and must NOT be manually added to CHANGELOG entries.

**Files modified:**
- `.github/workflows/release-generate-scripts.yml` (install block appended before Set-Content)
- `docs/instructions.md` (CHANGELOG ordering rule — install URL note added)
- `docs/log/2026/May/24 Sun/log-6.md` (created)

**Decisions:**
- Chose to fix at the CI level rather than requiring every CHANGELOG entry to include
  install commands — CI is the single authoritative source for version-specific URLs,
  so it's the right place for this logic.
- Used `$notes.TrimEnd() + $installBlock` to avoid a double blank line between the
  CHANGELOG content and the appended section.

**Bug status:** Bug reported: v2.2.0 GitHub release page has no install URL.
Fix applied — will take effect on the next release (v2.3.0+).

**Commit message:** `fix(ci): always append install URLs to release notes`
