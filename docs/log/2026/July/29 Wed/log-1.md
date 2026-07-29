# Log 1 — July 29, 2026 — drilling into one program, and the inverse view (v3.14.0)

Three asks in one turn, each of which changed the design:

1. "i ran pc-whoami -ram java, this would magnify only java items here is 8 processes"
2. "we should remove the ability to end processes from pc-whoami -ram since the list is to
   vast, instead the user can have this ability after they run -ram <name>"
3. "while in -ram <name>, the user should have the power to kill the whole group but after
   being warned"
4. "we also need --ram for those items less than 0.5gb… -- meaning less, and - meaning greater"

## `-ram java` did not just lack a feature — it crashed

Before anything else: `pc-whoami -ram java` **errored**. With no positional parameter, `java`
bound to `[int]$days` and the command died with *"Cannot convert value 'java' to type
System.Int32"*. So the first fix was a parameter, not a view.

## The drill-in exists for the command line

Eight rows labelled `java` are worthless. The only thing that distinguishes them is the
command line, so `Get-ProcessDetail` was added to both adapters — Win32_Process on Windows,
`/proc/<pid>/cmdline` (NUL-separated) on Linux — alongside PID, memory, share of RAM and
uptime. Without that column the view would be prettier and just as useless.

Where the command line is unreadable (another user's process without elevation, or a kernel
thread) it *says so* rather than showing a blank, which would read as "no arguments".

## Moving the kill was the user's call, and it was right

v3.13.0 let you close a whole program from the overview. On this machine that meant one
keystroke ending **48 VS Code processes** — too blunt to sit against a list that long. The
overview is now strictly read-only; closing lives only in the drill-in, where you have already
seen every process and what it is running.

Then the counter-point, also right: once you are *in* the drill-in, killing the whole group is
a legitimate, informed choice. So the picker carries two verbs via `--expect=ctrl-a`:

- **Enter** → one process. Confirmation is **that PID typed back** — specific to the process
  being ended, where a program name would be equally true of the seven left running.
- **ctrl-a** → the whole program. Warned harder ("this ends the WHOLE program"), confirmation
  is the program name, and results are per-PID because a group genuinely can partially fail.

The group path **filters** rather than refuses: protected processes and the current shell are
excluded from the kill and named in the warning beforehand, so "close all pwsh" closes the
other shells and leaves yours running. That is strictly better than refusing the whole action
because one member is untouchable.

## `--ram`: PowerShell has no double-dash switches

The requested syntax does not exist in PowerShell, so the parser had to be measured rather
than assumed:

```
--ram        -> binds as the STRING "--ram" to position 0; the -ram switch stays False
--ram java   -> ERROR: "A positional parameter cannot be found that accepts argument 'java'"
```

Hence **two** positional slots: position 0 takes `java` for `-ram java`, and position 1 catches
`java` when `--ram` has already consumed position 0. The token is then read as a flag. No
process can be named `--ram`, so the overload is unambiguous.

The inverse list is long by nature, so it is sorted biggest-first, capped at 25, and the
remainder **counted** ("…and 123 more below 0.5 GB") rather than silently truncated.

## Verified by execution, including every destructive path

- **Real single-PID kill** (spawned child, PID typed, process confirmed gone) and the inverse:
  wrong PID typed → process **survived**.
- **Real group kill** of three spawned children with this shell and a protected row included in
  the group — all three died, both were filtered out and named in the warning, and the shell
  survived. Wrong confirmation → all three still alive.
  This had to run in a **child process with piped stdin**: `Read-Host` caches its reader on
  first use, so a second `[Console]::SetIn` in one process is ignored — the in-process test
  "passed" only because empty input also refuses, which is a false negative worth recording.
- Every invocation form binds without throwing: `-ram`, `--ram`, `-ram java`, `--ram java`,
  `-ram -min 2`, `--ram -min 0.2`, and the untouched `-crashes -days 1`, `-bios`, `-power`.
- The two overviews are provably **disjoint** (nothing appears in both), and the overview
  offers no kill path in either direction.
- Linux: same forms, `/proc` command lines decoded and distinguishing two `sleep` processes,
  real single kill, refusals.

Gates: parse, architecture, parity (`Get-ProcessDetail` on both platforms and in the hardcoded
CI contract regex), help registry, privacy.

## The adversarial review found three more blockers — one of them severe

Everything above passed before the review ran. It still found this:

**1. A wildcard was a whole-session kill.** `Get-Process -Name` is wildcard-enabled. Verified
independently, read-only, on this machine: `pc-whoami -ram *` listed **529 processes**, of which
**428 were killable** — `explorer`, `dwm`, `WindowsTerminal`, `ctfmon`,
`StartMenuExperienceHost`. `ctrl-a` then offered to end all of them behind the confirmation
"type the program name", where the program name **is `*`**: the gate is `('*' -ne '*')` → False,
so **one asterisk** authorises destroying the desktop session. `IsSelf` would not have saved it
either — it protects the pwsh PID, not the terminal hosting it, so the kill loop could have
destroyed its own window partway through and never printed what it had done.

One metacharacter silently converted "scoped to one named program" — the invariant the whole
feature is built on — into "everything". Fixed at both layers: the component refuses patterns
with an explanation, and both adapters match literally (`Where-Object { $_.ProcessName -eq
$Name }`), which also removes a crash where an unbalanced `[` threw a terminating
`WildcardPatternException` that `-ErrorAction SilentlyContinue` does not suppress.

**2. A recycled PID could be killed.** Rows are captured before the picker *and* before the
prompt. If a listed process exits in that window and the OS reuses its number, `Stop-Process
-Id` hits something the user never saw. `Test-RamStillSame` now re-verifies name **and start
time** immediately before every kill — a reused PID never has the original's start time.

**3. Truncation defeated the drill-in in its headline case.** Command lines were cut from the
head, but `java` processes share a long identical prefix (JVM path, `-classpath` blob) — so
eight different processes rendered as eight byte-identical rows, in exactly the `java` case the
view exists to solve. Now trimmed from the **middle**, keeping the tail where the jar, main
class and port live.

Plus: uptime was rounded up (`[int]` rounds — 1d 18h printed as 2d 18h); `ctrl-a`'s header
promised "closes ALL 8" when the action filters out protected rows and this shell; the success
line reported the whole group's memory even when kills failed; two-word names like
`Memory Compression` were silently split; and Linux had no analogue of the `svchost` rule, so
`gnome-shell`/`Xorg`/`plasmashell` and the display managers were killable.

### A test-fixture lesson worth keeping

After adding the identity check, four previously-passing assertions failed — because my
fixtures fabricated `Name='pf-grp'` on rows pointing at real `pwsh` processes. That was the new
guard **working**: it refused rows whose identity did not match. The fixtures now carry the real
`ProcessName` and `StartTime`. A test that passes only because it lies to the code under test is
worse than no test.
