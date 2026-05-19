# Log 3 — May 19, 2026

**Work performed:**
- Added fzf fuzzy-search to `nav`. BFS now collects ALL directories up to depth 4 as relative paths, pipes them to fzf with the typed term pre-filled, and auto-selects if only one match survives (`--select-1`).
- Added skip list to BFS traversal: node_modules, .git, dist, build, target, bin, obj, .next, __pycache__, .venv, etc. — prevents traversing into build artifacts.
- Added `-All` switch to `Search-Projects` for the candidate-collection mode; original best-match logic kept as fallback when fzf is unavailable.
- Confirmed: fzf IS installed on fresh install — `Initialize-Dependencies` runs on the first profile load and installs it via Scoop.

**Files modified:**
- `components/navigation/projects.ps1` — added `-All` mode and skip-dir list to `Search-Projects`
- `components/navigation/nav.ps1` — primary path now uses fzf; BFS best-match kept as fallback

**Decisions:**
- Delegate all fuzzy matching to fzf rather than re-implementing it (`*$Name*` etc.) — fzf's algorithm is better and handles typos, transpositions, non-consecutive letters.
- `--select-1` gives seamless UX: single-match queries auto-navigate, multi-match queries show the picker.
- Skip-list applied in both `-All` and best-match modes to avoid traversing node_modules (performance) and build dirs (irrelevant to navigation).

**Bug status:** No bug reported by user.

**Commit message:** `feat(nav): fzf fuzzy-search picker with BFS candidate collection and skip-list`
