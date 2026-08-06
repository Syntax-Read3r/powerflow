# Changelog

All notable changes to PowerFlow will be documented in this file.

## [Unreleased]

### Planning
- Additional database providers
- Testing framework integration
- Enhanced Docker optimizations

## [3.18.1] - Unreleased

### Fixed

- 🌐 **Interactive `srv` connections keep their terminal attached after password
  authentication.** The SSH helper no longer pipes the native session into `Out-Null`, so the
  remote shell remains visible and usable. The server picker also uses a taller layout and a
  compact ASCII instruction line to prevent controls from wrapping into the server list.

## [3.18.0] - 2026-08-06

### Added

- 🔐 **`srv <name> info` reveals a saved SSH endpoint only after successful SSH
  authentication.** The authentication probe opens no remote shell, stores no password, and
  keeps connection details hidden when authentication fails, is cancelled, or cannot run
  interactively.

### Changed

- 🌐 **Normal `srv` use is now alias-first and endpoint-private.** Lists, picker rows,
  connection handling, save/rename/remove messages, and reachability warnings identify a saved
  server only by alias and live status. The native OpenSSH client still owns its credential
  prompt and may display its own target while asking for a password.

### Fixed

- 🎨 **Windows no longer reports that FiraCode Nerd Font Mono failed after Scoop
  successfully installed it.** Scoop registers filename-derived names such as
  `FiraCodeNerdFontMono-Regular`, while PowerFlow looked only for the spaced family label.
  Detection now normalizes both forms, `pwsh-font` preserves the real failed command when
  something genuinely goes wrong, and a Windows regression covers the actual registry shape.
- 🧰 **Scoop is now an explicit Windows prerequisite.** The installer verifies or bootstraps
  it even under `-NoDeps`, activates its shim in the current process, and refuses to continue
  dependency setup without it. Interactive uninstall asks separately whether to remove Scoop;
  only after yes does it explain that every Scoop-managed application, bucket and shim is at
  risk, and Scoop retains its own final confirmation. Automated `-Yes` always keeps Scoop.

## [3.17.0] - 2026-08-06

### Added

- ⚡ **`pmx` grows from a Proxmox host dashboard into guarded VM management.** The v3.16
  command could inspect the node and investigate physical drives; v3.17 keeps that entire
  surface and adds the day-to-day VM workflow, locally on a Proxmox shell or remotely through
  a saved `srv` SSH alias:

  ```powershell
  pmx config set host proxmox
  pmx config validate
  pmx discover
  pmx vm list
  pmx vm clone --source debian-base --new-vmid auto --name docker-host --full --dry-run
  pmx vm cpu set --vm docker-host --cores 4
  pmx vm memory set --vm docker-host --size 8GiB
  pmx disk grow --vm docker-host --disk scsi0 --to 100GiB
  pmx snapshot create --vm docker-host --name pre-docker
  pmx vm start --vm docker-host
  ```

  Discovery reports real nodes, VM storage, bridges, templates and authoritative VMIDs before
  a plan is made. Reads cover inventory, status, configuration, virtual disks and snapshots;
  changes cover independent full clones, CPU, memory, final-size disk growth, start, graceful
  shutdown and snapshot creation. `pmx help <topic>` explains both the PowerFlow command and
  the native Proxmox operation it represents.

- 🛡️ **Every PMX mutation crosses one explicit amber safety boundary.** There is no
  `pmx run` escape hatch and no user text is passed to a shell. PowerFlow resolves names to
  authoritative VMIDs, validates the requested end state, shows the exact plan, refuses a
  redirected confirmation prompt, and then re-reads identity and configuration in case the VM
  changed while the operator was deciding. Only fixed allow-listed `qm` operations execute;
  the result is read back and a secret-free JSONL audit record is written. `--dry-run`,
  `--show-native`, `--explain`, `--json` and `--table` keep the workflow inspectable.

- 🧩 **PMX is a component system, not another oversized shell function.** Configuration,
  shared parsing, host views, physical disks, evidence, VM reads, VM changes, snapshots and
  educational help live in responsibility-based components behind a thin command router.
  Matching Windows and Linux adapters own local/SSH transport, while the component layer stays
  platform-neutral and testable. The existing physical-disk, SMART, evidence-bundle and
  destructive capacity-test behaviour is preserved.

- 🧪 **Dedicated PMX regression suites now run on both release platforms.** Dependency-free
  tests cover strict option parsing, one-token routing, virtual/physical disk separation,
  adapter token parity, hostile-input rejection, VM and disk resolution, dry-run and
  cancellation, time-of-check/time-of-use revalidation, execution, postcondition verification,
  physical descendant safety and audit output. A separate Linux test pins authenticated,
  retried GitHub release downloads.

### Fixed

- 🐧 **Ubuntu 24.04 no longer loses Starship during release validation.** The unpublished
  v3.16.2 tag failed because Ubuntu's apt repositories did not provide Starship and the binary
  fallback ignored the workflow's `GITHUB_TOKEN`. Parallel jobs exhausted GitHub's anonymous
  API allowance, then the adapter swallowed the HTTP failure; the later dependency check could
  only report that `starship` was missing. GitHub release requests now authenticate when a
  token is available, retry bounded transient failures, and preserve the actionable request or
  download error. Starship remains required, and the same hardened path benefits real Linux
  installations outside CI.
- 💽 **Physical-disk idle checks include every descendant device identity.** Mount namespaces
  and open handles are checked for partitions and mapped descendants, and missing identities
  fail closed before the destructive capacity workflow.
- 🧭 **Strict PMX routing and identifiers.** One-item token tails remain arrays, short-option-
  shaped values are rejected, and VMIDs with leading zeroes no longer pass the component only
  to be rejected later by the platform adapter.
- 📦 GitHub releases attach `RELEASE_NOTES.md` as a downloadable asset, and the maintainer
  guide now states plainly that `git-rl` runs `git add .` and commits the whole working tree.

## [3.16.1] - 2026-08-04

### Fixed

- 🧱 **`team-room` columns collided when an arm reason was long.** Reported from real output:
  `no-repo-pathtask:Ready` and `armed-in-previous-boottask:Ready`. The arm slot was `{0,-9}`,
  which — as with `Capacity test` in v3.16.0 — is a **minimum** width that .NET never
  truncates, so a 12- or 22-character reason emitted no padding and ran straight into the next
  column. Arm reasons are diagnostic strings, not column values, so the list now shows a short
  tag (`disarmed`, `prev-boot`, `bad-stamp`, `no-repo`) and the **detail view keeps the full
  reason**. Every column now carries an explicit trailing space, and `no task` was one
  character wider than `task:Ready`, so the rows did not line up either.

- 🕰️ **"0 live" beside a moving "ran 2m ago" read as a contradiction.** It was not one — a
  disarmed connector still fires on schedule, and the wake script checks the arm stamp
  *first* and returns `dormant-unarmed` without observing anything — but the list never said
  so, and that explanation existed only in the detail view. A connector that fired while
  disarmed is now labelled **`ticked 2m ago · no-op`**, and when any such room is listed the
  legend explains why the timestamps move while nothing is live. An armed room, or one with a
  live watcher, still reads a plain `ran 2m ago`.

  *Both were found by the repo owner reading real output, not by the test suite — which had
  no assertion that two adjacent columns stay separated. It has one now, over every arm
  reason the adapters can emit plus an unknown future one.*

## [3.16.0] - 2026-08-04

### Added

- 🖥️ **`team-room` — see the agent watchers you started, and stop them.** Until now a team
  room could only be shut down by *asking the agent to shut itself down*. If the agent was
  not listening, was not running, or was the thing you wanted stopped, there was nothing to
  type. `team-room` is the missing control.

  ```
  🖥️  TEAM ROOMS — 2 live of 5

     ●  powerflow       armed · 1 watcher                      live
     ●  zavoya          armed · connector Ready                live
     ○  belief-index    connector Ready · not armed
     ○  Hutano          connector Running · not armed
     ⚠  Hutano-360      connector only — no config in this repo
  ```

  **A room is three independent things, and this command refuses to merge them:** a wake
  connector (a Scheduled Task), a boot-scoped arm stamp, and a live `teamchat-wait` process.
  Any one alone does nothing. Collapsing them into a single "on/off" is precisely why a room
  was impossible to reason about — you could not tell whether anything would happen, and so
  could not tell whether stopping it had worked. **Live** is the derived, honest answer to
  *"will an agent actually wake up?"*, and the detail view shows all three states with the
  reason for each.

  `team-room stop <name>` disarms **and** ends the watcher. `team-room start <name>` re-arms
  a room you set up earlier — arming is boot-scoped by design, so a room armed yesterday is
  correctly inert today and has to be re-armed deliberately.

  **Everything fails closed.** An unreadable stamp, a malformed stamp and a stamp from a
  previous boot all read as *disarmed*, each with its own reason. Rooms whose scheduled task
  exists but whose config does not are surfaced with a warning rather than hidden — an
  invisible orphan is the state that started this. And `Stop-TeamRoomWatcher` re-verifies the
  process is still a `teamchat-wait` immediately before signalling: PIDs are reused, and this
  runs after a confirmation a human may have taken time over.

- ⚡ **`pmx` — Proxmox VE as a PowerFlow command (Linux).** The node dashboard, physical
  disks, ZFS pools, guests, pending updates and SMART, without remembering which of `pvesh`,
  `lsblk -J`, `smartctl -j`, `zpool` or `journalctl -k` answers which question.

  ```
  pmx                     # node: uptime, load, memory, storage, guests, updates
  pmx disks               # every physical disk, health, and what is using it
  pmx disk sdg            # one disk in full — stable IDs, SMART, what would be destroyed
  pmx disk sdg report     # is this drive genuine?
  ```

- 🔎 **`pmx disk <sel> report` — an evidence-based answer to "is this drive fake?"** Built
  against a real counterfeit: a "4 TB SSD" whose model string was literally `SSD 4TB`, whose
  serial was six digits, whose WWN was all zeros, and which dropped off the bus twice.

  The report does not guess. It states which signals fired and what each means — zero WWN,
  generic model, short/absent/numeric serial, a drive that refuses SMART, a size that
  disagrees with itself, reallocated/pending/uncorrectable sectors, media errors, kernel I/O
  errors. **`-Write` saves the bundle** (`report.md`, raw SMART, kernel log, identity JSON,
  tarballed), because a refund request should be a file you attach, not a story you tell.

### Fixed

Six defects below were found by **executing** the Proxmox code rather than reading it. The
component layer never touches an OS API — that is PowerFlow's architecture rule — so all 626
lines of it run on Windows against a faked adapter; and the Linux adapter reaches the OS
through `& smartctl` / `& lsblk`, which PowerShell resolves to a *function* before a binary,
so its parsers run against recorded tool output. The first two were **total failures of the
entire `pmx` subsystem on a real host**, and both had passed a green static-check suite.

- 💥 **`pmx` could not list a disk at all — `$matches` was used as a local.** `Get-PmxStableIds`
  did `$matches = @()` and then ran `-match` inside its loop. `$matches` is a PowerShell
  **automatic** variable that every `-match` overwrites with a Hashtable of capture groups, so
  the next `$matches += $path` threw *"A hash table can only be added to another hash table"*
  and aborted `Get-ProxmoxDisks` — and with it `pmx`, `pmx disks`, `pmx disk <x>`, everything.
  It fired on any host whose `/dev/disk/by-id` contains a `*-partN` link, which is all of them.
- 💥 **`Get-PmxBlockDescendants` recursed forever.** `lsblk` omits `"children"` entirely for
  every leaf partition and every unpartitioned disk, and **`@($null)` is a one-element array,
  not an empty one** — so the loop ran once with `$child = $null`, recursed on `$null`, and
  ended in *"The script failed due to call depth overflow"*. Same blast radius: every disk view.
- 🏷️ **Every `pmx disk` view printed `Capacity testblocked`.** `'{0,-12}'` is a *minimum* width
  and .NET never truncates, so the one label longer than 12 characters emitted no padding and
  no separator. The format string now carries an explicit trailing space, so a long label
  stays readable instead of merging into its value.
- 📛 **The destructive prompt documented the wrong token.** Two user-facing strings promised
  *"typed serial confirmation"* while the gate demands `DESTROY <by-id leaf>` — and the serial
  was printed two lines above the prompt, so the wrong token was the one under the user's eyes.
  A serial names a *product*; the by-id leaf names *this device*. The prose now matches.
- ⌨️ **Pressing Enter to back out of the destructive prompt threw a raw .NET exception.**
  `Read-Host` returns `''`, which a `[Parameter(Mandatory)][string]` refuses, so the most
  likely way to abort produced `ParameterBindingValidationException` instead of the designed
  refusal. It failed closed — but mid-destructive-flow it reads as a malfunction, and the
  reflex when a tool looks broken is to run it again. Now it cancels and says so.
- 🔐 **The last gate was culture-sensitive, not ordinal.** PowerShell's `-cne`/`-ceq` are
  case-sensitive but *culture*-sensitive, and culture comparison gives zero weight to
  characters like `U+00AD` soft hyphen and `U+200B` zero-width space — so a pasted phrase
  containing one compared **equal** to the real one. Confirmed on pwsh 7.5 for three separate
  zero-width characters. The phrase check and all five identity re-checks (serial, size,
  major:minor, diskseq, WWN) now use `[StringComparison]::Ordinal`.
