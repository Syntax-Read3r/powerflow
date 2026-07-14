# ==============================================================================
# PowerFlow — Command Bindings (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/bindings.ps1
# Purpose  : Bind PowerFlow's commands to their user-facing names, and provide the
#            Unix-style utilities Windows lacks
# Functions: which
# Depends  : loaded AFTER components/ (it rebinds names the components define)
# ==============================================================================
#
# Windows has no GNU coreutils, so there is nothing to shadow: PowerFlow's `rm`,
# `mv`, `ls`, `cat` etc. are the only implementations present, and they stay bound
# to their natural names exactly as they always have.
#
# Compare platform/linux/bindings.ps1, which must be far more careful.
# ==============================================================================

# Unix-style helpers Windows does not ship
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
