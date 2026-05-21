# Log 1 — May 21, 2026

**Work performed:**
- Fixed multi-word query bug in `nav` — extra words after the first were silently dropped.
- Built `$query` by joining `$command`, `$param1`, and `$param2` into a single space-separated string.
- Passed `$query` to fzf `--query` and to `Search-Projects -Name` in the non-fzf fallback.
- Updated the "no match" error message to show the full query instead of just `$command`.

**Files modified:**
- `components/navigation/nav.ps1` (lines 110–159 — `$query` variable added; `--query`, `-Name`, and error message updated)

**Decisions:**
- Used a simple `Where-Object { $_ }` join rather than `ValueFromRemainingArguments` to stay consistent with the existing three-param signature and avoid breaking bookmark sub-commands that rely on positional binding.

**Bug status:** Bug reported: `nav source code` only searched "source"; "code" was silently ignored.

**Commit message:** `fix(nav): join all positional args into query so multi-word searches work`