- 🎨 **`ls` broke end-anchored pipelines on Linux.** PowerFlow forced `lsd`'s colour and icons
  on unconditionally, so an invisible ANSI reset was appended after every filename. The
  listing *looked* right — but `ls -l /dev/disk/by-id | grep -E 'sdg$'` found nothing, and
  failed by reporting no such entry rather than by looking broken. Both call sites now pass
  `--icon=auto --color=auto`: full decoration at an interactive prompt, plain text into a pipe
  or a file, which is what GNU `ls` has always done. Covered by a Linux CI regression test
  that lists a **directory** — lsd colours those, so the test genuinely fails on the old code.
- 🧨 **The Proxmox capacity test could never run.** It asked the user to type one phrase and
  the adapter compared against a different one, so the confirmation never matched and the
  probe was unreachable. Both sides now use the same `DESTROY <by-id-leaf>`.
- 🛡️ **The capacity test's identity guard always tripped.** The expected WWN was not passed
  through, so the pre-flight re-check compared the disk's real WWN against nothing and
  reported *identity changed* every time. Now passed — the guard protects instead of blocking.
- 🐛 **`$matches` used as a local variable in two Proxmox renderers.** `$matches` is a
  PowerShell *automatic* variable that every `-match` overwrites; the disk resolver and the
  guest list were reading whatever the last regex had left behind. Renamed to `$hits`.
- ✅ **CI could not see the Proxmox or team-room contracts.** The adapter-parity gate matches
  contract names from a hardcoded list, so a function present on only one platform would have
  shipped and exploded at runtime on the other. All 13 Proxmox and 4 team-room names added.
- 🧹 Dead node lookup removed from `Get-ProxmoxUpdates`.
- 🔒 `pmx help` now works **before** the Proxmox check, so the help text is readable on the
  laptop you are reading about the host from.

- 📄 **f3probe's own verdict was printed and thrown away.** `"Bad news: The device is a
  counterfeit of type limbo"` and the *Usable* vs *Announced* size block are the artefacts the
  whole refund workflow exists to produce; they are now captured and returned as `Output`,
  matching `Start-ProxmoxSmartTest`. Also pinned `$PSNativeCommandUseErrorActionPreference`
  for that call — a counterfeit exits 102, which is a *success* here, and a user whose session
  sets `ErrorActionPreference = 'Stop'` would otherwise be told "device state is unknown"
  about a probe that completed correctly.
- 🧹 **The evidence bundle asserted `"Health":"UNKNOWN"` next to a `smart.txt` reporting
  PASSED.** The disk list is fetched with `--skipsmart 1`, so Proxmox never runs smartctl for
  it and returns the literals `UNKNOWN`/`N/A` for every disk, forever. Both fields had zero
  consumers and are gone; real health comes from `Get-ProxmoxSmartInfo`.

### Changed

- 🛡️ **New CI gate: no automatic variable may be used as a local.** This class produced four
  separate bugs in this repository, one of which shipped past a green test run. Assigning to
  `$matches`, `$args`, `$input`, `$error`, `$host`, `$PID` and friends now fails the release;
  *reading* `$matches` straight after a `-match` is correct and stays allowed. Two pre-existing
  `$input = Read-Host` locals (in `git/release.ps1` and `navigation/bookmarks.ps1`) were
  renamed so the gate can be strict.
- 🧪 **New CI gate: the Proxmox adapter parsers run against recorded `smartctl`/`lsblk`
  output.** CI is not a Proxmox node, but the parsers are pure once the tool output is in
  hand, so the external commands are shimmed as functions and the real adapter bodies execute.
  Both total-failure bugs above are pinned by name. `f3probe` is never defined there, so the
  destructive path cannot run even by accident.
- 📖 The `ls` pipeline CI check no longer claims to prove more than it does: it exercises the
  piped path only, so its message now says exactly that.
- `docs/proxmox.md` and the new design notes carry placeholder addresses only — no real host
  IP appears in the repository. `docs/plan/proxmox/powerflow-pmx.md` is marked **superseded**,
  since it still describes the serial-based confirmation that was deliberately replaced.

### Known limits

- `pmx guests` counts guests **cluster-wide** (`/cluster/resources`) while the dashboard's
  storage line is node-scoped. Invisible on a single node, wrong on a cluster.
- `pmx disk <dev>` enumerates disks three times and walks `/proc/*/mountinfo` for one
  read-only view. Slow on a many-disk or LXC-heavy host, not incorrect.
- `Get-PmxMountNamespaceCheck` compares a whole-disk `major:minor` against mountinfo's
  *partition* `st_dev`, so it cannot fire; the case it would catch is already refused a line
  earlier. It is redundant rather than fail-open — but it is not a safety layer.

## [3.15.0] - 2026-07-29

### Added

- 🎚️ **Memory levels — `pc-whoami -ram` is now a map, not a list.** Listing every program at
  once meant 167 rows, which is unreviewable; an unreviewable list is exactly what should not
  sit near a kill action. The bare command now answers *"where is my memory?"* in five rows:

  ```
  🧠 MEMORY — 167 programs, 24 GB in use of 32 GB

     huge    1 GB and up        5 programs     13 GB   ██████████████████████
     large   250 MB – 1 GB     10 programs      6 GB   ██████████
     medium  50 – 250 MB       28 programs      3 GB   █████
     small   10 – 50 MB        69 programs      2 GB   ███
     tiny    under 10 MB       55 programs    239 MB
  ```

  Then `pc-whoami -ram huge` opens that level — six rows, and it holds 13 of the 24 GB in use.

  **The boundaries were measured, not guessed.** Equal-count bands were tried first and the
  real distribution rules them out: memory is extremely concentrated — the top 5 program groups
  (3% of the list) held 56% of all RAM, while 76 groups under 25 MB held 2.6% between them.
  Five equal slices of ~33 would have put a 6 GB editor and an 86 MB helper in one band, and
  left the bottom two bands as dozens of sub-18 MB entries. Scale bands keep the levels people
  act on — `huge`, `large` — short enough to read at a glance, which is precisely what limits
  blast radius. Levels are half-open `[min, max)` so every program lands in exactly one, and
  the level totals reconcile to the whole population.

  `-min N` remains as the custom cut-off in GB, for when a preset is not the cut you want.

### Removed

- 🔁 **`--ram` is retired**, one release after it shipped. The named levels say the same thing
  more precisely: `-ram small` (10–50 MB) and `-ram tiny` (under 10 MB) replace "everything
  below 0.5 GB", and two overlapping ways to ask one question is clutter. Running `--ram`
  prints what to use instead rather than failing.

## [3.14.0] - 2026-07-29

### Added

- 🔍 **`pc-whoami -ram <name>`** — drill into one program and see its processes individually,
  each with **its command line**. That is the whole point: eight rows all called `java` are
  useless, and only the command line says which one is the runaway.

  ```
  🧠 java — 8 processes · 5 GB total

     31284       1 GB   3.1%   up 2d 4h
                 java -Xmx4g -jar build/libs/service.jar --port 8081
     18220     742 MB   2.3%   up 6h 12m
                 java -Didea.paths.selector=… gradle-daemon
  ```

  From here you can close things, with the scope you choose:
  - **Enter** closes the selected **process**; the confirmation is that PID typed back —
    specific to the one process, where a program name would be equally true of the others.
  - **ctrl-a** closes the **whole program**, warned harder because the blast radius is every
    window at once. Protected processes and your own shell are **filtered out** rather than
    blocking the action, so "close all pwsh" closes the other shells and leaves yours running,
    and it says so before you confirm. Results report per-PID ("Closed 6 of 8").

- 🔎 **`pc-whoami --ram`** — the inverse: programs using **less** than the threshold. A double
  dash means "below", a single dash means "at or above". The list is long by nature, so it is
  sorted biggest-first, capped at 25, and the remainder is **counted** rather than silently
  dropped. `--ram <name>` drills in exactly like `-ram <name>`.

### Changed

- 🧠 **The `-ram` overview is now read-only.** v3.13.0 let you close a whole program straight
  from that list — one keystroke ended 48 VS Code processes, which is far too blunt to sit
  against a list that long. Closing now lives only in `pc-whoami -ram <name>`, where you have
  already seen every process and its command line before choosing.

### Security

- 🔒 **A wildcard could have turned the drill-in into a whole-session kill.** `Get-Process -Name`
  is wildcard-enabled, so `pc-whoami -ram *` listed **all 529 processes** on the test machine —
  **428 of them killable**, including `explorer`, `dwm` and the terminal itself — and `ctrl-a`
  then offered to end them behind a confirmation of *"type the program name"*, where the program
  name **is `*`**. One asterisk, the same character just typed as the argument. Patterns are now
  refused with an explanation, and both adapters match the name **literally** so the contract
  cannot glob even when called directly. (This also removes a crash: an unbalanced `[` threw a
  terminating `WildcardPatternException` that `-ErrorAction SilentlyContinue` does not suppress.)

### Fixed

