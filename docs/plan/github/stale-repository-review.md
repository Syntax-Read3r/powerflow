# GitHub Oldest-First Browsing and Stale Repository Review

**Status:** Approved, implemented, and published in v5.2.0 on 2026-10-14. Mocked regressions, local architecture gates, and release CI pass; a live account repository review remains a user-run check.

## Goal

Help the owner review their longest-unchanged GitHub projects while clearly identifying repositories that host GitHub Pages.

## Recommended interface

`github` is the canonical PowerFlow command family, leaving `gh` for the GitHub CLI:

```powershell
github                      # recent repositories and existing clone/open flow
github 50 --oldest           # oldest-first browser with a count limit
github stale                # all owned repositories, oldest-first review
github stale --older-than 1y # optional age filter
github stale --pages         # Pages-enabled repository review
github org my-team          # existing organization browser
github token status         # existing token status
github token reset          # existing token reset
github help                 # executable command reference
```

Use a thin root dispatcher in `components/github/command.ps1`, loaded after the repository, browser, and review modules. Keep behavior in those modules; neither call nor wrap the native `gh` executable. Check for a `github` command at profile load and report any collision rather than silently overriding another command.

Keep `gh-l`, `gh-l-org`, `gh-l-status`, and `gh-l-reset` as compatibility wrappers for this release, registered with help metadata and a once-per-session migration hint. Document `github` as canonical. Removing the old names outright would require an explicit breaking-release decision.

Implementation chunk 2 includes the dispatcher, root help registration, and compatibility wrappers. Test every route above, preserved legacy calls, unknown-route/flag errors, and unchanged `gh` resolution.

The sort flag and review subcommand share one implementation. Use `stale` rather than `redundant`: inactivity is measurable; redundancy is the owner's judgment.

`github stale` defaults to all accessible owned repositories with no arbitrary age cutoff. The optional age filter accepts positive integer days, months, or years (`180d`, `6m`, `1y`); calendar months/years use UTC calendar subtraction. An exact cutoff match is included. Unsupported, zero, negative, duplicate, and conflicting flags fail with an example retry command. `--pages` includes Pages-enabled repositories whose details could not be retrieved and clearly labels that uncertainty.

## Scope and meaning

- Personal repositories returned by the existing owner-affiliation API query, with complete pagination. Existing organization browsing remains available through `github org` and `gh-l-org`; organization review is a later extension.
- Keep existing `gh-l`, `gh-l 50`, token, status/reset, clone, and browser flows compatible. New long flags must use the shared flag translation mechanism rather than relying on native `param()` to bind `--word`.
- Rank by `pushed_at`, ascending for oldest-first, descending for the existing default. Explain the column as **last push**, not last edit or proof of disuse. A push to any branch can affect this signal; external usage is not measured.
- Show repository creation date separately. Missing/invalid push timestamps are **unknown last push**, never a fabricated 1900 date. Put those rows in a separate clearly labeled group; do not include them in a dated age-filter result.
- Break equal-date ties by full repository name for repeatable results. Identify selections by stable repository ID/full name, not decorated display text.
- Show archived, fork, and template indicators as context, not reasons to remove a project. They remain visible by default.
- The review offers inspect repository, open Pages site when a confirmed URL exists, copy URL, and clone. It does not inherit the browser's deletion action. No automatic deletion, archiving, or numeric redundancy score is part of this feature.
- Pages metadata is visible in ordinary `github` as well as review mode, including its existing action menu before any deletion confirmation. Existing deletion confirmations remain intact.

## GitHub Pages recognition

1. Read `has_pages` from repository metadata as the initial enabled/disabled signal.
2. For displayed Pages-enabled repositories, query `GET /repos/{owner}/{repo}/pages`. Retain the API-reported site URL, custom domain, build status/type, and source branch/path when supplied. Missing source fields remain unknown, including workflow-based publishing.
3. Recognize user/account sites named `<owner>.github.io`, project sites, and custom domains. A matching name or homepage is a hint only; neither proves that Pages is enabled. A confirmed Pages record takes precedence.
4. Show explicit states: `enabled · built`, `enabled · building`, `enabled · errored`, `enabled · status unknown`, `disabled`, or `unknown`. Build status is not a claim of current HTTP reachability or active visitors.
5. If `has_pages` is true but the detail request fails, keep **Pages enabled · details unavailable**. A 404/403, missing permission, rate limit, or network failure must not turn a known Pages site into a no-Pages cleanup candidate. If the initial field is absent, state is unknown.
6. A Pages-enabled project gets the review note **hosts a site — review before retiring**, regardless of age. Include its confirmed URL in the detail view and an open-site action through `Open-Url`.
7. Document Pages read permission for fine-grained tokens where required; public Pages resources may be queried without authentication. Do not broaden permissions automatically or expose tokens in output.

