# 14 Aug 2026 — `git-rl` stops lying, twice; and a claim I got wrong

Two field reports on the same command, both about **what it said** rather than what it did. Plus
a correction to something I asserted confidently in the v5.0.0 notes and had wrong.

---

## 1 · PF-UX-005 — `git-rl` in a project that was never set up

**Reported:** running `git-rl` in `trc`, a project with no release pipeline:

```text
❯ git-rl
❌ Release cancelled
```

**False twice.** No release was possible — the project has no version source, no parseable
CHANGELOG and no `v*` tag pipeline — so nothing was cancelled. And the wording blamed the user
for backing out of a flow that could never have succeeded. What actually happened: with no
version source, the old code warned "starting from v0.0.0", opened the bump picker anyway, and
printed that line when the picker was escaped.

### The first fix was wrong, and the correction is the interesting part

I made bare `git-rl` write the setup walkthrough straight into the current repo. The owner
rejected it:

> *"you should have told me git-rl -h was active. Then we would have just told the user to run
> git-rl -h instead of assuming the user is in a repo"*

Two separate mistakes, worth keeping apart:

**The process one.** I had read `git-rl -h` minutes earlier and knew it already delivered this
exact guide. The useful reply to "paste the walkthrough into that project" was *"that command
already exists and it asks which folder first — point at it, or build the inline version?"* —
a question, before code. Instead I implemented the sketch literally.

**The design one.** Bare `git-rl` may be run in any repo — a clone, a scratch checkout,
someone else's project. Creating files there as the side effect of what amounts to a status
query assumes this repo is the one the user wants a pipeline in. `git-rl -h` puts the
confirmation *before* the write on purpose; my version routed around it.

### What shipped

```text
⚠️  This project isn't set up for git-rl yet — no version file and no v* tag.
   A release needs: a version source · a parseable CHANGELOG · a v* tag pipeline

💡 Run: git-rl -h
   It confirms you're in the right folder, writes the setup walkthrough
   (docs/git-release-help.md), and puts the AI setup prompt on your clipboard.
```

Bare `git-rl` writes nothing. If the walkthrough is already present it points at the file
instead of at the command that would offer to overwrite it.

---

## 2 · The same command, one message later

**Reported:** `git-rl -h`, answered yes, then:

> *"i dont know what is the paste fuction. when i selected yes, it should have automatically
> pasted the file into the repo"*

It **had**. `✅ Wrote: docs/git-release-help.md` was right there in the output. But the closing
message led with the clipboard — *"Paste the prompt into your AI assistant (it is on your
clipboard)"* — which reads as though a paste step is still required to get the file into the
repo. The owner's diagnosis was exact: *"It did paste it, it was just worded poorly."*

Two things were wrong with that sentence, and neither was the behaviour:

- **It buried the delivery.** The one fact the user needed — the file is already here — was a
  line of output above, competing with a path and a clipboard note.
- **It assumed a web-chat assistant.** With Claude Code or Cursor open *in the repo*, there is
  nothing to paste at all; the assistant can just read the file. The clipboard is the fallback
  route, not the primary one. And "paste" was never spelled out as Ctrl+V.

Now:

```text
✅ Done — the walkthrough is in your project: docs/git-release-help.md

Next, have an AI assistant build the pipeline. Either way works:
  •  Assistant open IN this repo (Claude Code, Cursor):
       tell it:  follow docs/git-release-help.md and set this project up for git-rl
       (nothing to paste — the file is already here)
  •  Assistant somewhere else (a web chat):
       the setup prompt is on your clipboard — click its message box and press Ctrl+V
```

`Write-GitReleaseGuide`'s clipboard line became a statement of fact rather than an instruction,
since the "Next" block now carries the instructions.

**The pattern across both reports:** the command was correct and the sentence was not. A tool
that does the right thing while describing it badly is indistinguishable, from the user's
side, from a tool that does the wrong thing.

---

## 3 · A claim I got wrong, and how it surfaced

In the v5.0.0 notes I wrote that `CLAUDE.md` documented a Linux CI job which "did not exist —
the workflow has only ever had one, on `windows-latest`".

**It exists.** `release-validate-linux.yml` runs a `distros` matrix (Alpine, Arch, …) that
installs PowerFlow, loads the profile, and asserts `rm`/`mv`/`cp`/`cat`/`grep` resolve to
`Application` and that `del`/`mvf`/`nav`/`git-a`/`pwsh-h` exist — precisely what CLAUDE.md
describes.

The error was **method**: I grepped one workflow file, found no Linux job in it, and
generalised to the directory. There are seven. Two things made it worse than a wrong grep —
the phrasing was confident ("entirely fictional"), and it propagated into the CHANGELOG, a
session log, two test headers and a gate comment before anything contradicted it.

What contradicted it was the release run itself: the green
`🚀 Profile loads and coreutils stay unshadowed` step is the job I said was missing. Corrected
in all six places in `60748f2`.

The two static gates added in v5.0.0 still stand on their own merit — they fail on the
offending *name*, in the file that defines it, before the Linux leg installs anything. They are
additive, not filling a hole.

---

## 4 · A privacy slip, caught and closed

Commit `a2363ad` accidentally tracked `.claude/settings.json` via `git add -A`. Its
auto-accumulated permission entries contained machine-absolute paths with the real username —
exactly what the release checklist's privacy item exists to catch, and missed because the
sweep happened *after* the scan had run.

Fixed in `56e4176`: entries merged into the git-ignored `settings.local.json`, tracked file
removed, tree verified clean. The one historical blob joins the pending history-rewrite list.

**Process rule, now recorded:** run the privacy scan on the exact staged set immediately before
committing, and never `git add -A` after the scan — a sweep can pick up files the scan never
saw.

---

## Test and gate state

| | |
|---|---|
| Suites | files · flags · **git** · safety · containers · storage · proxmox · network · windows — all green |
| Gates | 7 runnable, all green (4 skipped locally: they need GitHub's expression context) |
| New | `tests/git/` — 19 assertions over the `git-rl` setup path |

`tests/git/release-setup.ps1` is built around **tripwires** rather than only assertions. Stubs
for `fzf`, `Read-Host` and `Write-GitReleaseGuide` all *throw*, so the suite fails loudly if
bare `git-rl` ever opens the picker, prompts, or writes a file again. A separate probe drives
the real `git-rl -h` flow headless (fzf stubbed to answer "yes") and asserts the delivered-first
wording, the nothing-to-paste line and the Ctrl+V spelling. A fourth check proves a **set-up**
project still reaches the picker, so the fix cannot have over-corrected.

---

## Still open

- **PF-BUG-006** — `srv` echoes the typed password in cleartext. Root cause found (the Windows
  askpass helper never clears `ENABLE_ECHO_INPUT`), not yet fixed. Next up.
- **PF-BUG-007** — `/sbin` and `/usr/sbin` missing from PATH under pwsh on Linux, which is why
  `swapon` reported "not recognized".
