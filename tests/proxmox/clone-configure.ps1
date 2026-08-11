# ==============================================================================
# PF-FEAT-003 — clone then configure, as one guarded workflow
# ==============================================================================
# Replaces the native four-command sequence:
#   qm clone 100 103 --name web-prod --full 1
#   qm set 103 --cores 2 --memory 4096
#   qm resize 103 scsi0 +8G
#   qm config 103
#
# Three properties matter more than the convenience:
#   1. EVERYTHING IS VALIDATED BEFORE ANYTHING IS CREATED. Discovering that "4Q" is not a memory
#      size after a VM exists costs a manual cleanup; refusing costs nothing.
#   2. ONE CONFIRMATION COVERS THE WHOLE TRANSACTION, and every step it will take appears in the
#      plan. A step that is not previewed is a step nobody agreed to.
#   3. IT IS NOT ATOMIC, and says so up front. If a later step fails the clone is KEPT —
#      deleting a successfully cloned VM because a setting failed is the more destructive choice.
# ==============================================================================

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
function Register-PFCommand { }
. (Join-Path $root 'components/proxmox/shared.ps1')

$text = Get-Content -LiteralPath (Join-Path $root 'components/proxmox/vm-change.ps1') -Raw
$ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
foreach ($name in @('Get-PmxCloneConfigurePlan', 'Show-PmxCloneConfigureOutcome')) {
    $fn = $ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $args[0].Name -eq $name }, $true)
    Assert-PmxTest ($fn.Count -eq 1) "could not extract $name"
    Invoke-Expression $fn[0].Extent.Text
}

# A source with exactly one growable 32 GiB disk.
$sourceDetails = [pscustomobject]@{
    Success = $true
    Disks = @(
        [pscustomobject]@{ Disk = 'scsi0'; SizeBytes = 32GB; Growable = $true }
        [pscustomobject]@{ Disk = 'ide2';  SizeBytes = 0;    Growable = $false }
    )
}

# ---- validation happens up front, and refuses rather than guesses --------------------
foreach ($bad in @(
    @{ Label = 'cores 0';      Options = @{ Cores = '0' };     Match = 'cores' }
    @{ Label = 'cores two';    Options = @{ Cores = 'two' };   Match = 'cores' }
    @{ Label = 'cores 99999';  Options = @{ Cores = '99999' }; Match = 'cores' }
    @{ Label = 'memory 4Q';    Options = @{ Memory = '4Q' };   Match = 'memory' }
    @{ Label = 'memory 1';     Options = @{ Memory = '1' };    Match = 'memory' }
    # 0G is refused by the shared size parser before the positive-size guard is reached, so the
    # message comes from there. The guard stays as a backstop in case that parser ever loosens.
    @{ Label = 'grow-by 0G';   Options = @{ GrowBy = '0G' };   Match = 'grow-by' }
    @{ Label = 'grow-by big';  Options = @{ GrowBy = 'big' };  Match = 'grow-by' }
)) {
    $plan = Get-PmxCloneConfigurePlan -Options $bad.Options -SourceDetails $sourceDetails
    Assert-PmxTest (-not $plan.Success) "$($bad.Label) should be refused"
    Assert-PmxTest ($plan.Error -match $bad.Match) `
        "the refusal for $($bad.Label) should mention '$($bad.Match)'; got '$($plan.Error)'"
    Assert-PmxTest (@($plan.Steps).Count -eq 0) "a refused plan must contain no steps ($($bad.Label))"
}

# ---- a valid plan produces one step per requested setting, in order ------------------
$plan = Get-PmxCloneConfigurePlan -Options @{ Cores = '2'; Memory = '4G'; GrowBy = '8G' } -SourceDetails $sourceDetails
Assert-PmxTest $plan.Success "a valid plan should succeed: $($plan.Error)"
Assert-PmxTest (@($plan.Steps).Count -eq 3) "expected 3 steps, got $(@($plan.Steps).Count)"
Assert-PmxTest ((@($plan.Steps | ForEach-Object { $_.Kind }) -join ',') -ceq 'cpu,memory,disk') `
    'steps should be ordered cpu, memory, disk - the disk grows last because it is the slowest and least reversible'

# Memory is converted to MiB, because that is what Proxmox takes.
$memoryStep = $plan.Steps | Where-Object { $_.Kind -eq 'memory' }
Assert-PmxTest ($memoryStep.Value -eq 4096) "4G should become 4096 MiB, got $($memoryStep.Value)"
Assert-PmxTest ($memoryStep.Field -ceq 'MemoryMiB') 'the memory step must fill the MemoryMiB parameter'

# --grow-by is a DELTA, applied to the source size to reach an absolute target.
$diskStep = $plan.Steps | Where-Object { $_.Kind -eq 'disk' }
Assert-PmxTest ($diskStep.Value -eq (32GB + 8GB)) `
    "grow-by 8G on a 32 GiB disk should target 40 GiB, got $($diskStep.Value)"
Assert-PmxTest ($diskStep.Disk -ceq 'scsi0') 'the growable disk should be resolved from the source layout'
Assert-PmxTest ($diskStep.Display -match '32') 'the preview should show the size it starts from'
Assert-PmxTest ($diskStep.Display -match '40') 'the preview should show the size it ends at'

# Each step names an allow-listed operation rather than a compound command string.
foreach ($step in $plan.Steps) {
    Assert-PmxTest ($step.Operation -in @('vm-set-cpu', 'vm-set-memory', 'vm-disk-grow')) `
        "step '$($step.Kind)' must use an allow-listed operation, got '$($step.Operation)'"
}

