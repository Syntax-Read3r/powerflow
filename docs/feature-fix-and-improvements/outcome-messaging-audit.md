# Outcome messaging audit — what the shell says happened, versus what happened

**Status:** findings, not a change. Nothing in this document has been fixed.
**Scope:** every user-facing message that reports *how a command ended*.
**Date:** 2026-08-22 · branch `storage-allocation`

---

## 1. The symptom that started it

```
> nav zovoya
❌ Cancelled
```

Nothing was cancelled. The user typed a directory name that matched nothing.

`nav` piped its candidate directories to `fzf` with `--select-1 --exit-0` and then tested only
whether the returned string was empty:

```powershell
if ($selected) { ... } else { Write-Host "❌ Cancelled" }
```

fzf has three exits and they mean three different things:

| exit | meaning |
|---|---|
| `0` | something was selected |
| `1` | **nothing matched** — with `--exit-0`, fzf quits before drawing anything |
| `130` | the user pressed Escape or Ctrl-C |

Both `1` and `130` produce an empty string, so two opposite outcomes reached one branch — and
the branch printed the message written for the *other* one. A typo was reported as a decision
the user never made. The source comment admitted it: *"User pressed Esc or no fuzzy match
survived."*

Two separate faults are stacked here, and they need different fixes:

1. **The outcome is wrong.** The discriminator existed (`$LASTEXITCODE`) and was thrown away.
2. **The severity marker is wrong.** Even for a real Escape, `❌` is the wrong glyph. PF-UX-002
   settled that: *the red marker is the one piece of output that has to stay trustworthy —
   spending it on a user who simply changed their mind teaches them to scan past it, and the
   next time it means something, they will.* The house rendering is a dim `↩ Cancelled.`
   `nav.ps1` used `❌ Cancelled` in **DarkGray** — a red-cross glyph with grey text, which is
   neither convention.

**`nav.ps1` itself is already fixed** in this tree. `components/navigation/nav.ps1:386` now
captures `$fzfExit = $LASTEXITCODE` on the line immediately after the pipeline, branches `130`
to `↩ Cancelled.` (`:400`) and reserves the red marker for a genuine no-match that names the
query, the scope searched, and the nearest real directory name (`:405-412`).
`tests/navigation/outcomes.ps1:68-94` asserts all of it against source.

The reason for this audit is what happened next: the same defect is everywhere else. `nav.ps1`
was fixed at the call site rather than at a boundary, and the shape it fixed survives, in the
same file family, in sixteen other places.

---

## 2. The convention to adopt

One rule, stated once:

> **The message names the outcome that actually happened; the marker names its severity; and
> both are read from a signal the code is holding, never inferred from an empty value.**

### 2.1 The marker table

Read the marker from this table at the moment of rendering. It is data, not decoration — never
a literal baked into a format string next to a value it might contradict.

