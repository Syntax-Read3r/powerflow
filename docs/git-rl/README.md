# `git-rl` — Release Tooling

`git-rl` (alias of `git-release`) is PowerFlow's one-command release: it bumps the version,
commits, tags, pushes the tag, and the tag push triggers the CI pipeline that builds and
publishes the GitHub Release.

It only works in a repository that is **set up for it**. This directory explains that setup.

| File | Purpose |
|---|---|
| [SETUP-PROMPT.md](SETUP-PROMPT.md) | The setup prompt. `git-rl -h` copies it to your clipboard and embeds it in the guide it writes into your project. |
| [../git-rl-project-setup.md](../git-rl-project-setup.md) | The deep technical reference — every workflow, field by field. |
| This file | What the setup *is*, and how to run a release **by hand** if the tooling is unavailable. |

---

## Quick start

```powershell
git-rl -h        # confirm the folder, write docs/git-release-help.md into it, copy the prompt
```

Paste it into an AI assistant that is open in the target repository. It will create the
version file, the CHANGELOG, and the CI pipeline, then verify them.

---

## What `git-rl` actually does

```
git-rl
  │
  ├─ 1. detect the project's version file(s) and read the current version
  │      (falls back to the latest git tag, then 0.0.0)
  ├─ 2. warn if several version files DISAGREE, and offer to sync them
  ├─ 3. fzf picker → patch / minor / major / custom
  ├─ 4. prompt for a one-line description
  ├─ 5. rewrite EVERY version file to the new version
  ├─ 6. git add .
  ├─ 7. git commit -m "vr-commit (vX.Y.Z) - <description>"
  ├─ 8. git push
  ├─ 9. git tag vX.Y.Z
  └─ 10. git push origin vX.Y.Z    ← THIS triggers CI
```

Everything downstream hangs off the last step. The tag is the trigger; nothing else is.

---

## The three requirements

### 1. A version source

`git-rl` reads **your project's own version file**. It detects and rewrites any of these:

| Project | File | Pattern |
|---|---|---|
| Node | `package.json` | `"version": "X.Y.Z"` |
| Python | `pyproject.toml` | `version = "X.Y.Z"` (`[project]` / `[tool.poetry]`) |
| Rust | `Cargo.toml` | `version = "X.Y.Z"` (`[package]` only) |
| .NET | `*.csproj` | `<Version>X.Y.Z</Version>` |
| Gradle | `build.gradle(.kts)` | `version = "X.Y.Z"` |
| Any | `VERSION` | plain text |
| PowerShell | `config/PowerFlow.settings.ps1` | `$script:POWERFLOW_VERSION` |

If none exists, it falls back to the latest **git tag** and rewrites nothing.

**Formatting is preserved.** The rewrite is a targeted regex, never a parse-and-
reserialise — round-tripping `package.json` through a JSON serialiser would reorder keys
and reindent the whole file, which is an unacceptable diff for a version bump.

**Nested versions are safe.** A `version` under `[dependencies]`, or a nested `"version"`
key inside `package.json`, is never touched — only the project's own version.

> ✅ **Version drift is handled at the source.** If a project has *several* version files
> (say `package.json` **and** a `VERSION` file), `git-rl` updates **all of them together**
> and warns you before bumping if they currently disagree. You do not need a CI check to
> police it — though `release-validate.yml` still asserts the tag matches, which catches a
> hand-edited tag or a bad merge.

### 2. A parseable CHANGELOG

CI extracts the release notes with:

```
(?s)## \[$version\].*?(?=## \[|\z)
```

So the heading must be exactly `## [X.Y.Z] - YYYY-MM-DD` (or `- Unreleased` while in
progress), newest first. If the regex finds nothing, the release ships with a generic body.

### 3. A tag-triggered pipeline

```yaml
on:
  push:
    tags: ['v*']
```

`validate` → build jobs (parallel) → `publish` → `notify`.

`publish` must `needs:` every job that could invalidate the release, so that a broken build
**blocks publication** instead of shipping. It also needs `contents: write` and
`fail_on_unmatched_files: true` — a missing asset should hard-fail, not warn.

---

## Running a release by hand

If `git-rl` is unavailable, this is the whole thing:

```bash
# 1. Bump EVERY version file the project has — package.json, pyproject.toml,
#    Cargo.toml, *.csproj, build.gradle, VERSION, config/PowerFlow.settings.ps1.
#    If you miss one, they drift. (git-rl does all of them for you.)

# 2. Add the CHANGELOG section
#    ## [1.2.0] - Unreleased
#      ### Added ...

git add .
git commit -m "vr-commit (v1.2.0) - short plain-text description"
git push

git tag v1.2.0
git push origin v1.2.0        # ← triggers CI
```

**Keep the description plain text.** No markdown, no backticks, no `**`. It goes straight
into a commit message, and pasted changelog markdown gets truncated mid-sentence — leaving
orphaned backticks in the git log. (This has happened.)

---

## Aborting a bad release

```bash
git push origin :refs/tags/v1.2.0   # delete the remote tag
git tag -d v1.2.0                   # delete the local tag
gh release delete v1.2.0            # delete the GitHub Release, if one was created
```

If the version-bump commit was already pushed and you want a truly clean slate, you must
also rewind the branch — which rewrites public history:

```bash
git reset --soft <commit-before-the-bump>   # keeps all your work staged
# restore the version file by hand
git push --force origin main                # ⚠️ rewrites history
```

Prefer deleting just the tag and re-tagging a fixed commit. Force-pushing a shared branch
is a bigger hammer than most situations need.

---

## Post-release verification (do not skip)

A green CI run does **not** guarantee the release object exists.

1. Open `https://github.com/<owner>/<repo>/releases` — the new version must be listed.
2. Confirm the expected **assets** are attached.
3. If assets are missing, the publish job failed after the tag was pushed. `releases/latest`
   will still point at the previous version, and users will silently keep installing the
   old one.

---

## Semver, briefly

| Change | Bump |
|---|---|
| Bug fix only | **patch** — `1.2.3 → 1.2.4` |
| New backwards-compatible feature | **minor** — `1.2.3 → 1.3.0` |
| Breaking change | **major** — `1.2.3 → 2.0.0` |

If a release contains both a fix and a feature, use the **higher** bump.