# ---- ambiguity is refused, never guessed --------------------------------------------
$twoDisks = [pscustomobject]@{ Success = $true; Disks = @(
    [pscustomobject]@{ Disk = 'scsi0'; SizeBytes = 32GB; Growable = $true }
    [pscustomobject]@{ Disk = 'scsi1'; SizeBytes = 64GB; Growable = $true }
) }
$ambiguous = Get-PmxCloneConfigurePlan -Options @{ GrowBy = '8G' } -SourceDetails $twoDisks
Assert-PmxTest (-not $ambiguous.Success) 'two growable disks must not be guessed between'
Assert-PmxTest ($ambiguous.Error -match 'several growable') 'the refusal should say why'
Assert-PmxTest ($ambiguous.Error -match 'scsi0') 'the refusal should name the candidates'

$noDisk = [pscustomobject]@{ Success = $true; Disks = @(
    [pscustomobject]@{ Disk = 'ide2'; SizeBytes = 0; Growable = $false }) }
$none = Get-PmxCloneConfigurePlan -Options @{ GrowBy = '8G' } -SourceDetails $noDisk
Assert-PmxTest (-not $none.Success) 'no growable disk must be refused, not silently skipped'

# ---- no settings requested means no steps, and the plain clone is unchanged ----------
$plain = Get-PmxCloneConfigurePlan -Options @{} -SourceDetails $sourceDetails
Assert-PmxTest $plain.Success 'a clone with no configure options is still valid'
Assert-PmxTest (@($plain.Steps).Count -eq 0) 'no options means no steps'

# ---- partial failure keeps the VM and prints the remaining work ----------------------
$planned = @($plan.Steps)
$outcomes = @(
    [pscustomobject]@{ Step = $planned[0]; Success = $true;  Error = '' }
    [pscustomobject]@{ Step = $planned[1]; Success = $false; Error = 'proxmox said no' }
)
$report = @(Show-PmxCloneConfigureOutcome -VmId 103 -Planned $planned -Outcomes $outcomes 6>&1)
$rendered = ($report | ForEach-Object { "$_" }) -join "`n"
Assert-PmxTest ($rendered -match 'KEPT') 'a partial failure must state that the VM was kept'
# The report DOES contain the words "rolled back" — in the sentence "Nothing is rolled back" —
# so the assertion has to look for an affirmative destructive claim, not the phrase.
Assert-PmxTest ($rendered -match 'Nothing is rolled back') 'the report should state plainly that nothing was undone'
Assert-PmxTest ($rendered -notmatch '(?<!Nothing is )(has been|was|were) rolled back') `
    'nothing may claim the clone WAS rolled back'
Assert-PmxTest ($rendered -notmatch 'deleted VM|removed VM|destroying') 'no destructive action may be reported'
Assert-PmxTest ($rendered -match 'pmx vm memory 103') 'the failed step must be given as a runnable command'
Assert-PmxTest ($rendered -match 'pmx disk grow 103') 'the NOT-ATTEMPTED step must also be listed'
Assert-PmxTest ($rendered -match 'not attempted') 'skipped steps must be distinguished from failed ones'
Assert-PmxTest ($rendered -match 'pmx vm show 103') 'the report should end with how to inspect the result'

# A fully successful run says nothing about manual continuation.
$allOk = @($planned | ForEach-Object { [pscustomobject]@{ Step = $_; Success = $true; Error = '' } })
$okReport = @(Show-PmxCloneConfigureOutcome -VmId 103 -Planned $planned -Outcomes $allOk 6>&1)
$okRendered = ($okReport | ForEach-Object { "$_" }) -join "`n"
Assert-PmxTest ($okRendered -notmatch 'KEPT') 'a fully successful run must not print recovery advice'
Assert-PmxTest ($okRendered -notmatch 'Continue manually') 'a fully successful run needs no continuation list'

# ---- the command surface -------------------------------------------------------------
$clone = [regex]::Match($text, '(?ms)^function Invoke-PmxVmClone \{.*?\n\}').Value
Assert-PmxTest ($clone.Length -gt 0) 'could not extract Invoke-PmxVmClone'
foreach ($option in @('vmid', 'cores', 'memory', 'grow-by')) {
    Assert-PmxTest ($clone -match "'$option'") "clone should accept --$option"
}
Assert-PmxTest ($clone -match "switches\['show'\] = 'Show'") 'clone should accept --show'

# --vmid must be an alias of the existing NewVmid handling, not a second code path.
Assert-PmxTest ($clone -match "'vmid' = 'NewVmid'") '--vmid must map onto the existing NewVmid logic'

# The configure steps must only run after a VERIFIED, EXECUTED clone — never on a dry run.
Assert-PmxTest ($clone -match '\$mutation\.Success -and \$mutation\.Executed') `
    'configure steps must require a verified, executed clone'

# The whole transaction must be planned before the single confirmation.
$previewIdx = $clone.IndexOf('Get-PmxCloneConfigurePlan')
$confirmIdx = $clone.IndexOf('Invoke-PmxAmberMutation')
Assert-PmxTest ($previewIdx -ge 0) 'the clone must build a configure plan'
Assert-PmxTest ($previewIdx -lt $confirmIdx) `
    'the configure plan must be built BEFORE the confirmation, so one prompt covers everything'
Assert-PmxTest ($clone -match 'not an atomic transaction') `
    'the preview must warn that this is a sequence, while declining is still free'

# Every planned step must reach the previewed fields, or the user confirms less than happens.
Assert-PmxTest ($clone -match "foreach \(\`$step in \`$configureSteps\)") `
    'each configure step must be added to the previewed fields'

Write-PmxTestPass 'PF-FEAT-003: validated up front, previewed once, and a partial failure keeps the VM'
