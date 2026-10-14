# ==============================================================================
# PowerFlow — GitHub Repository Data
# Domain   : GitHub
# File     : components/github/repositories.ps1
# Purpose  : Shared authentication, pagination, last-push models and Pages evidence
# Functions: Get-PFGitHubToken, New-PFGitHubHeaders, Get-PFGitHubError,
#            Get-PFGitHubRepositories, ConvertTo-PFGitHubDate, ConvertTo-PFGitHubRepository,
#            Get-PFGitHubAgeCutoff, Select-PFGitHubRepositories, Set-PFGitHubPages,
#            Get-PFGitHubListing, Format-PFGitHubText
# Depends  : platform GitHub credential adapters, shared/outcome.ps1
# ==============================================================================

function Get-PFGitHubToken {
    param([string]$Token)
    if ($Token) { return $Token }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    $saved = Get-GitHubSavedToken
    if ($saved) { return $saved }
    if ([Console]::IsInputRedirected) {
        Write-PFFailure 'A GitHub token is required.' -Hint 'Set GITHUB_TOKEN, or run github in an interactive terminal.'
        return $null
    }
    Write-Host 'Enter a GitHub token with access to the repositories you want to browse.' -ForegroundColor Cyan
    Write-Host 'Create one at https://github.com/settings/tokens. Pages details may require Pages read permission.' -ForegroundColor DarkGray
    $secureInput = Read-Host 'GitHub token (hidden)' -AsSecureString
    $tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
    try { $entered = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer) }
    if (-not $entered) { Write-PFCancelled; return $null }
    if ($script:PowerFlowOS -eq 'windows') {
        if ((Read-Host 'Save in Windows Credential Manager? (y/n)') -eq 'y') {
            $null = Set-GitHubSavedToken -Token $entered
        }
    }
    return $entered
}

function New-PFGitHubHeaders {
    param([string]$Token)
    return @{
        Authorization = "Bearer $Token"
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'PowerFlow-github'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
}

function Get-PFGitHubError {
    param($ErrorRecord)
    $statusCode = 0
    try { $statusCode = [int]$ErrorRecord.Exception.Response.StatusCode } catch { }
    # Do not render raw exceptions: they can contain request/credential data.
    switch ($statusCode) {
        401 { return 'authentication failed; check your token with github token status' }
        403 { return 'permission denied or API rate limit reached; check token access and retry later' }
        404 { return 'resource unavailable or not accessible to this token' }
        429 { return 'API rate limit reached; retry later' }
        default { return 'request failed; check your connection and retry' }
    }
}

function Get-PFGitHubRepositories {
    param([hashtable]$Headers, [string]$Org, [string]$Type = 'all')
    $repositories = @()
    $page = 1
    do {
        try {
            $url = if ($Org) {
                "https://api.github.com/orgs/$([uri]::EscapeDataString($Org))/repos?type=$Type&per_page=100&page=$page"
            } else { "https://api.github.com/user/repos?affiliation=owner&per_page=100&page=$page" }
            $batch = @(Invoke-RestMethod -Uri $url -Headers $Headers -ErrorAction Stop)
            $repositories += @($batch | Where-Object { $null -ne $_ })
        }
        catch {
            $failure = $_
            $statusCode = 0
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
            return [pscustomobject]@{ Repositories = @($repositories); Complete = $false; Error = (Get-PFGitHubError $failure); Status = $statusCode }
        }
        $page++
    } while ($batch.Count -eq 100)
    return [pscustomobject]@{ Repositories = @($repositories); Complete = $true; Error = ''; Status = 200 }
}

function ConvertTo-PFGitHubDate {
    param($Value)
    if ($Value -is [DateTimeOffset]) { return $Value.UtcDateTime }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return $null }
    $parsedDate = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsedDate)) {
        return $parsedDate.UtcDateTime
    }
    return $null
}

function Format-PFGitHubText {
    param($Value)
    # API text must not add picker columns/lines or terminal escape sequences.
    return ([string]$Value -replace '[\x00-\x1f\x7f-\x9f]', ' ')
}

function ConvertTo-PFGitHubRepository {
    param($Repository)
    $pagesEnabled = $null
    if ($null -ne $Repository.has_pages) { $pagesEnabled = [bool]$Repository.has_pages }
    $pagesState = if ($pagesEnabled -eq $true) { 'enabled · status unknown' }
                  elseif ($pagesEnabled -eq $false) { 'disabled' } else { 'unknown' }
    $context = @()
    if ($Repository.archived) { $context += 'archived' }
    if ($Repository.fork) { $context += 'fork' }
    if ($Repository.is_template) { $context += 'template' }
    return [pscustomobject]@{
        Repository = $Repository
        Key = [string]$Repository.id
        FullName = [string]$Repository.full_name
        LastPush = (ConvertTo-PFGitHubDate $Repository.pushed_at)
        Created = (ConvertTo-PFGitHubDate $Repository.created_at)
        PagesEnabled = $pagesEnabled
        PagesState = $pagesState
        PagesUrl = $null
        PagesDomain = $null
        PagesBuildType = $null
        PagesSource = $null
        PagesError = ''
        PagesChecked = $false
        Context = ($context -join ', ')
        PagesHint = ([string]$Repository.name -ieq "$($Repository.owner.login).github.io" -or
                     [string]$Repository.homepage -match '^https?://[^/]+\.github\.io(?:/|$)')
    }
}

