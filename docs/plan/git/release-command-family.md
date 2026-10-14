# Release Command Family

**Status:** Implemented, validated, and published in v5.2.0 on 2026-10-14. The owner-requested `release setup` run completed in the verified PowerFlow checkout, generating `docs/release-help.md` and copying the setup prompt. Release CI and assets were verified after the owner's later publication request.

## Goal

Name release preparation by its purpose through `release`, `release setup`, and `release help`, preserving existing commands and release behavior.

## Scope

- Bare `release` runs the existing interactive version/commit/tag/push flow.
- `release setup` runs the existing confirmed-folder guide delivery flow. New guides use `docs/release-help.md`; existing `docs/git-release-help.md` remains recognized.
- `release help`, `release --help`, and `release -h` show usage without writing, prompting, or accessing Git/network.
- `git-rl` and `git-release` remain compatibility wrappers, with a once-per-session migration hint. Their existing help/setup flags retain their setup behavior.
- Rename internal children to `Invoke-PFRelease`, `Show-PFReleaseSetup`, `Get-PFReleaseDocs`, and `Write-PFReleaseGuide`. Project version helpers already express their purpose and keep their names.
- Keep installed runtime document paths under `docs/git-rl/` to preserve packaging/older installations; update their contents to the canonical commands. Historical logs and changelog entries keep their original names.
- Do not publish, tag, push, or change the configured version. Confirm the exact checkout before the explicitly requested setup run.

## Chunks

1. Update `components/git/release.ps1` with the renamed helpers, thin public dispatcher, read-only help, compatibility wrappers, collision guard, guide filename fallback, and registry entries. Keep version detection and release mechanics intact.
2. Update `tests/git/release-setup.ps1`, add `tests/git/release-command.ps1`, extend `tests/git/run.ps1`, and update the real release parameter metadata reference in `tests/flags/convention.ps1`. Cover help/setup separation, legacy calls, invalid route refusal, confirmed guide writing, old-guide recognition, command collisions, and non-mutating bare unconfigured behavior.
3. Update current documentation in `README.md`, `COMPONENTS.md`, `docs/features.md`, `docs/git-rl/README.md`, `docs/git-rl/SETUP-PROMPT.md`, `docs/git-rl-project-setup.md`, `docs/release-checklist.md`, `CLAUDE.md`, `docs/instructions.md`, and relevant source/workflow/installer references. Extend the existing 5.2.0 Unreleased entry in `CHANGELOG.md`; log the task in `docs/log/`.
4. Run the Git and flag suites, the GitHub suite affected by registry integration, local release gates, and actual generated help. Then invoke `release setup` in the checked PowerFlow workspace, confirm this target through its existing UI, and verify `docs/release-help.md` was generated. The setup guide does not itself build a new pipeline or publish a release.

## Rollback

Revert only this task's source/documentation changes, preserving earlier uncommitted GitHub work. Remove the newly generated guide only if explicitly requested; setup does not mutate versions, Git history, or remote state.

## Testing

Read-only help and invalid invocations must never reach Git, a picker, file writing, or network access. Exercise configured bare release only up to a mocked picker to avoid real release mutations. Preserve the existing setup confirmation and overwrite prompt; check both canonical and legacy guide recognition. Ensure compatibility setup flags still route to setup and new help flags route to usage. Verify registration, collision protection, and unchanged configured version and HEAD after the actual setup run.

## Results

- Git suite: 22 setup assertions plus 44 command-family assertions passed.
- Flag suite: 130 assertions passed. The shim audit now uses the AST so multiline compatibility wrappers remain covered.
- GitHub suite: 124 assertions passed, preserving the prior command-family work.
- Local release gates: eight passed, zero failed; five requiring GitHub tag context skipped.
- Syntax parsed for seven affected executable files; actual `pwsh-h release` renders the canonical command in the release section; `git diff --check` passed.
- Ran the actual `release setup` command in the exact authorized workspace, selected its affirmative folder confirmation through fzf, and verified the generated guide and clipboard prompt. HEAD remained `6de836839da73628acc7e594a2a284289103b9b4`; configured version remains 5.1.0.
