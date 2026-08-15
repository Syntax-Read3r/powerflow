# 14 Aug 2026 (2) — two reported bugs, and a third found underneath one of them

Both reported defects were fixed. The one that matters most was not reported at all: it
surfaced only because fixing the second one reproduced it.

---

## 1 · PF-BUG-006 — `srv` echoed the password in cleartext

```text
❯ srv web-prod
Password for 'web-prod': hunter2
********
```

Both lines are real, and together they name the cause. A Windows console handle arrives with
`ENABLE_ECHO_INPUT` and `ENABLE_LINE_INPUT` already **on**, and
`platform/windows/helpers/powerflow-ssh-askpass.cs` never cleared them:

- `ENABLE_ECHO_INPUT` — the **console** prints each keystroke itself. That is line one, in
  cleartext, and therefore in scrollback, screenshots, and any recorded session.
- `ENABLE_LINE_INPUT` — `ReadConsole` blocks until Enter, so the helper's own per-character
  `*` writes all arrive afterwards. That is line two, on its own.

### Why it read as careful code

The helper *does* mask, visibly and per character, with backspace handling and a scrubbed
buffer. Nothing about it looks careless. The defect was not a missing feature but an **unstated
assumption** — that a console handle starts in raw mode. It does not, and nothing in the code
said it was relying on that.

The Linux sibling was always correct: `stty -g` to save, `stty -echo` to clear, restore from an
`EXIT HUP INT TERM` trap. The fix is those three steps in Win32 terms, with two details that
matter:

- **Clear `ENABLE_LINE_INPUT` too**, not just echo — that is what makes `ReadConsole` return per
  keystroke, so the `*` appears *as* you type rather than in a block afterwards.
- **Restore in `finally`, before `CloseHandle`, guarded on the save having succeeded.** Every
  early return (Ctrl+C, Ctrl+D, a failed read) passes through it. A helper that exits with echo
  still disabled hands back a console that looks dead — the one failure mode worse than the bug
  being fixed. And restoring a mode that was never captured would set the console to 0.

Pinned by `tests/network/askpass-echo.ps1`, which asserts on **both** helpers so the pair cannot
drift, and says plainly why it is a source test: the behaviour needs a real console, a piped
stdin is not one, and a test that ran green against a pipe would assert nothing at all.

---

## 2 · PF-BUG-007 — `swapon` "not recognized"

```text
❯ swapon --show
swapon: The term 'swapon' is not recognized as a name of a cmdlet, function, script file...
❯ sudo /sbin/swapon --show
NAME      TYPE      SIZE USED PRIO
/dev/sda3 partition 1.7G   0B   -2
```

`swapon` was never missing. It lives in `/sbin`, which Debian keeps off a normal user's PATH.

**Why bash hides this and pwsh does not.** In bash, `sudo swapon` works because sudo runs with
root's own `secure_path` and finds it. Under pwsh, PowerShell resolves the command name against
**your** PATH *before* sudo is ever executed — so it fails at the resolution step, with a
message that reads "this isn't installed" rather than "this isn't on your PATH". That misleading
error is the actual defect: it sends an admin looking for a package that is already present.

`/usr/local/sbin`, `/usr/sbin` and `/sbin` are now appended when they exist. **Appended, never
prepended** — a same-named binary earlier on PATH must keep winning — and a directory that does
not exist is not added, so distros that merge these into `/usr/bin` are unaffected.

---

## 3 · The bug nobody reported: PowerFlow was replacing PATH on Linux

Fixing (2) meant appending to PATH, so I tested it in a container. The result:

```text
0. stripped        : /opt/microsoft/powershell/7:/usr/local/bin:/usr/bin:/bin
1. after paths.linux.ps1 alone : /sbin
```

One file reduced PATH to a single entry. The cause:

```powershell
$env:PATH = '/usr/bin:/bin'
$env:PATH = "$env:PATH:/home/you/.local/bin"
$env:PATH   # ->  /home/you/.local/bin       everything else GONE
```

**In an interpolated string, a colon after `$env:NAME` is read as part of the variable name.**
So `"$env:PATH:$dir"` asks for an environment variable literally called `PATH:` — which does not
exist and evaluates to empty — leaving just `$dir`.

This was not only my new line. `config/paths.linux.ps1` had appended `~/.local/bin` in exactly
that form, in shipped code.

### Why it survived this long

The guard only fires when the directory **exists** *and* is **absent from PATH**. On a fresh
machine `~/.local/bin` is created by the dependency install — which runs at step 4 of the
bootloader, *later* than `paths.linux.ps1` at step 3. So the very first session, the one anyone
tests after installing, never triggers it. It would hit on the **second** shell.

That is the shape worth remembering: a latent bug guarded by a condition that is false exactly
when a human is most likely to be watching.

### What made it visible

Nothing clever — my `/sbin` addition used the same idiom and fired immediately, because those
directories *do* exist at step 3. The new bug was a louder instance of the old one, in the same
file, three lines apart.

Every assignment now braces the name (`${env:PATH}`), and `tests/linux/sbin-path.ps1` fails if
the unbraced form returns.

---

## A note on the test that caught it

The first version of `sbin-path.ps1` **passed while proving nothing.** A container runs as root,
and root's PATH already contains the sbin directories — so the fix correctly did nothing, and
every assertion went green.

It now **strips those directories first**, recreating the non-root Debian condition from the
report, and asserts a precondition — that `swapon` is *not* resolvable before the profile loads —
so a future change that makes the setup unrepresentative fails loudly instead of quietly passing.

That check is the difference between a test that runs and a test that tests.

---

## State

| | |
|---|---|
| Suites | files · flags · git · safety · containers · storage · proxmox · network · windows — all green |
| Gates | 7 runnable, all green |
| Linux legs | `coreutil-resolution.ps1` and `sbin-path.ps1`, both in a container |
| New | `tests/network/askpass-echo.ps1` (23) · `tests/linux/sbin-path.ps1` |

## Still open

- **PF-FEAT-006 / 007** — the grouped storage/memory diagnostic and the `--educate` footer. The
  owner supplied a model for the latter: a `sudo ss -tulpn` walkthrough that gives an analogy
  first, then decodes each flag in one line.
- **PF-FEAT-001 / 002 / 004 / 005**, the team-room column check, and the deferred `pman all`.
