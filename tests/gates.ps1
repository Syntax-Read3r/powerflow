# ==============================================================================
# Run the release gates locally, by extracting them from the workflow itself
# ==============================================================================
# There used to be a hand-written local copy of these checks, and it drifted: its adapter
# list was five names short of the real one, so it reported "clean" on a tree the actual
# release gate would have rejected. A local gate that can disagree with CI is worse than
# no local gate, because it is trusted.
#
# So this does not reimplement anything. It parses .github/workflows/release-validate.yml,
# pulls out each `shell: pwsh` step's script verbatim, and runs it. If CI's gate changes,
# this changes with it — there is no second copy to forget.
#
# Steps referencing ${{ ... }} are skipped: they need GitHub's expression context (tag
# names, step outputs) that does not exist locally. They are listed as skipped rather than
# silently dropped, because "3 gates passed" reads very differently from "3 passed, 4 not
# run".
#
# Usage:
#   pwsh -File tests/gates.ps1                # every runnable gate
#   pwsh -File tests/gates.ps1 -Filter coreutil   # just the ones whose name matches
#   pwsh -File tests/gates.ps1 -List           # show what would run
# ==============================================================================

param(
    [string]$Filter = '',
    [switch]$List
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workflow = Join-Path $root '.github/workflows/release-validate.yml'
if (-not (Test-Path $workflow)) { throw "workflow not found: $workflow" }

# ── extract the steps ─────────────────────────────────────────────────────────
# Deliberately a small hand parser rather than a YAML library: the only structure that
# matters is "- name:" followed by "shell: pwsh" and a "run: |" block, and depending on a
# YAML module would make the local check harder to run than CI itself.
$lines = [IO.File]::ReadAllLines($workflow)
$steps = @()
$current = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]

    if ($line -match '^(\s*)- name:\s*(.+)$') {
        if ($current) { $steps += $current }
        $name = $Matches[2].Trim().Trim('"').Trim("'")
        # GitHub allows \U-escaped emoji in names; keep it readable in the local output.
        if ($name -match '^\\U([0-9A-Fa-f]{8})\s*(.*)$') {
            $name = [char]::ConvertFromUtf32([Convert]::ToInt32($Matches[1], 16)) + ' ' + $Matches[2]
        }
        $current = [ordered]@{ Name = $name; Shell = ''; Script = @(); Indent = 0 }
        continue
    }
    if (-not $current) { continue }

    if ($line -match '^\s*shell:\s*(\S+)') { $current.Shell = $Matches[1]; continue }
    if ($line -match '^(\s*)run:\s*\|\s*$') {
        # The block body is indented past `run:` itself.
        $current.Indent = $Matches[1].Length + 2
        for ($j = $i + 1; $j -lt $lines.Count; $j++) {
            $body = $lines[$j]
            if ($body.Trim().Length -eq 0) { $current.Script += ''; continue }
            $lead = $body.Length - $body.TrimStart().Length
            if ($lead -lt $current.Indent) { break }
            $current.Script += $body.Substring($current.Indent)
        }
        $i = $j - 1
        continue
    }
}
if ($current) { $steps += $current }

$runnable = @($steps | Where-Object { $_.Shell -eq 'pwsh' -and $_.Script.Count -gt 0 })
if ($Filter) { $runnable = @($runnable | Where-Object { $_.Name -match [regex]::Escape($Filter) }) }

if (-not $runnable.Count) {
    Write-Host "no pwsh gates matched$(if ($Filter) { " filter '$Filter'" })" -ForegroundColor Yellow
    exit 1
}

if ($List) {
    Write-Host "gates in release-validate.yml:" -ForegroundColor Cyan
    foreach ($s in $runnable) {
        $needsCi = (($s.Script -join "`n") -match '\$\{\{')
        Write-Host ("  {0} {1}" -f $(if ($needsCi) { '(needs CI)' } else { '          ' }), $s.Name)
    }
    exit 0
}

# ── run them ──────────────────────────────────────────────────────────────────
Push-Location $root
$pwshExe = (Get-Process -Id $PID).Path
$passed = @(); $failed = @(); $skipped = @()
try {
    foreach ($step in $runnable) {
        $script = $step.Script -join "`n"
        if ($script -match '\$\{\{') { $skipped += $step.Name; continue }

        $temp = Join-Path ([IO.Path]::GetTempPath()) ("pf-gate-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
        try {
            [IO.File]::WriteAllText($temp, $script)
            $out = & $pwshExe -NoProfile -File $temp 2>&1
            if ($LASTEXITCODE -eq 0) {
                $passed += $step.Name
                Write-Host ("  PASS  {0}" -f $step.Name) -ForegroundColor Green
            }
            else {
                $failed += $step.Name
                Write-Host ("  FAIL  {0}" -f $step.Name) -ForegroundColor Red
                $out | Select-Object -Last 12 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkGray }
            }
        }
        finally { if (Test-Path $temp) { Remove-Item $temp -Force } }
    }
}
finally { Pop-Location }

Write-Host ''
Write-Host ("{0} passed, {1} failed, {2} skipped (need GitHub context)" -f $passed.Count, $failed.Count, $skipped.Count) `
    -ForegroundColor $(if ($failed.Count) { 'Red' } else { 'Green' })
foreach ($s in $skipped) { Write-Host "  skipped: $s" -ForegroundColor DarkGray }
if ($failed.Count) { exit 1 }
