# PowerFlow Import Order

The bootloader (`Microsoft.PowerShell_profile.ps1`) sources files in a specific order.
This document explains why each stage loads when it does.

As of v3.0.0 the profile is **platform-aware**: the same file is `$PROFILE` on Windows
and Linux, and it loads a different platform layer on each.

---

## Platform detection (before anything is sourced)

```powershell
$script:PowerFlowOS =
    if     ($PSVersionTable.PSEdition -eq 'Desktop') { 'windows' }   # Windows PowerShell 5.1
    elseif ($IsWindows)                              { 'windows' }   # pwsh 6+ on Windows
    elseif ($IsLinux)                                { 'linux' }
    ...
```

### ⚠️ Why the `PSEdition` check comes FIRST

**`$IsWindows` does not exist in Windows PowerShell 5.1.** It evaluates to `$null`,
which is *falsy*. A naive `if ($IsWindows) {...} elseif ($IsLinux) {...}` would classify
a 5.1 Windows box as **neither** — the platform layer would never load, no adapters
would exist, and every component call would fail.

PowerFlow supports 5.1+ (`install.ps1` declares `#Requires -Version 5.1`, and the README
advertises it). 5.1 is always `Desktop` edition and always Windows, so that check is
**mandatory**, not defensive.

---

## Stage 1 — Settings (`config/PowerFlow.settings.ps1`)

Loads first because it defines the script-scoped variables (`$script:POWERFLOW_VERSION`,
`$script:CHECK_*` flags, DB credentials, `$ProgressPreference`) that every later file may
read. Nothing behaves correctly without these.

## Stage 2 — Platform adapters (`platform/<os>/adapters/*.ps1`)

**Must load before `components/`.** This is the central rule of the architecture.

Components are platform-agnostic: they call `Copy-ToClipboard`, never `Set-Clipboard`.
Those adapter functions must already be defined by the time a component runs. Loading
adapters after components would leave every OS call unresolved.

Adapters are sourced alphabetically; they do not depend on each other, with two
exceptions that resolve naturally in that order:

- `env.ps1` calls `Assert-Admin` (from `elevation.ps1`) to gate System-scope PATH writes.
- `terminal.ps1` calls `Copy-ToClipboard` (from `clipboard.ps1`) for WSL path bridging.

Both callers only invoke those functions at *runtime*, not at load time, so alphabetical
ordering is safe.

## Stage 3 — Platform paths (`config/paths.<os>.ps1`)

Configures the shell environment: PATH, the Starship prompt, and Zoxide. Must run after
the adapters (Linux's `paths.linux.ps1` calls `Get-PowerFlowConfigPath` to locate its
PATH fragment) and before any interactive function needs those tools.

Also removes Zoxide's default `z` alias so `components/navigation/nav.ps1` can define its
own `z`.

## Stage 4 — Components (`components/**`)

Shared domain logic, loaded in dependency order:

1. **core** — `version`, `dependencies`, `recovery`. Loaded early because the startup
   checks at the bottom of the bootloader call them.
2. **shared** — `strings.ps1`; `git/remote.ps1` calls its case converters.
3. **navigation** — `bookmarks` → `projects` → `nav` → `directory`. `nav` depends on the
   first two.
4. **files** — `listing` first (it replaces `ls`, so later files may safely call `ls`),
   then `operations`, `rename`, `clipboard`.
5. **git** — `remote.ps1` **before** `commit.ps1`, because `git-a` calls
   `Create-RemoteRepository`. And `version-files.ps1` **before** `release.ps1`, because
   `git-rl` calls `Get-ProjectVersion` to find the project's version file. The rest are
   standalone.
6. **github** — after git; `gh-l` may `git clone` after a selection.
7. **terminal** — after navigation, so `open-nt` reports the correct current directory.
8. **projects** — `create-next.ps1` reads DB settings from Stage 1.
9. **system** — standalone; nothing depends on them.
10. **network** — `server-privacy.ps1` before `servers.ps1`; the router delegates native SSH
    argument construction and authenticated endpoint display to that privacy boundary.

## Stage 5 — Windows-only (`windows-only/*.ps1`)

Loaded **only** when `$script:PowerFlowOS -eq 'windows'`.

`wsl.ps1` (`open-ubuntu`, `open-wsl-simple`) launches a WSL tab *from* Windows Terminal.
WSL is a Windows concept and these functions must never exist on Linux — the Linux CI job
explicitly asserts they are absent.

## Stage 6 — Platform bindings (`platform/<os>/bindings.ps1`)

**Must load after `components/`,** because it rebinds names the components have just
defined. This is the mirror image of Stage 2.

- **Windows** — adds `grep`, `less`, `pwd`, `which`, which Windows lacks. PowerFlow's
  `rm`/`mv`/`ls` keep their natural names; there are no GNU tools to shadow.
- **Linux** — **stops PowerFlow from shadowing the GNU coreutils.** PowerShell resolves
  `Alias → Function → Cmdlet → native binary`, so PowerFlow's `rm` *function* would beat
  `/usr/bin/rm`, and its `cat`/`cp` *aliases* would beat GNU `cat`/`cp`. The bindings file
  clears both, preserving the features under new names: `rm` → **`del`**, `mv` → **`mvf`**.

  This matters concretely: PowerFlow's `rm somedir` recursively deletes a tree after one
  prompt, while GNU `rm somedir` *refuses* without `-r`. Shadowing it would silently
  remove a seatbelt Linux users rely on.

## Stage 7 — Help (`components/help/menu.ps1`)

Loads last because its static text references every command defined above.

---

## Startup checks

After everything is sourced:

```powershell
if ($script:CHECK_PROFILE_UPDATES) { Check-PowerFlowUpdates }
if ($script:CHECK_DEPENDENCIES)    { Initialize-Dependencies }
if ($script:CHECK_UPDATES)         { Check-PowerShellUpdates }
```

Toggle these flags in `config/PowerFlow.settings.ps1` to speed up profile load.

---

## The invariant CI enforces

> **No file under `components/` may call an OS API directly.**

`release-validate.yml` greps for `Set-Clipboard`, `scoop`, `wt`, `WindowsPrincipal`,
`shutdown.exe`, `$env:TEMP`, `winget`, … under `components/` and **fails the release** on
any hit. It also verifies that every adapter function called by a component exists on
**both** platforms.

That check is the machine-checkable definition of the architecture. Without it, Windows
could keep working while Linux silently broke — which is exactly how the previous Ubuntu
port rotted.