- 🐛 **`pc-whoami -ram java` used to crash.** With no positional parameter, `java` bound to
  `[int]$days` and the command died with *"Cannot convert value 'java' to type System.Int32"*.
  It now takes a program name. A second positional slot exists because PowerShell has no
  double-dash switch syntax: it parses `--ram` as the literal string `"--ram"` and hands it to
  position 0, which previously left `--ram java` with nowhere to put `java` (*"a positional
  parameter cannot be found"*).
- 🐛 **A recycled PID could have been killed.** Rows are captured before the picker and the
  prompt, so a listed process could exit and the OS reuse its number in that window. Identity
  (name **and** start time) is now re-verified immediately before every kill, in both the single
  and group paths — a reused PID never has the original's start time.
- 🐛 **Truncation made the drill-in useless in its main case.** Command lines were cut from the
  head, and `java` processes share a long identical prefix (JVM path, `-classpath` blob) — so
  eight genuinely different processes rendered as eight byte-identical rows, in exactly the
  situation the view exists to solve. It now trims from the **middle**, keeping the tail where
  the jar, main class and port live.
- ⏱️ **Uptime was rounded up.** `[int]` rounds rather than truncates, so a process up 1d 18h
  printed as `2d 18h`.
- 🔢 **`ctrl-a` promised more than it does.** The header counted every row ("closes ALL 8") while
  the action filters out system-critical processes and your own shell; it now states what will
  actually be closed ("closes 6 of 8 — system-critical and this shell stay"). The success line
  likewise reports only the memory of processes it **actually** closed, not the whole group's.
- 🐧 **Linux session processes are protected**, for the same reason `svchost` is on Windows:
  `Xorg`, `Xwayland`, `gnome-shell`, `plasmashell`, `kwin_*`, `mutter`, `sway`, `Hyprland` and
  the display managers hold real memory, sort high in a memory list, and killing one takes the
  desktop down rather than freeing anything.
- ❓ **Two-word program names** (`Memory Compression` is a real one) were silently split by the
  second positional slot; PowerFlow now shows the quoted form instead of reporting "not running".
  A bare `pc-whoami java` — no `-ram` — used to print the full dashboard and ignore the word
  typed; it now drills in.

## [3.13.0] - 2026-07-27

### Added

- 🧠 **`pc-whoami -ram`** — what is actually holding your memory, and a way to close it:

  ```
  🧠 MEMORY — programs using 0.5 GB or more

     Code                     6 GB   18.4%   48 processes
     java                     5 GB   14.4%   8 processes
     msedgewebview2           2 GB    4.9%   32 processes
     svchost                  1 GB    3.3%   86 processes   🔒 system-critical
     pwsh                   638 MB      2%   6 processes   ← this shell
  ```

  **Grouped by program, not by PID** — that is the whole point. VS Code runs 48 processes on
  this machine, each far under any sane threshold while the app holds 6 GB; a per-process list
  would print "Code 180 MB" forty-eight times and bury the answer. Rows show the share of
  installed RAM and sort biggest-first. `-min N` moves the threshold (default 0.5 GB).

  At a terminal with fzf it then offers a picker to close one. Three safeguards, because this
  is a kill and not a polite close:

  - **System-critical programs are refused outright.** Ending `lsass`, `csrss` or `wininit`
    bugchecks Windows instantly; `svchost` is refused too — 86 processes holding ~1 GB sorts
    it high in a memory list, right next to a kill action, and ending it takes down networking,
    audio and update at once. On Linux, PID 1 is protected *whatever it is called*, along with
    kernel threads and the systemd/dbus plumbing.
  - **The shell you are typing in is refused**, and marked in the list.
  - **Confirmation is the program's name typed back**, after showing the process count, the
    memory and every PID — and the result reports per-PID ("Closed 3 of 4"), because a group
    can partially fail when a process exits on its own or belongs to another user.

  The picker never opens unless there is a human at a terminal — piped, scripted or CI runs
  print the table and stop, so a destructive prompt can never appear where nothing can answer.

## [3.12.1] - 2026-07-27

### Changed

- 🔌 **`pc-whoami`: the storage headroom row is labelled `Ports`, not `Bays`.** A *bay* is a
  mounting position in the case; that row counts connectors on the **motherboard**, so
  "Bays … SATA 6 of 6 free" read as "six places I can put a drive" — which the board cannot
  promise, since you also need a free bay and a spare PSU lead. Two limits SMBIOS genuinely
  cannot express are now documented beside the code rather than implied away: many boards
  **mux M.2 against specific SATA ports** (populating an M.2 can switch a SATA port off), and
  the declared connectors are what physically *exist*, not what is currently *enabled* —
  the board manual's storage table remains the authority.

### Fixed

- 💾 **Zero-size block devices are no longer listed as drives.** Hypervisors and empty card
  readers expose placeholder devices; a Linux run surfaced `Virtual Disk · 0 GB`. A device
  that holds nothing does not get a row, on either platform.
- 💾 **Sub-gigabyte drives no longer render as "0 GB".** The drive-size formatter had no MB
  branch, so a 107 MB volume displayed as `0 GB`. Small drives are still real drives — a USB
  stick belongs in the list, correctly sized (`388 MB`).

## [3.12.0] - 2026-07-27

### Added

- 💾 **`pc-whoami` now reports your drives** — one row each, with what the drive *is*, how
  big it is, and how much is left:

  ```
  Disk     Samsung SSD 970 EVO Plus 1TB · 932 GB · M.2 NVMe SSD · 131 GB free on C:
  Disk     WD My Passport 25E1 · 1.8 TB · USB HDD · 686 GB free on E: · external
  ```

  SSD vs HDD comes from the OS itself (Windows `MediaType`; on Linux the kernel's
  rotational flag), and the **interface** — NVMe / SATA / USB — is what actually separates a
  modern M.2 from an old 2.5" SATA drive. A spinning disk shows its **RPM** when the drive
  reports one. Form factor is *inferred from the bus and labelled as such* (NVMe ⇒ M.2,
  SATA SSD ⇒ 2.5"), because `Get-PhysicalDisk.FormFactor` is blank on real hardware — there
  is no API answer to read, and a spinning SATA disk could be 3.5" or 2.5" with no way to
  tell, so it gets its RPM instead of a guess.

  The boot drive leads, external drives are marked and sort last, free space is attributed
  per drive (via partitions, not a machine-wide total), and a drive under 10% free earns a
  warning pointing at `installed-apps`. Drives are keyed by device ID, never by name — this
  machine has two identically-named NVMe SSDs that grouping by name would have merged.

- 🔌 **Upgrade headroom, read from the motherboard.** How many ports and slots are actually
  free, from the board's own SMBIOS records rather than a hardcoded database of models:

  ```
  Bays     M.2 2 of 4 free · SATA 6 of 6 free
  Slots    PCIe 2 of 3 free · RAM 0 of 4 slots free (max 128 GB)
  ```

  M.2 sockets and SATA ports come from SMBIOS Type 8 port connectors — Wi-Fi/CNVi M.2 keys
  are excluded (they take a radio, not a drive), and SATA connectors are counted from their
  paired designators, since vendors label them `SATA6G_12` for ports 1 *and* 2. PCIe slots
  come from Type 9, which carries a real Available/In-Use flag. Occupancy is counted from the
  drives actually attached, because SMBIOS describes the board, not what is plugged into it.
  On Linux this needs `dmidecode` (hence root, or `sudo -n` which never prompts) and says so
  when it has no access; the drive list itself needs no root.

## [3.11.0] - 2026-07-27

### Added

- 🎮 **`pc-whoami` now reports your GPU** — every real display adapter, on its own row, with
  its full product name. A machine with both an integrated chip and a card shows both,
  labelled apart, because they are different hardware:

  ```
  GPU      NVIDIA GeForce RTX 4080 · 16 GB
  iGPU     Intel UHD Graphics 770
  ```

  Two details that took real hardware to get right. `Win32_VideoController.AdapterRAM` is a
  **uint32, so it wraps above 4 GB** — a 16 GB RTX 4080 reports ~4.29 GB — so VRAM is read
  from the display-class registry key, which is 64-bit. And that same field reports *shared
  system memory* on an integrated chip, which would both invent VRAM the chip doesn't have
  and make the iGPU look discrete; only dedicated memory counts. Streaming/virtual display
  drivers (Virtual Desktop, Parsec, RDP, DisplayLink…) are filtered out, and a card whose
  driver is unhealthy is kept and **flagged** rather than hidden.

- 🧠 **RAM is a spec sheet, not just a number** — type, real speed and stick layout:

  ```
  RAM      32 GB · DDR4-3600 · 4x8GB
  ```

  The speed shown is what the modules are *running* at, not what they are rated for; when
  those differ the row warns that XMP/EXPO may be off — a real and normally invisible
  performance loss. `SMBIOSMemoryType` is used for the type because
  `Win32_PhysicalMemory.MemoryType` reports 0/"Unknown" on essentially every modern board.
  Mixed types or capacities are shown as they are rather than averaged away.

- 🔧 **Motherboard row.** `Get-FirmwareInfo` had carried the board vendor and model since
  v3.4.0 — it was simply never displayed, so `pc-whoami` could tell you your BIOS version
  without telling you which board it was for:

  ```
  Board    ASUS ROG STRIX Z690-A GAMING WIFI D4
  ```

  On Linux this needs no root (`/sys/class/dmi/id` is world-readable). Serial numbers are
  deliberately not read or shown.

  Linux gets the same three rows: GPUs via `nvidia-smi` (authoritative name and VRAM) then
  `lspci`, preferring the bracketed product name (`Navi 31 [Radeon RX 7900 XTX]` →
  "AMD Radeon RX 7900 XTX"). Integrated vs discrete is decided by **PCI topology**, not
  vendor — AMD ships both APUs and cards, so "AMD ⇒ discrete" would mislabel every Ryzen
  iGPU; bus 00 is the root complex where integrated graphics live. RAM type/speed comes from
  `dmidecode`, which needs root, so it is attempted as root or via `sudo -n` (never
  prompting) and otherwise reports the size with a plain reason why there is no more.

### Changed

- 🖥️ **`pc-whoami`: uptime moved to its own row** (`Up`), since RAM now carries type, speed
  and layout. Vendor names are shortened (`ASUSTeK COMPUTER INC.` → `ASUS`) and `(R)`/`(TM)`
  are stripped from CPU and GPU names.

## [3.10.0] - 2026-07-27

### Added

- 🚀 **`start-folder`** — one list of everything that runs at login, and one place to
  change it. The Startup folder is buried (`shell:startup`, or six levels into AppData)
  and it is only *part* of the story: on Windows most autostart entries live in the
  registry `Run` keys. On the machine this was built against, the folder held **one** item
  while the Run keys held **thirteen**.

  ```
  start-folder              # picker: Enter toggles · ctrl-d deletes · ctrl-o opens
  start-folder list         # plain print (also what pipes get)
  start-folder add <path>   # add a program to your Startup folder
  ```

  **Enter toggles rather than deletes**, because "stop this starting up" is what people
  actually want and it is completely reversible. Windows keeps the entry and flips the
  `StartupApproved` flag — the same mechanism Task Manager uses; Linux keeps the
  `.desktop` file and clears `Hidden=true`. Deleting is a separate confirmed key that
  shows the full command first, since a removed registry `Run` value cannot be restored.

  Crucially the list tells the **truth about state**: an entry can sit in `Run` yet be
  disabled by flag, so reading the key alone would report it as starting up when it does
  not. Every row is joined against `StartupApproved` (Linux: `Hidden`). Linux entries are
  XDG autostart; a system entry is shadow-copied into your autostart directory rather than
  edited, because the package owns the original.

### Changed

- ⚙️ **`pwsh-config` now works on Windows — it applies the change instead of telling you
  what to run.** Previously the Windows path printed "change these in Settings, or with
  cmdlets like `Set-TimeZone` / `Rename-Computer`", which is a printed man page, not a
  tool. Timezone, regional format, hostname and network time sync are now read from the
  machine and **set** by PowerFlow, with a single UAC prompt for the machine-wide ones
  rather than a refusal. Keyboard stays Linux-only on purpose: a Windows layout is a
  property of the input-language list, and a wrong value can leave you unable to type.
  Per-setting caveats (e.g. a hostname needing a restart) now come from the adapter and
  are printed after the change.

### Fixed

- ⚙️ **`pwsh-config` refuses a value that isn't on its own list.** `Set-Culture` accepts an
  unknown culture name instead of failing — during testing it wrote a bogus `zz-ZZ`
  regional format — so both the adapter and the menu now validate against the offered
  choices before applying anything.

## [3.9.1] - 2026-07-23

### Fixed

- 🔧 **The "disable update checks" option (Windows) now actually works.** Choosing `4` on
  the PowerShell-update prompt silently did nothing since the v3.0.0 split:
  `Disable-PowerShellUpdateCheck` rewrote `$PROFILE` looking for
  `$script:CHECK_UPDATES = $true`, but that flag moved into `config/PowerFlow.settings.ps1`,
  so the replace matched nothing and the prompt returned every session. It now edits the
  settings file — matching the Linux adapter, which was already correct — so the choice
  persists.
- 🪟 **Store/MSIX PowerShell installs get honest update guidance.** winget lists MSIX
  packages, so a Microsoft Store install was misclassified as "winget-managed" and told to
  "restart your terminal" — but an MSIX package can't be swapped while any of its processes
  are running, so `winget upgrade` only *stages* the new version. PowerFlow now detects the
  Store install, explains the update applies once **every** PowerShell window is closed (or
  after a reboot), and offers the Microsoft Store as an alternative.
- ⌨️ **`pwsh-config` keyboard now works on Debian/Ubuntu.** Those distros ship no vconsole
  keymaps and manage the keyboard through console-setup / X11 layouts, so `localectl
  list-keymaps` returned nothing and the setting dead-ended with "No choices available (are
  locales generated?)" — a message that also wrongly blamed locales. PowerFlow now detects
  which model the machine uses — vconsole keymaps on Fedora/Arch (`list-keymaps` /
  `set-keymap`), X11 layouts on Debian/Ubuntu (`list-x11-keymap-layouts` / `set-x11-keymap`)
  — reads the current layout from the X11 line when the VC keymap is unset, and gives a
  per-setting hint when a list genuinely is empty.

## [3.9.0] - 2026-07-23

### Added

- ⚙️ **`pwsh-config`** — one menu to change OS settings, replacing `dpkg-reconfigure`.
  Browse every setting (with its current value shown) and pick what to change — you don't
  have to know the setting's name:

  ```
  pwsh-config          # menu: keyboard · timezone · locale · hostname · time-sync
  pwsh-config kb       # jump straight to one (kb/tz/loc/host/sync also work)
  ```

  Each pick opens an fzf list (or a prompt), and the change is applied with `sudo`. Built
  on **systemd** (`localectl` / `timedatectl` / `hostnamectl`), so it behaves the same on
  Fedora, Debian, Ubuntu, Arch and openSUSE — unlike `dpkg-reconfigure`, which is
  Debian-only and silently does nothing when debconf has no dialog frontend (the original
  "I ran it and nothing happened"). Adding a new setting later is a single row in the
  adapter — the menu picks it up automatically.

  On Windows there's no systemd; the command says so and points at Windows Settings /
  `Set-TimeZone` / `Rename-Computer`.

- 📖 **`pwsh-h` is now a manual you read**, with the searchable browser one flag away.
  Plain `pwsh-h` prints a quiet, grouped reference — the whole command set folded into a
  handful of chapters (Navigation · Files · Git & GitHub · Learn Linux · System & Disk ·
  Setup & Config) — meant to be scrolled top to bottom like a page. The interactive fzf
  finder that used to be the default moved to **`pwsh-h -a`** (and **`pwsh-help -advanced`**,
  a new long alias). Filtering is unchanged: `pwsh-h git`, `pwsh-h chmod`. Both views still
  render from the command registry, so neither can drift from the code.

### Changed

- 🌐 **`pwsh-config` locale** now shows the bare value (`en_US.UTF-8`) instead of
  `LANG=en_US.UTF-8`, matching every other setting and the picker's own choices.

### Fixed

- 🌐 **`pwsh-config`** no longer lets you pick a setting it then refuses to apply: the menu
  and its prompts now agree on what counts as an interactive terminal, so `pwsh-config kb`
  in a non-tty context reports "run it in an interactive shell" instead of a misleading
  "Cancelled." A hostname typed with a leading `-` (or surrounded by spaces) is now passed
  through correctly rather than being read as a flag.

### Security

- 🔒 **Privacy scrub.** Replaced remaining occurrences of a real username used as example
  text with the `you` placeholder — across the Linux lessons (`chown`/`id`/`groups`/`getent`
  output), the teaching layer, two code comments, this CHANGELOG's historical `[3.3.0]`
  section, and a few planning docs. Also **untracked `.claude/settings.local.json`** (a
  machine-local editor permissions file that had been committed, leaking a local path) and
  added a `.gitignore` so it can't return. The v3.6.1 scrub only covered the `srv`
  `user@ip` examples; this finishes the job for the shipping tree.

---

## [3.8.0] - 2026-07-21

### Added

- 🐚 **`pwsh-exit`** — step out to bash **without closing your SSH session.** With
  `--auto-login` on, PowerFlow is your login shell — the `~/.bashrc` hook runs `exec pwsh`,
  which *replaces* bash — so a plain `exit` ends the whole connection (there is no bash
  underneath to fall back to; that's why `exit` disconnects you). `pwsh-exit` starts one:
  you land at a bash prompt with the connection still up, PowerFlow stepped aside. `pwsh`
  brings it back, `exit` from that bash ends the session. Linux only — on Windows PowerFlow
  isn't your login shell, and the command says so.

---

## [3.7.0] - 2026-07-21

> 🎨 **The prompt and `ls` finally have their font**, and starting PowerFlow on login is
> now one short word.

### Added

- 🎨 **A Nerd Font is now actually installed.** Starship and lsd draw with Nerd Font
  glyphs; without one you got tofu boxes or — on Fedora — Chinese characters from CJK
  fallback, with lsd's icons overlapping filenames. The README had claimed "FiraCode Nerd
  Font auto-installed" for years; **nothing ever installed it, on any platform.** Now it
  does: Scoop's nerd-fonts bucket on Windows, a direct download to `~/.local/share/fonts`
  + `fc-cache` on Linux — tracked in the manifest so uninstall removes it (but never a
  font you already had). The **Mono** variant, deliberately — single-cell glyphs are what
  stop lsd's icons from encroaching on filenames.

  - **`pwsh-font`** — install it (if missing) and print the one step no tool can do for
    you: pointing your terminal emulator at the font. `pwsh-font -status` just reports.

- 🔑 **`--auto-login`** — a short alias for `--login-shell auto`. Start PowerFlow on login
  straight from the install one-liner:
  ```bash
  curl -fsSL …/install.sh | bash -s -- --auto-login
  ```

- 🔑 **`pwsh-autologin`** — turn login-launch on or off from inside a running session, with
  no installer re-run. `pwsh-autologin` enables it, `pwsh-autologin off` disables it,
  `pwsh-autologin status` reports. It writes the **byte-identical** guarded `~/.bashrc`
  block the installer does. On Windows there is no login-shell hook to toggle (pwsh always
  loads `$PROFILE`), and the command says so rather than pretending.

### Fixed

- 🔒 **The login hook now survives a *broken* pwsh, not just a removed one.** The guard
  previously only checked `command -v pwsh` (does it exist on PATH). A pwsh that exists but
  crashes on start — the classic missing-ICU case the installer already guards against
  elsewhere — would `exec pwsh`, crash, and terminate the session, re-crashing on every
  fresh login: an effective lockout on a headless box. The guard now also runs
  `pwsh --version`, so a broken pwsh falls through to bash. Applies to both
  `install.sh --auto-login` and `pwsh-autologin` (they write the identical block).

- 🔒 **`pwsh-autologin off` can't eat your `~/.bashrc`.** Removal now only deletes a
  marker→`fi` block that actually contains `exec pwsh`, so a comment of yours that merely
  mentions the hook — or a `~/.bashrc` where the marker never really wrote a hook — is left
  untouched. The installer's own `sed` removal was hardened the same way (framed-comment
  anchor, CR-tolerant).

- 🔒 **A failed dependency install is no longer recorded as PowerFlow-owned.** The manifest
  used `(-not $preExisting) -or $weOwnIt`, which marked ownership whenever a tool/font was
  merely *absent* at the start — even if the install then failed. On Windows that could
  make uninstall remove a font you later installed yourself. Ownership is now recorded only
  on an actual successful install (or a prior owned record).

- 🎨 **Font detection matches the Mono variant specifically.** A pre-existing non-Mono
  `FiraCode Nerd Font` no longer counts as "installed" — otherwise the Mono variant that
  actually fixes lsd's icon overlap would never get installed.

  *(These four were found by an adversarial review pass over the feature before release.)*

---

## [3.6.1] - 2026-07-19

### Fixed

- 🔒 **Example text no longer contains a real username and server address.** The `srv`
  hints, examples, README, CHANGELOG and logs used a genuine `user@ip` where a
  placeholder (`you@192.168.1.50`) teaches identically. The v3.6.0 archive shipped
  before the scrub, so this release re-cuts from the cleaned tree. The release
  checklist now greps the staged diff and description for real IPs/usernames before
  every cut.

---

## [3.6.0] - 2026-07-19

### Fixed

- 🚨 **The documented Windows install was broken.** `irm …/install.ps1 | iex` died with
  *"Cannot bind argument to parameter 'Path' because it is an empty string"* right after
  printing the install location. Under `iex` there is **no script file**, so
  `$PSScriptRoot` is empty, and the local-checkout probe fed that emptiness to
  `Join-Path`. Guarded — a no-file context now falls through to the download path, which
  is what the one-liner always meant. Reproduced against the published v3.5.0 asset in a
  sandboxed `$PROFILE`; verified fixed the same way (download → full tree → manifest).
  The release checklist gains the Windows twin of the `curl | bash` item: the piped form
  of an installer is the *documented* form, and must be exercised as such.

### Added

- 🌐 **The `srv` picker is now a manager, not just a launcher.**

  ```
  Enter    connect          ctrl-d   delete (confirms first)
  ctrl-r   rename           Esc      close
  ```

  After a delete or rename the picker reopens with fresh statuses. And
  **`srv rename <old> <new>`** exists as a command too — the record travels intact
  (host, port, added date, **last seen**), which is the whole reason rename beats
  `rm` + `add`: re-adding would re-probe and lose the history that tells you when an
  offline server was last alive.

---

## [3.5.0] - 2026-07-19

> 📖 **pwsh-h is no longer a hand-drawn wall — it is generated, browsable, and cannot
> drift from the code.** Plus: 🌐 **`srv` — named SSH connections with live status.**

### Added

- 🌐 **`srv` — servers by name, not by memorised IP.**

  ```
  srv add proxmox you@192.168.1.50    tested before saving
  srv proxmox                            connect by name
  srv                                    fzf picker, online servers first
  srv list · srv rm <name>
  ```

  **The status check probes the SSH port, not just ping** — because the question is
  "can I ssh in?", not "is it on?". That yields *three* states, and the middle one is
  the one ping cannot see:

  | | |
  |---|---|
  | `✅ online` | the port accepts — connect |
  | `🟡 host up, ssh not answering` | machine on, **sshd down or blocked** — restart the service |
  | `⛔ offline · last seen Jul 17` | nothing answers — **go turn it on** (or the IP is mistyped) |

  `srv add` runs the same probe before saving, so a typo'd address is caught at entry;
  a genuinely powered-off server can still be saved after confirming. All prompts are
  pipe-safe (piped stdin refuses with an explanation rather than hanging — the
  installer's old bug class). Offline entries show **last seen**, the picker sorts
  online-first, ports are per-server (`user@host:2222`), and the server list survives
  uninstall like bookmarks do (`-Purge` removes it). `ssh` itself is never wrapped or
  shadowed — the coreutils principle.

### Changed

- 📖 **`pwsh-h` rewritten around a command registry.** The old menu was a 350-line wall
  of hand-padded box characters in a file far from the commands it documented. An audit
  found 4 commands missing and one row **actively false** (`ls -t` documented as "tree
  view" a full version after 3.3.0 made `-t` the GNU time-sort), and 11 rows had drifted
  off the 80-char grid from emoji-width bugs.

  Now every component declares its own commands beside their definitions:

  ```powershell
  Register-PFCommand -Name 'nav' -Aliases @('z') -Section '🧭 SMART NAVIGATION & BOOKMARKS' `
      -Synopsis 'fuzzy-find and jump to a project (4 levels deep)' -Example 'nav chess-guru'
  ```

  and `pwsh-h` renders from that data — alignment is arithmetic, sections are generated,
  and platform filtering is automatic (`del`/`mvf` appear on Linux, terminal tabs only on
  Windows, empty sections vanish).

- 🔎 **Bare `pwsh-h` opens an fzf browser** — type to filter all ~130 entries, preview
  pane shows synopsis + example + platform, Enter prints the detail view. Piped output,
  scripts, and fzf-less machines get the generated print automatically; `pwsh-h -all`
  forces it. Filtering got sharper too: `pwsh-h git` (section), `pwsh-h pc-cap` (command
  detail), `pwsh-h chmod` (routes to the lesson), `pwsh-h clipboard` (substring search
  over names *and* synopses).

- 🚧 **CI now fails a release if a user-facing command has no registration** — the
  "missing from pwsh-h" class is extinct the same way shadowed coreutils are. The gate is
  case-sensitive on purpose: PowerShell regex is case-insensitive by default, and a bare
  `[a-z]` would have swallowed every internal Verb-Noun helper into the requirement.

### Fixed

- 📝 Four commands that had quietly fallen out of the old menu (`clr`, `git-aa`,
  `removefile`, `unalias`) are documented again — by construction, this time.

---

## [3.4.0] - 2026-07-17

> 🖥️ **`pc-whoami` — the machine's vital signs on one screen.** Born from a real
> diagnosis session (CPU throttling + WHEA crashes) that took seven hand-typed
> incantations and an AI to decode. It is one command now.

### Added

- 🖥️ **`pc-whoami`** — power plan, CPU cap, hardware errors, crash dumps, BIOS age. One
  screen, triage-first: **green stays silent, every ⚠️ names the flag that drills in.**
  No hex (`0x55` renders as `85%`), no GUID aliases, no event-provider names.

  ```
  🔌 POWER
     Plan     GameTurbo (High Performance)   ⚠️ custom/OEM plan — not a system default
     CPU cap  85%                            ⚠️ full speed is being withheld
  💥 STABILITY (last 7 days)
     HW errors 4   ⚠️ the hardware itself reported faults
  ```

  - `pc-whoami -power` — every plan (custom/OEM ones flagged — stock plans are matched by
    **GUID**, because names are localised), caps decoded, AC/DC split shown only on
    machines that actually have a battery.
  - `pc-whoami -crashes` — WHEA/hardware errors, bugchecks, dump inventory.
    `-export` writes the raw evidence bundle (WHEA XML, bugcheck text, dump list) to a
    folder you can hand to whoever is helping you. `-days N` widens the window.
  - `pc-whoami -bios` — firmware version, **computed age**, board model, and the exact
    search string for updates. Deliberately no vendor-site scraping: a diagnostic tool
    should not depend on ASUS's HTML.
  - Honest degradation everywhere: an unelevated session says the minidump folder
    *"needs an elevated session to list — 0 here does not mean 0 exist"*; a container
    with no cpufreq says so instead of inventing a governor; an unreadable journal is
    *"unknown, not zero"*.

- 🔒 **`pc-cap`** — cap the CPU's maximum speed, with **guaranteed restoration**:

  ```
  pc-cap 85          cap at 85% — records the prior state to disk FIRST
  pc-cap restore     put back exactly what was recorded, verify, then forget
  ```

  Born from a real incident: a script capped a CPU at 85% "temporarily", its cleanup never
  ran, and the machine stayed throttled with no record of the original values. So:

  - The prior plan + values are written to `~/.powerflow-power-state.json` **before**
    anything changes — if the process dies mid-way, the truth is already on disk.
  - A second `pc-cap` **refuses** while a record exists: 100→85→70 must never make
    "restore" mean 85.
  - Restore **verifies by re-querying** (`powercfg` exit codes lie by omission) and only
    then deletes the record. A failed restore keeps it.
  - `pc-whoami` shows a banner for as long as the record exists — an abandoned cap
    cannot go unnoticed.

- 🐧 **Both platforms, per the architecture.** Windows: `powercfg` / WHEA / CIM /
  minidumps. Linux: cpufreq governor + `scaling_max_freq`, kernel MCE via `journalctl`,
  `/sys/class/dmi/id` for firmware (readable without root), `/var/crash`. Six new adapter
  contract functions, parity-checked by CI.

### Fixed

- 🚨 **The startup updater's "Install now" would have BROKEN the install.** It was a
  pre-2.0 relic: it downloaded **only** `Microsoft.PowerShell_profile.ps1` and overwrote
  `$PROFILE` — on the component layout that means a *new bootloader loading old
  components*, and since the version lives in `config/` (never touched), the "updated"
  install still reported the old version and **re-prompted every day, forever**.
  `powerflow-update` now runs the real installer in a child `pwsh` — full tree, manifest
  respected, ownership preserved (`-NoDeps` no longer erases the dependency records).

- 🔕 **The startup prompt can no longer hang or spam a piped shell.** With redirected
  stdin (scripts, tooling that forgot `-NoProfile`) `Read-Host` read EOF, fell through,
  and — because the fall-through branch never wrote the daily marker — the check re-ran
  on *every* load. Non-interactive loads now get one quiet line and a one-day snooze.

- 🌐 **Update checks no longer spend GitHub API quota.** The `releases/latest` redirect
  on github.com resolves the newest tag without touching `api.github.com` — the same
  anonymous API call that killed the v3.3.2 release. The API remains only as a fallback,
  with the existing 3-day cooldown on 403.

### Added (update flow)

- 😴 **Defer options that actually defer.** The prompt now offers **Install now · Remind
  me tomorrow · Snooze for a week · Turn off reminders** — the snooze marker holds a real
  date instead of only ever meaning "until midnight".

### Fixed (installer)

- 🌐 **The installer no longer dies to GitHub API rate limits.** The tarball path asked
  `api.github.com` for the latest PowerShell release; anonymous calls from shared CI
  runner IPs get 403'd, and that exact 403 silently killed the v3.3.2 release for three
  days. Three layers now: the `releases/latest` **redirect** on github.com (the website,
  not the API — resolves the tag with no rate limit), then the API **authenticated** when
  `GITHUB_TOKEN` is present (CI passes it), then a pinned known-good version, loudly, so
  an outage degrades instead of aborting. Verified on Arch — the leg that failed.

### Changed

- 🚧 **The architecture gate got stricter.** `powercfg`, `Get-CimInstance`, `Get-WinEvent`
  and `$env:SystemRoot` are now forbidden in `components/` alongside the existing list —
  the health feature routes all of them through adapters, and CI now keeps it that way.

---

## [3.3.2] - 2026-07-14 · published 2026-07-17

> Tagged Jul 14; its release run failed on a transient GitHub API rate-limit (the Arch
> leg's anonymous `api.github.com` call got a 403) and sat unnoticed for three days.
> Re-run and published Jul 17. The 3.4.0 installer no longer depends on that API call.

> 🚨 **Upgrading via `curl … | bash` was impossible.** If you already had PowerFlow, the
> installer asked a question nobody could answer, then cancelled.

### Fixed

- 💥 **`curl … | bash` could not upgrade an existing install.**

  ```
  ⚠️  A PowerShell profile already exists.
  Overwrite it? (y/n):
  ❌ Installation cancelled
  ```

  Two bugs, stacked:

  1. **It was asking about its own profile.** The check was `Test-Path $profilePath` — any
     profile at all. But if PowerFlow is already installed, that profile *is PowerFlow's*.
     This is an **upgrade**, and asking "overwrite it?" is asking whether you would like to
     install the thing you just asked to install. It now recognises its own manifest and
     simply says `🔄 PowerFlow v3.3.1 is already installed — upgrading it.`

  2. **`Read-Host` cannot be answered through a pipe.** In `curl … | bash`, stdin is the
     pipe curl already drained, so `Read-Host` reads EOF and returns `""`. `"" -ne 'y'`, so
     the install cancelled — **it could never have succeeded that way**, and it never said
     why. When there is no terminal, it no longer pretends to ask: it explains, and gives
     you the exact command (`| bash -s -- --yes`).

- 💥 **The installer exited 1 after succeeding.** With no `--yes`, `install.sh` prompted for
  the login-shell choice. Piped, `read` hits EOF and returns non-zero — and under
  `set -euo pipefail` that killed the installer **after** it had already printed
  `🎉 PowerFlow installed!`. A successful install that reports failure is a good way to make
  someone distrust an installer that worked. It now skips the question when there is no
  terminal (`[[ ! -t 0 ]]`), leaves your login shell untouched, and tells you how to enable
  it (`--login-shell auto`).

- 📖 **The uninstall instructions were wrong.** They were Windows-only, told you to
  `Remove-Item $PROFILE` by hand — which bypasses the manifest, orphans the component tree
  and the dependencies, and destroys the only record of which tools were *yours* — and had
  no Linux section at all. Rewritten. The installer now also prints the uninstall command
  when it finishes.

  Note that **`bash install.sh --uninstall` only works if `install.sh` is on disk**, and the
  documented install (`curl … | bash`) leaves no file behind, so it fails with
  `No such file or directory`. Use `powerflow-uninstall`, or
  `pwsh -NoProfile -File ~/.config/powershell/uninstall.ps1`.

---

## [3.3.1] - 2026-07-14

> The last member of the family that produced 3.3.0's `touch` / `rm -rf` / `mkdir` bugs.

### Fixed

- 💥 **`mv a.txt b.txt` silently did nothing on Windows.** The most basic operation in any
  shell. PowerFlow's `mv` is a cut/paste workflow (`mv <file>` holds it, `mv-t` pastes),
  so with two arguments it joined them into the single filename `"a.txt b.txt"`, found no
  such file, and gave up without a word. `mv report.pdf ~/Documents/` did nothing either.

  **One argument still cuts. Two or more is now a real move.**

  ```
  mv old.txt new.txt          rename
  mv report.pdf ~/Documents/  move into a folder
  mv a.txt b.txt dest/        move several into a directory
  mv -f src dst               overwrite without asking
  mv -n src dst               never overwrite

  mv belief-index             ✂️  still cuts — then navigate, then mv-t
  ```

  Overwriting **prompts unless `-f`**, which follows PowerFlow's `rm` rather than GNU
  (GNU clobbers silently). Consistency inside PowerFlow beats strict parity, and safety is
  the right direction in which to differ.

  Guarded against the obvious ways this goes wrong: `mv same.txt same.txt` refuses instead
  of deleting the file; `mv f.txt notadir/` refuses rather than creating a stray *file*
  called `notadir`; and `mv my report.txt` — an unquoted name with a space — still **cuts**
  `my report.txt`, because that reading is only chosen when it is the unambiguous one (the
  joined name exists and the first word does not). `mv a.txt b.txt` is unaffected.

  *(Windows only — on Linux `mv` has always been the GNU binary. PowerFlow's version, which
  is exposed there as `mvf`, gains the same move form.)*

---

## [3.3.0] - 2026-07-14

> 🐧 **PowerFlow now behaves like a real shell on Linux — and teaches you Linux while you
> use it.**
>
> **Includes everything from 3.2.0**, which was tagged but never published — its release
> workflow failed and the fixes for that failure are in this release. Upgrading from 3.1.x
> gets you both.

### Fixed

- 🚨 **`touch` DESTROYED existing files on Windows.** Read that again.

  ```powershell
  function touch { param($f); New-Item -ItemType File -Path $f -Force }
  ```

  `New-Item -Force` on a file that **already exists** truncates it to zero bytes. So
  `touch README.md` — a completely ordinary thing to type — silently emptied README.md.
  Verified: a 42-byte file, `touch`ed, came back 0 bytes with its contents gone.

  GNU `touch` never does this. It updates the *timestamp*; creating the file is what it
  does only when the file is **absent**. That is now what PowerFlow's does, and an
  existing file is never rewritten. `-c` (never create) is supported.

  *(Windows only — on Linux `touch` has always resolved to the GNU binary.)*

- 💥 **`rm -rf <dir>` HUNG THE SHELL on Windows.** `rm` declared `param([switch]$f)`, so
  `-rf` matched nothing, fell through into the *filename* list, and `-f` was never seen.
  The confirmation prompt then fired and `Read-Host` blocked — forever, in any
  non-interactive context. `mkdir -p a/b/c` threw outright (*"the parameter name 'p' is
  ambiguous"*). Both are the same root cause as the `ls` bug below: **a `param()` block
  makes PowerShell bind `-r`/`-p`/`-f` as parameter names.**

  `rm`, `mkdir`, `touch` and `rmdir` now hand-parse `$args`, so GNU flags work as written:

  | | |
  |---|---|
  | `rm -rf node_modules` | recursive + force, no prompt |
  | `rm <dir>` (no `-r`) | **refuses**, exactly like GNU — a typo'd path should not take a tree with it |
  | `mkdir -p src/components/ui` | creates the whole chain |
  | `touch -c maybe.txt` | bump the timestamp, but never create |
  | `rm -- -rf` | delete a file genuinely *named* `-rf` |

  Bundled shorts (`-rf`), long flags (`--recursive`), and `--` all work.

- 💥 **`mkdir` rejected digits and slashes.** Its validation was `^[a-zA-Z ._-]+$`, so
  `mkdir v2` **threw** (a digit), and `mkdir src/app` **threw** (a slash). It also joined
  its arguments with spaces, so `mkdir a b` produced a single directory named `a b`. Now:
  one directory per argument, and only characters the *filesystem* actually forbids are
  rejected.

- 💥 **`rmdir` mangled any path containing "rmdir".** It read `$MyInvocation.Line` and did
  a string `.Replace("rmdir", "")` on it — so `rmdir ./rmdir-tests` tried to remove
  `./-tests`. It also could not see flags at all. Rewritten to parse `$args`.

- 💥 **`ls` silently listed the WRONG DIRECTORY.** Same root cause as the two above.

  ```
  ls -ld ward-a
    GNU:        drwxr-xr-x 2 you media 4096 ... ward-a
    PowerFlow:  <listed the current directory instead>
  ```

  `ls` declared a `param()` block (`$path`, `$t`, `$d`) and **no `[CmdletBinding()]`**.
  PowerShell therefore tried to bind `-l` as a *parameter name*, failed, and **silently
  dumped it — and the path — into `$args`, where they were discarded**. No error.

  Worse, two flags actively **contradicted** GNU:

  | Flag | GNU means | PowerFlow meant |
  |---|---|---|
  | `ls -t` | sort by **time** | tree view |
  | `ls -d` | the **directory itself**, not its contents | tree depth |

  So `ls -t` on Linux quietly produced a *tree* instead of a time-sorted list.

  **The rule now: single dash belongs to Linux; long dash belongs to PowerFlow.**
  `ls -l -a -d -h -R -t -S -r -i` all mean exactly what they mean on Linux.
  PowerFlow's extras moved to `--tree` and `--depth`, which GNU `ls` does not have and so
  can never collide. (Not `--t` — in Linux `--` introduces a *long* flag, so `--t` would
  teach the wrong convention.)

- 💥 **`nav` was completely non-functional on Linux.**

  ```
  ❯ nav linux lab
  ❌ No directories found in /home/you\Code
                                          ↑ a literal backslash
  ```

  `nav` built its search root as the string `"$HOME\Code"`. On Windows that is a path.
  On Linux it interpolates to `/home/you\Code` — and because a backslash is a perfectly
  legal **filename character** on Linux, not a separator, this is not an error. It is a
  request for a directory that has never existed. `nav` dutifully searched it, found
  nothing, and said so. Every default bookmark (`~\Documents`, `~\Pictures`, …) was built
  the same way, so **every one of them was dead on Linux too**.

  Underneath sat a second bug: the bookmark-context logic compared paths with
  `TrimEnd('\')` and `StartsWith($bmPath + '\')`. On Linux that separator never appears,
  so "am I inside a bookmark?" was permanently false — silently, with no symptom.

  All path handling now goes through `Join-Path` and
  `[IO.Path]::DirectorySeparatorChar`. Path comparison is case-insensitive on Windows and
  **case-sensitive on Linux**, where `/home/Foo` and `/home/foo` are genuinely different
  directories.

- 🔖 **Default bookmarks no longer point at directories that do not exist.** A headless
  server has no `~/Pictures` and no `~/Code`; PowerFlow bookmarked them anyway. Defaults
  are now filtered by `Test-Path` at first run, and `~` is always among them.

- 💥 **`defaultmode` (umask) never worked at all.** It printed *"'umask' is not available
  on this system"* every single time — because `umask` is a **shell builtin, not a
  binary**. There is no `/usr/bin/umask` to execute, and `sh -c 'umask 022'` sets the umask
  of a subshell that immediately exits, changing nothing. It has to be done in-process, so
  the perms adapter now calls libc's `umask(2)` directly (verified on glibc *and* musl).

  `defaultmode` also now shows what the mask actually *produces*, since a umask is
  **subtractive** and that is the part everyone gets wrong:

  ```
  ❯ defaultmode 027
    umask 0022 → 0027   new files 640, new dirs 750
    🐧 real linux command: umask 027
  ```

  (A trap worth knowing: `umask(2)` has **no getter**. It always *sets*, returning the
  previous value — so reading it means setting `0` and restoring immediately. Skip the
  restore and every file the shell creates from then on is world-writable.)

- 💥 **Re-running the installer permanently disabled its own cleanup.** The manifest
  recorded `installedByPowerFlow = (-not $preExisting)` — but on a *second* install every
  tool is present **precisely because the first install put it there**. So each re-install
  quietly flipped `starship`, `fzf`, `zoxide` and `lsd` to "the user already had this", and
  `uninstall` then correctly honoured a manifest that had become a lie, leaving all of them
  behind forever.

  Ownership is now carried forward from the previous manifest. The safety guarantee is
  unchanged and still verified in CI in **both** directions: a tool PowerFlow installed is
  removed; a tool that was already on the machine (`git`, on the runner) is never touched.

- 💥 **Re-installing then uninstalling left a dead profile behind.** `install.ps1` backed
  up *any* existing profile — including PowerFlow's own. So on a second install the
  "backup" was a copy of PowerFlow, and `uninstall.ps1`, which restores the backup,
  put PowerFlow back **after** deleting `components/` and `platform/`. The result was a
  profile that errored on every single shell start. Install now backs up only what it did
  not write, and keeps pointing at your genuine pre-PowerFlow backup across re-installs.

- 🐧 **`install.sh` could not be run twice.** It copied the whole source tree into
  `~/.local/share/powerflow` with `cp -r`, **including `.git/`**. Git's loose objects are
  mode `444`, so the second run could not overwrite them; `cp` failed, `set -euo pipefail`
  aborted, and the installer died in a wall of *Permission denied*. Re-running the
  installer from a clone — the normal way to change your mind about `--login-shell` — was
  therefore impossible. `.git`, `.github`, `node_modules` and `assets/` are now excluded.

- 📦 **A Linux install was 60 MB; it is now 1.3 MB.** `assets/` — 58 MB of README
  screenshots that nothing reads at runtime — was being copied into every install. The
  Windows installer never shipped it; now neither does the Linux one.

- 🧰 **`install-gui.sh` built its arguments by string-splitting** (`--yes $NO_DEPS_FLAG
  $LOGIN_FLAG`), so a flag whose value contained a space depended on word-splitting to
  land correctly. Now an array (`"${INSTALL_ARGS[@]}"`), which passes exactly the
  arguments intended and nothing else. (shellcheck SC2086 — it was right.)

### Added

- 📍 **`nav roots` — configurable search roots.** `nav` no longer assumes your work lives
  in `~/Code`.

  ```
  nav roots              # show where nav looks
  nav roots add /srv     # also search /srv  (or /opt, /mnt/data, …)
  nav roots rm  /srv
  nav roots reset
  ```

  Defaults: **`~/Code` on Windows** (unchanged), **`~` on Linux** — which already contains
  `~/Code`, `~/linux-lab` and anything else you actually work in.

  **The default is deliberately not `/`.** Scanning `/` walks `/proc`, `/sys`, `/dev` and
  `/run` — kernel-backed pseudo-filesystems, not directories in any useful sense — and
  hits permission errors across most of the rest. On a bare Debian container `/` holds
  ~1,600 directories to `$HOME`'s 5, and a real server is far worse; you would wait
  seconds to fuzzy-match against mostly noise. Those paths are now skipped outright even
  if you do add `/`. Add the roots you actually want instead.

  With more than one root, the picker shows each entry under its real root
  (`~/linux-lab`, `/srv/media`) so two same-named directories are never ambiguous.
  If your current directory is inside a bookmark, that bookmark still wins — it is a
  better guess at what you meant than any global scan.

- 🎓 **A Linux teaching layer.** `perms <path>` explains a file's permissions — including
  **which column is which**, the thing that is genuinely hard to remember:

  ```
    d : rwx : rwx : r-x   2   you   media   4.0K   Jul 14 12:05   ward-a
    ╷    ╷     ╷     ╷    ╷     ╷       ╷
    │    │     │     │    │     │       └── GROUP  · members of 'media'
    │    │     │     │    │     └── OWNER  · the user who owns it
    │    │     │     │    └── hard links
    │    │     │     └── others · r-x = read + enter
    │    │     └── group  · rwx = read + write + enter
    │    └── owner  · rwx = read + write + enter
    └── type · d = directory

    🔢 numeric : 775          chmod 775 ward-a
    🐧 real linux command : ls -ld ward-a
    💡 On a DIRECTORY, x means 'may enter', not 'may run'.
  ```

  Colon-separated (`d:rwx:rwx:r-x`) because the three triads are the whole point and
  `drwxr-xr-x` runs them together.

- 🎚️ **`linux-lessons full | hint | off`** — teaching is a phase, not a permanent state.
  `off` produces byte-identical GNU output. Persisted to settings; defaults to `full` on
  Linux and `off` on Windows (nobody on Windows is learning `chmod`).

- 👬 **Brother commands.** Full-word twins of cryptic Linux names — **same flags, same
  result** — that always print the real command, so you build muscle memory for `chmod`
  while typing `changemode`:

  | | | | |
  |---|---|---|---|
  | `changemode`→`chmod` | `changeowner`→`chown` | `changegroup`→`chgrp` | `defaultmode`→`umask` |
  | `whoamifull`→`id` | `mygroups`→`groups` | `lookupentry`→`getent` | `findtext`→`grep` |
  | `findfile`→`find` | `listprocs`→`ps` | `stopproc`→`kill` | `service`→`systemctl` |
  | `fileinfo`→`stat` | `makelink`→`ln` | `firstlines`→`head` | `lastlines`→`tail` |
  | `dirsize`→`du` | `diskfree`→`df` | `listdisks`→`lsblk` | `listports`→`ss` |
  | `systemlogs`→`journalctl` | `archive`→`tar` | `removefile`→`rm` | `listfiles`→`ls` |

- 📖 **24 lessons across 7 topics** — `permissions`, `files`, `text`, `disk`, `network`,
  `processes`, `archives`. The nine added here are the ones you reach for when something
  is actually broken at 3am:

  | | |
  |---|---|
  | `lesson df` | *"No space left on device" but `df` shows free space? Check `df -i` — you are out of **inodes**.* |
  | `lesson ss` | *Connection refused from another machine but fine locally? The service is bound to `127.0.0.1`, not `0.0.0.0`. Nothing to do with the firewall.* |
  | `lesson journalctl` | *`systemctl status` shows the last ten lines and everyone stops there. The answer is nearly always further back: `journalctl -u X -e`.* |
  | `lesson ln` | *Target FIRST, link second — backwards is the classic mistake, and it will happily create a link pointing at nothing.* |
  | `lesson tail` | *`-F` over `-f` on anything logrotate touches, or you follow a deleted file forever.* |
  | `lesson du` · `lesson lsblk` · `lesson head` · `lesson stat` | |

- 📚 **`lesson <command>`** — learn any Linux command. It **runs nothing**, so it is always
  safe, even for `rm`. Shorthand `l`, and it tab-completes:

  ```
  lesson chmod          # the real command
  l grep                # shorthand
  lesson changemode     # the brother name finds the same lesson
  lesson permissions    # every lesson in a topic
  lesson                # the full index
  ```

  **Why a verb and not `chmod -lesson`.** `chmod -lesson` would require PowerFlow to define
  a *function* named `chmod` — PowerShell gives no other way to see a native command's
  arguments. That was built, and then removed, because a function is not a transparent
  stand-in for a binary: **it does not forward stdin**, so a wrapped `grep` would make
  `cat access.log | grep ERROR` start the real grep with no input and **hang on the
  console**. Defending against that meant denylisting `grep`, `rm`, `cp`, `cat` — which
  left the commands a beginner most needs as exactly the ones that could not have a lesson.

  `lesson <command>` shadows nothing. So it covers **every** command, `grep` and `rm`
  included, and there is no failure mode to defend against. Brothers keep `-lesson`
  (`changemode -lesson`), since a brother name is not a real command.

  One data file backs `lesson`, `pwsh-h <topic>` and the inline hints, so they cannot drift.

- 🔍 **One menu, with topics.** No separate `linux-h`. `pwsh-h` already renders 16k
  characters, so it now takes a topic: `pwsh-h permissions`, `pwsh-h files`, `pwsh-h linux`,
  or a command name (`pwsh-h chmod`).

- 🐚 **The bash builtins PowerShell lacks**, so you never have to leave PowerFlow:

  | | |
  |---|---|
  | `export VAR=value` | bash-style env vars |
  | **`alias ll='ls -lh'`** | **an alias WITH ARGUMENTS** — `Set-Alias` fundamentally cannot do this |
  | `unset` · `source` | remove a var · load `KEY=value` lines from a file |
  | `jobs` · `fg` · `bg` | job control, mapped onto PowerShell jobs |
  | `history` · **`!!`** · **`!$`** | `sudo !!` is muscle memory. Implemented as PSReadLine handlers that rewrite the line **in place**, so you see what will run before pressing Enter — arguably better than bash, where `!!` expands invisibly. |

  (`&&`, `\|\|`, pipes, redirection, `$()` and globbing already worked in PowerShell 7.)

- 🪟 **Windows tells the truth.** `perms` on Windows does **not** invent a fake `755` —
  Windows has ACLs, not POSIX mode bits, and there is no honest mapping. It says so and
  points at `icacls`. The **lessons still work** on Windows; only the *action* does not.

## [3.2.0] - 2026-07-14 · tagged, never published

> ⚠️ **This version was tagged but no release was ever published — its release workflow
> failed** (shellcheck SC2086 in `install-gui.sh`, and `install.sh` could not run twice
> because it copied read-only `.git` objects). Both are fixed in **3.3.0**, which contains
> everything below. There is nothing to install here; go to 3.3.0.

> 🌍 **`git-rl` now works in any project — not just PowerFlow's.**
>
> It reads *your* project's version file (`package.json`, `pyproject.toml`, `Cargo.toml`,
> `*.csproj`, `build.gradle`, `VERSION`), bumps it, and keeps multiple version files in
> sync. No more asking a Node developer to keep a PowerShell file in their repo.

### Added

- 🌍 **Project version-file detection (`components/git/version-files.ps1`).**
  `git-rl` previously read **one hardcoded location** — `config/PowerFlow.settings.ps1`,
  matching `$script:POWERFLOW_VERSION`. In any other project it silently fell back to the
  latest git tag and **rewrote nothing**, so a Node project's `package.json` was never
  bumped. It now detects and rewrites the project's own version file:

  | Project | File | Pattern |
  |---|---|---|
  | Node | `package.json` | `"version": "X.Y.Z"` |
  | Python | `pyproject.toml` | `version = "X.Y.Z"` (`[project]` / `[tool.poetry]`) |
  | Rust | `Cargo.toml` | `version = "X.Y.Z"` (`[package]` only) |
  | .NET | `*.csproj` | `<Version>X.Y.Z</Version>` |
  | Gradle | `build.gradle(.kts)` | `version = "X.Y.Z"` |
  | Any | `VERSION` | plain text |
  | PowerShell | `config/PowerFlow.settings.ps1` | `$script:POWERFLOW_VERSION` |

  Falls back to the latest git tag when a project has none.

- 🔗 **Multiple version files are updated together, and drift is caught before the bump.**
  If a project has both `package.json` and a `VERSION` file, `git-rl` shows both, warns if
  they currently **disagree**, and — on confirmation — brings all of them to the same new
  version. Version drift is now handled at the source rather than policed by a CI check
  after the fact. If any file fails to update, the release **aborts before** anything is
  committed, tagged or pushed.

- 🛡️ **Formatting is preserved, and nested versions are never touched.**
  The rewrite is a targeted regex anchored to the *current* version, not a
  parse-and-reserialise — round-tripping `package.json` through a JSON serialiser would
  reorder keys and reindent the file, an unacceptable diff for a version bump. Verified
  against fixtures for all seven project types: a `version` under `[dependencies]` in
  `Cargo.toml`, a nested `"version"` key in `package.json`, and a `[tool.other]` version
  in `pyproject.toml` are all left alone, while only the project's own version moves.

- 🐚 **`install.sh --login-shell` — PowerFlow can now start on login.**

  PowerFlow is a PowerShell *profile*: it only loads when `pwsh` runs. On a server the
  login shell is bash, so users installed it successfully, rebooted, landed in bash, and
  found no PowerFlow — while the installer cheerfully told them to *"restart your shell"*,
  which on Linux does **nothing**. Reported from a real headless Proxmox box.

  ```bash
  install.sh --login-shell auto    # launch pwsh from ~/.bashrc  (recommended)
  install.sh --login-shell login   # chsh — make pwsh the login shell
  install.sh --login-shell none    # do nothing; run `pwsh` by hand
  ```

  With no flag it **asks**. With `--yes` and no flag it does **nothing** — CI and
  `curl … | bash` must never rewrite someone's shell config unasked.

  `auto` is recommended because it **cannot lock you out**. The `~/.bashrc` block is
  guarded three ways: `$- == *i*` (interactive only — never scp/rsync/cron), a
  `PWSH_STARTED` flag (no login loop), and `command -v pwsh` (if pwsh disappears you still
  get bash). Verified by deleting `pwsh` and confirming the shell still comes up. It is
  idempotent, and `--uninstall` strips it back out.

### Changed

- 📖 **`git-rl -h` setup docs rewritten for real projects.** The prompt previously told
  Node and Python developers to create a PowerShell file (`config/PowerFlow.settings.ps1`)
  in their repo, and then add a CI step to stop it drifting from `package.json`. That was
  a workaround for a limitation, not a design. The prompt now says: *if your project
  already has a version file, you are done* — and explicitly warns against creating a
  PowerShell file in a non-PowerShell project.

- 🐧 **The post-install message no longer misleads on Linux.** It said "Restart your shell
  to activate PowerFlow". Restarting bash does nothing — it now says
  *"PowerFlow is a PowerShell profile — start it with: `pwsh`"*.

### Fixed

- 🔐 **`chsh` failed silently, and could have left you with no shell.** Plain `chsh`
  prompts for a password, so it fails when piped or non-interactive — the login shell was
  never changed and **nothing was reported**. It now elevates via `sudo`, and verifies the
  result in `/etc/passwd` rather than trusting the exit code. The same bug hit *uninstall*:
  it printed "reverting to bash" while leaving `pwsh` as the login shell — meaning it would
  remove pwsh and leave the user's next login pointing at a shell that no longer exists.
  Uninstall now reverts the shell **before** removing pwsh, verifies it, and **aborts
  loudly** if it cannot.

## [3.1.0] - 2026-07-14

> 🗄️ **New: find what is actually eating your disk** — `installed-apps` and `disk-big`.
>
> 🐧 **Plus: the Linux installer now works on every distro it claims to support.**
> v3.0.0 and v3.0.1 were only ever tested on Ubuntu; the `dnf`, `pacman`, `zypper` and
> `apk` paths were written but **never executed once**. Every package manager is now
> exercised on a real container of that distro, on every release.

### Added

- 🗄️ **`installed-apps` — find installed applications by size, then act on them.**

  ```powershell
  installed-apps -o          # 📊 overview of every band, then drill into one
  installed-apps             # pick a size band, then browse it
  installed-apps 2gb-4gb     # apps in a range
  ```

  `installed-apps -o` scans once and reports where the space actually is:

  ```
  BAND           APPS          TOTAL
  1 - 5 GB          9       22.41 GB
  5 - 20 GB         2       11.33 GB
  20 - 50 GB        0           0 KB
  50 GB +           5      502.12 GB
  TOTAL            16      535.86 GB
  ```

  Pick a band in fzf to drill straight into it — no rescan, because the overview and the
  drill-in share the same pass. Each row shows **size *and* age**, since "big *and* old"
  is the strongest signal that something is safe to remove. Age comes from the registry's
  `InstallDate` on Windows (falling back to folder creation time), `rpm INSTALLTIME` and
  pacman's Install Date on Linux, and — because dpkg records none — the mtime of
  `/var/lib/dpkg/info/<pkg>.list`.

- 📁 **`disk-big` — find large FOLDERS and FILES, not just apps.**
  A registry enumeration will never surface a 169 GB `docker_data.vhdx`, a bloated
  `node_modules`, or a Downloads folder full of ISOs — none of those are "installed
  apps". `disk-big` scans the places where bulk actually accumulates (`%LOCALAPPDATA%`,
  `ProgramData`, `scoop`, `.gradle`/`.cargo`/`.m2`, Downloads … and on Linux
  `/var/lib/docker`, `/var/cache`, `~/.cache`, `/snap`) rather than walking all of `C:\`,
  which is slow and spends most of its time in directories that are protected anyway.

- 🛡️ **Safety model.** These commands delete things, so:
  - **Nothing below 1 GB is ever listed.** If the disk is full, a 50 MB utility is not
    the cause.
  - **A query cannot span two size bands.** `2gb-4gb` is fine; `1gb-100gb` is refused.
    An unreviewable list in front of a delete action is how people destroy things.
  - **Protected paths are refused outright** and cannot be overridden — `C:\Windows`,
    `System32`, `Program Files`, `C:\`, `$HOME`; `/`, `/usr`, `/etc`, `/boot`, `/opt/microsoft`.
  - **Apps are uninstalled, never `rm -rf`'d.** Deleting an app's folder leaves its
    uninstaller, registry keys and PATH shims behind — the tool says so and offers the
    real uninstaller first.
  - **Recycle Bin / trash by default; permanent delete requires typing the name.**
  - **Virtual disks are special-cased.** Deleting a `.vhdx`/`.vmdk` destroys every image,
    container and volume inside it — and would not even reclaim the space, because a
    VHDX grows but never shrinks. It recommends `docker system prune` *then* compacting.

- 🧰 **`git-rl -h` — set up `git-rl` in another project.**
  `git-rl` only works in a repository that satisfies its contract (a version source, a
  CHANGELOG it can parse, and a `v*`-tag-triggered pipeline). That knowledge previously
  lived nowhere.

  Run `git-rl -h` from inside the project you want to set up. It asks — via fzf — whether
  you are in the right folder. If yes it creates `docs/` if needed, writes
  **`docs/git-release-help.md`** into the project, and copies an **AI setup prompt** to
  your clipboard. If no, it tells you to navigate there and exits **without printing
  anything** — dumping a 13,000-character prompt into the scrollback of the wrong
  directory helps nobody.

  The generated file is self-contained: the **AI prompt** (paste it into any assistant and
  it builds the version file, CHANGELOG and all six workflows, then verifies them) *and*
  the **manual** — how to cut a release by hand, how to abort a bad one, and post-release
  verification. So the project keeps everything even if PowerFlow is never installed on
  that machine again.

  Source docs: `docs/git-rl/SETUP-PROMPT.md` and `docs/git-rl/README.md`.

- 🧪 **CI distro matrix.** `release-validate-linux.yml` now installs PowerFlow on **Debian
  12/13, Ubuntu 22.04/24.04, Fedora, Arch, openSUSE and Alpine** — all five package
  managers — and asserts on each that pwsh *runs*, all five dependencies install, the
  profile loads, and the GNU coreutils are not shadowed. A release can no longer ship a
  distro that was never executed.

### Fixed

- 📦 **`docs/git-rl/` did not survive installation.** `install.ps1` copied only `config/`,
  `components/`, `platform/` and `windows-only/`. But `git-rl -h` **reads** those docs at
  runtime to write the guide into a user's project — they are a dependency, not
  documentation. On a real install they were absent, so `git-rl -h` silently fell back to
  fetching from GitHub and simply failed offline. The installer now ships them, the
  uninstaller removes them, and CI asserts they survive an install.

- 🩹 **A failed install left the machine permanently broken.** If an earlier attempt
  installed the wrong Microsoft repo (e.g. a *bookworm* source on a *trixie* box), its
  SHA1-signed key poisons **every** subsequent `apt-get update`. Because `install.sh` runs
  `set -e`, the script then aborted on its very first apt call — *before* reaching the
  fixed repo logic — so re-running even a corrected installer could never recover. The
  installer now detects a stale Microsoft source, **purges** it (`dpkg --purge`, not `-r`,
  which would leave the conffile registered and trigger an interactive
  `"end of file on stdin at conffile prompt"` failure), and treats third-party repo errors
  as non-fatal.
- 💥 **PowerShell "installed" but could not run on Fedora / Arch / openSUSE / Alpine.**
  The release-archive fallback installs no runtime libraries, so pwsh died on first use
  with `"Couldn't find a valid ICU package"` — and the installer reported
  `✅ PowerShell installed ()` and carried on, because it only checked
  `command -v pwsh`. It now installs `libicu`/`icu-libs` first and verifies pwsh **runs**
  (`pwsh --version`) rather than merely existing on PATH.
- 📦 **`dnf` / `zypper` never added the Microsoft repository** — they imported the signing
  key and then ran `dnf install powershell`, which cannot work because the package does
  not exist without the repo config. Both now install
  `config/<distro>/<version>/packages-microsoft-prod.rpm` first.
- 🏔️ **Alpine could never work** — it is musl, not glibc, so the standard archive is the
  wrong binary. `apk` was also missing from package-manager detection entirely. Alpine now
  gets the `linux-musl` archive and is a supported target.
- 🏹 **Arch no longer dead-ends.** It previously printed "PowerShell is in the AUR" and
  exited; it now installs from the official archive, which needs no AUR helper.

## [3.0.1] - 2026-07-14

### Fixed

- 🐧 **PowerShell could not install on Debian.** `install.sh` built an *Ubuntu* repo URL
  from the distro's `VERSION_ID` without ever reading `ID`, so on Debian it 404'd and fell
  back to a hardcoded `debian/12` repo. That places a *bookworm* source on a *trixie*
  machine, and the bookworm signing key carries a **SHA1** binding signature that Debian
  13's apt rejects: `"SHA1 is not considered secure"` → `"The repository is not signed."`
  The installer now reads the real `ID`/`VERSION_ID` and requests the correct repo.
  Added a universal fallback that installs PowerShell from Microsoft's official release
  archive (no repo, no GPG key), so repo-signing problems cannot block installation.

## [3.0.0] - 2026-07-14

> 🐧 **Linux is back — rebuilt from scratch on a shared codebase.**
>
> The old Ubuntu port was a 4,160-line parallel re-implementation in bash/zsh/fish.
> Every feature existed twice and the two halves drifted until the Linux one rotted.
> It has been **deleted and replaced** by a Linux platform layer that shares one
> codebase with Windows, so it cannot drift again.
>
> - **Windows users — nothing to do.** Every command behaves exactly as before.
> - **Linux users — a real port, for the first time.** `curl … install.sh | bash`,
>   or a graphical installer. Your GNU coreutils are left alone.
> - **WSL users — unaffected.** `open-ubuntu` / `open-nt u` still open a WSL tab.
>
> ⚠️ **Breaking:** the old bash `.bashrc` port and its `ubuntu-install.sh` are gone.
> 📖 **[Upgrade guide → docs/migration/v3-upgrade.md](https://github.com/Syntax-Read3r/powerflow/blob/main/docs/migration/v3-upgrade.md)**

### Added

- 🐧 **Linux support (PowerShell 7).** PowerFlow now runs natively on Linux from the
  same codebase as Windows — not a second implementation. `nav`, the whole `git-*`
  suite, `gh-l`, bookmarks, fuzzy pickers, `set-path`, `shutdown` and `pwsh-h` all work.
- 🧩 **Platform adapter layer (`platform/<os>/adapters/`).** `components/` is now
  entirely OS-agnostic and calls adapters (`Copy-ToClipboard`, never `Set-Clipboard`).
  Nine adapters implement the same 32-function contract on each OS:

  | Adapter | Windows | Linux |
  |---|---|---|
  | clipboard | `Set-Clipboard` | `wl-copy` → `xclip` → `xsel` |
  | packages | Scoop | apt / dnf / pacman / zypper / apk |
  | elevation | `WindowsPrincipal` | `id -u` / sudo |
  | openers | `explorer.exe` | `xdg-open` |
  | terminal | Windows Terminal + SendKeys | tmux windows |
  | power | `shutdown.exe` | `shutdown -h +N` |
  | env | registry PATH | managed rc fragment |
  | locations | `%LOCALAPPDATA%` / `%TEMP%` | XDG dirs / `$TMPDIR` |
  | pwsh-update | winget / MSI / Store | apt / snap |

- 📦 **Two Linux installers, one installer.** `install.sh` (terminal) and
  `install-gui.sh` (zenity → kdialog → yad → terminal fallback) are thin front-ends;
  both delegate to the same `install.ps1` that Windows uses. Writing a second bash
  installer is the exact duplication that killed the old port.
- 🗑️ **Manifest-based uninstall.** The installer records what it placed and which tools
  it installed. **A dependency you already had is never removed** — the old uninstaller
  ripped out shared Scoop tools regardless, and the old bash one deleted `~/.bashrc`
  outright. Reachable three ways: `powerflow-uninstall`, `install.sh --uninstall`, or
  the GUI.
- 🚧 **CI enforces the architecture.** `release-validate.yml` fails the release if any
  file under `components/` calls an OS API directly, or if an adapter exists on only one
  platform. A new `release-validate-linux.yml` job proves **install → load → use →
  uninstall** on a real `ubuntu-latest` box and **blocks publish** if Linux is broken.
  The old port had no such check, which is why it rotted silently.
- 🛡️ **Shared elevation helpers (`Test-Admin`, `Assert-Admin`)** — one consistent
  Administrator/root check for every admin-gated command.

### Changed

- ⏰ **`shutdown` maximum delay raised to 6 hours** (was 3). `shutdown 6h` now works.
  The 10-minute minimum and `shutdown cancel` / `s c` are unchanged.
- 🐧 **Linux keeps its GNU coreutils.** PowerShell resolves
  `Alias → Function → Cmdlet → native binary`, so PowerFlow's `rm`/`mv` functions and
  `cat`/`cp` aliases would have **shadowed the real tools**. They no longer do:

  | On Linux | Behaviour |
  |---|---|
  | `rm` `mv` `cp` `cat` `mkdir` `touch` `rmdir` `which` `grep` | the **real GNU tools**, untouched |
  | **`del`** | PowerFlow's smart removal (what `rm` is on Windows) |
  | **`mvf`** | PowerFlow's cut-and-paste move (what `mv` is on Windows) |
  | `ls` `la` `ll` | PowerFlow's pretty listing (deliberately overridden) |

  This matters: PowerFlow's `rm somedir` recursively deletes a tree after one prompt,
  while GNU `rm somedir` **refuses** without `-r`. Shadowing it would have silently
  removed a seatbelt Linux users rely on. **Windows behaviour is unchanged.**
- 📦 **`install.ps1` now installs the whole component tree.** It previously downloaded
  only the bootloader, leaving `config/` and `components/` missing — the profile could
  not actually load from a fresh install.
- ⚙️ **Release scripts are shipped, not generated.** The CI used to rebuild `install.ps1`
  from a here-string embedded in YAML, which could silently drift from the real file.

### Fixed

- 🗑️ **`rm` now supports wildcards and multiple targets**: `rm *.log` and
  `rm a.txt b.txt` previously matched nothing and silently deleted nothing —
  every argument was joined into a single literal path (`"a.txt b.txt"`), which
  never resolved. Each argument is now resolved as its own path pattern.
  Multi-target deletes list every match and take one confirmation; `-f` still
  skips it. Unquoted filenames with spaces (`rm my report.txt`) still work, and
  names with wildcard characters (`rm build[1].log`) now resolve too.
- 🖥️ **`$IsWindows` does not exist on PowerShell 5.1** — it is `$null`, which is falsy.
  Platform detection checks `PSEdition -eq 'Desktop'` first, so a 5.1 box is correctly
  identified as Windows. A naive check would have failed to load the profile entirely
  for every 5.1 user.
- 🐧 **`$env:TEMP` / `$env:USERPROFILE` are unset on Linux** — state files (update
  markers, bookmarks) would have been written to bogus paths. Components now go through
  `Get-TempPath` / `Get-HomePath` adapters.
- 📦 **Dependency install failed for *every* tool on a clean Linux box** — `apt-get install`
  was called without ever running `apt-get update`, so on a fresh machine (or container)
  the package lists are empty and even `git` fails with "Unable to locate package".
  The index is now refreshed once per session.
- 📦 **`starship` and `lsd` are not in Ubuntu's repos at all** — apt could never install
  them, so `ls` had no `lsd` and the prompt had no `starship`. They are now fetched from
  their GitHub releases, using PowerShell's own web cmdlets rather than `curl` (a slim
  image often has neither `curl` nor `wget`, which made the old fallback fail silently).
- 🗑️ **Uninstall claimed to remove tools it did not remove** — removals were batched
  (`apt-get remove starship zoxide lsd`), and apt aborts the *entire* command if one name
  is not an apt package. A single unpackaged tool silently left every other tool installed.
  Removal is now one package at a time, and binaries installed to `/usr/local/bin` are
  deleted directly since the package manager cannot see them.
- ⛔ **The startup update check could block a non-interactive shell** — it ran during
  profile load and called `Read-Host`, so in CI, a script, or `curl … | bash` it would wait
  for input that never comes. It now skips prompting when stdin is redirected.
- 🧪 **`install.sh` ignored a local checkout and always downloaded `main`** — which meant
  the Linux CI job checked out the tag being released and then validated *different* code.
  It now installs from the checkout when run inside one.
- 🐧 **PowerShell could not install on Debian** — `install.sh` always built an *Ubuntu*
  repo URL from the distro's `VERSION_ID` (it never read `ID`), so on Debian it 404'd and
  fell back to a **hardcoded `debian/12`** repo. That put a *bookworm* source on a
  *trixie* box, and the bookworm signing key carries a **SHA1** binding signature that
  Debian 13's apt rejects outright:
  `"OpenPGP signature verification failed … SHA1 is not considered secure"` →
  `"The repository … is not signed."` The installer now reads the real `ID`/`VERSION_ID`
  and requests the correct repo (`config/debian/13/…`, which exists and works). Added a
  universal fallback that installs PowerShell from Microsoft's official release archive —
  no repo, no GPG key, so repo-signing problems cannot block installation on any distro.
  Verified end-to-end on Debian 13 (trixie).
- 💥 **Dependency install crashed for every non-root user** — `"The term 's' is not
  recognized"`. PowerShell **unrolls a single-element array into a scalar**, so
  `$sudo = if (root) { @() } else { @('sudo') }` produced the *string* `'sudo'`, making
  `$sudo + $cmd` a string concatenation rather than an array one. `$full[0]` then indexed
  the first **character** — `s`. It only broke when *not* root (as root the empty array
  concatenates correctly), so it passed in a root container and failed on every real user.
  All elevated calls now go through a single `Invoke-Elevated` builder.

### Removed

- 🐧 **The old Ubuntu/bash port is gone** — `ubuntu/` deleted (`.bashrc`, a 2,105-line
  `.zshrc`, `install.sh`, `uninstall.sh`, `install-essentials.sh`, `nav.fish` and its
  READMEs — 4,160 lines), along with `ubuntu-install.sh` / `ubuntu-uninstall.sh` from
  the release pipeline.

  It was a parallel re-implementation, which is why it rotted. **Linux is not gone —
  it is rebuilt** on the shared codebase above. If you installed the old port, see the
  [upgrade guide](https://github.com/Syntax-Read3r/powerflow/blob/main/docs/migration/v3-upgrade.md)
  to restore your `.bashrc` backup.
- ℹ️ Windows-side WSL support is **unaffected**: `open-ubuntu`, `open-wsl-simple` and
  `open-nt u` still launch a WSL tab from Windows Terminal with path bridging.

## [2.2.1] - 2026-05-25

### Fixed
- 🏢 **`gh-l-org` organisation selection parsing**: fixed a bug where selecting
  an organisation from the fzf picker could fail with
  `Could not parse organisation name from selection.` The picker now stores the
  organisation login in a stable hidden field instead of parsing it from the
  emoji-decorated display text.

## [2.2.0] - 2026-05-24

### Added
- 🔔 **Version display on startup**: profile load line now shows the running version
  (`✅ PowerFlow v2.2.0 loaded`) so the current version is always visible without
  running a command.
- 📋 **3-option update prompt**: when a new version is available the bare `y/n/s` prompt
  is replaced with a numbered menu — `1) Install now`, `2) Skip today`,
  `3) Turn off update reminders`.
- 🔕 **Persistent reminder toggle (option 3)**: choosing option 3 permanently writes
  `$script:CHECK_PROFILE_UPDATES = $false` to `config/PowerFlow.settings.ps1` so
  the setting survives profile reloads without manual editing.
- 🔔 **`pwsh-reminders` command**: interactive toggle for update reminder notifications.
  Shows current ON/OFF status and flips it by rewriting the settings file. Re-enabling
  clears the daily check marker so the update check fires on the very next load.

### Fixed
- 📦 **README install URL**: changed from `releases/latest/download/install.ps1` to
  `raw.githubusercontent.com/main/install.ps1` — the old URL resolved to v1.0.5 because
  newer releases were never confirmed to have created GitHub Release objects.

### Documentation
- 📋 **`docs/instructions.md`**: added mandatory post-release verification rule to §9
  and a CHANGELOG ordering convention so release drift cannot recur silently.

## [2.1.0] - 2026-05-24

### Added
- 🏢 **GitHub Organisation Browser** (`gh-l-org`): Browse and bulk-clone GitHub
  organisation repositories from the terminal.
  - **Org picker**: fzf list of all organisations the authenticated user belongs to
  - **Repo picker**: identical column layout to `gh-l` — privacy, name, last push date,
    24h commits, 1w commits, language
  - **Action menu**: clone selected repo, clone ALL repos into `.\<orgName>\` folder,
    open in browser, copy HTTPS or SSH URL
  - **Bulk clone**: uses `Push-Location`/`Pop-Location` to restore CWD; reports per-repo
    success/failure counts on completion
  - **Token scope fallback**: automatically retries with `type=public` and warns user if
    token lacks `read:org` scope
  - **Direct org argument**: `gh-l-org mycompany` skips the org picker
  - **Shared token helpers**: `_GhL-SetToken`, `_GhL-GetToken`, `_GhL-CommitCount`
    extracted to module level — shared by `gh-l` and `gh-l-org`, compiled once per session

## [2.0.1] - 2026-05-21

### Fixed
- 🐛 **`nav` multi-word query truncation**: `nav source code` previously only searched for `"source"` — every word after the first was silently dropped. Extra positional arguments are now joined into a single query string before being passed to fzf (or the BFS fallback), so `nav source code` correctly searches for `"source code"`.

## [2.0.0] - 2026-05-19

### Breaking Change — Modular Architecture
The profile is no longer a single monolithic file. `Microsoft.PowerShell_profile.ps1` is now a thin bootloader (~109 lines) that dot-sources 28 component files organized by domain. **Installation must use the `powerflow-v2.0.0.zip` archive** — downloading only the profile file will produce a broken install.

### Architecture
- **Component-based layout** inspired by React feature-folder conventions
- **28 component files** split across 10 domain folders under `components/`
- **`config/`** folder for settings (`PowerFlow.settings.ps1`) and environment init (`PowerFlow.paths.ps1`)
- **`_pf_source` bootloader helper** — warns on missing components instead of hard-failing, portable via `$script:PowerFlowRoot`
- **`COMPONENTS.md`** — registry table of every file, domain, and exported function
- **`IMPORT_ORDER.md`** — documented rationale for load order at each stage
- **`docs/`** and **`tests/`** scaffold directories for future growth

### Changed
- `$script:POWERFLOW_VERSION` moved from main profile to `config/PowerFlow.settings.ps1`
- Release workflow updated: version validation now checks `config/PowerFlow.settings.ps1`; releases now ship a `powerflow-v2.0.0.zip` archive containing the full component tree
- Install script updated to download and extract the zip archive into the profile directory

## [1.0.5] - 2025-01-23

### Added
- 🚀 **Automatic GitHub Repository Creation**: `git-a` now creates remote repositories on-the-fly
  - **Smart Remote Detection**: Automatically detects when no remote repository exists
  - **GitHub CLI Integration**: Checks for `gh` installation and authentication before offering to create
  - **Interactive Repository Setup**: Beautiful fzf interface for repository configuration
  - **Naming Convention Options**: Choose from kebab-case, snake_case, PascalCase, camelCase, or custom
  - **Visibility Selection**: Interactive private/public repository selection with clear descriptions
  - **Seamless Workflow**: Creates remote, sets origin, and pushes in one smooth operation
  - **Error Recovery**: Handles deleted remotes and offers to recreate them
  - **Authentication Status**: Shows current GitHub user during repository creation
- 🖥️ **Cross-Platform Terminal Integration**: Enhanced `open-nt` function with shell switching
  - **PowerShell from Ubuntu**: `open-nt pwsh` or `open-nt p` to launch PowerShell tabs from Ubuntu
  - **Ubuntu from PowerShell**: `open-nt ubuntu` or `open-nt u` to launch Ubuntu tabs from PowerShell
  - **Smart Path Conversion**: Automatically converts WSL paths ↔ Windows paths when switching shells
  - **Command Prompt Support**: `open-nt cmd` to open Command Prompt tabs from either environment
  - **Fallback Handling**: Graceful degradation when Windows Terminal is unavailable
- 🐧 **Ubuntu `open-nt` Function**: Complete implementation for Ubuntu/WSL environments
  - **Cross-shell navigation**: Launch any shell from Ubuntu terminal
  - **Windows Terminal integration**: Seamless tab management across environments
  - **Path translation**: Intelligent handling of /mnt/ paths to Windows drive letters

### Enhanced
- **`git-a` Workflow**: Now handles the complete git lifecycle from init to push
  - **Repository initialization**: Offers to init git if not in a repository
  - **Remote status display**: Shows if repository is local-only or has remote
  - **Upstream handling**: Automatically sets upstream on first push to new branches
  - **Complete automation**: From local changes to live GitHub repository in one command
- **PowerShell `open-nt`**: Extended existing function with cross-platform shell selection
- **Ubuntu Help System**: Updated `wsl_help` to include `open-nt` cross-platform usage
- **Documentation**: Comprehensive coverage of cross-platform terminal features

### Fixed
- 🐛 **`git-a` Syntax Errors**: Resolved critical issues in the git-a function
  - **Incomplete regex pattern**: Fixed unclosed regex replacement for repository name sanitization
  - **Duplicate code removal**: Eliminated ~140 lines of duplicated code in `Create-RemoteRepository` function
- 🔤 **Naming Convention Functions**: Improved word boundary detection in case conversion
  - **Smart word detection**: Now properly handles camelCase, PascalCase, snake_case, and kebab-case
  - **Single word preservation**: Fixed issue where single words like "back" were split into "b-a-c-k"
  - **Enhanced patterns**: Better regex patterns for detecting transitions between words and acronyms
  - **Examples**: "MyProject" → "my-project", "XMLParser" → "xml-parser", "back" → "back" (not "b-a-c-k")

## [1.0.4] - 10-07-2025

### Added
- 🚀 **Professional Next.js Project Creator**: `create-next` / `create-n` command
  - **Database Selection**: Choose from PostgreSQL+Prisma, Supabase, MongoDB, MySQL+Prisma, or SQLite+Prisma
  - **Complete CI/CD Pipeline**: 3 GitHub Actions workflows (ci.yml, docker-build.yml, deploy.yml)
  - **Docker Integration**: Development and production Docker configurations with database services
  - **Enterprise Structure**: Professional folder organization with all necessary directories
  - **Comprehensive Documentation**: API docs, development guide, and deployment guide auto-generated
  - **Database-Specific Configurations**: Tailored setup for each database type with proper connection strings
  - **TypeScript Ready**: Full TypeScript support with database-specific type definitions
  - **Beautiful Interface**: Same fzf-powered interface as `git-a` with database selection
- 🏷️ **Version release workflow**: `git-a -VersionRelease` / `git-a -vr` 
- 🤖 **GitHub Actions integration**: Automatic release creation when version tags are pushed
- 🎯 **One-command releases**: Update version → `git-a -vr` → Automatic release generation
- ✅ **Smart release validation**: Ensures profile version matches git tag
- 📦 **Auto-generated release assets**: install.ps1, uninstall.ps1, and release notes

### Enhanced
- `git-a` function now supports version release workflow
- Help documentation updated with new release commands and `create-next` functionality
- Release process streamlined from manual to automated
- `pwsh-h` help system expanded with comprehensive Next.js project creation documentation

### Technical Details
- **`create-next`**: Creates production-ready Next.js applications with:
  - Latest Next.js 15+ with App Router, TypeScript, Tailwind CSS, ESLint
  - Database integration: Prisma schemas, Supabase client, or Mongoose models
  - Docker Compose configurations for development and production
  - GitHub Container Registry integration
  - Automated dependency installation based on database choice
  - Environment variable templates for each database type
  - Professional npm scripts for database operations and Docker management
