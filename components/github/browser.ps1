# ==============================================================================
# PowerFlow — GitHub Repository Browser
# Domain   : GitHub
# File     : components/github/browser.ps1
# Purpose  : Repository browser actions and organization browsing
# Functions: Show-PFGitHubBrowser, Show-PFGitHubRepositoryAction, Invoke-PFGitHubOrgBrowser,
#            Format-PFGitHubRow, Show-PFGitHubDetails, Test-PFGitHubInteractive, _GhL-CommitCount
# Depends  : repositories.ps1, platform GitHub credential and opener adapters
# ==============================================================================

function _GhL-CommitCount {
    param(
        [string]$RepoFullName,
        [string]$Since,
        [hashtable]$Headers
    )
    try {
        $commitsUrl = "https://api.github.com/repos/$RepoFullName/commits?since=$Since&per_page=100"
        $commits = Invoke-RestMethod -Uri $commitsUrl -Headers $Headers -ErrorAction SilentlyContinue
        return $commits.Count
    } catch {
        return $null
    }
}

function Test-PFGitHubInteractive { return (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) }

function Format-PFGitHubRow {
    param($Model, [datetime]$Now = [datetime]::UtcNow, [string]$Activity = '')
    $pushDate = 'unknown last push'
    $idle = 'unknown'
    if ($null -ne $Model.LastPush) {
        $pushDate = $Model.LastPush.ToString('yyyy-MM-dd')
        $idle = "{0}d" -f [Math]::Max(0, [Math]::Floor(($Now - $Model.LastPush).TotalDays))
    }
    $created = if ($null -ne $Model.Created) { $Model.Created.ToString('yyyy-MM-dd') } else { 'unknown' }
    $visibility = if ($Model.Repository.private) { 'private' } else { 'public' }
    $context = $Model.Context
    if ($Model.PagesEnabled -eq $true) { $context = "$context hosts a site — review before retiring".Trim() }
    return ('{0,-38} {1,-17} {2,-8} {3,-29} created {4} · {5} {6} {7}' -f
        (Format-PFGitHubText $Model.FullName), $pushDate, $idle, $Model.PagesState, $created,
        $visibility, $context, $Activity).TrimEnd()
}

function Show-PFGitHubDetails {
    param($Model)
    Write-Host "Repository: $(Format-PFGitHubText $Model.FullName)" -ForegroundColor Cyan
    Write-Host "Pages: $($Model.PagesState)" -ForegroundColor DarkGray
    if ($Model.PagesEnabled -eq $true) {
        Write-PFWarning 'Hosts a site — review before retiring this repository.'
    }
    if ($Model.PagesUrl) { Write-Host "Site: $(Format-PFGitHubText $Model.PagesUrl)" }
    if ($Model.PagesDomain) { Write-Host "Custom domain: $(Format-PFGitHubText $Model.PagesDomain)" }
    if ($Model.PagesBuildType) { Write-Host "Publishing: $(Format-PFGitHubText $Model.PagesBuildType)" }
    if ($Model.PagesSource) {
        Write-Host "Source: $(Format-PFGitHubText $Model.PagesSource.branch) $(Format-PFGitHubText $Model.PagesSource.path)"
    }
    if ($Model.PagesError) { Write-Host "Details unavailable: $($Model.PagesError). Fine-grained tokens may need Pages read permission." -ForegroundColor Yellow }
    if ($Model.PagesHint -and $Model.PagesEnabled -ne $true) {
        Write-Host 'Name/homepage resembles a github.io site; Pages hosting is not confirmed.' -ForegroundColor DarkGray
    }
    Write-Host 'Age measures last push across the repository, not usage, visitors, or redundancy.' -ForegroundColor DarkGray
}

