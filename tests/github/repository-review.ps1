$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:assertions = 0
function Ok([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
    $script:assertions++
}
function Register-PFCommand { }
. (Join-Path $root 'components/shared/flags.ps1')
. (Join-Path $root 'components/shared/outcome.ps1')
. (Join-Path $root 'platform/linux/adapters/github.ps1')
. (Join-Path $root 'components/github/repositories.ps1')
. (Join-Path $root 'components/github/browser.ps1')
. (Join-Path $root 'components/github/review.ps1')
$ghBefore = @(Get-Command gh -ErrorAction SilentlyContinue | ForEach-Object { "$($_.CommandType):$($_.Definition)" }) -join '|'
. (Join-Path $root 'components/github/command.ps1')
$ghAfter = @(Get-Command gh -ErrorAction SilentlyContinue | ForEach-Object { "$($_.CommandType):$($_.Definition)" }) -join '|'
Ok ($ghBefore -ceq $ghAfter) 'GitHub CLI resolution is unchanged'

function New-Repo([int]$Id, [string]$Name, $Push = '2020-01-01T00:00:00Z', $Pages = $false) {
    [pscustomobject]@{
        id = $Id; name = $Name; full_name = "owner/$Name"; owner = [pscustomobject]@{ login = 'owner' }
        pushed_at = $Push; created_at = '2019-01-01T00:00:00Z'; has_pages = $Pages
        html_url = "https://github.com/owner/$Name"; clone_url = "https://github.com/owner/$Name.git"
        ssh_url = "git@github.com:owner/$Name.git"; private = $false; homepage = ''
        archived = $false; fork = $false; is_template = $false
    }
}
$repos = @((New-Repo 1 'new' '2025-01-01T00:00:00Z'), (New-Repo 2 'old' '2020-01-01T00:00:00Z'),
           (New-Repo 3 'unknown' $null), (New-Repo 4 'bad' 'invalid'), (New-Repo 5 'aaa' '2020-01-01T00:00:00Z'))
$recent = @(Select-PFGitHubRepositories -Repositories $repos -Count 1)
Ok ($recent.Count -eq 1 -and $recent[0].Key -eq '1') 'recent default sorts before count'
$oldest = @(Select-PFGitHubRepositories -Repositories $repos -Oldest -Count 2)
Ok (($oldest.Key -join ',') -eq '5,2') 'oldest sorts before count with full-name tie break'
$all = @(Select-PFGitHubRepositories -Repositories $repos -Oldest)
Ok (($all.Key -join ',') -eq '5,2,1,4,3') 'unknown dates group last, sorted by name'
Ok ($null -eq $all[-1].LastPush) 'unknown timestamp is not a fabricated date'
$cutoff = [datetime]'2020-01-01T00:00:00Z'
$aged = @(Select-PFGitHubRepositories -Repositories $repos -Oldest -Cutoff $cutoff)
Ok (($aged.Key -join ',') -eq '5,2') 'cutoff includes exact equality and excludes unknown dates'
Ok ((Get-PFGitHubAgeCutoff '1m' ([datetime]'2024-03-31T12:00:00Z')) -eq [datetime]'2024-02-29T12:00:00Z') 'calendar month handles leap-day boundary'
Ok ((Get-PFGitHubAgeCutoff '1y' ([datetime]'2024-02-29T12:00:00Z')) -eq [datetime]'2023-02-28T12:00:00Z') 'calendar year handles leap-day boundary'
Ok ((Get-PFGitHubAgeCutoff '1d' ([datetime]'2024-03-31T00:00:00Z')) -eq [datetime]'2024-03-30T00:00:00Z') 'day cutoff remains UTC'
Ok ((ConvertTo-PFGitHubDate '2024-03-31T01:00:00+01:00') -eq [datetime]'2024-03-31T00:00:00Z') 'offset timestamp normalizes to UTC'
foreach ($bad in @('0d', '-1y', '1w', 'y', '1.5m', '999999999999d', '999999999y')) {
    $refused = $false
    try { $null = Get-PFGitHubAgeCutoff $bad } catch { $refused = $true }
    Ok $refused "bad age $bad is refused"
}

$script:requests = @()
$script:apiRepos = $repos
$script:pageFailure = 0
$script:pagesFailure = $false
$script:pagesFailureStatus = 0
$script:orgForbidden = $false
$script:pagesRecord = [pscustomobject]@{
    html_url = 'https://owner.github.io/project/'; cname = $null; status = 'built'
    build_type = 'legacy'; source = [pscustomobject]@{ branch = 'main'; path = '/docs' }
}
function Invoke-RestMethod {
    param($Uri, $Headers, $Method = 'GET', $ErrorAction)
    $script:requests += [pscustomobject]@{ Uri = $Uri; Method = $Method }
    if ($Uri -match '/pages$') {
        if ($script:pagesFailure) {
            $failure = [Exception]::new('deliberately includes secret-test-token; must not render this')
            $failure | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = $script:pagesFailureStatus })
            throw $failure
        }
        return $script:pagesRecord
    }
    if ($Uri -match '/commits\?') { return @() }
    if ($script:orgForbidden -and $Uri -match '/orgs/.*/repos\?type=all') {
        $failure = [Exception]::new('permission denied')
        $failure | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = 403 })
        throw $failure
    }
    if ($Method -ne 'GET') { throw 'Unexpected account mutation' }
    $page = [int]([regex]::Match($Uri, '[?&]page=([0-9]+)').Groups[1].Value)
    if ($page -eq $script:pageFailure) { throw 'network secret-test-token' }
    return @($script:apiRepos | Select-Object -Skip (($page - 1) * 100) -First 100)
}
function Test-PFGitHubInteractive { return $script:interactive }
$script:interactive = $false
$script:apiRepos = @(1..101 | ForEach-Object { New-Repo $_ "project-$_" })
$fetched = Get-PFGitHubRepositories @{}
Ok ($fetched.Complete -and $fetched.Repositories.Count -eq 101) 'all repository pages are fetched'
Ok ($script:requests.Count -eq 2) 'pagination stops at final short page'
$script:pageFailure = 2
$partial = Get-PFGitHubRepositories @{}
Ok (-not $partial.Complete -and $partial.Repositories.Count -eq 100) 'partial failure preserves fetched repositories with incomplete marker'
Ok ($partial.Error -notmatch 'secret-test-token') 'fetch errors never disclose exception secrets'
$partialOut = @(Get-PFGitHubListing -Headers @{} -Count 1 6>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($partialOut -match 'incomplete') 'partial list is disclosed to user'
$script:pageFailure = 1
$failedOut = @(Show-PFGitHubBrowser -Token 'secret-test-token' 6>&1 | ForEach-Object { "$_" }) -join "`n"
Ok ($failedOut -match 'Could not fetch' -and $failedOut -notmatch 'No repositories match|secret-test-token') 'total failure is not an empty result or credential leak'
$script:pageFailure = 0

$accountSite = New-Repo 10 'owner.github.io' '2020-01-01T00:00:00Z' $true
$projectSite = New-Repo 11 'project' '2021-01-01T00:00:00Z' $true
$disabledHint = New-Repo 12 'hint' '2020-01-01T00:00:00Z' $false
$disabledHint.homepage = 'https://owner.github.io/hint'
$unknownPages = New-Repo 13 'missing-field' '2020-01-01T00:00:00Z' $null
$unknownPages.PSObject.Properties.Remove('has_pages')
foreach ($repo in @($accountSite, $projectSite)) {
    $model = ConvertTo-PFGitHubRepository $repo
    Set-PFGitHubPages $model @{}
    Ok ($model.PagesState -eq 'enabled · built' -and $model.PagesUrl -eq $script:pagesRecord.html_url) 'account and project Pages sites use API evidence'
}
$model = ConvertTo-PFGitHubRepository $projectSite
$script:pagesRecord = [pscustomobject]@{ html_url = 'https://example.com/'; cname = 'example.com'; status = 'building'; build_type = 'workflow' }
Set-PFGitHubPages $model @{}
Ok ($model.PagesUrl -eq 'https://example.com/' -and $model.PagesDomain -eq 'example.com') 'custom-domain URL is preserved'
Ok ($model.PagesBuildType -eq 'workflow' -and $null -eq $model.PagesSource) 'workflow publishing does not invent source branch'
Ok ($model.PagesState -eq 'enabled · building') 'building status is preserved'
$calls = $script:requests.Count
Set-PFGitHubPages $model @{}
Ok ($calls -eq $script:requests.Count) 'Pages enrichment runs once per model'
$script:pagesRecord.status = 'errored'
$errorModel = ConvertTo-PFGitHubRepository $projectSite
Set-PFGitHubPages $errorModel @{}
Ok ($errorModel.PagesState -eq 'enabled · errored') 'errored build is not reported built'
$script:pagesRecord.status = 'unexpected'
$script:pagesRecord.html_url = 'javascript:alert(1)'
$unsafeModel = ConvertTo-PFGitHubRepository $projectSite
Set-PFGitHubPages $unsafeModel @{}
Ok ($null -eq $unsafeModel.PagesUrl -and $unsafeModel.PagesState -eq 'enabled · status unknown') 'unrecognized status and unsafe site URL remain unknown'
$hintModel = ConvertTo-PFGitHubRepository $disabledHint
Set-PFGitHubPages $hintModel @{}
Ok ($hintModel.PagesHint -and $hintModel.PagesState -eq 'disabled') 'homepage hint does not override disabled Pages'
$missingModel = ConvertTo-PFGitHubRepository $unknownPages
Ok ($missingModel.PagesState -eq 'unknown') 'absent Pages metadata remains unknown'
$script:pagesFailure = $true
$failedSite = ConvertTo-PFGitHubRepository $accountSite
Set-PFGitHubPages $failedSite @{}
Ok ($failedSite.PagesEnabled -and $failedSite.PagesState -eq 'enabled · details unavailable') 'failed details preserve known Pages-enabled site'
Ok ($failedSite.PagesError -notmatch 'secret-test-token') 'Pages errors are sanitized'
foreach ($status in @(401, 403, 404, 429)) {
    $script:pagesFailureStatus = $status
    $unavailable = ConvertTo-PFGitHubRepository $projectSite
    Set-PFGitHubPages $unavailable @{}
    Ok ($unavailable.PagesEnabled -and $unavailable.PagesState -eq 'enabled · details unavailable') "HTTP $status never erases hosting evidence"
    $expected = switch ($status) { 401 { 'authentication' }; 403 { 'permission' }; 404 { 'resource unavailable' }; 429 { 'rate limit' } }
    Ok ($unavailable.PagesError -match $expected -and $unavailable.PagesError -notmatch 'secret-test-token') "HTTP $status has a safe categorized error"
}
$script:pagesFailureStatus = 0
$projectSite.archived = $true; $projectSite.fork = $true; $projectSite.is_template = $true
$contextModel = ConvertTo-PFGitHubRepository $projectSite
Ok ($contextModel.Context -eq 'archived, fork, template') 'context is visible without deciding redundancy'
Ok ((Format-PFGitHubText "one`tcolumn`nnext$([char]27)line") -notmatch '[\x00-\x1f]') 'API text cannot inject picker columns or terminal control characters'
$script:apiRepos = @($accountSite, $projectSite, $disabledHint, $unknownPages)
$script:requests = @()
$pagesListing = Get-PFGitHubListing -Headers @{} -Count 1 -Oldest -Pages
Ok ($pagesListing.Models.Count -eq 1 -and $pagesListing.Models[0].Key -eq '10') 'Pages filter keeps unavailable enabled site, before count'
Ok (@($script:requests | Where-Object { $_.Uri -match '/pages$' }).Count -eq 1) 'enrichment is bounded to displayed enabled sites'

$oldToken = $env:GITHUB_TOKEN
$env:GITHUB_TOKEN = 'secret-test-token'
try {
    $script:requests = @()
    $reviewOut = @(github stale 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($reviewOut -match 'Showing 4 of 4' -and $reviewOut -match 'oldest last push first') 'bare review includes all owned repos'
    Ok ($reviewOut -match 'hosts a site' -and $reviewOut -match 'details unavailable') 'report preserves Pages hosting warning and uncertainty'
    Ok ($reviewOut -notmatch 'secret-test-token') 'review never prints token'
    Ok (@($script:requests | Where-Object { $_.Uri -match '/commits\?' }).Count -eq 0) 'review performs no commit-count queries'
    Ok (@($script:requests | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) 'review performs no write API calls'
    $reportOut = @(github 2 --oldest 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($reportOut -match 'Showing 2 of 4' -and $reportOut -match 'oldest last push first') 'canonical oldest flag binds with positional count'
    $recentOut = @(gh-l -Count 1 -Token 'secret-test-token' 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($recentOut -match 'Showing 1 of 4' -and $recentOut -match 'newest last push first') 'legacy Count and Token flags still work'
    $secondLegacy = @(gh-l 1 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($secondLegacy -notmatch 'gh-l is now') 'migration notice appears once per session'
    foreach ($argv in @(
        @('stale', '--older-than', '0y'), @('stale', '--older-than', '1y', '--older-than', '2y'),
        @('--oldest', '--oldest'), @('--oldest', '-Oldest'), @('--count', '1', '2'),
        @('--wat'), @('oops'), @('0'), @('-1'), @('999999999999'),
        @('stale', '--oldest'), @('stale', '--older-than'), @('--oldest=bad'),
        @('token', 'reset', 'extra'), @('org', '..'), @('stale', '--pages', '--pages')
    )) {
        $script:requests = @()
        $badOut = @(Invoke-PFGitHubCommand -Argv $argv 6>&1 | ForEach-Object { "$_" }) -join "`n"
        Ok ($badOut -match '❌') "invalid invocation is refused: $($argv -join ' ')"
        Ok ($script:requests.Count -eq 0) 'invalid input causes no API requests'
    }
    $script:requests = @()
    $helpOut = @(github help 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($helpOut -match 'github stale --older-than 1y' -and $helpOut -match 'github org') 'help documents executable routes'
    Ok ($script:requests.Count -eq 0) 'help makes no account requests'
    foreach ($helpForm in @(@('--help'), @('-h'), @('stale', '--help'), @('org', '-h'))) {
        $helpOut = @(Invoke-PFGitHubCommand -Argv $helpForm 6>&1 | ForEach-Object { "$_" }) -join "`n"
        Ok ($helpOut -match 'PowerFlow GitHub') 'help aliases route without account requests'
    }
    $filteredOut = @(github stale --older-than 1y --pages 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($filteredOut -match 'Showing 2 of 4') 'age and Pages filters compose through public route'
    $falseOut = @(github --oldest=false --count=1 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($falseOut -match 'newest last push first') 'explicit false switch retains recent order'
    $statusOut = @(gh-l-status 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($statusOut -match 'GITHUB_TOKEN is set' -and $statusOut -notmatch 'secret-test-token') 'legacy token status routes safely'
    $null = gh-l-reset 6>&1
    Ok ($env:GITHUB_TOKEN -eq 'secret-test-token') 'token reset leaves environment token intact'
    $orgOut = @(gh-l-org 'my-team' -Count 1 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($orgOut -match 'Showing 1 of 4') 'legacy organization browser arguments remain supported'
    $script:orgForbidden = $true
    $publicOrgOut = @(github org my-team 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($publicOrgOut -match 'public repositories only' -and $publicOrgOut -match 'incomplete') 'organization permission fallback remains explicit about missing private repos'
    $script:orgForbidden = $false

    # Picker/action path uses a stable repository ID, even for similar names.
    $script:interactive = $true
    $script:pagesFailure = $false
    $script:pagesRecord.html_url = 'https://example.com/'
    $script:apiRepos = @($accountSite, $projectSite)
    $script:pickerCode = 0; $script:selectedId = '11'; $script:answers = @('1')
    $script:gitCalls = @(); $script:opened = @(); $script:copied = @(); $script:cloneCode = 0
    function fzf {
        $incoming = @($input)
        $global:LASTEXITCODE = $script:pickerCode
        if ($script:pickerCode -eq 0) { return ($incoming | Where-Object { $_ -like "$($script:selectedId)`t*" } | Select-Object -First 1) }
    }
    function Read-Host { param($Prompt) $answer = $script:answers[0]; $script:answers = @($script:answers | Select-Object -Skip 1); return $answer }
    function git { $script:gitCalls += ,@($args); $global:LASTEXITCODE = $script:cloneCode }
    function Open-Url { param($Url) $script:opened += $Url }
    function Copy-ToClipboard { param($Value) $script:copied += $Value }
    $cloneOut = @(github stale 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($script:gitCalls.Count -eq 1 -and $script:gitCalls[0][1] -eq $projectSite.html_url) 'selected ID clones correct repository'
    Ok ($cloneOut -match 'cloned successfully' -and $cloneOut -notmatch 'Delete repository') 'review clone succeeds without delete menu'
    $script:cloneCode = 1; $script:answers = @('1')
    $cloneFail = @(github stale 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($cloneFail -match 'Clone failed' -and $cloneFail -notmatch 'cloned successfully') 'failed clone never reports success'
    $script:answers = @('6')
    $null = github stale 6>&1
    Ok ($script:opened[-1] -eq 'https://example.com/') 'open-site action uses confirmed URL through adapter'
    $script:answers = @('4')
    $script:requests = @()
    $null = github stale 6>&1
    Ok (@($script:requests | Where-Object { $_.Method -ne 'GET' }).Count -eq 0) 'review action 4 inspects and never deletes'
    $script:pickerCode = 130
    $cancelOut = @(github stale 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($cancelOut -match 'Cancelled' -and $cancelOut -notmatch '❌') 'Escape cancellation is neutral'
    $script:pickerCode = 1
    $noMatch = @(github stale 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($noMatch -match 'No repository matched' -and $noMatch -notmatch 'Cancelled') 'no match differs from cancellation'
    $script:pickerCode = 2
    $pickerFail = @(github stale 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($pickerFail -match 'picker failed') 'picker failure is reported'
    $script:pickerCode = 0
    $script:answers = @('4', 'wrong-name')
    $script:requests = @()
    $refusedDelete = @(github 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($refusedDelete -match 'Refused: repository name' -and @($script:requests | Where-Object { $_.Method -eq 'DELETE' }).Count -eq 0) 'ordinary deletion still requires matching repository name'
    $script:answers = @('4', 'project', 'wrong')
    $refusedDelete = @(github 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($refusedDelete -match 'Refused: confirmation' -and @($script:requests | Where-Object { $_.Method -eq 'DELETE' }).Count -eq 0) 'ordinary deletion still requires DELETE confirmation'
    $script:answers = @('4', 'project', 'DELETE', 'wrong')
    $refusedDelete = @(github 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($refusedDelete -match 'Refused: final confirmation' -and @($script:requests | Where-Object { $_.Method -eq 'DELETE' }).Count -eq 0) 'ordinary deletion still requires final confirmation'
    Ok ($refusedDelete -match 'Pages enabled' -and $refusedDelete -match 'removes its site') 'Pages context is visible before destructive confirmation'
    $script:answers = @('2', 'n')
    $orgCancel = @(github org my-team 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($orgCancel -match 'Cancelled') 'organization clone-all keeps original action 2 and requires confirmation'

    # No fzf in an interactive terminal still yields a report, not a failed picker.
    Remove-Item -LiteralPath Function:fzf
    $testPath = $env:PATH
    try {
        $env:PATH = ''
        $fallbackOut = @(github stale 6>&1 | ForEach-Object { "$_" }) -join "`n"
        Ok ($fallbackOut -match 'Showing 2 of 2' -and $fallbackOut -match 'with fzf' -and $fallbackOut -notmatch 'picker failed') 'missing fzf yields readable report'
    } finally { $env:PATH = $testPath }
    $script:interactive = $false

    # A pre-existing command is preserved; reloading our own command is supported.
    function github { return 'external github sentinel' }
    $collisionOut = @(. (Join-Path $root 'components/github/command.ps1') 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ((github) -eq 'external github sentinel' -and $collisionOut -match 'another command') 'command-name collision warns and preserves external command'
    Remove-Item -LiteralPath Function:github
    . (Join-Path $root 'components/github/command.ps1')
    $reloadOut = @(. (Join-Path $root 'components/github/command.ps1') 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($reloadOut -notmatch 'another command') 'our own command reloads without false collision'
    $postReload = @(gh-l 1 6>&1 | ForEach-Object { "$_" }) -join "`n"
    Ok ($postReload -notmatch 'gh-l is now') 'migration notice remains once per session across reloads'
}
finally { $env:GITHUB_TOKEN = $oldToken }

# Both credential adapters expose exactly the same public contract.
foreach ($platform in @('windows', 'linux')) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root "platform/$platform/adapters/github.ps1"), [ref]$null, [ref]$null)
    $defined = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
    foreach ($name in @('Get-GitHubSavedToken', 'Set-GitHubSavedToken', 'Remove-GitHubSavedToken', 'Show-GitHubTokenStatus')) {
        Ok ($name -in $defined) "$platform exposes $name"
    }
}
Write-Host "GitHub repository review: $script:assertions assertions passed."
