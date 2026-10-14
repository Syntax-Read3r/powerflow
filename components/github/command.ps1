# ==============================================================================
# PowerFlow — GitHub Command Family
# Domain   : GitHub
# File     : components/github/command.ps1
# Purpose  : Thin github dispatcher, executable help, and legacy migration wrappers
# Functions: github, gh-l, gh-l-org, gh-l-status, gh-l-reset, Invoke-PFGitHubCommand,
#            Get-PFGitHubArguments, Show-PFGitHubHelp, Write-PFGitHubMigration
# Depends  : repositories.ps1, browser.ps1, review.ps1, shared/flags.ps1, help/registry.ps1
# ==============================================================================

if ($null -eq $script:PF_GitHubMigrationSeen) {
    $script:PF_GitHubMigrationSeen = [System.Collections.Generic.HashSet[string]]::new()
}

function Write-PFGitHubMigration {
    param([string]$Name, [string]$Replacement)
    if ($script:PF_GitHubMigrationSeen.Add($Name)) {
        Write-Host "   note: $Name is now $Replacement. Both still work." -ForegroundColor DarkGray
    }
}

function Show-PFGitHubHelp {
    Write-Host 'PowerFlow GitHub — gh remains the GitHub CLI' -ForegroundColor Cyan
    @(
        'github                       browse 10 recent repositories; select one to clone/open',
        'github 50 --oldest            browse 50 repositories, oldest last push first',
        'github stale                 review all owned repositories, oldest first',
        'github stale --older-than 1y  filter by last push (positive days/months/years: d/m/y)',
        'github stale --pages          review Pages-enabled repositories',
        'github stale --count 50       limit the review after filtering and sorting',
        'github org [my-team]          browse organization repositories; optional picker',
        'github org my-team --count 50 limit organization browsing',
        'github token status          show token sources without showing the token',
        'github token reset           remove the saved token; GITHUB_TOKEN is unchanged',
        'github help                  this reference (also --help or -h)',
        'github --token <token>        override token source; prefer GITHUB_TOKEN to shell history'
    ) | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Last push measures code activity, not usage or redundancy. Unknown dates are grouped last.' -ForegroundColor DarkGray
    Write-Host 'Pages includes account sites, project sites, and custom domains; unavailable details remain unknown.' -ForegroundColor DarkGray
    Write-Host 'Review offers inspect/open/copy/clone, with no delete or archive action.' -ForegroundColor DarkGray
    Write-Host 'Fine-grained tokens may need Pages read permission. Build status does not prove current reachability.' -ForegroundColor DarkGray
}

function Get-PFGitHubArguments {
    param([string]$Target, [object[]]$Argv, [string[]]$Allowed, [string[]]$Positionals)
    $metadata = (Get-Command $Target -CommandType Function).Parameters
    $surface = @{}; $byFlat = @{}
    foreach ($name in $Allowed) {
        $surface[$name] = $metadata[$name]
        $byFlat[($name.ToLowerInvariant() -replace '-', '')] = $name
        foreach ($alias in @($metadata[$name].Aliases)) {
            $byFlat[($alias.ToLowerInvariant() -replace '-', '')] = $name
        }
    }
    # The shared translator retains legacy spelling/prefix behavior. Validate repetitions
    # first because its general-purpose hashtable intentionally takes the last occurrence.
    $seen = @{}
    for ($i = 0; $i -lt $Argv.Count; $i++) {
        $word = [string]$Argv[$i]
        if ($word -eq '--') { break }
        if ($word -notmatch '^--?([A-Za-z][\w-]*)(?:=(.*))?$') { continue }
        $option = $Matches[1]
        $inline = $word.Contains('=')
        $resolved = Resolve-PFFlagName -Word $option -ByFlatName $byFlat
        if (-not $resolved) { throw "Unknown option '$word'. Run github help for accepted options." }
        if ($seen.ContainsKey($resolved)) { throw "Repeated option --$(ConvertTo-PFKebab $resolved). Supply it once." }
        $seen[$resolved] = $true
        if (-not (Test-PFFlagIsSwitch -Name $resolved -Parameters $surface) -and -not $inline) {
            if ($i + 1 -ge $Argv.Count -or [string]$Argv[$i + 1] -match '^--?[A-Za-z]') {
                throw "--$(ConvertTo-PFKebab $resolved) requires a value. Run github help."
            }
            $i++
        }
    }
    try { $parsed = ConvertTo-PFCanonicalFlags -Argv $Argv -Parameters $surface -Command 'github' }
    catch { throw 'Invalid option value. Run github help for examples.' }
    if ($parsed.Unknown.Count) { throw 'Unknown or incomplete option. Run github help for examples.' }
    if ($parsed.Positional.Count -gt $Positionals.Count) { throw 'Too many arguments. Run github help for examples.' }
    $named = $parsed.Named
    for ($i = 0; $i -lt $parsed.Positional.Count; $i++) {
        $name = $Positionals[$i]
        if ($named.ContainsKey($name)) { throw "Supply $name either positionally or as an option, once." }
        $named[$name] = $parsed.Positional[$i]
    }
    if ($named.ContainsKey('Count')) {
        $countValue = 0
        if ([string]$named.Count -notmatch '^[1-9][0-9]*$' -or -not [int]::TryParse([string]$named.Count, [ref]$countValue)) {
            throw 'Count must be a positive integer. Try github 50 --oldest.'
        }
        $named.Count = $countValue
    }
    if ($named.ContainsKey('OlderThan')) { $null = Get-PFGitHubAgeCutoff $named.OlderThan }
    return $named
}

