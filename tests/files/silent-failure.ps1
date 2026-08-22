$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}

# ==============================================================================
# A file operation that fails must not report success.
#
# Three sites printed a green banner over an operation that had not happened. All three had
# the same root cause and one of them had a second, worse one.
#
#   files/rename.ps1     asked the user to approve an overwrite, then called a cmdlet that
#                        CANNOT overwrite -- so the approved path failed 100% of the time,
#                        printed "RENAME COMPLETED", and with -Chmod then applied the
#                        permissions to the file it had failed to replace.
#   files/operations.ps1 printed "MOVE COMPLETED" and then CLEARED the held cut, so the user
#                        lost the file they were holding as well as the move. The catch's own
#                        advice -- "The file is still held" -- was true only when it could
#                        not print.
#   files/clipboard.ps1  printed "Pasted", then stat'd the PRE-EXISTING destination and
#                        printed its size. A false success that shows a plausible number
#                        beside it is far harder to disbelieve than a bare one.
#
# THE PLATFORM FACTS ARE EXECUTED, NOT ASSERTED ABOUT. If a future PowerShell made Move-Item
# terminating by default, or let Rename-Item overwrite, these tests would say so instead of
# quietly continuing to guard a hazard that no longer exists.
# ==============================================================================

$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('pf-silent-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

try {
    # ---- FACT 1: Rename-Item cannot overwrite, even with -Force --------------
    Set-Content -LiteralPath (Join-Path $sandbox 'a.txt') -Value 'SOURCE'
    Set-Content -LiteralPath (Join-Path $sandbox 'b.txt') -Value 'VICTIM'
    $renameThrew = $false
    try { Rename-Item -LiteralPath (Join-Path $sandbox 'a.txt') -NewName 'b.txt' -Force -ErrorAction Stop }
    catch { $renameThrew = $true }
    Assert-True $renameThrew 'Rename-Item -Force still cannot overwrite an existing file'
    Assert-True ((Get-Content -LiteralPath (Join-Path $sandbox 'b.txt')) -eq 'VICTIM') 'and it leaves the target untouched'

    # ---- FACT 2: Move-Item -Force CAN, which is why the fix swaps the cmdlet -
    Move-Item -LiteralPath (Join-Path $sandbox 'a.txt') -Destination (Join-Path $sandbox 'b.txt') -Force -ErrorAction Stop
    Assert-True ((Get-Content -LiteralPath (Join-Path $sandbox 'b.txt')) -eq 'SOURCE') 'Move-Item -Force overwrites'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sandbox 'a.txt'))) 'and consumes the source'

    # ---- FACT 3: without -ErrorAction Stop, a failed move never reaches catch
    # This is the fault all three sites shared, and the reason a green banner printed.
    Set-Content -LiteralPath (Join-Path $sandbox 'x.txt') -Value 'X'
    Set-Content -LiteralPath (Join-Path $sandbox 'y.txt') -Value 'Y'
    $reachedCatch = $false
    try { Move-Item -LiteralPath (Join-Path $sandbox 'x.txt') -Destination (Join-Path $sandbox 'y.txt') -ErrorAction SilentlyContinue }
    catch { $reachedCatch = $true }
    Assert-True (-not $reachedCatch) 'a failing Move-Item is NON-terminating: try/catch does not fire without -ErrorAction Stop'
    Assert-True (Test-Path -LiteralPath (Join-Path $sandbox 'x.txt')) 'and the file has demonstrably not moved'

    # ---- the three sites now stop on failure --------------------------------
    # Comment-stripped: every one of these files explains the old bug in prose, and a scan of
    # raw source would match the explanation instead of the code. The parity gate records
    # this repository having been fooled that way three times already.
    function Get-CodeOnly([string]$RelPath) {
        $lines = Get-Content -LiteralPath (Join-Path $repo $RelPath)
        return (@($lines | Where-Object { $_.Trim() -notmatch '^#' }) -join "`n")
    }

    $rename = Get-CodeOnly 'components/files/rename.ps1'
    Assert-True ($rename -match 'Move-Item[^\r\n]*-Force[^\r\n]*-ErrorAction Stop') 'rename overwrites with Move-Item -Force, and stops on failure'
    Assert-True ($rename -match 'Rename-Item[^\r\n]*-ErrorAction Stop') 'the non-overwrite rename stops on failure too'
    Assert-True ($rename -notmatch 'Rename-Item[^\r\n]*-NewName \$newFileName\s*$') 'no bare Rename-Item remains'

    $ops = Get-CodeOnly 'components/files/operations.ps1'
    Assert-True ($ops -match 'Move-Item[^\r\n]*-Destination \$currentDir[^\r\n]*-ErrorAction Stop') 'mv-t stops on a failed move'
    # The held cut must only be dropped after the move is known to have happened.
    # Searched FROM the move onwards: $script:MoveInHand = $null also appears earlier, in the
    # declaration and in the cancel path, and a bare IndexOf finds those instead.
    $moveIdx = $ops.IndexOf('-Destination $currentDir')
    Assert-True ($moveIdx -gt 0) 'the move site is present'
    $clearIdx = $ops.IndexOf('$script:MoveInHand = $null', $moveIdx)
    Assert-True ($clearIdx -gt $moveIdx) 'the held file is cleared only after the move'
    Assert-True ($ops -match 'Test-Path -LiteralPath \$landed') 'and the move is verified by reading the filesystem back'

    $clip = Get-CodeOnly 'components/files/clipboard.ps1'
    Assert-True ($clip -match 'Copy-Item[^\r\n]*-ErrorAction Stop') 'paste stops on a failed copy'
    Assert-True ($clip -match '\$copiedFile\.Length -ne \$sourceItem\.Length') 'and compares the written length against the source'
}
finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'OK - failed file operations stop, verify, and never print a green banner.'
