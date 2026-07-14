# `git-rl` — AI Setup Prompt

> This file is what `git-rl -h` prints. Copy **everything inside the fenced block below**
> and paste it into an AI coding assistant (Claude Code, Cursor, Copilot Chat …) that is
> open in the repository you want to set up.
>
> The AI has no PowerFlow context, so the prompt is deliberately self-contained.

---

```text
You are setting up this repository so that the `git-rl` release command works in it.

`git-rl` is an interactive release tool from PowerFlow (a PowerShell profile). It does NOT
exist in this repo — it runs on my machine. Your job is to make THIS repository satisfy the
contract `git-rl` expects, and to build the GitHub Actions pipeline it triggers.

Do not install PowerFlow here. Do not add PowerShell as a project dependency. You are only
creating a version file, a CHANGELOG, and CI workflows.

================================================================================
PART 0 — WHAT git-rl DOES (so you understand what you are wiring up)
================================================================================

When I run `git-rl` in this repo, it will:

  1. Verify it is inside a git repository.
  2. Detect the project's version file(s) — package.json, pyproject.toml, Cargo.toml,
     *.csproj, build.gradle, VERSION, or config/PowerFlow.settings.ps1 — and read the
     current version from them. If none exists, fall back to the latest git tag, then
     to 0.0.0.
  3. Warn if several version files DISAGREE, and offer to bring them into sync.
  4. Show an fzf picker: patch / minor / major / custom.
  5. Prompt me for a one-line release description.
  6. REWRITE every detected version file to the new version (formatting preserved).
  7. `git add .`
  8. `git commit -m "vr-commit (vX.Y.Z) - <description>"`
  9. `git push`
 10. `git tag vX.Y.Z`
 11. `git push origin vX.Y.Z`   <-- THIS is what triggers CI.

So: pushing a tag matching `v*` MUST trigger the release pipeline. Everything else in CI
hangs off that.

================================================================================
PART 1 — THE VERSION FILE
================================================================================

GOOD NEWS: you almost certainly do not need to do anything here.

`git-rl` reads the project's OWN version file. It detects and rewrites any of these,
automatically:

    package.json                  "version": "X.Y.Z"          (Node)
    pyproject.toml                version = "X.Y.Z"           (Python, [project] or [tool.poetry])
    Cargo.toml                    version = "X.Y.Z"           (Rust, [package] only)
    *.csproj                      <Version>X.Y.Z</Version>    (.NET)
    build.gradle / .gradle.kts    version = "X.Y.Z"           (Gradle)
    VERSION                       X.Y.Z                       (plain text)
    config/PowerFlow.settings.ps1 $script:POWERFLOW_VERSION   (PowerShell)

Notes:
  * It rewrites the file with a targeted regex, so FORMATTING AND KEY ORDER ARE
    PRESERVED. It does not reserialise your package.json.
  * A `version` under [dependencies] or a nested "version" key is NOT touched — only the
    project's own version.
  * If SEVERAL of these exist (e.g. package.json AND a VERSION file), git-rl updates
    ALL of them together and warns you if they currently disagree. Version drift is
    handled at the source; you do NOT need a CI check to police it.
  * If NONE exists, git-rl falls back to the latest git tag and rewrites nothing. That
    works, but the version then lives nowhere in the source tree.

SO: if this project already has one of the files above, YOU ARE DONE with this part.
Just confirm the version in it is correct and tell me what you found.

If the project has NO version file at all and you think it should have one, create the
idiomatic one for its language (e.g. add a "version" to package.json), NOT a PowerShell
file. Do not create config/PowerFlow.settings.ps1 in a non-PowerShell project.

================================================================================
PART 2 — CHANGELOG.md
================================================================================

Create `CHANGELOG.md` at the repo root if it does not exist. The CI extracts the release
notes from it with this regex, where $version is e.g. `1.2.0`:

    (?s)## \[$version\].*?(?=## \[|\z)

Therefore the format is NOT optional. Rules:

  * Newest version FIRST, at the top.
  * The section heading MUST be exactly:  ## [X.Y.Z] - YYYY-MM-DD
    While a version is being prepared, use:  ## [X.Y.Z] - Unreleased
  * Use `### Added` / `### Changed` / `### Fixed` / `### Removed` subsections.
  * Do NOT put installation commands in the CHANGELOG. CI appends an install section to
    the release notes automatically; duplicating it makes it appear twice.

Example:

    # Changelog

    ## [1.2.0] - Unreleased

    ### Added
    - New `foo` command.

    ### Fixed
    - `bar` no longer crashes on empty input.

    ## [1.1.0] - 2026-01-15
    ...

Seed it with the project's current version so the first `git-rl` run has something to
extract.

================================================================================
PART 3 — THE GITHUB ACTIONS PIPELINE
================================================================================

Create `.github/workflows/`. The pipeline is one ORCHESTRATOR that calls reusable
component workflows. Use the PowerFlow originals as your reference implementation — fetch
them and adapt, do not write YAML from memory:

  https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/.github/workflows/release.yml
  https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/.github/workflows/release-validate.yml
  https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/.github/workflows/release-generate-scripts.yml
  https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/.github/workflows/release-bundle-archive.yml
  https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/.github/workflows/release-publish.yml
  https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/.github/workflows/release-notify.yml

