# Linux release validation — Starship missing after installation

## Problem

A clean Ubuntu release job completed the PowerFlow installer but failed the mandatory
dependency check with:

```text
dependency missing: starship
```

Other distributions could pass in the same matrix, making this look Ubuntu-specific.

## Root cause

PowerFlow already had a Starship GitHub-release fallback and selected the correct Linux asset.
However, its Releases API call ignored the `GITHUB_TOKEN` supplied by GitHub Actions. Parallel
jobs therefore shared the anonymous API allowance, and whichever request lost the race could
be rate-limited. The adapter caught the exception without printing it, leaving only a generic
dependency failure.

Pre-installing Starship in CI would make the job green while bypassing the installer path that
real users depend on, so it would hide rather than fix the product defect.

## Solution

- Send the GitHub Actions token as a Bearer header when it exists.
- Keep anonymous installation supported when no token exists.
- Retry transient Releases API failures a bounded number of times.
- Print the actionable API/download exception without exposing the token.
- Keep Starship mandatory and continue checking the installed binary.
- Run a dependency-free regression that simulates a transient failure and asserts the retry
  and authorization header.

## Verification

- Local authentication/retry regression: passed on Windows PowerShell 7.
- Repository PowerShell parse-all and workflow YAML validation: passed.
- Exact Ubuntu 24.04 clean-container validation: passed from the working tree. PowerFlow
  installed Starship through the fixed fallback, both regression suites passed, coreutils
  remained native, and uninstall removed PowerFlow-owned dependencies while preserving Git.
- Replacement-tag CI and published-release assets remain the final confirmation.

## Status

Fix applied — awaiting confirmation.
