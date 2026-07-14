# `git-rl` — Release Tooling

`git-rl` (alias of `git-release`) is PowerFlow's one-command release: it bumps the version,
commits, tags, pushes the tag, and the tag push triggers the CI pipeline that builds and
publishes the GitHub Release.

It only works in a repository that is **set up for it**. This directory explains that setup.

| File | Purpose |
|---|---|
| [SETUP-PROMPT.md](SETUP-PROMPT.md) | The copy-pasteable prompt. `git-rl -h` prints it. Paste it into an AI in the repo you want to set up. |
| [../git-rl-project-setup.md](../git-rl-project-setup.md) | The deep technical reference — every workflow, field by field. |
| This file | What the setup *is*, and how to run a release **by hand** if the tooling is unavailable. |

---

## Quick start

```powershell
git-rl -h        # print the setup prompt (also copied to your clipboard)
```

Paste it into an AI assistant that is open in the target repository. It will create the
version file, the CHANGELOG, and the CI pipeline, then verify them.

---

## What `git-rl` actually does

```
git-rl
  │
  ├─ 1. resolve the CURRENT version
  │      a) config/PowerFlow.settings.ps1  →  $script:POWERFLOW_VERSION = "X.Y.Z"
  │      b) else: latest git tag (vX.Y.Z)
  │      c) else: 0.0.0
  │
  ├─ 2. fzf picker → patch / minor / major / custom
  ├─ 3. prompt for a one-line description
  ├─ 4. rewrite the version line (only if it used source (a))
  ├─ 5. git add .
  ├─ 6. git commit -m "vr-commit (vX.Y.Z) - <description>"
  ├─ 7. git push
  ├─ 8. git tag vX.Y.Z
  └─ 9. git push origin vX.Y.Z    ← THIS triggers CI
```

Everything downstream hangs off step 9. The tag is the trigger; nothing else is.

---

## The three requirements

### 1. A version source

`git-rl` reads a **hardcoded** path and variable name:

```
config/PowerFlow.settings.ps1
$script:POWERFLOW_VERSION = "1.0.0"
```

It does **not** read `package.json`, `pyproject.toml`, or `Cargo.toml`. If that file is
absent it falls back to the latest git tag and rewrites nothing.

> ⚠️ **The classic failure.** If the project has its *own* version file, you now have two
> numbers that will drift apart. Add a check in `release-validate.yml` that fails the
> release when the tag, the settings file, and `package.json` disagree. Do not rely on
> remembering to bump both.

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
# 1. Bump the version file(s)
#    config/PowerFlow.settings.ps1  →  $script:POWERFLOW_VERSION = "1.2.0"
#    ...and package.json etc. if the project has one

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
