# Resolved Issues

## Issue 1 — `gh-l-org` cannot parse selected organisation

**File:** `components/github/browser.ps1`
**Severity:** Medium
**Description:** `gh-l-org` successfully fetches organisations and shows the fzf picker, but after selecting an organisation it can fail with `Could not parse organisation name from selection.` The parser depends on the selected display line containing the exact `🏢` emoji prefix. If fzf, the terminal, font fallback, encoding, or copied output changes that decorative glyph, the org login is no longer extracted even though the selected row is valid.

**Status:** Resolved — organisation picker now stores the login in a tab-delimited hidden field and validates it against the fetched API results.