| Outcome | Marker | Colour | Sentence shape | Already done right at |
|---|---|---|---|---|
| Did what was asked, **and the claim was re-read** | `✅` | Green | `✅ <past-tense verb> <thing>` — name what changed and where it now is | `components/navigation/bookmarks.ps1:98` (gates on `Save-Bookmarks`' return); `platform/windows/adapters/apps.ps1:217` (`return (-not (Test-Path $App.InstallLocation))`) |
| Dispatched and accepted, **verification could not run** | `⚠️` | Yellow | `⚠️ <X> was accepted, but it could not be verified: <why>` — never assert the negative | `components/proxmox/vm-change.ps1:103-104` |
| **Partly** done | `⚠️` | Yellow | Name what did happen and what did not, each by name, then the command that finishes it | `components/files/rename.ps1:213-230` |
| A **decision** by the user (Escape, `n`, declined overwrite, kept, picked the current item) | `↩` | DarkGray | `↩ Cancelled.` — that string, alone. No cause, no hint, no colour | `components/navigation/nav.ps1:400`; `components/navigation/roots.ps1:946`; `components/proxmox/shared.ps1:419-423` |
| A deliberate **no-op** (nothing selected, nothing to do) | none or `ℹ️` | DarkGray | State the null effect in the user's terms | `components/files/operations.ps1:197` — `ℹ️ No selection made. Nothing deleted.` |
| A read-only query whose **true answer is "no"** | `⭕` | Yellow | `⭕ <X> is not <state>.` plus the one command that would change it | `components/system/login.ps1:54` — `⭕ PowerFlow does NOT start on login — you land in bash.` |
| **Nobody could be asked** (stdin redirected, no fzf, no tty) | `ℹ️` if the output was still delivered, `⚠️` if not | DarkGray / Yellow | Name the missing precondition and the non-interactive spelling. **Never the word "cancelled"** | `components/navigation/roots.ps1:935-938`; `components/containers/containers.ps1:949` |
| **Refused** — a mutation was requested that cannot be confirmed | `❌ Refused:` | Red | `❌ Refused: this change requires an interactive terminal.` Name the precondition, not the user | `components/proxmox/shared.ps1:322` |
| Nothing **matched what was typed** | `❌` | Red | `❌ Nothing matching '<query>' in: <scope actually searched>` + nearest real name if one is close | `components/navigation/nav.ps1:405-412` |
| **Could not look** — an enumeration or query failed | `⚠️` | Yellow | Name the query that failed and its own error text. Never a count, never "none", never `n/a` | `components/containers/containers.ps1:286-288`; `components/files/listing.ps1:107` (`(no readable entries)`) |
| Attempted and **failed** | `❌` | Red | Name the operation, the target, and the engine's or exception's **own** message. Never a guessed cause | `components/proxmox/shared.ps1:428-446`; `components/navigation/bookmarks.ps1:73` |
| **Usage error** — missing, malformed or unknown argument | `❌` | Red | `<cmd>: <what was wrong with this token>` + `Usage:` / `accepts:` | `components/network/servers.ps1:306-308`; `components/shared/flags.ps1:354-370` |

Two mechanical corollaries fall out of the table and are worth stating separately, because
they are the two most frequent violations:

- **`❌` may only appear on a `-ForegroundColor Red` line.** `❌` in DarkGray or Yellow is the
  seed defect's signature. It appears at roughly 37 sites across 16 component files.
- **A glyph is never a string literal beside a value it may contradict.**
  `components/core/version.ps1:244` prints `✅ Profile Loaded: False`.

### 2.2 The eight rules that produce the table

Each is already practised somewhere in this tree; none is invented here.

**R1 — Capture before you speak.** Any external call whose result a user will be told about
captures its discriminator on the *very next line* (`$fzfExit = $LASTEXITCODE`, `nav.ps1:386`)
or is made terminating (`-ErrorAction Stop`, `components/files/operations.ps1:249` and `:345`).
No `Write-Host` may describe the result of a call whose status was never read. Writing
`2>$null`, `-ErrorAction SilentlyContinue` or `catch { }` is a promise that nothing downstream
will make a claim about that call.

**R2 — Empty is not an outcome.** `if (-not $x)` may not select a message when `$x` can be
empty for more than one reason. After fzf, empty means Escape *or* no-match *or* fzf never ran.
After a `SilentlyContinue` enumeration, empty means "nothing there" *or* "could not read".

**R3 — Reasons travel upward.** A helper whose `$false` / `$null` / `''` / `@()` has more than
one cause returns an envelope carrying the cause. The house shape already exists:
`New-PmxCancelledResult` (`components/proxmox/shared.ps1:402-409`) with `Success` / `Cancelled`
/ `Error`. If the cause cannot be carried, the message may not name one.

**R4 — "Could not look" is never "nothing there."** A failed query may not be rendered as an
empty list, a `0`, an `n/a`, or a statement about the user's machine. Where an adapter provides
a sentinel for exactly this — `Get-ContainerStoreCount` returns `-1`,
`platform/windows/adapters/container.ps1:468-470`, *"so the caller can distinguish 'nothing
here' from 'could not look', and say so"* — the caller must test for it.

**R5 — Claim only what was verified.** `✅` prints only after a re-read: exit code 0, the file
exists, the destination content matches, the install location is gone. And only downstream of
a save that *returns* a status.

**R6 — A decision is not a failure, and nobody-asked is not a decision.** Escape, `n`, a
declined overwrite, taking the `[y/N]` default: `↩ Cancelled.` dim. A redirected stdin or a
missing fzf is **not** a cancellation — `components/proxmox/shared.ps1:389-391`: *"Nobody was
asked, so nobody declined — and reporting it as one would tell a script author their pipeline
was cancelled by a user who is not there."*

**R7 — Echo the input the message is about.** If the token is in scope, print it. Never a
literal stand-in like `nothing chosen` (`roots.ps1:951`), and never a suggestion identical to
the thing just rejected (`flags.ps1:356` + `:358`).

**R8 — One reporter per domain, not one per call site.** `components/proxmox/shared.ps1:377-378`
gives the reason in advance: *"Fixed here rather than at each call site because there are nine
of those, and a convention enforced in nine places is a convention that will drift in one of
them."* That prediction has already come true: `↩ Cancelled.` exists as a literal string in
three files, two of which are copies rather than calls, while the red-cross cancellation it
replaced survives in sixteen.

### 2.3 Where the convention comes from

Ranked by authority, all read for this audit:

1. **`components/proxmox/shared.ps1:359-464`** — the finished article. It enumerates five
   outcomes and refuses to flatten them, then implements the split as three mechanisms:
   `Test-PmxCanPick` (`:393`) as one predicate for whether a picker may open at all,
   `New-PmxCancelledResult` (`:402`) as an envelope carrying `Cancelled` as a *field* rather
   than as an empty string, and `Write-PmxResolveFailure` (`:415`) as the single renderer —
   dim for a decision, red for a fault.
2. **`components/navigation/nav.ps1:373-413`** — the same rule at a call site, with the
   mechanics written in the comment: the exit-code table, the capture on the next line
   *because `$LASTEXITCODE` is clobbered by any later command*, then three branches.
3. **`components/containers/containers.ps1`** — the reference for the read side, where no exit
   code is involved. `:286-288` (*"Unreachable is not empty. Saying 0 here is a confident wrong
   answer about someone's data"*), `:918-931` (zero rows triggers a re-probe of engine health
   before any claim is made, *"it reads as a fact about the host"*), `:949` (the correct
   rendering of a missing fzf: an install hint, not a claim about the terminal).
4. **`docs/plan/ethos/ETHOS.md:108-124`** — the severity rule. `pwsh-font --status` installed a
   font because an unbindable token vanished and the command ran its default action. The
   conclusion generalises: *"A command must never do something other than what its arguments
   asked for. Refusing costs a retype; guessing cost a font install nobody requested."*

---

## 3. Findings

**Class:** `A` conflation (two outcomes, one branch, a discarded signal) · `B` misleading text
(names something that did not happen) · `C` wrong marker.

**Evidence:** `probed` = independently reproduced by execution against the real code or the
real binary · `read` = the cited lines were read in this session · `digest` = carried from the
candidate list and **not** re-read here. Treat `digest` rows as unverified leads.

### 3.1 Navigation — `components/navigation/`

| # | file:line | prints | what actually happened | class | sev | evidence |
|---|---|---|---|---|---|---|
| 1 | `roots.ps1:932` | `No drive besides the system one — naming what you have is still worth doing.` | Reached for **four** machine states: genuinely one volume; `Get-PFStorageCandidate` threw and was swallowed (`:818` `catch { }`); a real second volume whose *root* is not writable (`:829`); and a second volume that is writable but holds only `$*` / `System Volume Information` (`:833`) — i.e. a freshly formatted data drive. `nav setup` exists to find the second drive. | A+B | high | probed |
| 2 | `roots.ps1:139` | `❌ Not a search root: $Path` | Four conditions: never configured; configured but the directory is gone (filtered out at `:72` before the remover sees it); configured live but spelled relatively (`Add` resolves at `:106`, `Remove` compares raw at `:135`); and every saved root dead, so `Get-NavSearchRoots` returned platform defaults (`:73`→`:78`). Worse: any *successful* removal writes back `$kept`, derived from the filtered list, **silently deleting the dead entries the user was just told did not exist**. | A+B | high | probed |
| 3 | `roots.ps1:161` | `🧭 nav search roots  (configured)` | `$isDefault` is file-existence only (`:157`), but `Get-NavSearchRoots` returns platform **defaults** when every saved root fails `Test-Path`. A user whose `D:\Projects` is unmounted sees "(configured)" over the fallback list, with green ticks, and their real root nowhere on screen. The per-root `❌` at `:166` can never fire for a saved root — dead ones were filtered upstream. | B | medium | read |
| 4 | `roots.ps1:946` | `↩ Cancelled.` | The seed defect's untouched twin. `Select-PFCodeRoot` returns `''` for Escape, for an fzf that failed to launch, **and** for an Enter whose row could not be mapped back (`[array]::IndexOf` → `-1`, `:886-888`). In the third case the user made a choice and is told they cancelled. `$LASTEXITCODE` after `:881` is never captured — contrast `nav.ps1:386`. | A | medium | read |
| 5 | `roots.ps1:634` | `❌ No anchor called '-$key'.` | Three conditions: never created; stored but its directory is gone (`:449`); or `.nav_anchors.json` is unreadable (`:458` `catch { return [ordered]@{} }`, which makes *every* anchor report as nonexistent). In two of the three the config holds an entry the command denies is there, with no way to delete it. | A | medium | digest |
| 6 | `nav.ps1:97` | `❌ Unknown starting point '$token'.` | `Resolve-PFRootAlias` returns `''` both for a token that was never a root and for one that is saved but currently unresolvable. `nav -pro foo` after unplugging the drive reads as "your config was never saved" when the truth is "the directory is gone". | A | medium | digest |
| 7 | `roots.ps1:666` | `You have not added any yet.` | Printed whenever `$user.Count` is 0, which includes an unreadable anchors file and a file whose anchors all point at missing directories. It states a fact about the user's history that their own config contradicts — and nothing anywhere reports the parse failure, unlike `Get-NavSearchRoots` (`:75` `Write-Warning`). | B | medium | digest |
| 8 | `roots.ps1:951` | `❌ Not a directory: nothing chosen` | On the picker route `$Path` is empty, so it renders the literal `nothing chosen` — but this line is reached precisely when the user **did** choose: the numbered-list branch returns whatever path they typed (`:901`). `$chosen` holds that text and is in scope one line up. | B | medium | read |
| 9 | `nav.ps1:405` | `❌ Nothing matching '$query' in: $rootLabel` | Residual of the fix. `$fzfExit` is captured (`:386`) but compared only against `130` (`:399`); fzf's `2` (bad option — an fzf older than 0.27 rejects `--header-first`, `:370`) falls into the no-match branch. That user is told their directory does not exist when the picker never ran. | A | medium | read |
| 10 | `roots.ps1:882` | `…Enter chooses · Esc to type a path instead` | Escape does not let you type a path. In the fzf branch it produces empty output → `''` (`:883`) → `↩ Cancelled.` (`:946`) → `nav setup` ends. The "type a path" fallback exists only in the *non*-fzf branch, whose prompt is `Number, or a path` (`:896`). The header describes the other branch. | B | medium | read |
| 11 | `bookmarks.ps1:45` | `📚 Initialized $($defaultBookmarks.Count) default bookmarks` | Printed unconditionally after an unchecked `Set-Content` (`:44`). If the write fails, the file still does not exist, so `Initialize-DefaultBookmarks` runs again on the next call (it is invoked from `nav.ps1:79` and from `Get-Bookmarks`, `:49`) — the banner prints on *every* command while nothing is saved. `Save-Bookmarks` (`:62-76`) shows the correct shape: catch, print `$_.Exception.Message`, return `$false`. | B | medium | read |
| 12 | `bookmarks.ps1:130` | `❌ Deletion cancelled` | The user answered anything but `y`/`Y` at `Confirm (y/n)` (`:122`). A decision, rendered with the error cross in **Yellow** — neither convention. It also fires with no prompt at all on a redirected stdin, where `Read-Host` returns `''`; there is no `[Console]::IsInputRedirected` guard as at `roots.ps1:913`. | C | medium | read |
| 13 | `roots.ps1:121` | `✅ Search root added: $full` | `Save-NavSearchRoots` (`:81-91`) has no try/catch and returns nothing; its `Set-Content` failing is non-terminating, so the claim prints regardless — and `Show-NavSearchRoots` on the next line re-reads the unchanged file, so the user is told it worked and shown proof that it did not. Same unconditional claim at `:145` (removed) and `:151` (reset, after an unchecked `Remove-Item`). Contrast `Save-Bookmarks`/`Save-PFUserAnchorTable`, which return a status their callers gate on. | B | medium | read |

### 3.2 Files — `components/files/`

| # | file:line | prints | what actually happened | class | sev | evidence |
|---|---|---|---|---|---|---|
| 14 | `clipboard.ps1:165` | `✅ Pasted: notes.txt` + `📍 Location:` + `📊 Size: 0.03 KB` | **The copy failed and nothing was pasted.** `Copy-Item` at `:162` carries no `-ErrorAction Stop`, so the failure is non-terminating, the `catch` at `:169` never runs, and neither `$?` nor `-ErrorVariable` is tested. Reproduced against a destination held open with `FileShare.None`: `$?` was `False`, the destination kept its original content, the green banner printed. The `📊 Size` line stats the **pre-existing destination**, so the false success even looks corroborated. | A+B+C | high | probed |
| 15 | `operations.ps1:717` | `╭─ ✅ MOVE COMPLETED ─…╮` | **The move failed and the file never left its source directory.** `Move-Item` at `:713` lacks `-ErrorAction Stop` (contrast `:345` in the same file, which has it), so `catch` at `:729` never fires. Reproduced: source still present afterwards, banner printed anyway. Worse — `:727` then sets `$script:MoveInHand = $null`, so the hold is dropped, and the recovery line at `:738` (*"The file is still held. Try mv-t again"*) is unreachable for exactly the failures it was written for. | A+B+C | high | probed |
| 16 | `rename.ps1:192` | `╭─ ✅ RENAME COMPLETED ─…╮` | **No rename occurred.** `Rename-Item` cannot overwrite an existing target, so the entire `Overwrite existing file? (y/n)` path at `:177-184` fails **100% of the time**: answering `y` reaches `:188`, `Rename-Item` errors non-terminating, and the green banner prints naming an old and new name that were never swapped. Verified end to end. Not an edge case — it is the whole approved-overwrite flow. | A+B+C | high | probed |
| 17 | `clipboard.ps1:55` guard | (falls through to the `✅ Pasted` banner) | The guard `-not $clipboardContent.StartsWith('FILE:')` fails open for a **multi-line** clipboard: `Get-Clipboard` returns `string[]`, member enumeration makes `StartsWith` yield `@($false,$false)`, and `-not` on a multi-element array is `$false`. Single-line non-file text is handled correctly, so the same user mistake reports opposite outcomes depending only on line count. **The downstream path to the banner was not traced** — see the note in §5. | A | medium | probed (guard only) |
| 18 | `operations.ps1:684` | `❌ Source file no longer exists: build[1].log` | The file exists and is untouched. `Test-Path $sourceFile` at `:683` is wildcard-interpreting, so any held file whose name contains `[ ] * ?` tests as absent. `:686` then clears `$script:MoveInHand`, discarding the hold on the strength of the false report. `del` in the same file handles this deliberately at `:173-177` with `-LiteralPath`. | B | medium | read |
| 19 | `rename.ps1:63` | `❌ No file selected` | Three outcomes: Escape (a decision, red cross in Yellow); fzf found no match; fzf is not installed at all — a missing command in a pipeline does not abort the function, so a user without fzf is told they made no selection. `del` guards that case explicitly (`operations.ps1:187`); `rn` does not. | A+C | medium | digest |
| 20 | `operations.ps1:706` | `❌ Move operation cancelled` | Only the *overwrite* was declined — the cut is still held (`$script:MoveInHand` untouched, returns at `:707`). `mv-c` at `:759` prints the same six words with the opposite marker and the opposite state: `✅ Move operation cancelled` in **Green**, after `$script:MoveInHand = $null`. One sentence, two contradictory states, two contradictory markers, same file. | B+C | medium | read |
| 21 | `operations.ps1:536` | `❌ Invalid selection` | Pressing Enter at the cut picker — the ordinary way to back out — produces a red error identical to typing garbage. `:522` one line above treats `q` as a clean silent exit, so the two natural ways to cancel get opposite treatment. Repeats at `:587`, `:641`, `rename.ps1:104`. | A | medium | digest |
| 22 | `listing.ps1:72` | `  (empty)` | A directory whose enumeration failed — permission denied being the ordinary cause — is reported as empty. `Get-ChildItem … -ErrorAction SilentlyContinue` at `:69` suppresses the ErrorRecord; only `-not $items.Count` is tested at `:71`. The same function proves the distinction was understood: `:107` says `(no readable entries)`. Linux-only path. | A | medium | read |
| 23 | `windows-only/coreutils.ps1:259` | `❌ Cancelled.` | The user declined `Delete it and everything in it? [y/N]` — the safe decision — rendered with the red cross in Yellow. | C | low | digest |
| 24 | `operations.ps1:241` | `❌ Deletion cancelled.` | The user declined the delete confirmation. Red cross in Yellow. The same file gets it right two branches earlier: `:197` prints `ℹ️ No selection made. Nothing deleted.` in DarkGray. | C | low | digest |
| 25 | `rename.ps1:181` | `❌ Rename cancelled` | Declining `Overwrite existing file? (y/n)` — the decision that protected an existing file. | C | low | digest |
| 26 | `rename.ps1:166` | `❌ Rename cancelled - no filename provided` | Text accurate for all three causes (Escape, empty query, no fzf), but the outcome is a cancellation wearing a red cross in Yellow. `$LASTEXITCODE` from `:141-153` is never read. | C | low | digest |
| 27 | `operations.ps1:338` | `❌ Skipped: <target>` | The user declined one overwrite in a multi-file move; the loop continues normally. The adjacent `-n/--no-clobber` skip at `:331` renders the same outcome quietly in DarkGray. | C | low | digest |

### 3.3 Git — `components/git/`

| # | file:line | prints | what actually happened | class | sev | evidence |
|---|---|---|---|---|---|---|
| 28 | `rollback.ps1:48` | `✅ Rollback branch operations completed!` | On the clean-tree path `git-rba` runs `git push origin $currentBranch` (`:36`) and then unconditionally prints success plus a PR link. Reproduced offline against a rejected non-fast-forward push: `$LASTEXITCODE` was `1` at the point it could have been read, remote SHA unchanged, `✅ … completed!` and the PR URL printed. The same function checks `$LASTEXITCODE` correctly for the push at `:145`. | A+B+C | high | probed |
| 29 | `release.ps1:442` | `❌ Description too short — release cancelled` | **REFUTED IN ITS LOAD-BEARING PART.** The claim was that Escape after typing 3+ characters is indistinguishable from Enter and ships a real release. Probed against fzf 0.74.3: abort prints **nothing at all** (exit 130, zero lines), so `$fzfOut` is empty, `$description` is `''`, and the function returns at `:443` before any version bump, commit, tag or push. **What survives:** Escape (whatever was typed) and Enter-with-a-2-char-description collapse into one line, so a user who typed a full description and changed their mind is told it was "too short"; and the marker is a red cross in Yellow on a decision. Severity drops from high to medium. | A+B+C | medium (was high) | probed |
| 30 | `commit.ps1:141` | `❌ Commit message too short or cancelled` | Two outcomes: Escape (nothing was too short) and Enter with a 1-2 char message (nothing was cancelled). **The claimed "commits silently on Escape" mirror case is false** — abort prints nothing, `$userMessage` stays `''` from `:131`, `:140` fires. The real cost: type a 20-character message, press Escape, and be told it failed a length check it never went near. The discriminator is `$LASTEXITCODE` (first read at `:150`, *after* `git add .` has clobbered it) and the emptiness of `$fzfOutput` already tested at `:132`. | A+B+C | high | probed |
| 31 | `rollback.ps1:123` | `❌ Commit message too short or cancelled` | **REFUTED IN ITS LOAD-BEARING PART**, same mechanism as #30: nothing is staged, committed or pushed on Escape. The conflation at `:123` is real (abort / empty query / genuinely short), and the red cross on a decision is real. `"too short or cancelled"` is an explicit disjunction — ambiguous, not false — so this is materially weaker than the nav case. **Trap for any fix:** exit `1` is the *normal* success path here, because the message arrives via `--print-query` and matches no list line. The discriminator must be `-eq 130`, as `nav.ps1:399` does. | A+C | medium (was high) | probed |
| 32 | `interactive.ps1:200` | `📤 Popped stash: $stashRef` | `git stash pop` exits non-zero on a conflicting apply and deliberately **does not drop the stash**. Reproduced: exit 1, `CONFLICT (content)`, stash still in `git stash list`, conflict markers in the file, green success line printed. Two further non-zero paths land here too — a dirty tree (`Aborting`, nothing applied) and a stale ref (`fatal: log for 'stash' only has 1 entries`, exit 128). Four outcomes, one green line. The same file tests `$LASTEXITCODE` for cherry-pick at `:56`. | A+B+C | high | probed |
| 33 | `interactive.ps1:268` | `📤 Pushed to: $remoteName` | `git push $remoteName $branch` at `:267` followed by an unconditional green line. A rejected push, missing upstream, auth failure or no network all end with the terminal's last word being `📤 Pushed to: origin` in green. | A+B+C | high | read |
| 34 | `interactive.ps1:49` | `✅ Created and switched to branch: $branchName` | `git checkout -b` at `:48` followed by an unconditional success line. An existing name, an invalid name, or a checkout blocked by local changes all report a switch that never happened — and the user keeps working believing HEAD moved. | A+B+C | high | read |
| 35 | `branches.ps1:352` | `🔄 Switched to branch: $selected` | `git switch $selected` at `:351` followed by an unconditional cyan line. Same pattern at `:369`, `:375`, `:379`. | A+B+C | high | digest |
| 36 | `branches.ps1:262` | `🔄 Switched to main branch` | `git-cm` is `git checkout main` then the line, unconditionally. In a `master`-default repo checkout fails and the user is still told they are on main — then commits believing it. **`git-branch` in the same file already resolves main-vs-master at `:23-27`**, and `git-cm`'s own `pwsh-h` synopsis claims it handles both. | A+B+C | high | read |
| 37 | `reset.ps1:38` | `✅ Reinstall complete.` | `npm install` at `:37` followed by an unconditional green line — after `git-next` has already deleted `.next`, `node_modules` and the lockfile at `:30`. A failed install still reports a completed destructive-then-restore cycle when only the destructive half ran. `git-next` never checks it is in a Node project. | A+B+C | high | read |
| 38 | `reset.ps1:33` | `⚠️ Some files may be locked or in use. Try closing editors and rerunning.` | `Remove-Item -Recurse -Force .next,node_modules,package-lock.json -ErrorAction Stop` (`:30`) throws `ItemNotFoundException` when **any** of the three is absent — running twice, running before a first build, or a yarn/pnpm project. `-Force` does not suppress not-found. Every failure is reported as a file lock, and the caught `$_` is never inspected or printed. | A+B | medium | read |
| 39 | `reset.ps1:18` | `✅ Repository cleaned and updated` | One success line covers three commands: `reset --hard` (`:15`), `clean -fdx` (`:16`), `fetch --all --prune` (`:17`). Offline, the fetch fails and the user is still told the repo was "updated". None of the three exit codes is tested. | A+B | medium | read |
| 40 | `release.ps1:459` | `Nothing has been committed, tagged or pushed.` | Literally true about commit/tag/push, but `Update-ProjectVersion` (`:454`) has already rewritten the version files that *did* verify. The user is told the release aborted cleanly and is left with a partially bumped tree — the drift `version-files.ps1` exists to prevent. `$written` is used only for `.Count` and never reported. | B | medium | digest |
| 41 | `version-files.ps1:272` | `❌ $($s.Label) — could not update` | `Set-ProjectVersion` writes at `:241` and verifies at `:244-249`, so `$false` means "written, but the read-back did not match" — reported as "could not update". For `plain` VERSION files `:212` has already replaced the whole file. | A | medium | digest |
| 42 | `commit.ps1:189` | `❌ Cannot push without a remote repository` | `Create-RemoteRepository` returns a bare `$false` from eight places in `remote.ps1` — including the user deliberately choosing *"No — Keep this as a local-only repository"* (`remote.ps1:46`), who has already been told `📁 Keeping as local repository` and now gets a red `❌` for doing exactly what they asked. | A | medium | digest |
| 43 | `commit.ps1:209` | `❌ git push failed` | After reporting failure, `:212` runs `git push` **again** purely to string-match its error text. That second push can succeed, in which case the commit is on the remote while the terminal says it failed and (`:229`) advises resolving conflicts. Its exit status is thrown away; only the output text is matched. | A+B | medium | digest |
| 49 | `rollback.ps1:268` | `❌ Failed to create rollback branch` | Reached *after* `:241` has already force-deleted the user's existing rollback branch, which the message never mentions; the hint blames the commit hash while the common causes are a blocked checkout or an invalid name. Separately, the guard at `:188` is unreachable for a typo — `git rev-parse zzzz` echoes the argument and exits 128, so `$fullHash` is truthy and `:197-198` throws a raw null-reference instead. | A+B | medium | digest |
| 50 | `reset.ps1:20` | `❌ Cancelled.` | The user declined `Flush all changes and clean repo? (y/n)` — red cross in **DarkGray**, character-for-character the seed defect's marker. Repeated verbatim at `:40`. | C | low | read |
| 52 | `release.ps1:350` | `❌ Release cancelled` | Escaping the bump-type picker, marked `❌` in Yellow. This exact string is called out as *"a lie twice over"* by this file's own comment at `:258-260` for the neighbouring case. | C | low | digest |
| 53 | `remote.ps1:89` | `❌ Repository creation cancelled` | Escaping the naming-convention picker. Repeated at `:127`, `:164`, and joined by `❌ No custom name provided` at `:123`. | C | low | digest |
| 54 | `rollback.ps1:222` | `❌ Rollback cancelled` | The confirmation prompt doing its job. Repeated at `:234`. | C | low | digest |
| 55 | `branches.ps1:354` | `❌ No branch change needed` | The user picked the branch they are already on — a deliberate no-op — marked `❌` in DarkGray. | C | low | digest |
| 56 | `branches.ps1:281` | `❌ Could not delete branch: $branchName (not fully merged?)` | Every non-zero exit from `git branch -d` gets a guessed cause and a pointer to the **destructive** `git-bd-force` (`:282`), which cannot help if the branch does not exist or the name is ambiguous. git's own stderr is discarded. | A | low | digest |

### 3.4 GitHub — `components/github/browser.ps1`

| # | file:line | prints | what actually happened | class | sev | evidence |
|---|---|---|---|---|---|---|
| 44 | `:374` | `ℹ️ No saved token found in Credential Manager` | Every non-zero exit from `cmdkey /delete:` is read as "nothing was there". cmdkey also exits non-zero for access-denied and target errors, so a token that is still stored is reported as absent — the user believes they revoked a credential they did not. `$result` (`:370`) is captured and never used. | A | medium | digest |
| 45 | `:391` | `ℹ️ No GitHub token saved` | The catch reports a fixed negative for any exception — cmdkey missing, a hung credential provider, a policy block. A failure to *ask* the store is reported as a definitive answer *from* the store. | A | medium | digest |
| 46 | `:134` | `❌ GitHub Personal Access Token required for private repos` | `_GhL-GetToken` returns `$null` from four conditions including `catch { return $null }` at `:89-91`. A user whose token is saved but temporarily unreadable is sent to mint a second one. | A | medium | digest |
| 47 | `:105` | `📊24h: 0  📈1w: 0` | `_GhL-CommitCount` returns `0` from its catch, so a rate-limited or failed query is displayed as a truthful zero. Two API calls per repo for up to 100 repos reliably trips the secondary rate limit; the user then prioritises repos from a column that silently means "the query failed". | A | medium | digest |
| 48 | `:329` | `❌ Repository not found. It may have already been deleted.` | Classified by regex on the exception text. GitHub returns **404** for a repo a token cannot see, so "you lack permission" is reported as "it may already be deleted" — after three capitalised confirmations, for a repo that is intact. `StatusCode` and `ErrorDetails.Message` are available and unread. | B | medium | digest |
| 51 | `:302` | `❌ Repository name mismatch. Deletion cancelled.` | The three-stage deletion guard working as designed, marked `❌` rendered in **Green** — glyph and colour disagree with each other and both with the convention. Repeated at `:309`, `:317`. | C | low | digest |

### 3.5 Containers — `components/containers/containers.ps1`

| # | file:line | prints | what actually happened | class | sev | evidence |
|---|---|---|---|---|---|---|
| 57 | `:1034` | `[X] Name a container: this is not an interactive terminal, so no picker can open.` | `Test-PFContainerCanPick` (`:861-864`) returns `$false` for **two** independent conditions and the message names one: `[Console]::IsOutputRedirected` (`:862`) *and* fzf simply not being installed (`:863`). A user in an ordinary terminal without fzf is told a false fact about their session. The correct sentence exists 85 lines earlier at `:949`: `Install fzf to act on these from here: $(Get-DependencyInstallHint 'fzf')`. The function's own docstring (`:856-859`) says both halves matter. | A+B | high | read |
| 58 | `:1057` | same string | The same collapse on the `inspect` / `show` path — distinct call site, different follow-up hint at `:1058`. | A+B | high | read |
| 59 | `:625` | `{}` | `dkr inspect <name> --json` renders a **failed** inspect as an empty JSON document with no marker and no failure status. `:625` is `Select-Object * -ExcludeProperty Supported, Native, Error`, and a failed `Get-ContainerInspectState` returns an object carrying *only* those three properties (`platform/windows/adapters/container.ps1:712-724`, e.g. `Error = "inspect failed: Error: No such object: sonarr"`). Excluding all three yields `{}`. This is the machine-readable path: it lies to `jq` as well as to a human. | A+C | high | read |
| 60 | `:980` | `[X] No compose project or service matching 'media'.` | `Resolve-ContainerComposeProject` returns `$null` both for "nothing matched" and for "a project matched but its `ConfigFile` is empty" (`:795` falls through to `:803`). In the second case `:986` then prints `Projects on this host: …` listing the very name the user was told does not match. | A | medium | digest |
| 61 | `:725` | `Either run with sudo, or join the docker group: sudo usermod -aG docker $USER…` | `Show-ContainerEngineProblem` branches on `$Engine.State` alone (`:712`) and prints Linux remediation for a Windows named-pipe ACL refusal. Windows has no sudo, no usermod and no docker group; the pipe ACL is granted to `docker-users` at install time. `$Engine.NeedsSudo` — hard-coded `$false` on Windows, `$true` on Linux only where a sudo retry actually worked — is in hand at `:710` and never consulted. | B | medium | digest |
| 62 | `:568` | `  inspect failed: Error: No such object: sonarr` | The total failure of `dkr inspect <name>` printed in **DarkGray**, the colour of the decorative rules two lines above, with no marker, under a Cyan `📦 CONTAINER` header. Dim is right in this function's *other* role (a `-Footer` appended after a log view, where the caller already guards on `$state.Supported`); the `-Footer` switch is in the param block at `:560` and used for layout at `:562/:571/:588/:593` but not for severity at `:568`. | C | medium | read |
| 63 | `:382` | (silence, and the flat claim at `:931` `No containers in the active podman store.`) | `Show-ContainerStoreHint` takes `$count = Get-ContainerStoreCount` (`:381`) and filters `if ($count -gt 0)` (`:382`), so the adapter's **-1 sentinel for an unreadable store** fails the test exactly as a genuine 0 does. "every other store is empty" and "another store could not be checked" produce byte-identical output. The adapter's docstring says the sentinel exists *"so the caller can distinguish 'nothing here' from 'could not look', and say so"* (`platform/windows/adapters/container.ps1:468-470`) — and the comments at `:918-931` exist to prevent precisely this class of confident wrong answer. | A | medium | read |
| 64 | `:293` | `n/a` | `n/a` is documented to mean "a resource this engine lacks", but `:227-228` pre-filters the only inapplicable pair (pods-on-docker), so every column rendered *is* applicable. A `$null` here can therefore only mean the resource query **failed**, on a store already established as reachable at `:285`. The user reads "not applicable"; the truth is "we asked and the call errored". `:288` in the same function refuses to make that trade for the store as a whole. | B | medium | read |

### 3.6 Proxmox — `components/proxmox/`

| # | file:line | prints | what actually happened | class | sev | evidence |
|---|---|---|---|---|---|---|
| 65 | `connection-state.ps1:45` | `🟡 Not connected to Proxmox server 'proxmox'.` + `Sign in first: srv proxmox` | Every session failure on an ssh transport carrying **any** non-empty `FailureKind` prints this one screen: `authentication-required`, `host-key`, `unreachable`, and the catch-all `connection-failed` returned for any non-zero remote exit — which includes a login that *succeeded* but where `pvesh` is missing or the account lacks permission. For a host-key mismatch (`REMOTE HOST IDENTIFICATION HAS CHANGED`) the printed advice is the opposite of the fix. `ConvertTo-PmxSessionFailure` receives the adapter's specific text as `-ErrorMessage` and discards it on that branch (`:18-25`); `FailureKind` reaches `:42` and is used only as a boolean gate. | A+B | high | read |
| 66 | `vm-change.ps1:95` | `❌ Proxmox rejected the change: The saved Proxmox server is unreachable over SSH.` | `Invoke-ProxmoxManagementChange` returns `Success=$false` for a genuine refusal **and** for pure transport failures, all prefixed "Proxmox rejected the change". If the channel dies after dispatch the mutation may have been applied, yet the line asserts a rejection while the envelope at `:98` sets `Executed = $true` and the audit record at `:96-97` stores `failed`. `$result.FailureKind`, `.ExitCode` and `.Diagnostics` are on the object and unread. | A+B | high | read |
| 67 | `vm-change.ps1:75` | `⛔ Cancelled — no Proxmox state was changed.` | `Confirm-PmxAmberPlan` returns a bare `$false` both for a declined prompt and for a non-interactive session where **nobody was asked** — which also prints `❌ Refused: this change requires an interactive terminal.` (`shared.ps1:322`). A CI run therefore gets both lines, contradicting each other, and the audit record stores `cancelled` with the message `confirmation declined or unavailable` — the code admitting it cannot tell. `shared.ps1:389-391` states the rule this breaks. | A | medium | read |
| 68 | `vm-read.ps1:80` | `↩ Cancelled.` | The VM picker tests only `-not $picked` after the fzf pipeline at `:77-79`. Empty means Escape *or* fzf failing outright, so an fzf error is rendered to the user as their own cancellation. `$LASTEXITCODE` is available on the very next line and never read. | A | medium | digest |
| 69 | `physical-disks.ps1:37` | `↩ Cancelled.` | Same shape for the physical-disk picker (`:36`). `pmx disk` ends with a cancellation the user never made when fzf could not start. | A | medium | digest |
| 70 | `vm-change.ps1:379` | `❌ ` (a bare red cross, no text) | The only `Resolve-PmxManagedVm` call site that renders the envelope by hand instead of via `Write-PmxResolveFailure`. It tests only `.Success`, so a cancellation — whose `Error` is `''` by construction (`shared.ps1:404`) — prints an empty red cross. `.Cancelled` is on the object; the sibling renderer exists and is used at `:555`, `:601`, `:654`. | C | medium | digest |
| 71 | `vm-change.ps1:386` | `❌ Could not obtain the next VMID: ` | The guard is `-not $next.Success -or -not (Test-PmxVmId $next.Data)`. When the query **succeeded** but returned an invalid VMID, `$next.Error` is `''`, so the sentence ends in a colon and blames the transport for a payload problem. `vm-read.ps1:257-259` handles the identical pair correctly. | A+B | medium | digest |
| 72 | `vm-change.ps1:672` | `⚠️ Proxmox accepted the change, but verification failed: VM did not reach 'running'` | The verify block returns this when `-not $fresh.Success` **or** the status differs. A failed re-read establishes nothing about power state, yet the line asserts the VM did not start. The sibling verifiers hedge correctly (`:582` *"desired core count was not returned"*), so the file already knows the careful wording. | B | medium | read |
| 73 | `network-view.ps1:170` | `No addresses match the selected filters.` | `Show-PmxNetworkAddressTable` applies **no filters at all**. The line fires whenever the count is zero, which includes: the VM is stopped, no agent channel, the agent did not respond. `pmx vm ip <stopped-vm>` blames filters the user never typed. | B | medium | digest |
| 74 | `clone-plan.ps1:37` | `❌ source storage 'local-zfs' is not active for VM images` | Reached by `if (-not $row)` — the storage name was **absent** from the node's storage list — not by any inactivity test. The genuinely-inactive case is the *next* branch (`:39-41`). The operator is sent to enable something that is already enabled. | B | medium | digest |
| 75 | `disk-grow.ps1:55` | `❌ storage 'local-lvm' is not active for VM images` | Three conditions in one expression at `:54`: not found at all, `enabled -ne 1`, `active -ne 1`. The fix differs for each (wrong node / re-enable / bring online). | A | medium | digest |
| 76 | `host.ps1:34` | `No ZFS pools present.` | `Get-ProxmoxZfsPools` returns `@()` for four conditions: no pools; the pvesh query failed; `zpool` absent; `zpool list` exited non-zero (permission denied for a non-root caller). Only the first justifies the assertion. The adjacent branch at `:25` words the same situation honestly: *"No Proxmox storage data returned."* | B | medium | digest |
| 77 | `host.ps1:209` | `❌ Discovery failed: The Proxmox SSH command did not complete.` | The loop at `:208` walks four independent queries (version, storage-list, bridge-list, next-id) and reports the first failure without naming which. Over SSH all four render identically, so the user cannot tell "no bridges endpoint" from "no storage rights" from "broken connection". | A | medium | digest |
| 78 | `network-read.ps1:478` | `not-tested` | One label for three things: `--no-probe` was passed (`:446`), the reachability helper was unavailable so `$reach` became `@{}` (`:466-468`), or the helper returned an unrecognised value. Nothing is added to `$Warnings` in the second case. | A | low | digest |
| 79 | `physical-disks.ps1:71` | `No physical disks found.` | Printed under a `💾 PHYSICAL DISKS — 0` header whenever `Get-ProxmoxDisks` returns `@()` — which includes `lsblk` missing and `lsblk` JSON failing to parse. A tool failure reported as a statement about the hardware. `Resolve-PmxDisk` in the same file words it carefully at `:21`. | B | low | digest |

### 3.7 Network and system — `components/network/`, `components/system/`

| # | file:line | prints | what actually happened | class | sev | evidence |
|---|---|---|---|---|---|---|
| 80 | `network/servers.ps1:179` | `❌ Could not connect to '$Name'.` + `Check its status with: srv list` | `ssh` returns the exit status of the **remote shell**, so a completed hour-long session whose last remote command exited non-zero comes back non-zero. The adapter turns any non-zero code into `FailureKind='connection-failed'` (`platform/windows/adapters/ssh-session.ps1:102`), and the `default` branch then says the connection failed. The same branch also swallows `launch-failed` and `not-run`. SSH reserves 255 for its own failures precisely so a caller can tell "never connected" from "remote command exited non-zero"; `ExitCode` is populated at adapter `:103` and never read. | A+B | high | read |
| 81 | `system/team-room.ps1:228` | `Nothing to stop — it was already inert.` | **An off-switch reporting success for a room it did not switch off.** `$did` records only successes (`:212`, `:217`, `:224`). If `Set-TeamRoomArm` returns `$false` the code prints `⚠️ could not remove the arm stamp` at `:213` and then, four lines later, declares the room already inert — while it is still armed and can still wake an agent. Two contradictory lines, and the reassuring one is last. `:224` is the same fault silent: no `else`, so a failed connector-disable produces no output at all. | A+B | high | read |
| 82 | `system/apps.ps1:521` | `✅ Uninstalled '$($App.Name)' — reclaimed ~<size>` | For any non-scoop app the adapter runs the vendor uninstaller with `Start-Process … -Wait` and unconditionally `return $true` (`platform/windows/adapters/apps.ps1:236-239`) — no `-PassThru`, no exit code, no re-check of the install location. Open the wizard, click Cancel, and be told the app was uninstalled and a size reclaimed. The scoop branch two cases up verifies properly (`:217`). The natural next move is option 4, which the component itself warns leaves the registry and PATH shims behind (`apps.ps1:532`). | A+B+C | high | read |
| 83 | `system/storage.ps1:440` | `Nothing known is still parked there.` | `:432` is `try { $stragglers = @(Get-StorageStraggler) } catch { }`. Any enumeration failure leaves `$stragglers` empty, rendered in **Green** as a clean bill of health. "the check found nothing" and "the check did not run" produce the identical reassuring line. | A | medium | digest |
| 84 | `system/team-room.ps1:296` | `❌ No team room called '$Name'.` | Reached whenever `$hits.Count -ne 1`, so it also fires when **two or more** rooms match — telling the user no such room exists while several do. The start/stop path 13 lines above splits exactly this test into two messages (`:283-285`). | A | medium | digest |
| 85 | `system/shutdown.ps1:29` | `❌ Failed to cancel shutdown (is one scheduled?)` | `shutdown.exe /a` returns **1116** for "no shutdown is in progress" — a deliberate no-op — and **5** for access denied. The adapter reduces both to a boolean (`platform/windows/adapters/power.ps1:22-23`), so a permissions refusal is reported as maybe-nothing-was-scheduled. Same at `:84` and `:60`. | A | medium | digest |
| 86 | `system/path.ps1:37` | `❌ Failed to add to $label PATH — please try again.` | `Add-PersistentPathEntry` returns `$false` both for "not elevated for System scope" (`platform/windows/adapters/env.ps1:33`) and for "the write happened and the read-back failed" (`:52`). *"Please try again"* is exactly wrong for the elevation case, where retrying unelevated fails identically every time — and contradicts the red line `Assert-Admin` already printed. | A+B | medium | digest |
| 87 | `network/server-privacy.ps1:73` | `❌ Authentication did not succeed; connection details remain hidden.` | The fall-through for every `FailureKind` that is not `client-missing` or `prompt-unavailable` — including `connection-failed` where ssh never reached the host. `srv <name> info` does not gate on reachability, so running it against an offline server reports an authentication failure for a login never attempted. `-State` is a mandatory parameter (`:53`) used only for display at `:87`. | A+B | medium | digest |
| 88 | `system/health.ps1:754` | `⚠️ could not close PID 1234 (exited before we got there)` | Two opposite outcomes append to the same `$failed` list: a process that had already exited on its own (`:748` — the user's goal is met) and a `Stop-Process` that genuinely threw (`:750`). If every target had already exited, `$killed` stays 0 and `:755` prints `❌ Nothing was closed.` in red — when nothing was *left* to close. | A | medium | digest |
| 89 | `system/apps.ps1:578` | `❌ Cancelled.` | The `default` arm of `switch (Read-Host "Choose")` catches the deliberate `q` **and** every unrecognised keystroke. Someone who fat-fingers a key next to `5` (PERMANENT DELETE) is told they cancelled, as though the shell understood and accepted a decision. Marker wrong twice over: `❌` in DarkGray. | A+C | medium | digest |
| 90 | `system/startup.ps1:101` | `❌ Cancelled` | Escape in the start-folder picker, `❌` in DarkGray — the identical construction to the seed defect. `:106` repeats it for an `--expect` key line with no selection row, which is not a cancellation at all. | C | medium | digest |
| 91 | `system/sysconfig.ps1:118` | `❌ Cancelled` | Escaping the settings picker, `❌` in DarkGray. Twice more in the same file at `:167` and `:198`. | C | medium | digest |
| 92 | `network/servers.ps1:413` | `ℹ️ No servers yet.` + `srv add proxmox you@192.168.1.50` | `Get-PFServers` returns an empty hashtable both when the file does not exist (`:32`) and when it exists but could not be parsed (`:38-41`). A corrupt or permission-denied `~/.powerflow-servers.json` presents as "no servers yet" **with an invitation whose first action runs `Save-PFServers` over the unreadable file**. The `Write-Warning` at `:39` interpolates the path but not `$_.Exception.Message`, so malformed JSON and access-denied read identically. | A+B | medium | read |
| 93 | `network/servers.ps1:285` | `❌ No server called ''.` | A bare `srv rm` with no argument reports a lookup failure against the empty string. The `rename` path two branches down splits this correctly (`:306-308`, `❌ Usage: srv rename <old> <new>`). | B | low | digest |
| 94 | `network/servers.ps1:294` | `❌ Kept.` | The user answered `n` to `Forget '<name>'? [y/N]` — the safe outcome and the prompt's own default — marked with the red cross. Again at `:264` and `:259`. | C | low | digest |
| 95 | `system/apps.ps1:541` | `❌ Cancelled.` | Declining `Continue? (y/n)` before a trash-delete, `❌` in Yellow. Same at `:518`. The family recurs at `health.ps1:737` and `:825`, `startup.ps1:161`, `sysconfig.ps1:139` and `:145`. | C | low | read (`:518`, `:541`) |
| 96 | `system/fonts.ps1:60` | `❌ $name is not installed.  Run:  pwsh-font` | `pwsh-font --status` is a read-only query and this is its successful negative answer, marked with the error cross in Yellow. The sibling gets it right for the identical shape: `system/login.ps1:54` renders "not enabled" as `⭕ PowerFlow does NOT start on login.` | C | low | digest |
| 97 | `system/storage.ps1:447` | a straggler row rendered in **Red** | `Get-StorageColour ([double]$s.SizeBytes / 1GB * 10)` passes one positional argument, so `$FreeBytes` defaults to 0 and the Red rule (`$UsedFraction -ge 0.90 -and $FreeBytes -lt 25GB`) is satisfied by every row over roughly 92 MB. The colour reserved for "a volume is about to run out" paints every row of a read-only inventory. | C | low | digest |

### 3.8 Shared, shell and core

| # | file:line | prints | what actually happened | class | sev | evidence |
|---|---|---|---|---|---|---|
| 98 | `shared/flags.ps1:356` | `❌ pwsh-h: unknown option '--topic (expects a value)'` + `did you mean --topic ?` | A **known, declared** flag typed with no value after it. `Resolve-PFFlagName` returned non-null at `:254`, proving the flag is known; `:279` then pushes `"$token (expects a value)"` into the same `$unknown` array the unresolvable branch uses at `:259`, and the renderer at `:356` labels the whole array "unknown option". The command tells the user an option that exists does not exist, then suggests the option it just rejected. This is the flag ethos eating itself: `ETHOS.md:108-124` holds this message up as the teaching mechanism. | A+B | medium | read |
| 99 | `shell/bash-compat.ps1:231` | `❌ fg: no such job` | Three conditions: no jobs at all; jobs exist but none is Running — a bare `fg` after a job Completed, when `jobs` (`:200`) will happily list it; or `fg <id>` naming a missing id. The `Where-Object { $_.State -eq 'Running' }` at `:229` drops the count and states of the jobs that do exist. | A | medium | digest |
| 100 | `shell/teach.ps1:190` | `❌ No such file or directory: <path>` | `Get-FileMode` returns `$null` for three reasons on Linux: the path does not exist, `stat` failed (commonly `Permission denied` on a non-searchable parent), or `stat` returned fewer than 8 fields. `2>/dev/null` at `platform/linux/adapters/perms.ps1:27` throws the reason away. The component picks the harshest of the three to name. | A | medium | digest |
| 101 | `shell/keys.ps1:212` | `3 chord(s) this PSReadLine build would not accept.` | `Source = 'unbound'` is set at `:121` purely because the chord is not listed as bound — it says nothing about why. The same state is reached when PowerFlow never attempted the binding (`:151`, `:155`). The `--educate` footer registered at `:244` defines `unbound` honestly as *"Nothing happens on this key. Nothing claimed it."* | B | medium | digest |
| 102 | `shell/keys.ps1:256` | `Rebound every editing chord to PowerFlow's mapping.` | Printed unconditionally in Green after `Set-PFEditingKeys -Force`, which can rebind nothing at all (returns early at `:151`/`:155`, skips chords silently at `:164`). In the PSReadLine-missing case the user is told every chord was rebound and then, two lines later, that PSReadLine is not loaded. | B | medium | digest |
| 103 | `core/recovery.ps1:164` | `✅ Dependencies removed` | On Windows, printed whatever scoop did. `Uninstall-Dependency` runs `scoop uninstall @Name 2>$null` and `return $true` unconditionally (`platform/windows/adapters/packages.ps1:162-163`); its only `$false` path is "no package manager", which `recovery.ps1:162` has already excluded one line earlier. **The honest branch at `:166` is unreachable on Windows.** No post-check with `Test-Dependency`, unlike `Install-Dependency` in the same adapter (`:154`) and unlike the Linux uninstall path. | A+B | high | read |
| 104 | `core/recovery.ps1:61` | `❌ starship — try: scoop install starship` | `Install-Dependency` returns `$false` immediately when there is **no package manager** (`packages.ps1:151`), without running anything. On a fresh box the user gets five red lines telling them to run a command that does not exist. The sibling routine handles it correctly (`dependencies.ps1:35-39`, `❌ No usable package manager — skipping dependency install.`). | A | medium | read |
| 105 | `core/dependencies.ps1:104` | `⚠️ Could not check for PowerShell updates (network/API limit)` | The catch at `:102` wraps the whole try opened at `:82`, so it blames the network for a `[Version]` cast failure on a preview tag (`:86`), a file write (`:99`), and **all of `Invoke-PowerShellUpdate` (`:91-97`)** — which is not a check at all but the interactive updater that can uninstall and reinstall PowerShell. A failure while *updating* is reported as a failure to *check*. | B | medium | digest |
| 106 | `core/recovery.ps1:131` | `❌ Uninstall cancelled` | The user declined `Are you sure you want to uninstall PowerFlow? (yes/n)` — red cross in Yellow. Secondary: `:130` tests `$confirm -ne 'yes'`, so the answer `y` — which the other two prompts in this very file accept at `:71` and `:161` — also lands here, telling a user who meant yes that they cancelled. | C | low | read |
| 107 | `core/recovery.ps1:107` | `❌ Invalid option` | The `default` arm of the recovery menu. Fires for a mistyped choice **and** for a bare Enter, which at an interactive menu is the ordinary way to back out. The explicit `q` arm at `:103` gets it right: `👋 Recovery menu closed` in DarkGray. | A+C | low | read |
| 108 | `shell/bash-compat.ps1:116` | `⚠️ source: nothing to import from ./thing` + `PowerShell cannot execute bash syntax…` | Honest for an empty or comments-only file, but the same branch is reached when the content could not be **read at all**: `Get-Content` at `:102` has no error handling, so a directory path (which passes `Test-Path` at `:90`) or an unreadable file produces a raw error and then an explanation about bash syntax that had nothing to do with it. | A+B | low | digest |
| 109 | `core/version.ps1:244` | `✅ Profile Loaded: False` | The `✅` is a literal in the format string, so the success marker prints regardless of the value beside it. The label is wrong too: `$profileExists` is `Test-Path $PROFILE` (`:239`), which measures existence, not loading — so a profile that exists but blew up on load reports `✅ Profile Loaded: True` in the one command whose job is install status. | C | low | digest |

### 3.9 Refuted and downgraded — kept on purpose

| # | claim as filed | verdict | what actually holds |
|---|---|---|---|
| 29 | `release.ps1:442` — "Escape after typing 3+ characters ships a real release: bumps version files, commits, tags and pushes" | **REFUTED** | fzf 0.74.3 prints **nothing** on abort — `--print-query` does not emit the query when aborting. `$fzfOut` is empty, `$description` is `''`, and the function returns at `:443` before any mutation. Probed three ways (`--bind start:abort`, `--bind load:abort`, and a real runtime abort POSTed to fzf's `--listen` API after full startup): exit 130, zero output lines. Accept yields exactly two lines. **The message defect survives at medium severity** (Escape and a 2-char description collapse into one line; `❌` in Yellow on a decision). Do not write this up as a release-safety bug. |
| 30 | `commit.ps1:141` — "Escape after typing 3+ characters is treated as confirmation and git-a stages, commits and pushes" | **half REFUTED** | Same mechanism: no output on abort, so `:140` always fires. There is no silent-commit path. The conflation, the false "too short" for a full message, and the wrong marker all stand — hence the row remains high on the strength of those, not of data loss. Also: the claimed discarded signal `$lines[1]` cannot exist on the abort path; the real discriminators are `$LASTEXITCODE` and the emptiness of `$fzfOutput` already tested at `:132`. |
| 31 | `rollback.ps1:123` — "Escape after typing a message is silently treated as Enter — git-rba commits and pushes" | **REFUTED** | Nothing is staged, committed or pushed on Escape. Downgraded to medium. `"too short or cancelled"` is an explicit disjunction — ambiguous, not false — which is materially weaker than the nav case where "Cancelled" asserted an act the user never performed. |
| 14 | "The same banner also prints when the clipboard held no file at all" | **that sub-clause REFUTED** | The guard at `clipboard.ps1:55` does block `$null`, `''` and ordinary single-line text — all three probed, all three return early at `:58`. There *is* a real hole (a multi-line `string[]` clipboard passes the guard, filed as #17), but the path from there to the success banner was **not traced** and must not be asserted. Everything else in #14 reproduces exactly. |
| 28 | "a rejected push, no origin remote, or an auth failure all hand the user a PR URL" | **partly REFUTED** | With **no origin remote**, `git config --get remote.origin.url` at `:39` returns empty, the `*github.com*` test at `:40` fails, and no PR link is printed. The green `✅ … completed!` at `:48` still prints in all three cases, so the finding holds; only the PR-URL half is narrower than filed. |
| 2 | "there is no way to remove a dead root" | **needs a qualifier** | `Reset-NavSearchRoots` (`:149-153`) deletes the whole file, so a dead entry *can* go — only by discarding every other root at the same time. Precisely: there is no **targeted** way, and the only escape is all-or-nothing. |
| 1 | "the swallowed `Get-PFStorageCandidate` exception is an equal peer of the other causes" | **downgraded** | Both adapters wrap their own enumeration with a fallback (`platform/windows/adapters/apps.ps1:314`, `platform/linux/adapters/apps.ps1:274`), so for the exception to escape to `roots.ps1:818` the adapter must be unloaded or the fallback must also fail. The signal really is discarded — the catch is empty — but this is not the everyday route. The other three causes carry the finding. Also: the Linux `/mnt/data` example is dropped by the writability test at `:829`, not by the `/boot|/snap|/var` mount filter at `:826`. |
| 20 | "the identical sentence at `:759` in mv-c means the opposite" | **corrected** | `:759` is `✅ Move operation cancelled` in **Green**, not `❌` in Yellow. Same six words, opposite markers, opposite states — which makes the finding sharper, not weaker, and adds `:759` as a wrong-marker site in its own right. |

---

## 4. Per-fix, for the confirmed high-severity ones

Ordered by what a wrong message causes the user to *do*, not by how wrong it reads.

### F1 — `mv-t` reports a move that did not happen, and drops the hold
`components/files/operations.ps1:713-727`

Three lies compound: it moved, it is there, and you no longer hold it. Reproduced end to end
against a locked destination: `Move-Item` printed its own red error, the source file was still
present, the green banner printed, and `$script:MoveInHand` was nulled — so `mv-t` cannot be
retried and the user must find and re-cut a file they were told had been moved.

```powershell
# :713
Move-Item -Path $sourceFile -Destination $currentDir -Force -ErrorAction Stop
```

`-ErrorAction Stop` is the whole fix. The `catch` at `:729` and its recovery line at `:738`
were written for exactly this and are currently unreachable, because a FileSystem-provider
failure is **non-terminating** under the default `$ErrorActionPreference` (which nothing on
PowerFlow's load path overrides — `Microsoft.PowerShell_profile.ps1` sets no preference). The
same file already does it correctly at `:249` and `:345`.

Move `$script:MoveInHand = $null` (`:727`) to **after** a verifying re-read, or leave it where
it is once the catch actually fires — but it must not run on a failed move.

### F2 — `paste-file` reports a paste that did not happen, with a corroborating size
`components/files/clipboard.ps1:162-167`

```powershell
# :162
Copy-Item -Path $sourceFile -Destination $destinationPath -Force -ErrorAction Stop
```

Probed: with the destination held open `FileShare.None`, `$?` was `False` and `$Error` held the
record — the information was sitting right there — and `✅ Pasted` printed anyway. The `📊 Size`
line at `:167` stats the **pre-existing** destination via `Get-Item` at `:164`, so the false
success looks verified. Probed the other shape too (destination absent, source locked):
`Get-Item` also fails non-terminating, `$copiedFile` is `$null`, `$null/1KB` rounds to `0`, and
the banner still prints. **There is no reaching path on which `✅ Pasted` is currently true after
a failure.**

Also fix the guard at `:55`, which fails open on a multi-line clipboard:

```powershell
$clip = @(Get-FromClipboard)                     # normalise: Get-Clipboard returns string[]
if ($clip.Count -ne 1 -or -not $clip[0].StartsWith('FILE:')) { ... }
```

### F3 — `rn`'s approved-overwrite flow fails 100% of the time and always reports success
`components/files/rename.ps1:177-192`

`Rename-Item` cannot overwrite an existing target — verified, including with `-Force`. So every
user who is shown `⚠️ File already exists` and answers `y` is then shown `✅ RENAME COMPLETED`
naming a swap that did not occur. `:170`'s case-insensitive `-eq` already intercepts the one
benign traversal (a case-only self-rename), so **lines 177-184 have no benign path at all**.

```powershell
# :188
Rename-Item -Path $fileInfo.FullName -NewName $newFileName -ErrorAction Stop
```

With `-ErrorAction Stop`, the existing `catch` at `:233` draws the RENAME FAILED banner it was
written for. A real overwrite needs `Remove-Item` on the target first (with its own
`-ErrorAction Stop`) — or the prompt should be replaced by a refusal that names the collision.

**Blast radius beyond the banner:** on this same failed path, `:204-206` recompute
`$newPath = Join-Path $currentPath $newFileName` and call `Set-FileMode`. That path resolves to
the **pre-existing victim file**, which exists and is untouched, so the chmod succeeds and
`:209` prints `✅ Permissions`. `rn notes.txt --chmod 600` against a collision reports a rename
that never happened *and* silently chmods an unrelated bystander file.

### F4 — the app uninstall claims a size it never reclaimed
`components/system/apps.ps1:521` · `platform/windows/adapters/apps.ps1:236-239`

The adapter runs the vendor uninstaller and returns `$true` regardless. Fix in the adapter,
where the evidence is:

```powershell
$p = if ($argline) { Start-Process -FilePath $exe -ArgumentList $argline -Wait -PassThru }
     else          { Start-Process -FilePath $exe -Wait -PassThru }
if ($p.ExitCode -ne 0) { return $false }
if ($App.InstallLocation) { return (-not (Test-Path $App.InstallLocation)) }
return $true            # nothing left to verify against
```

The scoop branch at `:217` already does the re-read. Where the location cannot be re-read, the
component must print the ⚠️ hedge rather than ✅ with a figure: the reclaimed size in the
component's message is `$App.SizeBytes`, measured **before** the uninstall, and must not be
quoted as fact after an unverified one.

### F5 — `team-room stop` reports success for a room it did not stop
`components/system/team-room.ps1:208-228`

`$did` collects successes only. A failed disarm prints `⚠️ could not remove the arm stamp`
(`:213`) and then, four lines later, `Nothing to stop — it was already inert.` — the reassuring
line last, over a room that is still armed and can still wake an agent.

```powershell
$did = @(); $failed = @()
if ($Room.Armed) {
    if (Set-TeamRoomArm -RepoRoot $Room.RepoRoot -On $false) { $did += 'disarmed …' }
    else { $failed += 'the arm stamp could not be removed' }
}
…
if     ($failed.Count) { Write-Host "   ⚠️  Still live: $($failed -join '; ')" -ForegroundColor Yellow }
elseif ($did.Count)    { foreach ($d in $did) { Write-Host "   ✅ $d" -ForegroundColor Green } }
else                   { Write-Host '   Nothing to stop — it was already inert.' -ForegroundColor DarkGray }
```

`:224` needs an `else` too: a failed connector-disable under `-All` currently produces no output
at all.

### F6 — `dkr inspect --json` renders a failed inspect as `{}`
`components/containers/containers.ps1:624-627`

This is the machine-readable path, so it misleads `jq` as well as a human. The three properties
excluded at `:625` — `Supported`, `Native`, `Error` — are the **entire content** of a failed
state object (`platform/windows/adapters/container.ps1:713-724`).

```powershell
if ($Json) {
    if (-not $state.Supported) {
        Write-Host "❌ $($state.Error)" -ForegroundColor Red      # stderr-shaped, not JSON
        return
    }
    $state | Select-Object * -ExcludeProperty Supported, Native, Error | ConvertTo-Json -Depth 6
    return
}
```

Related, same file: `:568` prints the total failure of `dkr inspect <name>` in DarkGray with no
marker. The `-Footer` switch declared at `:560` already distinguishes "bonus footer after logs"
from "the entire requested output" and is used for layout at `:562/:571/:588/:593` — consult it
at `:568` and render red without `-Footer`.

### F7 — the unconditional git success line (one pattern, seven sites)

Every one of these runs a git or npm command and then prints a success line on the next line,
with `$LASTEXITCODE` available and unread. Each is the same three-line fix.

| site | command | line that lies |
|---|---|---|
| `git/rollback.ps1:36` | `git push origin $currentBranch` | `:48` `✅ Rollback branch operations completed!` (+ a PR URL) |
| `git/interactive.ps1:199` | `git stash pop $stashRef` | `:200` `📤 Popped stash:` |
| `git/interactive.ps1:195` | `git stash apply $stashRef` | `:196` `✅ Applied stash:` |
| `git/interactive.ps1:267` | `git push $remoteName $branch` | `:268` `📤 Pushed to:` |
| `git/interactive.ps1:48` | `git checkout -b $branchName $hash` | `:49` `✅ Created and switched to branch:` |
| `git/branches.ps1:351/368/374/378` | `git switch` / `git checkout -b` | `:352/369/375/379` |
| `git/reset.ps1:37` | `npm install` | `:38` `✅ Reinstall complete.` |

```powershell
git push $remoteName $branch
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Push to $remoteName failed." -ForegroundColor Red    # git already printed why
    return
}
Write-Host "📤 Pushed to: $remoteName" -ForegroundColor Green
```

`interactive.ps1:56` in the same file already does exactly this for cherry-pick, so the pattern
does not need inventing — only applying.

Two of these need more than the guard:

- **`git-cm` (`branches.ps1:260-263`)** must resolve main-vs-master before checking out.
  `git-branch` in the same file does it at `:23-27`, and `git-cm`'s own `pwsh-h` synopsis
  already claims "main/master, whichever exists".
- **`git-next` (`reset.ps1:24-42`)** should verify it is in a Node project before deleting
  anything, and `:30`'s catch must distinguish `ItemNotFoundException` (finding #38) from a real
  lock instead of naming a lock for every failure.

### F8 — the `--print-query` pickers (one pattern, four sites)

`git/commit.ps1:116-141`, `git/rollback.ps1:98-123`, `git/release.ps1:425-442`,
`navigation/roots.ps1:880-888`.

The measured facts, from probing fzf 0.74.3 with the exact flag sets in these files:

| user action | exit | stdout |
|---|---|---|
| Enter, query matches a row | `0` | query, `--expect` key, selected row |
| Enter, query matches nothing | `1` | query, `--expect` key |
| Escape / Ctrl-C | `130` | **nothing at all** |
| fzf could not run (bad option) | `2` | nothing on stdout |

Two consequences for any fix. First, **exit 1 is the normal success path** for these pickers,
because the message arrives via `--print-query` and usually matches no list row — a fix keyed
on "non-zero means trouble" breaks the happy path. Branch on `-eq 130` specifically, exactly as
`nav.ps1:399` does. Second, because abort prints nothing, the emptiness of `$fzfOutput` is
*already* a sufficient discriminator at `commit.ps1:132` — no new call is needed, only a branch:

```powershell
$fzfOutput = $formLines | fzf … --print-query --expect=enter
$fzfExit = $LASTEXITCODE                     # next line: Write-Host clobbers it

if ($fzfExit -eq 130 -or -not $fzfOutput) { Write-Host '↩ Cancelled.' -ForegroundColor DarkGray; return }
if ($fzfExit -eq 2)  { Write-Host '❌ The picker could not run. Type the message with: git-a "<message>"' -ForegroundColor Red; return }

$userMessage = @($fzfOutput)[0].Trim()
if ($userMessage.Length -lt 3) {
    Write-Host "❌ A commit message needs at least 3 characters — got '$userMessage'." -ForegroundColor Red
    return
}
```

`roots.ps1:880-888` additionally needs the `IndexOf` → `-1` case split out: an Enter whose row
could not be mapped back is currently returned as the same `''` as Escape, so the user who
*did* choose is told they cancelled (`:946`). And `:882`'s header must stop promising
`Esc to type a path instead` — that fallback exists only in the non-fzf branch (`:896`).

### F9 — `nav setup` tells the user they have no second drive
`components/navigation/roots.ps1:818-859, 923-932`

Replaying the real function body against fabricated volume sets under `pwsh -NoProfile`
(no repo file modified) produced the branch actually taken:

| machine state | branch taken |
|---|---|
| second volume, root unwritable | `No drive besides the system one` |
| `Get-PFStorageCandidate` throws | `No drive besides the system one` |
| second volume, writable, **empty** (only `$*` and `System Volume Information`) | `No drive besides the system one` |
| writable + has a child dir | `Found another drive: D:` |

The third row is the everyday Windows case: a freshly formatted NTFS data drive contains
exactly the two entries `:833` skips. `nav setup` exists to find the second drive, so this is
the one statement that defeats the command's own purpose (its header at `:799` says
*"Non-system volumes lead, because finding them is the entire point"*).

The classifier already computes the reason and stores it: `components/shared/volumes.ps1:90-102`
builds `Reason = ($why -join ', ')`, e.g. `not writable`. It is not merely unused —
`components/system/storage.ps1:414` reads exactly that field (`$verdict = if ($c.Eligible)
{ 'eligible' } else { $c.Reason }`) and `:474` ships a glossary entry for it. So `storage root`
tells the user why a volume was rejected and `nav setup` throws the same field away.

Fix: keep the rejected volumes with their reasons and say so.

```powershell
try { $volumes = @(Get-PFStorageCandidate) }
catch { Write-Host "   ⚠️  Could not enumerate volumes: $($_.Exception.Message)" -ForegroundColor Yellow; $volumes = @() }
…
if ($offSystem.Count)      { Write-Host "   Found another drive: $drives" -ForegroundColor Green }
elseif ($rejected.Count)   { foreach ($r in $rejected) { Write-Host "   $($r.Volume) skipped — $($r.Reason)" -ForegroundColor Yellow } }
else                       { Write-Host '   No drive besides the system one …' -ForegroundColor DarkGray }
```

An empty-but-writable non-system volume should be **offered**, not skipped: the whole point of
`nav setup` is to name a drive before it has anything on it.

### F10 — `nav roots rm` denies a root the user can see, then deletes it silently
`components/navigation/roots.ps1:68-147`

`Get-NavSearchRoots` reads `$saved` at `:71` and immediately filters it to `$live` at `:72`.
`$saved` is a local with exactly one reader; nothing else in the tree ever reads
`.nav_roots.json`. So `Remove-NavSearchRoot` cannot see a saved-but-missing root, tells the user
it is not a root (`:139`), then — on the next successful removal of any *other* root — writes
back `$kept`, derived from the filtered list, **deleting the dead entry it just denied existed**.
Reproduced against a throwaway JSON file. Worse: with *every* saved root dead, `:73` falls
through to platform defaults, so removing a default root wrote `[]` and destroyed both saved
roots while naming neither.

Two changes:

1. `Remove-NavSearchRoot` must operate on the **raw saved list**, not the live one. Give
   `Get-NavSearchRoots` a `-Raw` switch, or add `Get-NavSavedRoots`, and resolve the user's
   argument (`(Resolve-Path $Path).Path`) the way `Add-NavSearchRoot` does at `:106` — currently
   `.\probe_live_A` is refused for a root that is configured, live and removable.
2. `Save-NavSearchRoots` (`:81-91`) must return `$true`/`$false` and its three callers must gate
   on it (`:121`, `:145`, `:151`). `Save-Bookmarks` (`bookmarks.ps1:62-76`, gated at `:98`) is
   the shape to copy. Right now `✅ Search root added` prints unconditionally, and
   `Show-NavSearchRoots` on the very next line re-reads the unchanged file — the user is told it
   worked and shown proof that it did not.

Then `Show-NavSearchRoots` can stop deriving "(configured)" from file existence (`:157`) and be
handed the fact directly, which also makes its dead-root `❌` at `:166` reachable for the first
time.

### F11 — "this is not an interactive terminal" for a machine that simply lacks fzf
`components/containers/containers.ps1:861-864, 1033, 1056`

Split the predicate. The correct sentence for the fzf half already exists in the same file at
`:949`.

```powershell
function Get-PFContainerPickBlock {
    if ([Console]::IsOutputRedirected) { return 'redirected' }
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return 'no-fzf' }
    return ''
}

$block = Get-PFContainerPickBlock
if ($block -eq 'redirected') {
    Write-Host "⚠️  Name a container: output is redirected, so no picker can open." -ForegroundColor Yellow
    Write-Host "    $command $verb <name>" -ForegroundColor DarkGray; return
}
if ($block -eq 'no-fzf') {
    Write-Host "⚠️  Name a container, or install fzf to pick one: $(Get-DependencyInstallHint 'fzf')" -ForegroundColor Yellow
    Write-Host "    $command $verb <name>" -ForegroundColor DarkGray; return
}
```

The same split applies to `Test-PmxCanPick` (`components/proxmox/shared.ps1:393-396`), whose
docstring already says both halves matter for different reasons.

### F12 — `srv` reports "could not connect" for a session that connected fine
`components/network/servers.ps1:163-182` · `platform/windows/adapters/ssh-session.ps1:100-104`

`ssh` returns the exit status of the **remote shell**. A full session ending in `exit 1`, or a
Ctrl-C'd remote program (130), comes back non-zero — and the user who just spent an hour logged
in is told the connection failed and sent to `srv list`.

SSH reserves **255** for its own failures. The adapter has the code at `:103`; use it:

```powershell
FailureKind = if ($code -eq 0)      { '' }
              elseif ($null -eq $code) { 'launch-failed' }
              elseif ($code -eq 255)   { 'connection-failed' }
              else                     { 'remote-exit' }
```

and in the component, render `remote-exit` quietly — the session happened; the remote command's
status is not PowerFlow's failure — while keeping the red branch for `connection-failed`, and
splitting `launch-failed` out of the `default` arm, where it currently hides.

### F13 — Proxmox: a transport failure reported as a refusal, and one screen for four faults
`components/proxmox/connection-state.ps1:11-57` · `components/proxmox/vm-change.ps1:92-99`

`ConvertTo-PmxSessionFailure` receives the adapter's specific text as `-ErrorMessage` at
`config.ps1:363` and discards it whenever the transport is ssh and any `FailureKind` is set
(`:18-25`). `Write-PmxDisconnectedState` then prints one screen for `authentication-required`,
`host-key`, `unreachable` and the catch-all `connection-failed`. For a host-key mismatch the
printed advice — *"Sign in first: srv proxmox"* — is the opposite of the fix.

Branch on `FailureKind` at `connection-state.ps1:42`, which is already in hand and currently
used only as a boolean gate. `host-key` needs its own screen naming
`REMOTE HOST IDENTIFICATION HAS CHANGED` and the `ssh-keygen -R` line; `unreachable` names the
host state, not the login.

At `vm-change.ps1:95`, `❌ Proxmox rejected the change:` must not prefix a transport failure.
`$result.FailureKind`, `$result.ExitCode` and `$result.Diagnostics` are all on the object:

```powershell
if (-not $result.Success) {
    if ($result.FailureKind -in @('unreachable','host-key','authentication-required','connection-failed')) {
        Write-PmxQueryFailure -Message "The change could not be sent: $($result.Error)" -Diagnostics $result.Diagnostics -Options $Options
        $outcome = 'undelivered'
    } else {
        Write-Host "❌ Proxmox rejected the change: $($result.Error)" -ForegroundColor Red
        $outcome = 'rejected'
    }
    …
}
```

This matters beyond the wording: a channel that dies **after** dispatch may have applied the
mutation, and the current envelope says `Executed = $true` while the message asserts a
rejection and the audit record stores `failed`. `undelivered` is the honest third state.

### F14 — `Uninstall-Dependency` always returns `$true` on Windows
`platform/windows/adapters/packages.ps1:157-164` · `components/core/recovery.ps1:161-167`

```powershell
function Uninstall-Dependency {
    param([Parameter(Mandatory)][string[]]$Name)
    if (-not (Test-PackageManager)) { return $false }
    scoop uninstall @Name 2>$null
    $allOk = $true
    foreach ($n in $Name) { if (Test-Dependency $n) { $allOk = $false } }
    return $allOk
}
```

That is the Linux adapter's shape (`platform/linux/adapters/packages.ps1:346`), and
`Install-Dependency` two functions up already verifies with `Test-Dependency` at `:154`. Without
it, `recovery.ps1:164`'s `✅ Dependencies removed` is unconditional on Windows and the honest
branch at `:166` is unreachable.

---

## 5. Enforcement

The marker sweep is mechanical and can be done in one pass; without a gate it will drift
straight back, exactly as it just did — PF-UX-002 was closed with a passing test
(`tests/navigation/outcomes.ps1`) and reopened in `nav.ps1` because it was fixed at call sites.
This repo's own habit is one implementation plus a CI gate (the coreutil scan, the adapter
parity check). Outcome messaging should get the same treatment:

1. **A shared renderer.** `components/shared/outcome.ps1` with `Write-PFCancelled` /
   `Write-PFOutcome`, modelled directly on `Write-PmxResolveFailure`
   (`components/proxmox/shared.ps1:415-426`), which already picks dim-cancel from red-error off
   a `.Cancelled` field. `↩ Cancelled.` currently exists as a **string literal** in three files
   — two of them copies rather than calls.
2. **`release-validate.yml` scans of `components/`:**
   - `❌` on any line whose `-ForegroundColor` is not `Red` — fails. (Catches ~37 sites.)
   - `❌` on any line also matching `cancel|skipped|kept|unchanged|not saved|not deleted` — fails.
     `tests/navigation/outcomes.ps1:93` already asserts this for one file; generalise it.
   - a `| fzf` pipeline not followed within two non-comment lines by a `$LASTEXITCODE` capture —
     fails.
   - `git push` / `git switch` / `git checkout` / `npm install` followed by a `✅`/`🔄`/`📤`
     line with no `$LASTEXITCODE` test between them — fails.
   - a `Write-Host "✅` inside a `try` whose mutating cmdlet lacks `-ErrorAction Stop` — fails.

`tests/navigation/outcomes.ps1` is the shape to copy, including its own honesty about the
trade: it asserts the exit-code branching **against source** and says why — driving it would
need a pty for fzf to raise 130 on, and a test that fakes the thing under test proves nothing
about it.

---

## 6. Coverage — what was read, sampled, and not examined

**Read in full or in the cited ranges, this session:**

- `CLAUDE.md`, `docs/plan/ethos/ETHOS.md`, `tests/navigation/outcomes.ps1`
- `components/navigation/` — `nav.ps1:360-414`, `roots.ps1:66-174` and `:862-961`,
  `bookmarks.ps1:1-135`
- `components/files/` — `operations.ps1:190-200`, `:668-767`, `clipboard.ps1:45-74`,
  `listing.ps1:62-112`
- `components/git/` — `interactive.ps1:40-64` and `:255-274`, `branches.ps1:18-31` and
  `:255-269`, `reset.ps1:10-47`
- `components/containers/containers.ps1` — `:275-300`, `:556-635`, `:374-392`, `:852-864`,
  `:915-954`, `:1028-1061`
- `components/proxmox/` — `shared.ps1:320-460`, `connection-state.ps1` (whole file),
  `vm-change.ps1:60-108`
- `components/network/servers.ps1` — `:28-45`, `:155-183`, `:405-420`
- `components/system/` — `team-room.ps1:200-235`, `apps.ps1:505-548`, `login.ps1:50-58`
- `components/core/recovery.ps1` — `:45-110`, `:125-170`
- `components/shared/flags.ps1` — `:245-292`, `:340-374`
- `platform/windows/adapters/` — `container.ps1:462-480` and `:700-735`, `apps.ps1:200-244`,
  `packages.ps1:140-169`, `ssh-session.ps1:80-105`

**Independently probed by execution** (all against throwaway files in the scratchpad or
isolated copies of the function bodies; no repo file was modified, and `git status` was
unchanged before and after): findings 1, 2, 14, 15, 16, 28, 29, 30, 31, 32, plus the fzf
0.74.3 exit/stdout matrix in F8. Probes covered locked-file `Copy-Item` / `Move-Item` /
`Rename-Item` behaviour under the default `$ErrorActionPreference`, offline git pushes into a
local bare repo, JSON round-trips of `.nav_roots.json`, and fzf abort via `--bind start:abort`,
`--bind load:abort` and a real runtime abort through fzf's `--listen` API.

**Carried from the candidate list and NOT re-read here** — treat as unverified leads:
`components/github/browser.ps1` (all six findings), `components/proxmox/` except the three files
above, `components/shell/` (`bash-compat.ps1`, `teach.ps1`, `keys.ps1`),
`components/system/health.ps1`, `path.ps1`, `shutdown.ps1`, `startup.ps1`, `sysconfig.ps1`,
`storage.ps1`, `fonts.ps1`, `components/core/version.ps1`, `dependencies.ps1`,
`components/git/release.ps1`, `remote.ps1`, `version-files.ps1`, `windows-only/coreutils.ps1`,
and the Linux adapters throughout.

**Not examined at all:** `install.ps1` and `uninstall.ps1` (both are outside `components/` and
both set `$ErrorActionPreference = 'Stop'`, so their failure semantics differ and they need
their own pass); `platform/linux/` beyond the three adapter references cited above;
`components/help/`, `components/prompt/`, and anything under `docs/` other than the two files
named at the top.

**What was not verified even where a finding is marked `probed`:** the claim in #17 that a
multi-line clipboard reaches the `✅ Pasted` banner. The guard failing open at
`clipboard.ps1:55` was reproduced; the path from there through `Test-Path` / `Resolve-Path`
with an array argument was not traced, and must not be asserted until it is.

**Counts:** 109 candidate findings assessed. 107 stand as filed or with a stated correction;
2 (#29, #31) are refuted in their load-bearing claim and downgraded from high to medium, with
the surviving message defect described. 3 more (#14, #28, #1) carry a corrected sub-clause and
#2 and #20 carry a qualifier — all recorded in §3.9 rather than deleted, because the
eliminations are the part of an audit that is easiest to lose and most expensive to redo.
</content>
</invoke>
