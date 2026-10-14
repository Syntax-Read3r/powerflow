$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$script:assertions = 0
function Ok([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:assertions++
}
. (Join-Path $root 'components/help/registry.ps1')
. (Join-Path $root 'components/shared/outcome.ps1')
. (Join-Path $root 'components/shared/flags.ps1')
. (Join-Path $root 'components/git/release.ps1')
$script:PowerFlowRoot = $root
$script:POWERFLOW_REPO = 'example/powerflow'

$docs = Get-PFReleaseDocs
Ok ($docs.Prompt -match 'release.*release command' -and $docs.Prompt -notmatch 'git-rl') 'local setup prompt teaches canonical release name'
Ok ($docs.Manual -match 'release setup') 'local manual teaches canonical setup route'
$registered = @(Get-PFCommandRegistry | Where-Object { $_.Name -in @('release', 'git-rl', 'git-release') })
Ok ($registered.Count -eq 3 -and @($registered | Where-Object { $_.Section -ne '🚀 RELEASE WORKFLOWS' }).Count -eq 0) 'all release commands register in a release-specific section'

$script:releaseCalls = 0; $script:setupCalls = 0
function Show-PFReleaseSetup { $script:setupCalls++ }
function Invoke-PFRelease {
    [CmdletBinding()]
    param([Alias('h', 'help', '?')][switch]$ShowSetupPrompt)
    if ($ShowSetupPrompt) { Show-PFReleaseSetup } else { $script:releaseCalls++ }
}
function git { throw 'TRIPWIRE: routing and help must not invoke Git' }
function fzf { throw 'TRIPWIRE: routing and help must not open a picker' }
function Read-Host { throw 'TRIPWIRE: routing and help must not prompt' }
function Invoke-WebRequest { throw 'TRIPWIRE: routing and help must not access network' }
function Write-PFReleaseGuide { throw 'TRIPWIRE: help must not write a guide' }

release
Ok ($script:releaseCalls -eq 1 -and $script:setupCalls -eq 0) 'bare release routes to release preparation'
release setup
Ok ($script:setupCalls -eq 1 -and $script:releaseCalls -eq 1) 'setup routes only to setup flow'
foreach ($argv in @(@('help'), @('--help'), @('-h'), @('-help'), @('-?'), @('setup', '--help'))) {
    $helpOut = @(Invoke-PFReleaseCommand -Argv $argv 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($helpOut -match 'release setup' -and $helpOut -match 'release help') 'help contains executable canonical routes'
    Ok ($script:setupCalls -eq 1 -and $script:releaseCalls -eq 1) 'new help never starts setup or release'
}
foreach ($argv in @(@('oops'), @('setup', 'extra'), @('--patch'), @('--show-setup-prompt'), @('help', 'extra'), @('--help', '--help'))) {
    $badOut = @(Invoke-PFReleaseCommand -Argv $argv 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($badOut -match 'Unknown release' -and $badOut -match 'No action was taken') 'unknown or extra arguments are refused'
    Ok ($script:setupCalls -eq 1 -and $script:releaseCalls -eq 1) 'invalid arguments cause no preparation or setup'
}

$legacyOut = @(git-rl 6>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($legacyOut -match 'git-rl is now release' -and $script:releaseCalls -eq 2) 'legacy release routes with migration notice'
$legacyAgain = @(git-rl 6>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($legacyAgain -notmatch 'git-rl is now' -and $script:releaseCalls -eq 3) 'migration notice appears once per session'
$null = git-release 6>&1
Ok ($script:releaseCalls -eq 4) 'legacy long command routes to release'
foreach ($form in @('-h', '--help', '-help', '--show-setup-prompt')) {
    $before = $script:setupCalls
    $null = git-rl $form 6>&1
    Ok ($script:setupCalls -eq ($before + 1)) "legacy git-rl $form still opens setup"
    $before = $script:setupCalls
    $null = git-release $form 6>&1
    Ok ($script:setupCalls -eq ($before + 1)) "legacy git-release $form still opens setup"
}
$before = $script:releaseCalls
$invalidLegacy = @(git-rl --unknown 6>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($invalidLegacy -match 'unknown option' -and $script:releaseCalls -eq $before) 'legacy invalid option cannot release'

function release { return 'external release sentinel' }
$collisionOut = @(. (Join-Path $root 'components/git/release.ps1') 6>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ((release) -eq 'external release sentinel' -and $collisionOut -match 'another command') 'external release command is preserved on collision'
Remove-Item -LiteralPath Function:release
. (Join-Path $root 'components/git/release.ps1')
$reloadOut = @(. (Join-Path $root 'components/git/release.ps1') 6>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($reloadOut -notmatch 'another command') 'own command reloads without collision'
$helpOut = @(release help 6>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($helpOut -match 'A release is published only after') 'help distinguishes tag push from publication'

Write-Host "Release command family: $script:assertions assertions passed."
