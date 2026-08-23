# 19 Aug 2026 — a drive layout, and an audit that started as a typo

The session began with a request to use a second drive for installs. It ended having found
three file operations that reported success while failing, one of which lost the user's held
file. The route between the two is the point of this log.

---

## 1 · The storage work that was asked for

The owner had hand-built a `D:\DevTools` layout — CLI binaries, tool state, caches and
runtimes separated, around eighty environment variables pointing into it — and wanted future
installs to find a second drive on their own.

A design pass against the tree refuted four things the repository believed:

| Believed | Measured |
|---|---|
| the install tree can be relocated behind a `$PROFILE` stub | the *mechanism* works on pwsh 7.6.5 and WinPS 5.1, but nothing in the repo supports it: no destination parameter, `powerflow-update` reinstalls to the default, uninstall strands the tree |
| setting `$env:SCOOP` is how a relocated root is recorded | Scoop writes `root_path` in its **own** config, and the upstream installer writes it **only when no User-scope `SCOOP` exists** |
| `DriveType` distinguishes internal from external | `Get-Volume` reports a USB WD My Passport as `Fixed`, 481 GB free — indistinguishable from an ideal second drive |
| Linux can already tell a data mount from noise | against a fixture, 9 of 10 junk rows survived: boot and EFI partitions, nfs4, cifs, removable exfat, a loop image and a read-only mount |

The tree/Scoop ratio settled the design without argument: **1.67 MB of install tree against
570 MB of Scoop root**, 1:341. Relocating the tree spends the whole risk budget on 0.3% of
the problem. So only what *grows* moves.

Shipped: `storage root` (read-only), `nav setup`, multi-spelling anchors, one shared volume
classifier, and `Get-PackageManagerRoot` reading `root_path` across the four sites that had
each been reading only the variable.

## 2 · The typo

Mid-session, from real use:

```
❯ nav zovoya
❌ Cancelled
```

Nothing was cancelled. `nav` piped its candidates to fzf and tested only whether the result
string was empty:

```powershell
$selected = $map.Keys | fzf --query $query --select-1 --exit-0 ...
if ($selected) { ... } else {
    # User pressed Esc or no fuzzy match survived
    Write-Host "❌ Cancelled" -ForegroundColor DarkGray
}
```

fzf exits **0** on a selection, **1** when nothing matched and **130** on Escape. Two
opposite outcomes reached one branch, and the branch printed the message written for the
other one. The comment admitted it.

That looked like a wording bug. It was not.

## 3 · What the audit actually found

Twenty-one agents across the command surface: **107 findings confirmed, 2 refuted**. Three
were not messaging problems at all, and each was reproduced on the machine before being
touched.

**The shared cause.** `Move-Item`, `Copy-Item` and `Rename-Item` fail **non-terminatingly**.
Without `-ErrorAction Stop` the failure never reaches the surrounding `catch`, so execution
walks into the green banner underneath. Every "did it work" check written as `try/catch`
around those cmdlets had been answering a question it never asked.

**`rn` had never once completed an approved overwrite.** It asked *"Overwrite existing file?
(y/n)"* and then called `Rename-Item`, which cannot overwrite even with `-Force` — measured,
`IOException`. Say yes, and you were told `RENAME COMPLETED` while the original sat there
under its old name. With `--chmod`, the permission half then applied itself to the file the
rename had failed to replace.

**`mv-t` lost the cut as well as the move.** A failed move printed success and then cleared
the held file. Its own `catch` says *"The file is still held"* — true only in the one case
where it could not print.

**`paste-file` corroborated its own lie.** It printed `Pasted`, then stat'd the destination
and reported its size. Where the destination already existed, that was the **old** file: a
plausible number beside a green tick, describing a file that was never written.

A false success carrying evidence is much harder to disbelieve than a bare one. That is the
lesson worth keeping.

## 4 · The convention, and a gate with teeth

Thirty-five red crosses sat on user decisions. Three refused repository deletions printed in
**green**. Twenty-six fzf calls never read their exit code.

`components/shared/outcome.ps1` now holds the renderer, and `release-validate.yml` fails the
release on a `❌` beside cancel language and on an `| fzf` pipeline whose exit code is never
read. Writing the gate took three corrections, all of which are the gate teaching itself:

- **Red exempts.** *"Not every version file could be updated — release cancelled"* is a
  genuine failure that *causes* a cancellation and is correctly red. The rule catches the
  decision wearing an error's clothes, not the reverse.
- **The window starts after the statement.** An fzf call with backtick continuations runs to
  thirteen lines on its own, so a window measured from its first line filled before reaching
  the capture and flagged code that was already correct.
- **Count code lines, not raw lines.** Otherwise a long explanatory comment between the call
  and the capture hides a real violation — or invents one.

Deliberately **not** enforced: "❌ implies Red". A status table legitimately prints an `❌`
cell in a per-row colour, and a gate that cannot tell those apart gets switched off rather
than obeyed.

## 5 · Three mistakes of mine, recorded because they were instructive

**`git add components` swept up someone else's work.** A concurrent session was mid-change on
`roots.ps1` and `bookmarks.ps1`. Staging the directory captured those two files but not the
adapters that *define* the function they had started calling — so a fresh checkout of that
commit would have hit an undefined function at profile load. The working tree hid it because
the adapters were present but unstaged. Completing the change was the repair; verifying it in
a clean `git worktree` was the proof. `git add <directory>` is the wrong instrument when
somebody else is working in the same tree.

**Completing it exposed a split.** Bookmarks and roots had moved to `POWERFLOW_DATA_HOME`;
anchors had not. One command's state, two locations, on two drives — which is exactly how the
owner experienced nav "losing" its configuration.

**My own gate caught my own code.** `Select-PFCodeRoot`, written earlier the same day, never
read `$LASTEXITCODE`. So did `nav setup`'s headline, which announced *"Found another drive:
D:, E:"* where `E:` was the USB disk — the candidate list marked it removable and the summary
line, the one most likely to be read instead of the list, did not. Both found by the release
checklist rather than by review.

## 6 · What did not get done, and why

- **WSL is not enabled**, so podman is installed and fully placed but cannot run a container.
  `pman events` therefore has its parser but not its command surface: the half that shells
  out could not be verified, and shipping it unverified would be the same class of claim this
  session spent its time removing.
- **Installer placement** (setting the Scoop root at install time) is a major bump that
  changes where installs land, and is not something to ship unasked.
- **Round 2 of the backlog did not move.** Still 5 of 16.
- **103 audit findings remain**, with the worst ten listed in `TODO.md` by file and line.
  Coverage is stated honestly in the audit: `github/browser.ps1`, most of `proxmox/`, all of
  `shell/` and much of `system/` were carried from the candidate list rather than re-read.

## 7 · The continuity note

The machine reset had destroyed the agent memory, and with it a standing owner directive
forbidding `Co-Authored-By` trailers in this repository. Five commits broke it before the
team-chat archive surfaced the rule again.

The fix is not a better memory. It is
[`docs/feature-fix-and-improvements/TODO.md`](../../../feature-fix-and-improvements/TODO.md),
which is committed: open items with what each is blocked on, and the standing constraints
in §5. A rule that lives only in an agent's memory is one reset away from being broken, and
this session is the proof.
