# Log 5 — July 27, 2026 — pc-whoami -ram: what is eating memory, and closing it (v3.13.0)

**User:** "pc-whoami is great, we need to add another feature to it. pc-whoami -ram, this
would display all processes currently draining ram from 0.5ram and up. we need to see these
processes and have the ability to kill them."

```
🧠 MEMORY — programs using 0.5 GB or more

   Code                     6 GB   18.4%   48 processes
   java                     5 GB   14.4%   8 processes
   msedgewebview2           2 GB    4.9%   32 processes
   svchost                  1 GB    3.3%   86 processes   🔒 system-critical
   pwsh                   638 MB      2%   6 processes   ← this shell
```

## The one design decision that matters: group by program, not by PID

The request said "processes", but per-PID is the wrong unit here and the live data proves it.
VS Code runs **48 processes** on this machine — each far below any sane threshold, together
holding 6 GB. A per-process list at 0.5 GB would have shown almost none of them and hidden
the actual answer; at a lower threshold it would print "Code 180 MB" forty-eight times.

So rows are grouped by program name, the threshold applies to the group total, and the group
carries its PIDs so a kill still acts on real processes. `-min N` moves the bar (default 0.5).

`WorkingSet64` is the metric — resident physical memory, which is what "draining my RAM"
means. It counts shared pages in each sharer so group totals can slightly overstate; private
bytes would understate just as badly by ignoring loaded images. Noted in the adapter rather
than pretended away.

## Killing safely was most of the work

`Stop-Process` on the wrong thing is not a mistake you recover from — `lsass`, `csrss` and
`wininit` bugcheck Windows *instantly*. Three guards:

1. **System-critical programs are refused outright**, not warned about. The list lives in the
   adapter because it is inherently per-OS. On Linux, **PID 1 is protected whatever it is
   called** — the container test happened to run pwsh as PID 1 and the rule caught it, which
   is exactly why it keys on the PID and not just the name.
2. **The shell you are typing in is refused** and marked `← this shell` in the list.
3. **Confirmation is the program's name typed back**, after showing process count, memory and
   every PID, with the cost stated plainly ("this is a kill, not a polite close"). Results are
   reported per-PID — "Closed 3 of 4" — because a group genuinely can partially fail when a
   process exits on its own or belongs to another user.

The picker only opens when both streams are a terminal *and* fzf exists. A destructive prompt
must never appear in a pipe, a script or CI, where nothing can answer it.

### The safety gap the live run exposed

The first working build listed **`svchost` — 86 processes, ~1 GB, unprotected**, sorted high,
directly next to a kill action. It is not a BSOD process, so it had not occurred to me; but
svchost hosts nearly every Windows service, and ending the group takes down networking, audio
and update at once. It is never a sensible way to free memory. Now protected, with the reason
recorded. The Linux equivalents — `dbus-daemon` and the `systemd-*` helpers — were added for
the same reason: service plumbing that accumulates real memory and breaks the session rather
than freeing anything useful.

I would not have found that by reading the code. It came from looking at what the tool
actually printed on a real machine.

## Verified — including the destructive path, for real

Not "the kill code looks right": the kill was **executed**.

**Windows (live, 31 assertions):** grouping, sorting, threshold filtering both ways, PIDs
matching counts, sane percentages; protected and self flags correct against the real process
table (including svchost); `Stop-RamHog` refusing a protected group and refusing self, with
no kill attempted. Then **two pwsh children spawned for the purpose and actually killed** —
both confirmed gone, reported "Closed 2 of 2". Then the inverse: a third child, wrong
confirmation typed, and the assertion is that the process **survived**.

**Linux (container):** same contract, real kill of a spawned `sleep`, PID-1 protection,
refusals, and the piped path printing the table without ever offering a picker.

Gates: parse, architecture (`Get-Process` is cross-platform and not an OS API, but the
protected-name knowledge lives in the adapters), parity (`Get-ProcessMemoryUsage` on both
platforms and added to the hardcoded CI contract regex), help registry, privacy.