function Show-PFGitHubRepositoryAction {
    param($Model, [hashtable]$Headers, [switch]$Review, [object[]]$OrgModels = @(), [string]$Org)
    $repository = $Model.Repository
    Show-PFGitHubDetails $Model
    # Preserve the original browser's automatic URL copy, but review is explicit.
    if (-not $Review) { Copy-ToClipboard $repository.html_url }
    Write-Host '  1. Clone repository' -ForegroundColor DarkGray
    if ($Org) {
        Write-Host "  2. Clone all $($OrgModels.Count) displayed repositories into ./$Org/" -ForegroundColor DarkGray
        Write-Host '  3. Open repository in browser' -ForegroundColor DarkGray
        Write-Host '  4. Copy HTTPS URL' -ForegroundColor DarkGray
        Write-Host '  5. Copy SSH URL' -ForegroundColor DarkGray
    } else {
        Write-Host '  2. Open repository in browser' -ForegroundColor DarkGray
        Write-Host '  3. Copy SSH URL' -ForegroundColor DarkGray
        if ($Review) { Write-Host '  4. Inspect repository details' -ForegroundColor DarkGray }
        else { Write-Host '  4. Delete repository (PERMANENT)' -ForegroundColor Red }
        Write-Host '  5. Copy HTTPS URL' -ForegroundColor DarkGray
    }
    if ($Model.PagesUrl) { Write-Host '  6. Open Pages site' -ForegroundColor DarkGray }
    $action = Read-Host 'Choose action (Enter to finish)'
    if ($Org) {
        $action = switch ($action) { '2' { '7' }; '3' { '2' }; '4' { '5' }; '5' { '3' }; default { $action } }
    }
    switch ($action) {
        '1' {
            git clone $repository.html_url
            $cloneExit = $LASTEXITCODE
            if ($cloneExit -eq 0) { Write-Host '✅ Repository cloned successfully.' -ForegroundColor Green }
            else { Write-PFFailure "Clone failed (exit $cloneExit)." -Hint 'Check the Git output above.' }
        }
        '2' { Open-Url $repository.html_url }
        '3' { Copy-ToClipboard $repository.ssh_url }
        '4' {
            if ($Review) { Show-PFGitHubDetails $Model; return }
            # Three independent confirmations, as in the original browser.
            Write-PFWarning 'This permanently deletes the repository, its issues, pull requests, and history.'
            if ($Model.PagesEnabled -eq $true) { Write-PFWarning 'This repository has Pages enabled; deleting it also removes its site.' }
            if ((Read-Host "Type repository name '$($repository.name)' to continue") -cne $repository.name) {
                Write-PFFailure 'Refused: repository name did not match. Nothing was deleted.'; return
            }
            if ((Read-Host 'Type DELETE to confirm') -cne 'DELETE') {
                Write-PFFailure 'Refused: confirmation did not match. Nothing was deleted.'; return
            }
            if ((Read-Host 'Type I UNDERSTAND THIS IS PERMANENT to proceed') -cne 'I UNDERSTAND THIS IS PERMANENT') {
                Write-PFFailure 'Refused: final confirmation did not match. Nothing was deleted.'; return
            }
            try {
                $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$($Model.FullName)" -Method DELETE -Headers $Headers -ErrorAction Stop
                Write-Host "Repository '$(Format-PFGitHubText $Model.FullName)' was permanently deleted." -ForegroundColor Red
            } catch { Write-PFFailure 'Could not delete repository.' -Hint (Get-PFGitHubError $_) }
        }
        '5' { Copy-ToClipboard $repository.html_url }
        '6' {
            if ($Model.PagesUrl) { Open-Url $Model.PagesUrl }
            else { Write-PFFailure 'No confirmed Pages URL is available.' }
        }
        '7' {
            if (-not $Org) { Write-PFFailure 'Clone-all is only available in organization browsing.'; return }
            if ((Read-Host "Clone all $($OrgModels.Count) displayed repositories into ./$Org/? (y/n)") -ne 'y') {
                Write-PFCancelled; return
            }
            $cloned = 0; $failed = 0
            try {
                $null = New-Item -ItemType Directory -Path $Org -Force -ErrorAction Stop
                Push-Location -LiteralPath $Org -ErrorAction Stop
                try {
                    foreach ($orgModel in $OrgModels) {
                        git clone $orgModel.Repository.clone_url
                        $cloneExit = $LASTEXITCODE
                        if ($cloneExit -eq 0) { $cloned++ } else { $failed++ }
                    }
                } finally { Pop-Location }
                if ($failed) { Write-PFWarning "$cloned cloned; $failed failed. Check the Git output above." }
                else { Write-Host "✅ $cloned repositories cloned into ./$Org/." -ForegroundColor Green }
            } catch { Write-PFFailure 'Could not complete organization cloning.' -Hint 'Check the destination folder and Git output.' }
        }
        '' { return }
        default { Write-PFFailure 'Unknown action. Run github again and choose one of the displayed numbers.' }
    }
}

