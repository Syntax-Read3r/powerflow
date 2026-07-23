# PowerFlow — Linux Teaching Layer

> Make PowerFlow a place where you **learn Linux while using it** — then get out of the way
> once you know it.
>
> Companion doc: **[COMMAND-MAP.md](COMMAND-MAP.md)** — the full inventory of Linux
> commands and flags, and where PowerFlow currently gets them wrong.

---

## 0. First, a bug — and it is not cosmetic

```
$ ls -ld ward-a

GNU:        drwxr-xr-x 2 root root 4096 Jul 14 11:48 ward-a     ✅
PowerFlow:  <listed the current directory instead>              ❌
```

PowerFlow's `ls` declares only `path`, `t`, `d` and has **no `[CmdletBinding()]`**. Without
it, PowerShell silently drops unrecognised arguments into `$args` and discards them. `-l`
vanished. `ward-a` never bound. No error.

Worse, two flags **actively conflict** with GNU:

| Flag | GNU means | PowerFlow means |
|---|---|---|
| `ls -t` | sort by **time** | **tree** view |
| `ls -d` | the **directory itself**, not its contents | tree **depth** |

So `ls -t` on Linux silently gives a tree instead of a time-sorted list. **This is Tier 0.
It is a bug, not a feature request.**

---

## 1. The teaching output

What `ls -ld ward-a` should produce with lessons **on**:

```
  d : rwx : rwx : r-x   2   you   media   4.0K   Jul 14 11:48   ward-a
  ╷    ╷     ╷     ╷    ╷     ╷       ╷       ╷         ╷            ╷
  │    │     │     │    │     │       │       │         │            └── name
  │    │     │     │    │     │       │       │         └── modified
  │    │     │     │    │     │       │       └── size
  │    │     │     │    │     │       └── GROUP  · members of 'media'
  │    │     │     │    │     └── OWNER  · the user who owns it
  │    │     │     │    └── hard links
  │    │     │     └── others · r-x = read + enter, cannot write
  │    │     └── group  · rwx = read + write + enter
  │    └── owner  · rwx = read + write + enter
  └── type · d = directory   (- file, l symlink)

  🔢 numeric : 775          chmod 775 ward-a
  🐧 real linux command : ls -ld ward-a
  💡 'd' means show the DIRECTORY ITSELF, not what is inside it.

  (hide these lessons:  linux-lessons off)
```

Colon-separated (`d:rwx:rwx:r-x`) as you asked — the three permission triads are the whole
point and `drwxr-xr-x` runs them together.

### Lessons off

```
  drwxr-xr-x  2  you  media  4.0K  Jul 14 11:48  ward-a
```

Identical to GNU. No decoration, no teaching. Same command, same flags.

---

## 2. Brother commands

Cryptic Linux names are hard to recall. Give each a full-word twin that does **exactly** the
same thing, then teach the real name every time.

| Brother | Real | Brother | Real |
|---|---|---|---|
| `changemode` | `chmod` | `listfiles` | `ls` |
| `changeowner` | `chown` | `makedir` | `mkdir` |
| `changegroup` | `chgrp` | `removefile` | `rm` |
| `findtext` | `grep` | `movefile` | `mv` |
| `findfile` | `find` | `copyfile` | `cp` |
| `diskusage` | `du` | `showfile` | `cat` |
| `listprocs` | `ps` | `stopproc` | `kill` |

**The brother is not a dumbed-down version.** It takes the same flags and produces the same
result — it just *also* tells you the real command:

```
❯ changemode u+w ward-a
  ✅ ward-a   rwxrwxr-x → rwxrwxr-x
  🐧 real linux command:  chmod u+w ward-a
```

You build muscle memory for `chmod` *while* using `changemode`.

### `-lesson` on every command

```
❯ changemode -lesson

  changemode  →  chmod   "change mode"

  WHO            WHAT              WHICH
  u  owner       +  add            r  read      (4)
  g  group       -  remove         w  write     (2)
  o  others      =  set exactly    x  execute   (1)
  a  all

  chmod u+w  file      owner gains write
  chmod g-x  file      group loses execute
  chmod 755  dir       owner rwx · group r-x · others r-x
  chmod -R 775 dir/    recurse into everything below

  ⚠️  chmod 777 makes a file world-writable. Almost never correct.
  💡 On a DIRECTORY, x means "may enter", not "may run".

  see also:  changeowner (chown) · changegroup (chgrp) · defaultmode (umask)
```

Prints the lesson and **does nothing else** — safe to run any time.

---

## 3. `linux-h` — a separate menu

`pwsh-h` is PowerFlow's command reference. `linux-h` is a **Linux** reference: real commands,
their brothers, their flags, grouped by topic.

```
linux-h                 # all topics
linux-h permissions     # just chmod/chown/groups
linux-h files           # ls/cp/mv/rm/find
linux-h processes       # ps/kill/systemctl
linux-h search chmod    # fuzzy-find any command
```

Backed by one data file (`components/linux/lessons.ps1`) so `linux-h`, `-lesson`, and the
inline hints all read from **one source of truth**. A lesson written once appears everywhere.

---

## 4. Switching it off

Three levels, because "beginner" is a moving target:

```powershell
linux-lessons full     # column diagrams + numeric + real-command + tips   (default)
linux-lessons hint     # one line: "🐧 real linux command: chmod u+w ward-a"
linux-lessons off      # nothing. identical to GNU output.
```

Persisted to `config/PowerFlow.settings.ps1` as `$script:LINUX_LESSON_MODE`, so it survives
restarts. Per-command override:

