# Log 6 — Release command naming recommendation

**Timestamp:** 2026-10-14 19:03 UTC.

**Work performed:** Inspected the release and version-helper functions. Recommended a `release` command family with bare release execution, `setup` for the existing setup-guide flow, and `help` for usage. Explained the distinction between local release preparation and the CI/CD pipeline triggered by a tag.

**Files modified:** `docs/log/2026/October/14 Wed/log-6.md` (created).

**Decisions:** Name the public command after the user goal; retain Git terminology for actual Git operations. Proposed compatibility wrappers and release-focused internal helper names. No release implementation or naming changes made.

**Bug status:** No bug reported by user.

**Commit message:** No commit — naming recommendation only.