function Get-PFGitHubAgeCutoff {
    param([string]$OlderThan, [datetime]$Now = [datetime]::UtcNow)
    $Now = $Now.ToUniversalTime()
    if ($OlderThan -notmatch '^([1-9][0-9]*)([dmy])$') {
        throw 'Use a positive age such as --older-than 180d, 6m, or 1y.'
    }
    $amount = 0
    if (-not [int]::TryParse($Matches[1], [ref]$amount)) { throw 'The age is too large. Try --older-than 1y.' }
    try {
        switch ($Matches[2]) {
            'd' { return $Now.AddDays(-$amount) }
            'm' { return $Now.AddMonths(-$amount) }
            'y' { return $Now.AddYears(-$amount) }
        }
    } catch { throw 'The age is outside the supported date range. Try --older-than 1y.' }
}

function Select-PFGitHubRepositories {
    param([object[]]$Repositories, [switch]$Oldest, [Nullable[datetime]]$Cutoff,
          [switch]$Pages, [int]$Count = [int]::MaxValue)
    $models = @($Repositories | ForEach-Object { ConvertTo-PFGitHubRepository $_ })
    if ($Pages) { $models = @($models | Where-Object { $_.PagesEnabled -eq $true }) }
    if ($null -ne $Cutoff) {
        $models = @($models | Where-Object { $null -ne $_.LastPush -and $_.LastPush -le $Cutoff })
    }
    $known = @($models | Where-Object { $null -ne $_.LastPush } |
        Sort-Object @{ Expression = 'LastPush'; Descending = (-not $Oldest) }, FullName)
    $unknown = @($models | Where-Object { $null -eq $_.LastPush } | Sort-Object FullName)
    return @(($known + $unknown) | Select-Object -First $Count)
}

function Set-PFGitHubPages {
    param($Model, [hashtable]$Headers)
    if ($Model.PagesChecked -or $Model.PagesEnabled -ne $true) { return }
    $Model.PagesChecked = $true
    try {
        $pages = Invoke-RestMethod -Uri "https://api.github.com/repos/$($Model.FullName)/pages" -Headers $Headers -ErrorAction Stop
        if ($null -eq $pages) { throw 'No Pages record returned.' }
        $status = switch ([string]$pages.status) {
            'built' { 'built' }
            'building' { 'building' }
            'errored' { 'errored' }
            default { 'status unknown' }
        }
        $Model.PagesState = "enabled · $status"
        # Open only an explicit HTTP(S) site URL supplied by GitHub.
        $siteUri = $null
        if ([uri]::TryCreate([string]$pages.html_url, [UriKind]::Absolute, [ref]$siteUri) -and
            $siteUri.Scheme -in @('http', 'https') -and -not $siteUri.UserInfo) {
            $Model.PagesUrl = $siteUri.AbsoluteUri
        }
        $Model.PagesDomain = $pages.cname
        $Model.PagesBuildType = $pages.build_type
        $Model.PagesSource = $pages.source
    }
    catch {
        $Model.PagesState = 'enabled · details unavailable'
        $Model.PagesError = Get-PFGitHubError $_
    }
}

function Get-PFGitHubListing {
    param([hashtable]$Headers, [int]$Count, [switch]$Oldest, [string]$OlderThan, [switch]$Pages, [string]$Org)
    $cutoff = $null
    if ($OlderThan) { $cutoff = Get-PFGitHubAgeCutoff $OlderThan }
    $result = Get-PFGitHubRepositories -Headers $Headers -Org $Org
    if ($Org -and -not $result.Complete -and -not $result.Repositories.Count -and $result.Status -eq 403) {
        Write-PFWarning 'Organization access was denied or rate-limited; trying public repositories only.'
        $result = Get-PFGitHubRepositories -Headers $Headers -Org $Org -Type 'public'
        if ($result.Complete) {
            $result.Complete = $false
            $result.Error = 'Public repositories only; private organization repositories were not verified.'
        }
    }
    if (-not $result.Complete) {
        if (-not $result.Repositories.Count) {
            Write-PFFailure 'Could not fetch repositories.' -Hint $result.Error
            return $null
        }
        Write-PFWarning 'Repository list is incomplete; review covers only the fetched repositories.' -Detail $result.Error
    }
    $models = @(Select-PFGitHubRepositories -Repositories $result.Repositories -Oldest:$Oldest -Cutoff $cutoff -Pages:$Pages -Count $Count)
    foreach ($model in $models) { Set-PFGitHubPages -Model $model -Headers $Headers }
    return [pscustomobject]@{ Models = @($models); Complete = $result.Complete; Total = $result.Repositories.Count }
}