```powershell
ls -ld ward-a -Lesson      # force lessons on, once
ls -ld ward-a -NoLesson    # force them off, once
```

**Default: `full` on Linux, `off` on Windows.** Nobody on Windows is learning `chmod`.

---

## 5. Architecture

Per `CLAUDE.md`, `components/` must never call an OS API. The teaching layer is **text
formatting** — platform-agnostic — but the *data* it formats (mode bits, uid/gid, ACLs) is
deeply platform-specific. So:

```
components/linux/lessons.ps1      the lesson TEXT (one source of truth)
components/linux/format.ps1       the column diagram renderer
components/linux/brothers.ps1     changemode/changeowner/... → real commands
components/help/linux-menu.ps1    linux-h

platform/linux/adapters/perms.ps1     Get-FileMode, Set-FileMode, Get-FileOwner, ...
platform/windows/adapters/perms.ps1   same contract, ACL-backed (or declines cleanly)
```

> ⚠️ **The `chmod` problem on Windows.** Windows has no POSIX mode bits — it has ACLs. A
> `chmod` brother that pretends otherwise would be lying. Options:
> **(a)** Windows-only stub that explains the difference and points at `icacls`;
> **(b)** map the common cases to ACLs;
> **(c)** put the whole teaching layer in `linux-only/` and don't ship it on Windows.
> **I recommend (a)** — the lesson is still useful on Windows, the *action* is not.

---

## 6. Build order

| Phase | Work | Why |
|---|---|---|
| **0** | **Fix the traps.** `[CmdletBinding()]` on every override; pass GNU flags through to the native tool; stop `-t`/`-d` meaning the wrong thing. | It is **wrong today**. Ship before anything else. |
| **1** | Permissions: `chmod`/`changemode`, `chown`, `chgrp`, `id`, `groups`, `getent`, `umask` + the column renderer + `-lesson` + `linux-lessons off`. | Your actual lesson path. Proves the whole design. |
| **2** | `linux-h` menu + the lessons data file. | Ties phase 1 together. |
| **3** | Daily commands: `find`, `grep`, `cat`, `head`, `tail`, `du`, `df`, `ln`, `stat`. | Highest-frequency gaps. |
| **4** | Sysadmin: `ps`, `kill`, `systemctl`, `journalctl`, `ss`, `lsblk`. | Server work. |
| **5** | The rest: `tar`, `sed`, networking, mounts. | Long tail. |

Phase 0 is a **bugfix release**. Phases 1–2 are the feature.

---

## 7. THE RULE (decided)

> **Single dash belongs to Linux. Long dash belongs to PowerFlow.**
>
> If GNU has the flag, **GNU wins**. PowerFlow's own switches get a `--long-name`.

| | |
|---|---|
| `ls -l -a -d -h -R -t -S -r -i` | GNU semantics, exactly |
| `ls --tree`, `ls --depth 3` | PowerFlow |
| `rm -r -f -i -v` | GNU semantics |
| `rm --pick` | PowerFlow's fzf picker |

Not `--t`. In Linux, `--` introduces a **long** flag (`--all`, `--human-readable`), so `--t`
would teach the wrong convention. `--tree` is self-documenting, reinforces the convention
being learned, and can never collide — GNU `ls` has no `--tree`.

### How to implement it (verified, not assumed)

A PowerShell **param block is what caused the bug.** With one, PowerShell tries to bind `-l`
as a parameter name:

```powershell
# WITH a param block:
ls -l        →  ERROR "A parameter cannot be found that matches parameter name 'l'"
ls -ld x     →  silently swallowed into $args and DISCARDED

# With NO param block, $args takes everything verbatim:
ls -l              →  [-l]
ls -ld ward-a      →  [-ld] [ward-a]
ls -lh --tree /tmp →  [-lh] [--tree] [/tmp]
```

So every override becomes:

```powershell
function ls {
    # NO param block and NO [CmdletBinding()] — either makes PowerShell try to bind
    # `-l` as a parameter name and fail. $args receives the argv verbatim.
    $pf  = @{}      # PowerFlow long flags
    $gnu = @()      # everything else — passed straight through

    for ($i = 0; $i -lt $args.Count; $i++) {
        switch -Regex ($args[$i]) {
            '^--tree$'    { $pf.Tree = $true }
            '^--depth$'   { $pf.Depth = $args[++$i] }
            '^--lesson$'  { $pf.Lesson = $true }
            '^--no-lesson$' { $pf.Lesson = $false }
            default       { $gnu += $args[$i] }
        }
    }
    ...
}
```

## 8. One menu, not two

`linux-h` is dropped. There is **one** menu — but `pwsh-h` already renders 16k characters, so
40+ more commands would make it unreadable. It gains **topic filtering** instead:

```
pwsh-h                 # everything (unchanged)
pwsh-h permissions     # chmod / chown / groups only
pwsh-h files           # ls / cp / mv / rm / find
chmod -lesson          # a single command's lesson, inline
```

The Linux section only renders on Linux. All of it reads from **one** lessons data file, so
`pwsh-h`, `-lesson`, and the inline hints can never drift apart.

## 9. Remaining decisions

1. **Do the brothers ship on Windows?** `changemode` there can only ever be a *lesson* —
   Windows has ACLs, not POSIX mode bits. Pretending otherwise would be lying.
2. **How far do we go?** 40+ commands is a large surface. Phases 0–2 deliver most of the
   value; 3–5 can be demand-driven.
