# Upgrading to PowerFlow v3.0.0

v3.0.0 is a **major** release: the old bash/zsh Ubuntu port was **deleted and replaced**
by a real Linux port that shares one codebase with Windows.

## Am I affected?

| You installed with… | Affected? | What to do |
|---|---|---|
| `irm …/install.ps1 \| iex` (Windows / PowerShell) | ✅ **No** | Upgrade normally. Nothing changes. |
| `curl …/ubuntu-install.sh \| bash` (the old `.bashrc` port) | ⚠️ **Yes** | See [Linux users](#linux-users) — you get a real port now. |
| Using `open-ubuntu` / `open-nt u` to open WSL tabs from Windows | ✅ **No** | These still work. See [WSL](#wsl-users-you-are-fine). |

---

## Windows users — nothing to do

```powershell
powerflow-update
```

Every command behaves exactly as before. `rm`, `mv`, `ls` and everything else keep their
current names and behaviour. Under the hood the code was restructured behind a platform
adapter layer, but **no Windows behaviour changed**.

Three improvements you get for free:

- **`shutdown` now accepts up to 6 hours** (was capped at 3). `shutdown 6h` works.
- **`rm` now handles wildcards and multiple files.** `rm *.log` and `rm a.txt b.txt`
  previously matched nothing and silently deleted nothing. A multi-target delete now
  lists every match before asking for one confirmation.
- **The installer actually installs everything.** It previously downloaded only the
  bootloader, leaving `config/` and `components/` missing.

---

## Linux users

**The old bash port is gone. A real Linux port has replaced it.**

### What happened

The old port was a *parallel re-implementation*: an enhanced `.bashrc`, a 2,105-line
`.zshrc`, a fish script — every feature written a second time in shell script. Two copies
of everything meant guaranteed drift. Fixes landed on Windows and never reached Linux, and
the Linux half rotted.

v3.0.0 deletes it and rebuilds Linux on **PowerShell 7**, sharing the *same* codebase as
Windows. There is no second implementation to drift.

### Install the new port

```bash
# terminal
curl -fsSL https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install.sh | bash

# or a graphical installer
curl -fsSL https://github.com/Syntax-Read3r/powerflow/releases/latest/download/install-gui.sh -o install-gui.sh
bash install-gui.sh
```

The installer installs `pwsh` if you don't have it, then PowerFlow.

### ⚠️ PowerFlow only loads when `pwsh` runs

This is the single most common confusion, especially on a server.

**PowerFlow is a PowerShell profile.** Your login shell is almost certainly bash, so after
a reboot you land in bash and PowerFlow is simply **not there**. Nothing is broken — you
are in a different shell. Type `pwsh` and it appears.

To have it start automatically:

```bash
# recommended — cannot lock you out
bash install.sh --login-shell auto

# or make pwsh your actual login shell
bash install.sh --login-shell login
```

`auto` appends a guarded block to `~/.bashrc`. If `pwsh` is ever removed or broken you
still get bash, so you can never be locked out of your own server. `login` (`chsh`) is
cleaner but leaves you with **no shell** if pwsh fails to start — avoid it on a headless
box unless you have console access.

Test either one **without logging out**, from a session you already have open:

```bash
bash -l
```

### ⚠️ Your GNU coreutils are safe — read this

PowerShell resolves a bare command name as `Alias → Function → Cmdlet → native binary`.
PowerFlow defines `rm`, `mv`, `cp`, `cat`, so on Linux those **would have shadowed the
real GNU tools**. They do not:

| You type | You get |
|---|---|
| `rm` `mv` `cp` `cat` `mkdir` `touch` `rmdir` `which` `grep` | the **real GNU tools**, untouched |
| **`del`** | PowerFlow's smart removal — fzf picker, confirmation (what `rm` is on Windows) |
| **`mvf`** | PowerFlow's cut-and-paste move (what `mv` is on Windows) |
| `ls` `la` `ll` | PowerFlow's pretty listing (deliberately overridden) |

This is deliberate. PowerFlow's `rm somedir` recursively deletes the whole tree after one
prompt, while GNU `rm somedir` **refuses** without `-r`. Shadowing it would have silently
removed a seatbelt you rely on. So on Linux, `rm` is always the `rm` you expect.

### Clean up the old port

Your old install keeps working but receives no updates. Restore the `.bashrc` backup the
old installer made:

```bash
ls -la ~/.bashrc.backup.*
cp "$(ls -t ~/.bashrc.backup.* | head -1)" ~/.bashrc
source ~/.bashrc

rm -f ~/.wsl_bookmarks.json ~/.wsl_init_check \
      ~/.wsl_profile_update_check ~/.nav_history
```

> No `~/.bashrc.backup.*`? Then your `~/.bashrc` *was* PowerFlow's. Replace it with your
> distro's default — on Debian/Ubuntu: `cp /etc/skel/.bashrc ~/.bashrc`.

### What works on Linux

`nav` and bookmarks, the full `git-*` suite, `gh-l` / `gh-l-org`, fuzzy pickers, `ls`/`la`/`ll`,
`del`/`mvf`/`rn`, clipboard integration (`wl-copy`/`xclip`), `set-path`, `shutdown`,
`pwsh-h`, and tab management via **tmux** (Windows Terminal's equivalent).

### Uninstalling

Uninstall is **manifest-based**: PowerFlow records what it installed, and **never removes a
tool you already had**. If you had `fzf` before, uninstalling PowerFlow leaves `fzf` alone.

```bash
powerflow-uninstall           # from inside PowerFlow
bash install.sh --uninstall   # from a terminal
```

---

## WSL users — you are fine

The most common confusion, so explicitly:

**Launching a WSL tab *from Windows* still works.** `open-ubuntu`, `open-wsl-simple`,
`Get-WindowsTerminalProfiles` and `open-nt ubuntu|wsl|bash` are **Windows** PowerShell
functions — they open an Ubuntu tab in Windows Terminal and translate your current path to
its `/mnt/c/…` equivalent. None of that was part of the Linux port, and none of it changed.

What *did* change is the shell profile that runs **inside** Linux. The old enhanced
`.bashrc` is gone. If you want PowerFlow inside your WSL distro now, install the new Linux
port there and run `pwsh`.