API references: [repository metadata](https://docs.github.com/en/rest/repos/repos), [GitHub Pages metadata and permissions](https://docs.github.com/en/rest/pages/pages).

## Proposed display

Illustrative values, not an audit of the owner's account:

```text
Repository        Last push    Idle       Pages                 Context
old-experiment    2021-03-12   5y 7m      disabled              fork
portfolio         2022-06-09   4y 4m      enabled · built       hosts a site
sample-library    2023-01-20   3y 8m      disabled              archived
```

Show a summary of repository counts, Pages-enabled sites, and unknown Pages states. Disclose incomplete fetching or enrichment rather than presenting a complete-account conclusion. Use fzf when available and a readable report when unavailable or output is redirected. Escape cancellation is neutral; failed requests are distinct from no matching repositories.

## Ordered implementation chunks

### 1. Extract shared repository data and model

- Add `components/github/repositories.ps1`: existing token helper functions moved from `browser.ps1` without changing their contract; paginated repository requests, safe error handling, Pages enrichment, and repository normalization/sorting/filtering helpers.
- Update `components/github/browser.ps1` to use these helpers instead of duplicating fetch/sort logic. Replace fabricated timestamp fallback and remove sorting debug output in the touched flow.
- Update `Microsoft.PowerShell_profile.ps1` to source `repositories.ps1` before `browser.ps1` and the new review entry point.
- API calls are platform-independent. Continue using platform adapters for clipboard, opening paths/URLs, and location needs; add no direct OS calls to components.
- Bound Pages calls to displayed repositories, reuse each response within the invocation, and skip the current per-repository 24-hour/week commit queries in review mode. Do not add a persistent cache or a new dependency.
- Preserve existing credential behavior during extraction; a credential-storage redesign is outside this plan.

### 2. Add oldest-first browsing and review

- Update `components/github/browser.ps1`: translate `--oldest` through the adopted shared flag infrastructure, preserve existing arguments, add Pages column/detail context, and use stable selection keys.
- Add `components/github/review.ps1`: thin internal `Show-PFGitHubReview` entry point for `github stale`, optional age/Pages filters, and inspect/open/clone actions backed by the shared model. Register the public command beside its dispatcher definition.
- Ensure displayed count is applied after sorting; review filters run before display/enrichment. A repository marked Pages-enabled remains included in a Pages filter even when enrichment fails.
- Reuse `components/shared/outcome.ps1` for cancellation, failures, and empty results. Confirm clone success using its native exit status.

### 3. Verify and document

- Add `tests/github/repository-review.ps1` with mocked API responses and picker/actions; add `tests/github/run.ps1` as its runner.
- Update `.github/workflows/release-validate.yml` to run the GitHub regression suite.
- Update registrations in `browser.ps1` and `review.ps1`; generated `pwsh-h` should reflect both commands through the registry, without hand-editing its menu.
- Update `COMPONENTS.md`, `README.md`, and `docs/features.md` with oldest-first browsing, review examples, last-push semantics, and Pages uncertainty.
- Update `docs/troubleshooting.md` for unavailable Pages details and token permissions.
- Add a minor-feature entry for `5.2.0` to `CHANGELOG.md` when implementing, rechecking the then-current version first. Do not hand-edit the configured version or run `git-rl`.
- Add the required implementation session log under the actual date in `docs/log/`.

## Testing and acceptance

- Recent-first remains the default; oldest-first sorting precedes truncation and works over multiple API pages.
- Existing positional count and token forms remain compatible; canonical long flags bind correctly, and invalid flags fail without side effects.
- Age filters cover UTC boundaries, exact cutoffs, month/year arithmetic, missing dates, and malformed inputs. Ties are deterministic.
- Account `github.io` site, ordinary project site, custom domain, disabled Pages, missing metadata, workflow source omission, and detail-request failures render honestly.
- A name/homepage that resembles a Pages URL never overrides authoritative disabled/unknown state.
- Archived/fork/template context stays visible. Pages-only filtering does not discard enabled sites with unavailable details.
- Mock 401, permission failure, rate limit, network error, and partial pagination; no token appears in output, and incomplete results are labeled.
- Selection works for similar repository names; cancelled picker and no-match results remain distinct.
- Review triggers no deletion/archive/write API call. Its clone action runs only after explicit selection; its open action uses the adapter and confirmed URL.
- Assert bounded enrichment calls, no review commit-count requests, and readable operation without fzf or with redirected output.
- Run `pwsh -NoProfile -File tests/github/run.ps1`, the flags regression suite, and relevant local release gates through `tests/gates.ps1`. Validate supported Windows/Linux behavior using mocked adapters rather than requiring live account access.

## Rollback

Revert the implementation commits, including new helpers/review/tests, profile entries, workflow gate, and documentation. The feature creates no persistent configuration and makes no automatic repository mutations; no account rollback is required.

## Verification result

The owner approved execution of the revised command family. The GitHub regression suite passes 124 assertions; the flag convention suite passes 111 assertions; all eight runnable local release architecture gates pass. Five tag-dependent gates require GitHub's release context and were skipped. No account mutations or live repository inventory were performed during validation.
