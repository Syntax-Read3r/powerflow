# Linux Port — Architecture

## 1. Runtime: PowerShell 7 (`pwsh`) on Linux

**One codebase, two backends.** PowerFlow stays PowerShell. `pwsh` runs natively on
Linux, and `$IsWindows` / `$IsLinux` are built-in automatic variables.

### What works on Linux pwsh

- **Native binaries run normally.** `git`, `fzf`, `gh`, `docker`, `apt`, `sudo`,
  `systemctl`, `xdg-open`, `xclip` — pwsh resolves executables off `$PATH` like any shell.
- `&&`, `||`, `>`, `2>`, `$( )` all work (pwsh 7+).
- PowerFlow already shells out to `git` / `fzf` / `gh` / `npm` — **all of that ports unchanged.**

### What does NOT work

- **Bash syntax.** `if [ -f x ]`, `for x in *; do … done`, heredocs (`<<EOF`),
  backtick substitution. Use PowerShell control flow around native commands instead.
- Native commands return **strings**, not objects. `ls | Where-Object …` against the
  *native* `ls` gives text lines, not `FileInfo`. Keep parsing explicit.

### Why not a bash/zsh rewrite

That is exactly what v2.x did, and it rotted. Writing every feature twice guarantees
drift. See [README.md](README.md).

---

## 2. Command shadowing policy ⚠️

PowerShell resolves commands in this order:

```
Alias  →  Function  →  Cmdlet  →  Native executable
```

On Linux, PowerShell deliberately does **not** alias `ls`/`cat`/`cp`/`mv`/`rm` so that
the real GNU coreutils are reachable. **PowerFlow overrides them anyway** — as
*functions*, which beat native binaries in resolution order.

Left alone, a Linux user typing `rm` gets PowerFlow's `rm`, not `/usr/bin/rm`.
That must be a deliberate choice per command, not an accident.

Every overriding command gets a row here. Decide before Phase 2.

| Command | Defined in | On Windows | Proposed Linux behaviour |
|---|---|---|---|
| `ls` `la` `ll` | `files/listing.ps1` | Override (lsd-based) | **Override** — the pretty listing is the point of PowerFlow |
| `cat` | `files/listing.ps1` | Override (bat) | **Override**, but must pass through `-` stdin and flags |
| `cp` | `files/listing.ps1` | Override | **Defer to native** — GNU `cp` flags are muscle memory |
| `rm` `rmdir` | `files/operations.ps1` | Override (fzf + confirm) | **Rebind, don't rename away.** Keep the fuzzy-delete as `del` / `rmi`; let `rm` be GNU `rm`. See below. |
| `mv` | `files/operations.ps1` | Override (cut/paste model) | **Rebind** — the cut/paste model is not GNU `mv` semantics and would surprise |
| `mkdir` `touch` | `files/operations.ps1` | Override | **Defer to native** — native already does this |
| `grep` `less` `which` `pwd` | `shared/aliases.ps1` | Alias (Windows lacks them) | **Drop entirely on Linux** — the real tools exist and are better |

> **Rule of thumb:** override when PowerFlow *adds* value (pretty listing, fuzzy pickers);
> defer to native when PowerFlow merely *reimplements* a tool that already exists on Linux.
> The feature is never the problem — **the binding is.** Keep every command; just don't let
> it impersonate a native tool whose semantics differ.

### The `rm` case (measured, not assumed)

`rm` is the sharpest example. PowerFlow's `rm` joins all args into **one** literal path
(`$Name -join ' '`), resolves with `Get-Item -LiteralPath` (wildcards disabled by design),
then always calls `Remove-Item -Recurse -Force`.

Verified against a sandbox:

| Input | GNU `/usr/bin/rm` | PowerFlow `rm` |
|---|---|---|
| `rm a.txt b.txt` | deletes both | **deletes nothing** — "not found: a.txt b.txt" |
| `rm *.log` | deletes both | **deletes nothing** — "not found: *.log" |
| `rm subdir` | **refuses** — "Is a directory" | **recursively deletes the whole tree** |

The third row is the danger: GNU `rm` refuses to touch a directory without an explicit `-r`.
That refusal is a seatbelt Linux users rely on reflexively. PowerFlow's version drives
straight through it. Shadowing `rm` would also silently **remove** globbing and multi-file
deletes — the two things Linux users reach for most.

**Resolution:** on Linux, `rm` stays GNU `rm`. The fuzzy-delete keeps all of its value under
its own name (`del` / `rmi`). Windows is unchanged — it has no GNU `rm` to conflict with.
Only the **alias binding** is platform-specific; the function itself stays shared.

