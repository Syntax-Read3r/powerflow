# Windows Scoop fonts — installation succeeds but the application reports failure

## Problem

A Windows installer runs `scoop install FiraCode-NF-Mono`, the files appear under the user's
font directory, but the application reports that the font could not be installed. A recovery
hint may incorrectly say Scoop is missing even though `scoop --version` works.

## Root cause

Scoop's Nerd Font manifest registers filename-derived Windows font property names such as:

```text
FiraCodeNerdFontMono-Regular (TrueType)
```

A detector that searches only for the human-readable family label
`FiraCode Nerd Font Mono` returns a false negative. Suppressing Scoop's command output and using
one unconditional fallback hint then hides whether the package manager, bucket, download,
installation, or post-install detection actually failed.

## Solution

Normalize registry property names before matching so both the family and filename forms map to
`FiraCodeNerdFontMono`. Bootstrap the Windows package-manager prerequisite before invoking the
font command, refresh its shim path in the current process, check each command result, and keep
the exact failure for the recovery message.

When offering to remove a shared package manager, default to keeping it. Require a separate
interactive opt-in, explain only after yes that all managed applications/buckets/shims are
affected, and retain the package manager's own final confirmation. Non-interactive uninstall
must never infer permission to remove it.

## Notes

- Match the Mono variant specifically; the standard and Propo variants do not guarantee
  single-cell icon widths.
- Track ownership of the font only after post-install detection succeeds.
- Do not automatically remove a shared package manager merely because the application
  originally bootstrapped it; it may now own unrelated user software.

**Status:** Fix applied — awaiting confirmation.