function Show-PFGitHubBrowser {
    param([int]$Count = 10, [string]$Token, [switch]$Oldest, [string]$OlderThan,
          [switch]$Pages, [switch]$Review, [string]$Org)
    if ($Count -lt 1) { Write-PFFailure 'Count must be positive.' -Hint 'Try github 50 --oldest.'; return }
    # Validate before authentication/network access.
    if ($OlderThan) { $null = Get-PFGitHubAgeCutoff $OlderThan }
    $resolvedToken = Get-PFGitHubToken -Token $Token
    if (-not $resolvedToken) { return }
    $headers = New-PFGitHubHeaders $resolvedToken
    $listing = Get-PFGitHubListing -Headers $headers -Count $Count -Oldest:$Oldest -OlderThan $OlderThan -Pages:$Pages -Org $Org
    if ($null -eq $listing) { return }
    $models = @($listing.Models)
    if (-not $models.Count) {
        if ($listing.Complete) { Write-PFNothingFound 'No repositories match this review.' -Hint 'Try github stale without filters.' }
        else { Write-PFWarning 'No matches in the incomplete repository list. Retry before drawing a conclusion.' }
        return
    }
    $pagesCount = @($models | Where-Object { $_.PagesEnabled -eq $true }).Count
    $unknownCount = @($models | Where-Object { $_.PagesState -match 'unknown|unavailable' }).Count
    $order = if ($Oldest) { 'oldest last push first' } else { 'newest last push first' }
    Write-Host "Showing $($models.Count) of $($listing.Total) fetched repositories · $order · $pagesCount Pages-enabled · $unknownCount Pages unknown/unavailable" -ForegroundColor Cyan
    Write-Host 'Old does not mean redundant. Last push does not measure site traffic or external usage.' -ForegroundColor DarkGray
    $now = [datetime]::UtcNow
    $interactive = Test-PFGitHubInteractive
    $usePicker = $interactive -and [bool](Get-Command fzf -ErrorAction SilentlyContinue)
    $choices = @()
    foreach ($model in $models) {
        $activity = ''
        if (-not $Review -and $usePicker) {
            $dayCount = _GhL-CommitCount -RepoFullName $model.FullName -Since $now.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ') -Headers $headers
            $weekCount = _GhL-CommitCount -RepoFullName $model.FullName -Since $now.AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ssZ') -Headers $headers
            $dayText = if ($null -eq $dayCount) { '?' } else { $dayCount }
            $weekText = if ($null -eq $weekCount) { '?' } else { $weekCount }
            $activity = "commits 24h:$dayText 1w:$weekText"
        }
        $row = Format-PFGitHubRow -Model $model -Now $now -Activity $activity
        $choices += "$($model.Key)`t$row"
        if (-not $usePicker) {
            Write-Host $row
            if ($model.PagesUrl) { Write-Host "  Site: $(Format-PFGitHubText $model.PagesUrl)" -ForegroundColor DarkGray }
            if ($model.PagesError) { Write-Host "  Pages details unavailable: $($model.PagesError)" -ForegroundColor Yellow }
        }
    }
    if (-not $usePicker) {
        Write-Host 'Use an interactive terminal with fzf to select a repository and clone/open it.' -ForegroundColor DarkGray
        return
    }
    $selection = $choices | fzf --reverse --border --no-sort --height=25 --delimiter="`t" --with-nth=2.. `
        --prompt='GitHub repositories: ' --header='Repository | Last push | Idle | Pages | Created / context · Enter: actions · Esc: cancel'
    $pickerExit = $LASTEXITCODE
    if ($pickerExit -eq 130) { Write-PFCancelled; return }
    if ($pickerExit -eq 1) { Write-PFNothingFound 'No repository matched what you typed.'; return }
    if ($pickerExit -ne 0) { Write-PFFailure "Repository picker failed (exit $pickerExit)."; return }
    if (-not $selection) { Write-PFFailure 'Repository picker returned no selection.'; return }
    $key = ([string]$selection -split "`t", 2)[0]
    $selected = @($models | Where-Object { $_.Key -ceq $key })
    if ($selected.Count -ne 1) { Write-PFFailure 'Could not uniquely resolve the selected repository.'; return }
    Show-PFGitHubRepositoryAction -Model $selected[0] -Headers $headers -Review:$Review -OrgModels $models -Org $Org
}

function Invoke-PFGitHubOrgBrowser {
    param([string]$Org, [int]$Count = 100)
    if ($Count -lt 1) { throw 'Count must be positive. Try github org my-team --count 50.' }
    if ($Org -and $Org -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { throw 'Use an organization name, such as github org my-team.' }
    $resolvedToken = Get-PFGitHubToken
    if (-not $resolvedToken) { return }
    $headers = New-PFGitHubHeaders $resolvedToken
    if (-not $Org) {
        if (-not (Test-PFGitHubInteractive) -or -not (Get-Command fzf -ErrorAction SilentlyContinue)) {
            Write-PFFailure 'Specify an organization in this terminal.' -Hint 'Try github org my-team.'; return
        }
        $organizations = @(); $page = 1
        try {
            do {
                $batch = @(Invoke-RestMethod -Uri "https://api.github.com/user/orgs?per_page=100&page=$page" -Headers $headers -ErrorAction Stop)
                $organizations += @($batch | Where-Object { $null -ne $_ }); $page++
            } while ($batch.Count -eq 100)
        } catch { Write-PFFailure 'Could not fetch organizations.' -Hint (Get-PFGitHubError $_); return }
        if (-not $organizations.Count) { Write-PFNothingFound 'No organizations found.'; return }
        $selection = $organizations | ForEach-Object { $_.login } | fzf --reverse --height=20 --prompt='Organization: '
        $pickerExit = $LASTEXITCODE
        if ($pickerExit -eq 130) { Write-PFCancelled; return }
        if ($pickerExit -eq 1) { Write-PFNothingFound 'No organization matched.'; return }
        if ($pickerExit -ne 0) { Write-PFFailure "Organization picker failed (exit $pickerExit)."; return }
        if ($selection -notin $organizations.login) { Write-PFFailure 'Could not resolve the organization.'; return }
        $Org = $selection
    }
    # Organization names also become clone-all destination directory names.
    if ($Org -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { throw 'Use an organization name, such as github org my-team.' }
    Show-PFGitHubBrowser -Count $Count -Token $resolvedToken -Org $Org
}