> 🐞 **Pre-existing Windows bug found while testing this:** `rm *.log` and `rm a.txt b.txt`
> silently delete nothing on Windows *today* — the `-join ' '` collapses multi-target and
> wildcard deletes into one bogus literal path. Not destructive, but broken. Worth fixing
> independently of the port.

---

## 3. Ports and adapters

`components/` holds domain logic and is **platform-agnostic**. It calls adapter
functions only. `platform/<os>/` implements those contracts. This mirrors React
Native's `Component.ios.js` / `Component.android.js` split.

```
bootstrap.ps1                ← detects OS; sources platform/<os>/ BEFORE components/
config/
  PowerFlow.settings.ps1     ← shared (version, flags)
  paths.windows.ps1          ← Scoop PATH, Starship, zoxide
  paths.linux.ps1            ← ~/.local/bin, XDG dirs, Starship, zoxide
platform/
  windows/  clipboard.ps1  packages.ps1  elevation.ps1  terminal.ps1  openers.ps1  power.ps1  env.ps1
  linux/    clipboard.ps1  packages.ps1  elevation.ps1  terminal.ps1  openers.ps1  power.ps1  env.ps1
components/                  ← SHARED domain logic. Never calls an OS API directly.
  core/ shared/ navigation/ files/ git/ github/ projects/ system/ help/
windows-only/
  wsl.ps1                    ← open-ubuntu, open-wsl-simple. WSL is Windows-only; never ports.
```

### Adapter contracts

Same function names on both platforms. Domain code calls these and stays ignorant of the OS.

| Adapter | Contract | Windows | Linux |
|---|---|---|---|
| `clipboard` | `Copy-ToClipboard`, `Get-FromClipboard` | `Set-Clipboard` / `Get-Clipboard` | `wl-copy` (Wayland) → `xclip` (X11) fallback |
| `packages` | `Install-Dependency`, `Test-Dependency`, `Update-Dependencies` | Scoop | detect `apt` / `dnf` / `pacman` |
| `elevation` | `Test-Admin`, `Assert-Admin` | `WindowsPrincipal` | `id -u` -eq 0; `sudo` for actions |
| `openers` | `Open-Path`, `Open-Editor` | `explorer.exe`, `code` | `xdg-open`, `code` |
| `terminal` | `New-TerminalTab`, `Switch-TerminalTab`, `Close-TerminalTab` | `wt` + SendKeys | `tmux` |
| `power` | `Invoke-Shutdown`, `Stop-Shutdown` | `shutdown.exe /s /t` | `shutdown -h +N` / `shutdown -c` |
| `env` | `Set-PersistentPath`, `Get-PersistentPath` | `[Environment]::SetEnvironmentVariable` (registry) | append to a PowerFlow-managed rc fragment |

> `Test-Admin` / `Assert-Admin` already exist (`components/shared/admin.ps1`, v3.0.0).
> Phase 0 promotes that file into `platform/windows/elevation.ps1` — the contract is
> already the right shape, which validates the adapter approach.

### Load order

`platform/<os>/` **must** be sourced before `components/`, because components call
adapters at definition-independent runtime but the functions must exist by first use.
Same reasoning as the existing `remote.ps1` → `commit.ps1` ordering in `IMPORT_ORDER.md`.

---

## 4. Current Windows coupling (audit)

Measured against the v3.0.0 tree. This is the full extraction surface for Phase 0.

| Coupling | Count | Files |
|---|---|---|
| **Clipboard** | **7** | `files/clipboard`, `git/branches`, `git/interactive`, `github/browser`, `navigation/directory`, `terminal/tabs`, `terminal/wsl` |
| Scoop | 5 | `core/dependencies`, `core/recovery`, `files/listing`, `navigation/nav`, `config/paths` |
| Windows Terminal (`wt`, SendKeys) | 4 | `terminal/tabs`, `terminal/wsl`, `system/config-files`, `help/menu` |
| `shutdown.exe` | 1 | `system/shutdown` |
| PATH registry | 1 | `system/path` |
| Admin check | 1 | `shared/admin` *(already isolated)* |

**Already portable — no work needed:** all 7 `git/*` files, `shared/strings`,
`navigation/bookmarks`, `navigation/projects`, `files/operations`, `files/rename`,
`projects/create-next`.

> Clipboard is the highest-leverage adapter: building it alone unblocks git, github
> and navigation on Linux in one step. That is why it is Phase 2.
