# Current Issues

No open issues recorded.

---

## Resolved

### Issue 2 — PowerFlow `ls` decoration breaks end-anchored Linux pipelines

**File:** `components/files/listing.ps1`
**Severity:** Medium
**Description:** PowerFlow forces `lsd` colour and icons even when output is piped. The trailing
ANSI reset bytes make an expression such as `ls -l /dev/disk/by-id | grep -E 'sdg$'` return no
match, although the same pipeline works with GNU `ls` in Bash.

**Status:** Fixed in v3.16.0. Both `lsd` invocations (tree view and normal listing) now pass
`--icon=auto --color=auto`, so lsd detects the destination itself: full decoration at an
interactive prompt, plain text into a pipe or a file.

**Why it was hard to see:** the listing *looked* correct. The contamination was an invisible
ANSI reset appended after the filename, so only a pipeline that anchors on the end of the line
could notice — and it failed by finding nothing, which reads as "no such entry" rather than
as a bug.

**Regression test:** `release-validate-linux.yml` → *"PowerFlow ls stays pipeline-safe"*. It
lists a **directory**, deliberately: lsd colours directory names and appends the reset after
them, so the test genuinely fails against the old behaviour.