Required behaviour of each:

--- release.yml (ORCHESTRATOR) ------------------------------------------------
  * Trigger:  on: push: tags: ['v*']          <-- MANDATORY. git-rl pushes a v* tag.
  * permissions: contents: read  (the publish job elevates to write)
  * Calls, in order:
      validate  ->  (build jobs in parallel)  ->  publish  ->  notify
  * `publish` must `needs:` every job that could invalidate the release, so a broken
    build BLOCKS publication rather than shipping.

--- release-validate.yml ------------------------------------------------------
  * runs-on: ubuntu-latest (or windows-latest if the project needs it)
  * Parses the version out of the tag:  $version = $tagName -replace '^v',''
  * Outputs `version` and `tag_name` for the downstream jobs.
  * MUST FAIL the release if the tag disagrees with the project's version file.
    git-rl writes both, so they should always agree — this catches a hand-edited tag or
    a bad merge, which is exactly when you want the release to stop.
  * Add whatever project-specific gates make sense here (lint, typecheck, unit tests).
    Anything that must not ship broken belongs in this job.

--- release-generate-scripts.yml ----------------------------------------------
  * Produces RELEASE_NOTES.md by extracting the CHANGELOG section for this version
    (regex in Part 2). If no section is found, fall back to a generic body.
  * Uploads whatever install/distribution artifacts this project ships.
  * IMPORTANT: ship real files from the repo. Do NOT generate installer scripts from
    here-strings embedded in the YAML — PowerFlow did that and the generated copy
    silently drifted from the real one in the repo. One source of truth.

--- release-bundle-archive.yml ------------------------------------------------
  * Builds the distributable (zip/tarball/wheel/npm pack — whatever this project ships).
  * FAIL the job if a required path is missing, rather than silently shipping an
    incomplete archive.

--- release-publish.yml -------------------------------------------------------
  * permissions: contents: write
  * Downloads the artifacts, creates the GitHub Release with softprops/action-gh-release.
  * body_path: ./release-files/RELEASE_NOTES.md
  * fail_on_unmatched_files: true   <-- a missing asset must HARD FAIL, not warn.

--- release-notify.yml --------------------------------------------------------
  * Logs the release URL and the copy-pasteable install command(s).

================================================================================
PART 4 — REPOSITORY PREREQUISITES
================================================================================

  * A GitHub remote named `origin`. Verify: `git remote get-url origin`
  * Actions enabled, and Settings > Actions > General > Workflow permissions set to
    "Read and write permissions" (otherwise the publish job cannot create a release).
  * `fzf` must be installed on MY machine (git-rl uses it for the bump picker). That is
    my problem, not yours — but mention it if you notice it missing.
  * Tags must be semver with a leading v: `v1.2.3`. Not `1.2.3`, not `v1.2`.

================================================================================
PART 5 — VERIFY BEFORE YOU TELL ME IT IS DONE
================================================================================

Do not report success until you have actually checked these. Run the commands.

  [ ] `git remote get-url origin` resolves to a GitHub URL.
  [ ] The project has a version file git-rl understands (see Part 1), OR you have told me
      plainly that it does not and the tag will carry the version.
  [ ] If SEVERAL version files exist, their numbers AGREE right now.
  [ ] CHANGELOG.md has a `## [X.Y.Z]` section for the current version.
  [ ] Every workflow YAML parses. Actually validate it — e.g.:
          python -c "import yaml,glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/workflows/*.yml')]"
  [ ] `release.yml` triggers on `tags: ['v*']`.
  [ ] `publish` has `permissions: contents: write` AND `fail_on_unmatched_files: true`.
  [ ] Simulate the release-notes extraction and show me the output, so we know the
      CHANGELOG regex actually matches:
          the section for the current version must be found and be non-empty.

================================================================================
PART 6 — WRITE THE README
================================================================================

Create `docs/RELEASING.md` in THIS repo documenting what you built, so I can run a release
by hand if the tooling ever goes away. It must cover:

  * Which version strategy you chose and WHY.
  * The exact file(s) that hold the version, and how they stay in sync.
  * The CHANGELOG format contract (and that CI parses it).
  * What each workflow does and in what order.
  * The manual equivalent of `git-rl`, as copy-pasteable commands:

        # 1. bump the version file(s) by hand
        # 2. update CHANGELOG.md: ## [X.Y.Z] - Unreleased
        git add .
        git commit -m "vr-commit (vX.Y.Z) - <description>"
        git push
        git tag vX.Y.Z
        git push origin vX.Y.Z     # <-- triggers CI

  * How to ABORT / undo a bad release:

        git push origin :refs/tags/vX.Y.Z   # delete the remote tag
        git tag -d vX.Y.Z                   # delete the local tag
        gh release delete vX.Y.Z            # delete the GitHub release, if one was created

  * Post-release verification: confirm the GitHub Release exists AND has its expected
    assets attached. A green CI run does not guarantee the release object was created.

================================================================================
FINALLY
================================================================================

Report back with:
  1. Which version strategy you chose, and why.
  2. Every file you created or modified.
  3. The output of each verification check in Part 5 — actual command output, not a claim.
  4. Anything you could NOT verify, stated plainly.

Do not tell me it works if you have not run the checks.
```