function Invoke-PFGitHubCommand {
    param([object[]]$Argv = @())
    try {
        $tail = @($Argv)
        if ($tail.Count -eq 1 -and [string]$tail[0] -in @('help', '--help', '-h')) { Show-PFGitHubHelp; return }
        $route = if ($tail.Count) { [string]$tail[0] } else { '' }
        switch ($route) {
            'stale' {
                $tail = @($tail | Select-Object -Skip 1)
                if ($tail.Count -eq 1 -and [string]$tail[0] -in @('--help', '-h')) { Show-PFGitHubHelp; return }
                $named = Get-PFGitHubArguments -Target 'Show-PFGitHubReview' -Argv $tail `
                    -Allowed @('Count', 'Token', 'OlderThan', 'Pages') -Positionals @('Count')
                Show-PFGitHubReview @named
            }
            'org' {
                $tail = @($tail | Select-Object -Skip 1)
                if ($tail.Count -eq 1 -and [string]$tail[0] -in @('--help', '-h')) { Show-PFGitHubHelp; return }
                $named = Get-PFGitHubArguments -Target 'Invoke-PFGitHubOrgBrowser' -Argv $tail `
                    -Allowed @('Org', 'Count') -Positionals @('Org', 'Count')
                Invoke-PFGitHubOrgBrowser @named
            }
            'token' {
                if ($tail.Count -ne 2) { throw 'Use github token status or github token reset.' }
                switch ([string]$tail[1]) {
                    'status' {
                        if ($env:GITHUB_TOKEN) { Write-Host 'GITHUB_TOKEN is set for this session (value hidden).' -ForegroundColor DarkGray }
                        Show-GitHubTokenStatus
                    }
                    'reset' { Remove-GitHubSavedToken }
                    default { throw 'Use github token status or github token reset.' }
                }
            }
            default {
                if ($route -and $route -notmatch '^-|^[0-9]+$') { throw "Unknown route '$route'. Run github help." }
                $named = Get-PFGitHubArguments -Target 'Show-PFGitHubBrowser' -Argv $tail `
                    -Allowed @('Count', 'Token', 'Oldest') -Positionals @('Count', 'Token')
                Show-PFGitHubBrowser @named
            }
        }
    }
    catch { Write-PFFailure $_.Exception.Message -Hint 'Try github help.' }
}

# Retain the documented argument forms, while all logic lives in the new family.
function gh-l {
    Write-PFGitHubMigration 'gh-l' 'github'
    Invoke-PFGitHubCommand -Argv $args
}
function gh-l-org {
    Write-PFGitHubMigration 'gh-l-org' 'github org'
    Invoke-PFGitHubCommand -Argv (@('org') + $args)
}
function gh-l-status {
    Write-PFGitHubMigration 'gh-l-status' 'github token status'
    Invoke-PFGitHubCommand -Argv (@('token', 'status') + $args)
}
function gh-l-reset {
    Write-PFGitHubMigration 'gh-l-reset' 'github token reset'
    Invoke-PFGitHubCommand -Argv (@('token', 'reset') + $args)
}
Register-PFCommand -Name 'gh-l' -Section '🐙 GITHUB BROWSER' -Synopsis 'compatibility: use github to browse and clone repositories' -Example 'github 50 --oldest'
Register-PFCommand -Name 'gh-l-org' -Section '🐙 GITHUB BROWSER' -Synopsis 'compatibility: use github org to browse an organization' -Example 'github org my-team'
Register-PFCommand -Name 'gh-l-status' -Section '🐙 GITHUB BROWSER' -Synopsis 'compatibility: use github token status'
Register-PFCommand -Name 'gh-l-reset' -Section '🐙 GITHUB BROWSER' -Synopsis 'compatibility: use github token reset'

# Re-loading our own function is safe; another command must not be silently shadowed.
$_pf_existingGithub = Get-Command github -ErrorAction SilentlyContinue
if ($_pf_existingGithub -and ($_pf_existingGithub.CommandType -ne 'Function' -or
    $_pf_existingGithub.ScriptBlock.File -ne $PSCommandPath)) {
    Write-PFWarning "PowerFlow could not register github: another command already uses that name. Use gh-l, or resolve the collision and reload the profile."
    Remove-Variable _pf_existingGithub -ErrorAction SilentlyContinue
    return
}
Remove-Variable _pf_existingGithub -ErrorAction SilentlyContinue
function github { Invoke-PFGitHubCommand -Argv $args }
Register-PFCommand -Name 'github' -Section '🐙 GITHUB BROWSER' -Synopsis 'browse, clone, or review stale repositories with Pages status' -Example 'github stale --older-than 1y --pages'
