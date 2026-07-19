# Release Checklist

**Work through this top to bottom before every `git-rl`. Every item on this list exists
because skipping it shipped (or nearly shipped) a real failure — the incident is named so
nobody relitigates the item.**

---

## 1 · Code gates (run these, don't trust memory)

- [ ] **Architecture gate** — the exact CI regex, locally:
  ```powershell
  $forbidden = 'Set-Clipboard|Get-Clipboard|explorer\.exe|\bscoop\b|Start-Process "wt"|WindowsPrincipal|shutdown\.exe|SetEnvironmentVariable|System\.Windows\.Forms|winget|\bpowercfg\b|Get-CimInstance|Get-WinEvent|\$env:(TEMP|USERPROFILE|LOCALAPPDATA|APPDATA|SystemRoot)'
  Get-ChildItem components -Recurse -Filter *.ps1 | Where-Object Name -ne 'create-next.ps1' |
      Select-String -Pattern $forbidden | Where-Object { $_.Line -notmatch '^\s*#' }
  ```
  *Incident: the gate caught bash-compat.ps1 calling `SetEnvironmentVariable` before it shipped.*

- [ ] **Every `.ps1` parses** (Windows pwsh AND Linux pwsh — CI parses on Linux):
  ```powershell
  Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object {
      $e=$null; [Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$null,[ref]$e)|Out-Null
      if($e){ "$($_.Name): $($e[0].Message)" } }
  ```
  *Incident: `$(?:` inside a double-quoted string parsed as a subexpression and killed a whole file.*

- [ ] **Adapter parity** — every contract function exists on BOTH platforms, **and any NEW
  contract name is added to the hardcoded regex in `release-validate.yml`** (it is NOT
  picked up automatically):
  *Incident: the 3.4.0 plan doc assumed the parity list was automatic. It is a hardcoded regex.*

- [ ] **New command shadows nothing on Linux** — `rm/mv/cp/cat/mkdir/touch/rmdir/which/grep`
  must resolve to `Application`, and any new function wrapping a real command name is wrong
  by default:
  *Incident: a wrapped `grep` would have made `cat f | grep x` hang — a function does not forward stdin.*

## 2 · Behaviour verification (real machines, not assertions about code)

- [ ] **Windows**: profile loads under `pwsh -NoProfile`; every new command resolves; the
  new feature exercised for real.
- [ ] **Linux (Docker)**: install from the working tree → profile loads → new feature
  exercised → degradation paths honest → **uninstall leaves nothing and keeps pre-existing
  tools**.
  *Incident: reinstall+uninstall left a dead profile; a re-install disowned every dependency. Both found only by running the sequence.*
- [ ] **Anything that prompts**: run it with **stdin redirected** (`</dev/null`). No
  `Read-Host`/`read` may hang or mis-answer in a pipe.
  *Incident: `curl | bash` upgrades could never succeed — Read-Host read EOF and cancelled; the login-shell `read` made a SUCCESSFUL install exit 1.*
- [ ] **Anything that changes state**: verify by reading the state back, and verify the
  undo path restores it.
  *Incident: `touch` truncated existing files to zero bytes; a "temporary" CPU cap was left behind with no record.*

## 3 · Docs that ship with the release

- [ ] **Help registry** — every new user-facing command has a `Register-PFCommand` beside
  its definition (CLAUDE.md's Help Registration Rule). The CI gate enforces it; run it
  locally rather than discovering in the release run.
  *Incident: the old hand-drawn menu let 4 commands vanish and one row go false.*
- [ ] **`COMPONENTS.md`** — new files, new functions, Platform column, footnotes for any
  non-obvious design decision.
- [ ] **`README.md`** — feature list AND command tables. Check specifically that no
  existing row has become **false** (not just incomplete).
  *Incident: README documented `ls -t` as "tree view" for a full version after 3.3.0 made `-t` GNU time-sort.*
- [ ] **`CHANGELOG.md`** — new section complete; **no stale `Unreleased` headers on
  versions that shipped**; date the section.
  *Incident: 3.3.2 sat as "Unreleased" for three days — which is how its failed release went unnoticed.*
- [ ] **Session log** under `docs/log/YYYY/Month/DD Day/log-N.md`.
- [ ] **Plan doc** (if the release implements one) — flip its status line, record
  deviations from plan.

## 4 · The cut itself

- [ ] **`git status` is clean** of everything that belongs in the release — `git-rl`
  commits the tree, and the tag points wherever HEAD is.
  *Incident: the first v3.3.0 tag was cut before half the work was committed. It pointed at the file-destroying `touch`. The failing CI was the only thing that stopped it shipping.*
- [ ] Run `git-rl` with a description (it becomes the commit message; the GitHub release
  body comes from CHANGELOG automatically).

## 5 · After the tag — the release is not done until this passes

- [ ] **Watch the run to completion**: `gh run watch $(gh run list --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status`
- [ ] **Confirm the release is actually published with assets**:
  ```bash
  gh release view vX.Y.Z --json assets --jq '.assets[].name'
  ```
  *Incident — twice: v3.2.0 and v3.3.2 both failed CI silently and sat unpublished (3.3.2 for three days). A green tag push is not a release.*
- [ ] **If a leg failed**: read the actual step output before changing anything — two of
  this project's CI failures were the *test's* bug (the lockout test moved one of two
  pwsh installs) and one was transient infrastructure (anonymous API 403). `gh run rerun
  <id> --failed` is the right first move for a transient.
- [ ] **Post-release smoke** (clean container, the real user path):
  ```bash
  curl -fsSL https://raw.githubusercontent.com/Syntax-Read3r/powerflow/main/install.sh | bash -s -- --yes
  ```
