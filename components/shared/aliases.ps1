# ==============================================================================
# PowerFlow — Shared Aliases
# ==============================================================================
# Domain   : Shared
# File     : components/shared/aliases.ps1
# Purpose  : Provides cross-platform utility aliases (grep, less, which, pwd)
# Functions: which
# Depends  : none
# ==============================================================================

Set-Alias grep Select-String                        # Search text in files
Set-Alias less more                                 # Page through content

<#
.SYNOPSIS
    Find the location of a command (Unix-style which)
.PARAMETER cmd
    Command name to locate
.EXAMPLE
    which git     # Shows path to git executable
#>
function which {
    param($cmd)
    Get-Command $cmd | Select-Object -ExpandProperty Definition
}

# Additional useful aliases
Set-Alias pwd Get-Location         # Print working directory
