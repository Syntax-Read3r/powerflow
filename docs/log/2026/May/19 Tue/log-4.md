# Log 4 — May 19, 2026

**Work performed:**
- Updated `docs/instructions.md`:
  - Added §5b: "Check `dependencies.ps1` Before Proposing Tools" — agents must read the file before suggesting new dependencies; new tools must go in both `dependencies.ps1` and `install.ps1`
  - Strengthened §5a: plan creation is now a hard stop with a 4-step sequence (create doc → output to user → state "awaiting approval" → stop); skipping it is explicitly named a rule violation
- Created `docs/plan/navigation/fuzzy-search.md` — retrospective plan for the fzf nav integration (should have been created before implementation)
- Created `docs/plan/core/install-dependencies-at-install.md` — forward-looking plan for installing all tools during `install.ps1` execution; awaiting user approval before implementation

**Files modified:**
- `docs/instructions.md` — §5a strengthened, §5b added
- `docs/plan/navigation/fuzzy-search.md` (created — retrospective)
- `docs/plan/core/install-dependencies-at-install.md` (created — awaiting approval)

**Decisions:**
- §5b references `dependencies.ps1` explicitly so the agent knows the canonical tool list without having to rediscover it each session.
- The install-at-install change is planned but not implemented — it touches `install.ps1` (a release-shipped script) and requires user approval per §5a.

**Bug status:** No bug reported by user.

**Commit message:** `No commit — plan files created, awaiting approval for install.ps1 changes`
