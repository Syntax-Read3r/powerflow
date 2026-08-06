# Session Log — 2026-08-06 (2)

## Bug reported

- The v3.16.2 release failed in `validate-linux` because the Ubuntu 24.04 clean-container
  job could not find the mandatory `starship` dependency after installation.

## Investigation

- Read failed GitHub Actions run `31094947236` and isolated job `92594705816`.
- Confirmed that Ubuntu 22.04, Debian 13, Arch, openSUSE, Alpine, and the native Ubuntu job
  passed; only the Ubuntu 24.04 container failed.
- Confirmed PowerFlow selected the existing Starship GitHub-release fallback, but the
  adapter's Releases API request did not use the `GITHUB_TOKEN` supplied to the installer.
- Confirmed the adapter swallowed the request exception and exposed only a generic install
  failure, obscuring whether the cause was rate limiting or a network response.

## Decision

- Keep Starship mandatory: the release validation is intended to prove the real dependency
  install path works.
- Fix the production Linux package adapter so CI and real installations benefit, instead of
  pre-installing Starship in the workflow and masking the broken PowerFlow code path.
- Add authenticated API requests, bounded retries, useful diagnostics, and a regression test.

## Status

- Production fix complete and locally verified; replacement v3.17.0 tag/publish is awaiting
  the human-run `git-rl` workflow.

## Implementation completed

- Added token-aware, retrying GitHub Releases API requests to the Linux package adapter.
- Kept Starship mandatory and added actionable request/download warnings.
- Added the Linux package authentication/retry regression and wired it into Linux CI.
- Audited the tagged PMX implementation against its approved v3.17.0 plan.
- Fixed PMX one-token router array collapse, short-option-shaped values, and leading-zero VMIDs.
- Added modular PMX suites for parser/routing, config/SSH/audit, adapter tokens, VM models,
  mutation boundaries, and descendant physical-disk safety; wired them into Windows/Linux CI.
- Added `RELEASE_NOTES.md` to published assets and corrected the `git-rl` full-tree warning.
- Updated README, feature/troubleshooting docs, component inventory, PMX plan status, and the
  v3.17.0 changelog/release notes.
- Moved resolved Issues 2–7, 10, and 11 to `resolved-issues.md`; retained release verification
  and the pre-existing PowerShell 5.1 compatibility claim as open Issues 8 and 9.
- Redacted the PMX source-note node name, private-LAN examples, and hardware serial from the
  release contents, replacing them with explicit placeholders.

## Verification completed

- PMX regression suite: passed (7 responsibility-focused checks).
- Linux GitHub authentication/retry regression: passed.
- Every repository `.ps1` parsed under PowerShell 7.
- Working-tree profile loaded on Windows; PMX and both management adapter contracts resolved.
- Architecture, automatic-variable, help-registry, adapter-parity, YAML, changelog extraction,
  release-asset, privacy, whitespace, and Bash syntax gates passed.
- Windows `irm | iex` equivalent installed the working tree into a verified temporary sandbox
  with PMX components/adapters present, then the sandbox was removed.
- Redirected amber confirmation refused immediately without hanging or executing a change.
- Exact Ubuntu 24.04 Docker round trip passed: working-tree install, Starship 1.26.0 discovery,
  package and PMX regressions, native coreutils, uninstall of PowerFlow-owned dependencies,
  preservation of pre-existing Git, and removal of all 100 manifest-tracked files.
- Docker Desktop was started for that test. Five existing containers became active, so it was
  deliberately left running rather than disrupting user workloads to restore the prior state.

## Environment limitations recorded honestly

- Ubuntu WSL starts but has no `pwsh`; Debian WSL did not respond during the test window.
- The saved Proxmox target resolved, but batch-mode SSH authentication was unavailable, so no
  live discovery or mutation was claimed. Live read-only discovery remains a human smoke step.
- Windows PowerShell 5.1 cannot parse the existing UTF-8/PowerShell-7 source tree; tracked as
  Issue 9 rather than expanding this PMX/Starship release recovery.

## Release decision

- This session contains the backward-compatible PMX feature plus fixes, so the correct bump
  remains **minor**: current v3.16.2 → v3.17.0.
- The agent did not run `git-rl`; repository policy requires the human to initiate it.
- After the tag, watch CI to completion, confirm the published release and all six assets,
  then run the clean-container installer smoke before closing Issue 8.

## Release-note review

- Compared the v3.17.0 source notes with the published v3.16.1 release and the detailed
  v3.16.0 feature-release format.
- Expanded the `CHANGELOG.md` entry with a user-facing PMX walkthrough, the mutation safety
  boundary, component architecture, cross-platform regression coverage, and the precise
  Ubuntu 24.04/Starship failure and fix.
- Verified the release workflow extracts the v3.17.0 section into a 4,140-character release
  body, appends versioned installation commands, and publishes `RELEASE_NOTES.md` as an asset.
- Re-ran the architecture gate, all-file PowerShell parser, adapter parity (84 shared calls),
  PMX regression suite, Linux GitHub-release regression, working-tree profile/PMX load,
  added-lines privacy scan, whitespace check, and release-note asset wiring; all passed.

## Files modified for release-note review

- `CHANGELOG.md` (v3.17.0 section — expanded release notes)
- `docs/log/2026/August/06 Thurs/log-2.md` (this release-note review)

**Decisions:** Keep the changelog as the release-note source of truth; CI generates the
standalone `RELEASE_NOTES.md` so a duplicate working-tree copy would drift.

**Bug status:** Bug reported: v3.16.2 Linux release validation failed to install Starship;
production fix applied and locally verified, awaiting replacement release confirmation.

**Commit message:** `vr-commit (v3.17.0) - pmx: guarded VM management; harden Linux dependency downloads`
