# ==============================================================================
# PowerFlow — Command Registry
# ==============================================================================
# Domain   : Help
# File     : components/help/registry.ps1
# Purpose  : The one source of truth for what commands exist and what they do.
#            Every component registers its own commands; pwsh-h renders from here.
# Functions: Register-PFCommand, Get-PFCommandRegistry, Get-PFHelpSections
# Depends  : none — and it MUST load before every other component
# ==============================================================================
#
# WHY THIS EXISTS
#
# pwsh-h used to be a hand-drawn, 350-line wall of box characters in a file far away
# from the commands it documented. Nothing connected `function git-aa` to its menu row,
# so rows went missing (an audit found 4), went FALSE (`ls -t` was documented as "tree
# view" for a full version after 3.3.0 made -t the GNU time-sort), and every row needed
# hand-padding to exactly 80 chars (emoji width broke 11 of them).
#
# Now: each component calls Register-PFCommand right beside the functions it defines.
# Help metadata lives WITH the code, rendering is computed, and CI fails the release if
# a user-facing command exists without a registration (see release-validate.yml).
# ==============================================================================

# Registration order is preserved (bootloader load order), which keeps related
# commands adjacent within a section without any extra bookkeeping.
$script:PF_CommandRegistry = [ordered]@{}

# Canonical section order — the order pwsh-h prints them in.
$script:PF_HelpSections = @(
    '🧭 SMART NAVIGATION & BOOKMARKS'
    '🎯 ENHANCED GIT WORKFLOW'
    '🐙 GITHUB BROWSER'
    '📂 ENHANCED FILE OPERATIONS'
    '🎓 LEARN LINUX'
    '🐚 BASH BUILTINS'
    '🖥️ MACHINE HEALTH'
    '🌐 SSH SERVERS'
    '🗄️ DISK RECLAIM'
    '🪟 TERMINAL TABS'
    '🧱 PROJECT GENERATORS'
    '⚙️ CONFIGURATION & SETTINGS'
    '🐧 WSL (WINDOWS-ONLY)'
)

<#
.SYNOPSIS
    Register a user-facing command so pwsh-h can render it. Call beside the function.
.DESCRIPTION
    -Name      the command as the user types it
    -Synopsis  ONE line, ~60 chars, present tense, no trailing period
    -Section   one of $script:PF_HelpSections (new sections: add there first)
    -Example   optional, shown in the detail view and fzf preview
    -Platform  Both (default) · Windows · Linux — filtered at render time
    -Aliases   short forms; rendered inline and counted by the CI drift gate
#>
function Register-PFCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Synopsis,
        [Parameter(Mandatory)][string]$Section,
        [string]$Example,
        [ValidateSet('Both', 'Windows', 'Linux')][string]$Platform = 'Both',
        [string[]]$Aliases = @()
    )

    $script:PF_CommandRegistry[$Name] = [pscustomobject]@{
        Name     = $Name
        Synopsis = $Synopsis
        Section  = $Section
        Example  = $Example
        Platform = $Platform
        Aliases  = $Aliases
    }
}

<#
.SYNOPSIS
    The registry, filtered to the platform this shell is actually running on.
#>
function Get-PFCommandRegistry {
    $os = if ($script:PowerFlowOS -eq 'linux') { 'Linux' } else { 'Windows' }
    return @($script:PF_CommandRegistry.Values | Where-Object {
        $_.Platform -eq 'Both' -or $_.Platform -eq $os
    })
}

function Get-PFHelpSections { return $script:PF_HelpSections }
