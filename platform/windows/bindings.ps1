# ==============================================================================
# PowerFlow — Command Bindings (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/bindings.ps1
# Purpose  : Give PowerFlow's commands their extra Windows names, and provide the
#            Unix-style utilities Windows does not ship
# Functions: which
# Depends  : loaded AFTER components/ (it binds names on top of what they define)
# ==============================================================================
#
# THIS FILE ONLY ADDS.
#
# It used to have a Linux counterpart whose whole job was *removing* things —
# components/ defined `rm`, `mv`, `mkdir`, `touch`, `cat` and `cp`, and on Linux each of
# those hid the GNU tool of the same name, so platform/linux/bindings.ps1 had to unpick
# them one at a time. That failed in the dangerous direction: the shadowing happened
# unconditionally and the undo happened conditionally, so anything that kept the undo
# from running left a Linux user with a silently substituted `rm`. Its own header
# recorded that the bug had already shipped once.
#
# So the components no longer claim any coreutil name. PowerFlow's delete and move carry
# its own names — `del` and `mvf` — on every platform, the three clones Windows genuinely
# needs live in windows-only/coreutils.ps1, and `cat`/`cp` are gone entirely (PowerShell
# already ships both on Windows). Linux now needs no bindings file at all.
#
# What remains here is addition only, and the failure mode is correspondingly boring: if
# this file does not load, Windows loses a few conveniences. It cannot hand any platform
# a command that does something other than what its name says.
# ==============================================================================

# ── Extra Windows names for PowerFlow's own file commands ─────────────────────
# `rm` and `mv` are safe to take on Windows because there is no GNU tool underneath to
# hide — PowerShell's own `rm`/`mv` are thin aliases for Remove-Item/Move-Item, and
# PowerFlow's versions are strictly more capable (GNU flag parsing, an fzf picker,
# confirmation before a recursive delete). -Force is required: both names are already
# built-in aliases, and an alias outranks a function.
#
# On Linux these two lines are simply absent, so `rm` and `mv` mean what a Linux user's
# reflexes say they mean. `del` and `mvf` work identically on both.
Set-Alias rm del  -Scope Global -Force   # PowerFlow's delete (see components/files/operations.ps1)
Set-Alias mv mvf  -Scope Global -Force   # PowerFlow's move/cut workflow

# ── Unix-style helpers Windows does not ship ──────────────────────────────────
Set-Alias grep Select-String -Scope Global -Force   # search text in files
Set-Alias less more          -Scope Global -Force   # page through content
Set-Alias pwd  Get-Location  -Scope Global -Force   # print working directory

<#
.SYNOPSIS
    Find the location of a command (Unix-style which)
.EXAMPLE
    which git     # Shows path to git executable
#>
function which {
    param($cmd)
    Get-Command $cmd | Select-Object -ExpandProperty Definition
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
# Registered as Windows-only aliases of the canonical commands, so pwsh-h tells a Windows
# user that `rm` works without telling a Linux user the same untruth.
Register-PFCommand -Name 'del' -Section '📂 ENHANCED FILE OPERATIONS' `
    -Synopsis 'delete with GNU flags; refuses a dir without -r' -Example 'rm -rf node_modules' `
    -Aliases @('rm') -Platform 'Windows'
Register-PFCommand -Name 'mvf' -Section '📂 ENHANCED FILE OPERATIONS' `
    -Synopsis '2+ args move like bash; 1 arg cuts (mv-t pastes)' -Example 'mv old.txt new.txt' `
    -Aliases @('mv') -Platform 'Windows'
