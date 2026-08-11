# Linux tests

`github-release-download.ps1` runs anywhere — it exercises the packages adapter with no real
network.

`coreutil-resolution.ps1` is different: **it must run inside a real Linux pwsh**, because what it
checks is name *resolution*, and that cannot be faked from Windows. It is the check the deleted
`platform/linux/bindings.ps1` used to perform at runtime.

**CI already covers this too**, in `release-validate-linux.yml`: a `distros` matrix (Alpine,
Arch, …) installs PowerFlow, loads the profile, and asserts `rm`/`mv`/`cp`/`cat`/`grep` resolve
to `Application` and that `del`/`mvf`/`nav`/`git-a`/`pwsh-h` exist. This script is the same idea
run **locally, before pushing**, and it goes further: it also checks that `windows-only/` does
not load, that GNU `rm` still refuses a directory without `-r`, and that the flag shims bind.
Use it to find a coreutil regression in a container in one minute rather than in a release run.

## Running it

The tree is mounted read-only; the container is disposable. Any engine works — this is podman on
Windows, talking to the default machine:

```powershell
$repo = 'c:\path\to\powerflow'
podman run --rm -v "${repo}:/pf:ro" mcr.microsoft.com/powershell:latest `
    pwsh -NoProfile -File /pf/tests/linux/coreutil-resolution.ps1
```

It loads the **real** profile, so on a fresh image it will install PowerFlow's dependencies
(starship, fzf, zoxide, lsd, git) inside the container first. That is intentional: it exercises
the actual first-run Linux path rather than a stubbed one.

## What it proves

| | |
|---|---|
| `rm` `mv` `cp` `cat` `mkdir` `touch` `rmdir` `grep` `less` `head` `tail` `df` `du` | all resolve to `Application` — the real binaries, not PowerFlow functions |
| `del` `mvf` `mv-t` `mv-c` | exist as functions, on Linux as well as Windows |
| `ls` | is PowerFlow's — the one deliberate override |
| `mkdir` `touch` `rmdir` `which` | are **not** functions here: `windows-only/` must not load |
| GNU `rm <dir>` | still refuses without `-r`. That seatbelt is the entire reason PowerFlow's delete is called `del` |
| the flag shims | bind, and an unknown `--flag` is refused on Linux too |

## One thing it deliberately does not assert

`pwd` resolves to an **Alias** (`Get-Location`) on Linux, and that is correct. Measured in the
same image with `-NoProfile`: PowerShell keeps `pwd` on Unix, unlike `cat`/`rm`/`mv`/`cp`/`ls`
which it drops there specifically to avoid clashing with the coreutils. So `pwd` being an alias is
the platform's baseline, not something PowerFlow did — asserting otherwise would be testing
PowerShell, and would fail for a reason nobody could act on.

`del` is likewise an alias for `Remove-Item` at baseline **on both platforms**, which is why
`components/files/operations.ps1` clears it before defining the function. An alias outranks a
function, so without that the command would be silently unreachable.
