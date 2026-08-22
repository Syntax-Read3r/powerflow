$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

# ==============================================================================
# An upgrade must not silently undo what the user chose.
#
# THE BUG THIS EXISTS FOR. install.ps1 deletes config/ and replaces it wholesale, which is
# right for code but wrong for config/PowerFlow.settings.ps1 -- `pwsh-reminders` and the
# update prompt REWRITE THAT FILE IN PLACE to persist the user's answer
# (components/core/version.ps1). So turning update reminders off and then upgrading turned
# them back on, with nothing on screen to say why. A setting that quietly reverts is worse
# than one that cannot be changed: the user believes they have changed it.
#
# The preserve/restore logic is lifted out of install.ps1 and executed here, rather than
# reimplemented. Running the whole installer would drag in Scoop, the Nerd Font and a real
# $PROFILE; the roundtrip test already covers that path, and a test that copies the rule it
# is checking proves only that two copies agree.
# ==============================================================================

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$installer = Join-Path $repo 'install.ps1'
Assert-True (Test-Path -LiteralPath $installer) 'install.ps1 exists'
$src = Get-Content -LiteralPath $installer -Raw

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('pf-settings-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$profileDir = Join-Path $sandbox 'PowerShell'
New-Item -ItemType Directory -Path (Join-Path $profileDir 'config') -Force | Out-Null

try {
    # The user's INSTALLED settings: reminders switched off, a database password changed,
    # and an old version number that must NOT survive.
    $installed = @(
        '$script:POWERFLOW_VERSION = "4.0.0"'
        '$script:POWERFLOW_REPO = "Syntax-Read3r/powerflow"'
        '$script:CHECK_PROFILE_UPDATES = $false'
        '$script:CHECK_DEPENDENCIES = $true'
        '$script:CHECK_UPDATES = $true'
        '$script:DB_USERNAME = "postgres"'
        '$script:DB_PASSWORD = "hunter2"'
    )
    $settingsPath = Join-Path $profileDir 'config/PowerFlow.settings.ps1'
    Set-Content -LiteralPath $settingsPath -Value $installed -Encoding UTF8

    # --- capture, exactly as install.ps1 does, before the wipe ---------------
    # \r? before $ : install.ps1 is CRLF, and .NET's multiline $ matches before \n only, so
    # a bare ^\}$ never matches a line that really ends "}\r".
    $capture = [regex]::Match($src, '(?s)\$preserved = @\{\}.*?^\}\r?$', 'Multiline').Value
    Assert-True ([bool]$capture) 'the capture block is present in install.ps1'
    Invoke-Expression $capture
    Assert-True ($preserved.Count -eq 7) 'every script-scoped setting is captured'
    Assert-True ($preserved['CHECK_PROFILE_UPDATES'] -eq '$false') 'the user''s choice is captured'
    Assert-True ($preserved['DB_PASSWORD'] -eq '"hunter2"') 'a changed password is captured'

    # --- the wipe and copy, as the installer does ---------------------------
    # The SHIPPED defaults: a new version, reminders on, the stock password, and a setting
    # that did not exist in the user's installed copy.
    Remove-Item (Join-Path $profileDir 'config') -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $profileDir 'config') -Force | Out-Null
    Set-Content -LiteralPath $settingsPath -Encoding UTF8 -Value @(
        '$script:POWERFLOW_VERSION = "5.2.0"'
        '$script:POWERFLOW_REPO = "Syntax-Read3r/powerflow"'
        '$script:CHECK_PROFILE_UPDATES = $true'
        '$script:CHECK_DEPENDENCIES = $true'
        '$script:CHECK_UPDATES = $true'
        '$script:DB_USERNAME = "postgres"'
        '$script:DB_PASSWORD = "password"'
        '$script:BRAND_NEW_SETTING = $true'
    )

    # --- restore, exactly as install.ps1 does -------------------------------
    $restore = [regex]::Match($src, "(?s)\`$releaseOwned = @\('POWERFLOW_VERSION'.*?^\}\r?$", 'Multiline').Value
    Assert-True ([bool]$restore) 'the restore block is present in install.ps1'
    Invoke-Expression $restore

    $after = @{}
    foreach ($line in (Get-Content -LiteralPath $settingsPath)) {
        if ($line -match '^\s*\$script:([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$') { $after[$Matches[1]] = $Matches[2] }
    }

    # THE REGRESSION: the user's answer survives the upgrade.
    Assert-True ($after['CHECK_PROFILE_UPDATES'] -eq '$false') 'a setting the user turned off stays off across an upgrade'
    Assert-True ($after['DB_PASSWORD'] -eq '"hunter2"') 'a changed password survives an upgrade'

    # THE RELEASE OWNS THE VERSION. Carrying it forward would make the profile announce a
    # version it is not, and would defeat the update check that reads it.
    Assert-True ($after['POWERFLOW_VERSION'] -eq '"5.2.0"') 'the new version is NOT overwritten by the old one'
    Assert-True ($after['POWERFLOW_REPO'] -eq '"Syntax-Read3r/powerflow"') 'the repo stays release-owned'

    # A new release is free to change a default the user never touched.
    Assert-True ($after['BRAND_NEW_SETTING'] -eq '$true') 'a setting added by the new release keeps its default'
    Assert-True ($after['CHECK_DEPENDENCIES'] -eq '$true') 'a setting matching the default is left alone'
    Assert-True ($after.Count -eq 8) 'no setting is lost or invented'

    # --- a first install has nothing to preserve, and must not explode ------
    $fresh = Join-Path $sandbox 'Fresh'
    New-Item -ItemType Directory -Path (Join-Path $fresh 'config') -Force | Out-Null
    $profileDir = $fresh
    Invoke-Expression $capture
    Assert-True ($preserved.Count -eq 0) 'a first install captures nothing and does not throw'
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'OK - an upgrade keeps the settings you changed and takes the version it shipped with.'
