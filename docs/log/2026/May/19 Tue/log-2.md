# Log 2 — May 19, 2026

**Work performed:**
- Replaced the multi-phase hardcoded nav search with a clean BFS (breadth-first search) that walks up to 4 levels from the search root.
- Rewrote `Search-NestedProjects` → `Search-Projects` with configurable depth and proper match priority: exact > prefix (starts-with) > contains. Among equal-quality matches, shallowest wins.
- Simplified `nav.ps1` to remove all hardcoded directory lists and multi-phase logic; the BFS call handles everything.
- Updated `COMPONENTS.md` to reflect the renamed function.

**Files modified:**
- `components/navigation/projects.ps1` — full rewrite: `Search-Projects` BFS
- `components/navigation/nav.ps1` — full rewrite: single `Search-Projects` call, removed hardcoded phase logic
- `COMPONENTS.md` — `Search-NestedProjects` → `Search-Projects`

**Decisions:**
- MaxDepth=4 from search root covers `~/Code/Projects/Application/Windows Application/powerflow` exactly (4 levels down from ~/Code).
- Exact match returns immediately regardless of depth; prefix/contains matches compare depth and take the shallowest.
- Search root auto-detects: defaults to `~/Code`, switches to the most-specific bookmark root if the current directory is inside a different bookmark.

**Bug status:** No bug reported by user.

**Commit message:** `feat(nav): replace multi-phase search with BFS up to 4 levels, prefix-first matching`
