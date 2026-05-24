# ==============================================================================
# PowerFlow — GitHub Repository Browser
# ==============================================================================
# Domain   : GitHub
# File     : components/github/browser.ps1
# Purpose  : Browse, clone, open, and delete GitHub repositories via API with fzf interface
# Functions: gh-l, gh-l-reset, gh-l-status, gh-l-org
# Depends  : none
# ==============================================================================

# ── Internal helpers (shared by gh-l and gh-l-org) ───────────────────────────

function _GhL-SetToken {
    param([string]$Token)
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /generic:$credentialName /user:github /pass:$Token 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Token saved securely in Windows Credential Manager" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠️ Could not save to Credential Manager: $result" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "⚠️ Could not save token: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

function _GhL-GetToken {
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /list:$credentialName 2>&1
        if ($LASTEXITCODE -eq 0 -and $result -match "GENERIC") {
            if (-not ([System.Management.Automation.PSTypeName]'CredentialManager').Type) {
                Add-Type -TypeDefinition @"
                using System;
                using System.Runtime.InteropServices;
                using System.Text;

                public class CredentialManager
                {
                    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
                    public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

                    [DllImport("advapi32.dll", SetLastError = true)]
                    public static extern void CredFree(IntPtr cred);

                    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
                    public struct CREDENTIAL
                    {
                        public int Flags;
                        public int Type;
                        public string TargetName;
                        public string Comment;
                        public long LastWritten;
                        public int CredentialBlobSize;
                        public IntPtr CredentialBlob;
                        public int Persist;
                        public int AttributeCount;
                        public IntPtr Attributes;
                        public string TargetAlias;
                        public string UserName;
                    }

                    public static string GetPassword(string target)
                    {
                        IntPtr credPtr;
                        if (CredRead(target, 1, 0, out credPtr))
                        {
                            var credential = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
                            var password = Marshal.PtrToStringUni(credential.CredentialBlob, credential.CredentialBlobSize / 2);
                            CredFree(credPtr);
                            return password;
                        }
                        return null;
                    }
                }
"@
            }
            $password = [CredentialManager]::GetPassword($credentialName)
            if ($password) {
                Write-Host "🔐 Using saved token from Credential Manager" -ForegroundColor DarkGreen
                return $password
            }
        }
        return $null
    } catch {
        return $null
    }
}

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
        return 0
    }
}

# ── Public functions ──────────────────────────────────────────────────────────

function gh-l {
    param (
        [int]$Count = 10,
        [string]$Token
    )

    # Allow positional parameter for count: gh-l 15
    if ($args.Count -gt 0 -and $args[0] -match '^\d+$') {
        $Count = [int]$args[0]
    }

    $credentialName = "gh-l-github-token"

    # Get token from various sources
    if (-not $Token) {
        $Token = $env:GITHUB_TOKEN
        if (-not $Token) {
            $Token = _GhL-GetToken
        }
    }

    # If still no token, prompt for it
    if (-not $Token) {
        Write-Host "❌ GitHub Personal Access Token required for private repos" -ForegroundColor Red
        Write-Host ""
        Write-Host "🔧 Setup instructions:" -ForegroundColor Cyan
        Write-Host "  1. Go to: https://github.com/settings/tokens" -ForegroundColor DarkGray
        Write-Host "  2. Generate new token (classic) with 'repo' scope" -ForegroundColor DarkGray
        Write-Host "  3. Copy the token and paste it below" -ForegroundColor DarkGray
        Write-Host ""

        $secureInput = Read-Host "🔑 Enter your GitHub token (input hidden)" -AsSecureString
        $Token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
        )

        if ($Token) {
            $save = Read-Host "💾 Save token securely in Windows Credential Manager? (y/n)"
            if ($save -eq 'y') {
                _GhL-SetToken -Token $Token
            }
        }
    }

    if (-not $Token) {
        Write-Host "❌ No token provided" -ForegroundColor Red
        return
    }

    # Calculate date filters
    $now = Get-Date
    $yesterday = $now.AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $lastWeek = $now.AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")

    $allRepos = @()
    $page = 1
    $perPage = 100

    try {
        $headers = @{
            "Authorization" = "Bearer $Token"
            "Accept" = "application/vnd.github.v3+json"
            "User-Agent" = "pwsh-gh-l"
        }

        Write-Host "🔐 Fetching all your repositories to ensure proper sorting..." -ForegroundColor Cyan

        do {
            $url = "https://api.github.com/user/repos?per_page=$perPage&page=$page&affiliation=owner"
            $pageRepos = Invoke-RestMethod -Uri $url -Headers $headers

            if ($pageRepos.Count -gt 0) {
                $allRepos += $pageRepos
                Write-Host "📦 Fetched $($allRepos.Count) repositories..." -ForegroundColor DarkGray
                $page++
            }
        } while ($pageRepos.Count -eq $perPage)

        Write-Host "✅ Found $($allRepos.Count) total repositories" -ForegroundColor Green

        Write-Host "🔍 Debugging: Sorting $($allRepos.Count) repositories by push date..." -ForegroundColor Yellow

        $sortedRepos = $allRepos | ForEach-Object {
            $pushDate = try {
                [DateTime]$_.pushed_at
            } catch {
                [DateTime]"1900-01-01"
            }

            [PSCustomObject]@{
                Repo = $_
                PushDate = $pushDate
                PushDateString = $pushDate.ToString("yyyy-MM-dd HH:mm")
            }
        } | Sort-Object PushDate -Descending

        Write-Host "🔍 Top 3 most recent pushes:" -ForegroundColor Yellow
        $sortedRepos | Select-Object -First 3 | ForEach-Object {
            Write-Host "   $($_.Repo.name) - $($_.PushDateString)" -ForegroundColor DarkGray
        }

        $repos = $sortedRepos | Select-Object -First $Count -ExpandProperty Repo

        Write-Host "🎯 Showing top $Count most recently pushed repositories" -ForegroundColor Cyan

        if (-not $repos) {
            Write-Host "ℹ️ No repositories found." -ForegroundColor Yellow
            return
        }

        Write-Host "📊 Analyzing commit activity..." -ForegroundColor Yellow

        $terminalWidth = try {
            $Host.UI.RawUI.WindowSize.Width
        } catch {
            120
        }

        $maxHeight = [Math]::Min($repos.Count + 5, 25)

        $choices = $repos | ForEach-Object {
            $repoName = $_.name
            $privacy = if ($_.private) { "🔒" } else { "🌐" }
            $language = if ($_.language) { $_.language } else { "Text" }
            $lastPush = ([DateTime]$_.pushed_at).ToString("yyyy-MM-dd")
            $commits24h = _GhL-CommitCount -RepoFullName $_.full_name -Since $yesterday -Headers $headers
            $commits1w = _GhL-CommitCount -RepoFullName $_.full_name -Since $lastWeek -Headers $headers

            $nameWidth = [Math]::Min(30, [Math]::Max(20, $terminalWidth * 0.25))
            $langWidth = [Math]::Min(12, [Math]::Max(8, $terminalWidth * 0.12))

            "{0} {1,-$nameWidth}  📅{2}  📊24h:{3,2}  📈1w:{4,2}  💻{5,-$langWidth}" -f `
                $privacy, $repoName, $lastPush, $commits24h, $commits1w, $language
        }

        $header = "🔒=Private 🌐=Public | 📅=Last Push (YYYY-MM-DD) | 📊=Commits 24h | 📈=Commits 1w | 💻=Language"

        $selection = $choices | fzf --ansi --reverse --height=$maxHeight --border --no-sort `
            --prompt="📦 Recent Repos ($Count shown): " --header="$header"

        if ($selection) {
            Write-Host "🔍 Debug: Selection = '$selection'" -ForegroundColor Yellow

            if ($selection -match '^\S+\s+(\S+)') {
                $selectedRepoName = $matches[1].Trim()
                Write-Host "🔍 Debug: Extracted repo name = '$selectedRepoName'" -ForegroundColor Yellow

                $selectedRepo = $repos | Where-Object { $_.name -eq $selectedRepoName }
                if ($selectedRepo) {
                    $repoUrl = $selectedRepo.html_url
                    $repoFullName = $selectedRepo.full_name

                    Set-Clipboard $repoUrl
                    Write-Host "📋 Copied URL: $repoUrl" -ForegroundColor Green
                    Write-Host "`n🔧 What would you like to do with '$selectedRepoName'?" -ForegroundColor Cyan
                    Write-Host "  1. Clone repository" -ForegroundColor DarkGray
                    Write-Host "  2. Open in browser" -ForegroundColor DarkGray
                    Write-Host "  3. Copy SSH URL instead" -ForegroundColor DarkGray
                    Write-Host "  4. Delete repository (⚠️ PERMANENT)" -ForegroundColor Red
                    Write-Host "  5. Just copied HTTP URL" -ForegroundColor DarkGray

                    $action = Read-Host "Choose action (1-5)"
                    switch ($action) {
                        "1" {
                            Write-Host "📂 Cloning repository..." -ForegroundColor Cyan
                            Write-Host "Running: git clone $repoUrl" -ForegroundColor DarkGray
                            git clone $repoUrl
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "✅ Repository cloned successfully!" -ForegroundColor Green
                            } else {
                                Write-Host "❌ Clone failed. Check your git configuration." -ForegroundColor Red
                            }
                        }
                        "2" {
                            Write-Host "🌐 Opening in browser..." -ForegroundColor Cyan
                            Start-Process $repoUrl
                        }
                        "3" {
                            $sshUrl = $repoUrl -replace "https://github.com/", "git@github.com:" -replace "\.git$", "" + ".git"
                            Set-Clipboard $sshUrl
                            Write-Host "📋 Copied SSH URL: $sshUrl" -ForegroundColor Green
                        }
                        "4" {
                            Write-Host "`n⚠️ WARNING: YOU ARE ABOUT TO DELETE A REPOSITORY!" -ForegroundColor Red -BackgroundColor Yellow
                            Write-Host "Repository: $repoFullName" -ForegroundColor White -BackgroundColor Red
                            Write-Host "This action is PERMANENT and CANNOT be undone!" -ForegroundColor Red
                            Write-Host "All code, issues, pull requests, and history will be lost forever!" -ForegroundColor Red

                            Write-Host "`n🔴 CONFIRMATION 1 of 3:" -ForegroundColor Red
                            $confirm1 = Read-Host "Type the repository name '$selectedRepoName' to continue"
                            if ($confirm1 -ne $selectedRepoName) {
                                Write-Host "❌ Repository name mismatch. Deletion cancelled." -ForegroundColor Green
                                break
                            }

                            Write-Host "`n🔴 CONFIRMATION 2 of 3:" -ForegroundColor Red
                            $confirm2 = Read-Host "Type 'DELETE' (in capitals) to confirm you want to delete this repository"
                            if ($confirm2 -ne "DELETE") {
                                Write-Host "❌ Confirmation failed. Deletion cancelled." -ForegroundColor Green
                                break
                            }

                            Write-Host "`n🔴 FINAL CONFIRMATION 3 of 3:" -ForegroundColor Red
                            Write-Host "This is your LAST CHANCE to cancel!" -ForegroundColor Red
                            $confirm3 = Read-Host "Type 'I UNDERSTAND THIS IS PERMANENT' to proceed with deletion"
                            if ($confirm3 -ne "I UNDERSTAND THIS IS PERMANENT") {
                                Write-Host "❌ Final confirmation failed. Deletion cancelled." -ForegroundColor Green
                                break
                            }

                            Write-Host "`n💀 Deleting repository..." -ForegroundColor Red
                            try {
                                $deleteUrl = "https://api.github.com/repos/$repoFullName"
                                $deleteResult = Invoke-RestMethod -Uri $deleteUrl -Method DELETE -Headers $headers
                                Write-Host "💀 Repository '$selectedRepoName' has been permanently deleted." -ForegroundColor Red
                                Write-Host "🔄 You may want to run gh-l again to refresh the list." -ForegroundColor Yellow
                            } catch {
                                if ($_.Exception.Message -match "404") {
                                    Write-Host "❌ Repository not found. It may have already been deleted." -ForegroundColor Yellow
                                } elseif ($_.Exception.Message -match "403") {
                                    Write-Host "❌ Permission denied. You may not have delete permissions for this repository." -ForegroundColor Red
                                } else {
                                    Write-Host "❌ Failed to delete repository: $($_.Exception.Message)" -ForegroundColor Red
                                }
                            }
                        }
                        default {
                            Write-Host "✅ Done. HTTPS URL is on your clipboard." -ForegroundColor Green
                        }
                    }
                } else {
                    Write-Host "❌ Could not find repository details for: '$selectedRepoName'" -ForegroundColor Red
                    Write-Host "🔍 Available repos: $($repos.name -join ', ')" -ForegroundColor DarkGray
                }
            } else {
                Write-Host "❌ Could not extract repository name from selection" -ForegroundColor Red
                Write-Host "🔍 Selection format: '$selection'" -ForegroundColor DarkGray
                Write-Host "💡 Try selecting a different repository" -ForegroundColor Yellow
            }
        }
    } catch {
        if ($_.Exception.Message -match "401") {
            Write-Warning "❌ Authentication failed. Token may be invalid or expired."
            $remove = Read-Host "🗑️ Remove saved token from Credential Manager? (y/n)"
            if ($remove -eq 'y') {
                & cmdkey /delete:$credentialName 2>$null
                Write-Host "🗑️ Saved token removed from Credential Manager" -ForegroundColor Yellow
            }
        } elseif ($_.Exception.Message -match "403") {
            Write-Warning "❌ Forbidden. Token may lack proper permissions (needs 'repo' scope)."
        } else {
            Write-Warning "❌ Failed to fetch repos: $($_.Exception.Message)"
        }
    }
}

function gh-l-reset {
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /delete:$credentialName 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "🗑️ GitHub token removed from Credential Manager" -ForegroundColor Green
        } else {
            Write-Host "ℹ️ No saved token found in Credential Manager" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️ Error removing token: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function gh-l-status {
    $credentialName = "gh-l-github-token"
    try {
        $result = & cmdkey /list:$credentialName 2>&1
        if ($LASTEXITCODE -eq 0 -and $result -match "GENERIC") {
            Write-Host "✅ GitHub token is saved in Credential Manager" -ForegroundColor Green
        } else {
            Write-Host "ℹ️ No GitHub token saved" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ℹ️ No GitHub token saved" -ForegroundColor Yellow
    }
}

function gh-l-org {
    param (
        [string]$Org,
        [int]$Count = 100
    )

    # ── Authenticate ──────────────────────────────────────────────────────────
    $token = $env:GITHUB_TOKEN
    if (-not $token) { $token = _GhL-GetToken }

    if (-not $token) {
        Write-Host "❌ GitHub Personal Access Token required" -ForegroundColor Red
        Write-Host ""
        Write-Host "🔧 Setup instructions:" -ForegroundColor Cyan
        Write-Host "  1. Go to: https://github.com/settings/tokens" -ForegroundColor DarkGray
        Write-Host "  2. Generate new token (classic) with 'repo' and 'read:org' scopes" -ForegroundColor DarkGray
        Write-Host "  3. Copy the token and paste it below" -ForegroundColor DarkGray
        Write-Host ""

        $secureInput = Read-Host "🔑 Enter your GitHub token (input hidden)" -AsSecureString
        $token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
        )

        if ($token) {
            $save = Read-Host "💾 Save token securely in Windows Credential Manager? (y/n)"
            if ($save -eq 'y') { _GhL-SetToken -Token $token }
        }
    }

    if (-not $token) { Write-Host "❌ No token provided" -ForegroundColor Red; return }

    $headers = @{
        "Authorization" = "Bearer $token"
        "Accept"        = "application/vnd.github.v3+json"
        "User-Agent"    = "pwsh-gh-l-org"
    }

    # ── Org selection ─────────────────────────────────────────────────────────
    $selectedOrg = $Org

    if (-not $selectedOrg) {
        Write-Host "🏢 Fetching your organisations..." -ForegroundColor Cyan
        try {
            $orgs = Invoke-RestMethod -Uri "https://api.github.com/user/orgs?per_page=100" -Headers $headers
        } catch {
            Write-Host "❌ Failed to fetch organisations: $($_.Exception.Message)" -ForegroundColor Red
            return
        }

        if (-not $orgs -or $orgs.Count -eq 0) {
            Write-Host "ℹ️ You are not a member of any GitHub organisations." -ForegroundColor Yellow
            return
        }

        $orgChoices = $orgs | ForEach-Object {
            $desc = if ($_.description) { $_.description } else { "no description" }
            "🏢 {0,-30}  {1}" -f $_.login, $desc
        }

        $orgSelection = $orgChoices | fzf --ansi --reverse --height=20 --border `
            --prompt="🏢 Select organisation: " --header="Enter to select · Esc to cancel"

        if (-not $orgSelection) {
            Write-Host "Cancelled." -ForegroundColor DarkGray
            return
        }

        if ($orgSelection -match '🏢\s+(\S+)') {
            $selectedOrg = $Matches[1].Trim()
        } else {
            Write-Host "❌ Could not parse organisation name from selection." -ForegroundColor Red
            return
        }
    }

    Write-Host "🏢 Organisation: $selectedOrg" -ForegroundColor Cyan

    # ── Fetch org repos ───────────────────────────────────────────────────────
    Write-Host "📦 Fetching repositories for '$selectedOrg'..." -ForegroundColor Cyan

    $allOrgRepos = @()
    $repoTypes   = @("all", "public")

    foreach ($repoType in $repoTypes) {
        $allOrgRepos = @()
        $page        = 1
        $shouldRetry = $false
        $pageRepos   = @()

        do {
            $url = "https://api.github.com/orgs/$selectedOrg/repos?type=$repoType&per_page=100&page=$page"
            try {
                $pageRepos = Invoke-RestMethod -Uri $url -Headers $headers
                if ($pageRepos.Count -gt 0) {
                    $allOrgRepos += $pageRepos
                    Write-Host "   Fetched $($allOrgRepos.Count) repositories..." -ForegroundColor DarkGray
                    $page++
                }
            } catch {
                if ($_.Exception.Message -match "403" -and $repoType -eq "all") {
                    Write-Host "⚠️ Token may lack 'read:org' scope — showing public repos only." -ForegroundColor Yellow
                    Write-Host "   Regenerate at https://github.com/settings/tokens with read:org checked." -ForegroundColor DarkGray
                    $shouldRetry = $true
                    $pageRepos   = @()
                } else {
                    Write-Host "❌ Failed to fetch repositories: $($_.Exception.Message)" -ForegroundColor Red
                    return
                }
            }
        } while ($pageRepos.Count -eq 100)

        if (-not $shouldRetry) { break }
    }

    if (-not $allOrgRepos -or $allOrgRepos.Count -eq 0) {
        Write-Host "ℹ️ No repositories found in '$selectedOrg'." -ForegroundColor Yellow
        return
    }

    Write-Host "✅ Found $($allOrgRepos.Count) repositories in '$selectedOrg'" -ForegroundColor Green

    # Sort by pushed_at descending and apply limit
    $displayRepos = $allOrgRepos | ForEach-Object {
        $pushDate = try { [DateTime]$_.pushed_at } catch { [DateTime]"1900-01-01" }
        [PSCustomObject]@{ Repo = $_; PushDate = $pushDate }
    } | Sort-Object PushDate -Descending | Select-Object -First $Count -ExpandProperty Repo

    # ── Repo picker ───────────────────────────────────────────────────────────
    $now       = Get-Date
    $yesterday = $now.AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $lastWeek  = $now.AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ssZ")

    Write-Host "📊 Analysing commit activity..." -ForegroundColor Yellow

    $terminalWidth = try { $Host.UI.RawUI.WindowSize.Width } catch { 120 }
    $maxHeight     = [Math]::Min($displayRepos.Count + 5, 25)

    $repoChoices = $displayRepos | ForEach-Object {
        $privacy    = if ($_.private) { "🔒" } else { "🌐" }
        $language   = if ($_.language) { $_.language } else { "Text" }
        $lastPush   = ([DateTime]$_.pushed_at).ToString("yyyy-MM-dd")
        $commits24h = _GhL-CommitCount -RepoFullName $_.full_name -Since $yesterday -Headers $headers
        $commits1w  = _GhL-CommitCount -RepoFullName $_.full_name -Since $lastWeek  -Headers $headers

        $nameWidth = [Math]::Min(30, [Math]::Max(20, $terminalWidth * 0.25))
        $langWidth = [Math]::Min(12, [Math]::Max(8,  $terminalWidth * 0.12))

        "{0} {1,-$nameWidth}  📅{2}  📊24h:{3,2}  📈1w:{4,2}  💻{5,-$langWidth}" -f `
            $privacy, $_.name, $lastPush, $commits24h, $commits1w, $language
    }

    $repoHeader = "🔒=Private 🌐=Public | 📅=Last Push | 📊=Commits 24h | 📈=Commits 1w | 💻=Language  [$selectedOrg · $($displayRepos.Count) repos]"

    $repoSelection = $repoChoices | fzf --ansi --reverse --height=$maxHeight --border --no-sort `
        --prompt="📦 $selectedOrg repos: " --header="$repoHeader"

    if (-not $repoSelection) {
        Write-Host "Cancelled." -ForegroundColor DarkGray
        return
    }

    $selectedRepoName = $null
    if ($repoSelection -match '^\S+\s+(\S+)') {
        $selectedRepoName = $Matches[1].Trim()
    }

    $selectedRepo = $displayRepos | Where-Object { $_.name -eq $selectedRepoName }

    if (-not $selectedRepo) {
        Write-Host "❌ Could not resolve repo '$selectedRepoName' from selection." -ForegroundColor Red
        return
    }

    $repoUrl = $selectedRepo.html_url
    $sshUrl  = "git@github.com:$($selectedRepo.full_name).git"
    Set-Clipboard $repoUrl
    Write-Host "📋 Copied URL: $repoUrl" -ForegroundColor Green

    # ── Action menu ───────────────────────────────────────────────────────────
    Write-Host "`n🔧 What would you like to do with '$selectedRepoName'?" -ForegroundColor Cyan
    Write-Host "  1. Clone selected repo" -ForegroundColor DarkGray
    Write-Host "  2. Clone ALL $($displayRepos.Count) repos in '$selectedOrg'  (creates .\$selectedOrg\)" -ForegroundColor DarkGray
    Write-Host "  3. Open selected repo in browser" -ForegroundColor DarkGray
    Write-Host "  4. Copy HTTPS URL" -ForegroundColor DarkGray
    Write-Host "  5. Copy SSH URL" -ForegroundColor DarkGray

    $action = Read-Host "Choose action (1-5)"

    switch ($action) {
        "1" {
            Write-Host "📂 Cloning $selectedRepoName..." -ForegroundColor Cyan
            git clone $repoUrl
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Cloned successfully." -ForegroundColor Green
            } else {
                Write-Host "❌ Clone failed. Check your git configuration." -ForegroundColor Red
            }
        }
        "2" {
            Write-Host "`n⚠️ This will clone $($displayRepos.Count) repos into .\$selectedOrg\" -ForegroundColor Yellow
            $confirm = Read-Host "Proceed? (y/n)"
            if ($confirm -ne 'y') { Write-Host "Cancelled." -ForegroundColor DarkGray; return }

            New-Item -ItemType Directory -Path $selectedOrg -ErrorAction SilentlyContinue | Out-Null
            Write-Host "📁 Created .\$selectedOrg\" -ForegroundColor Green

            Push-Location $selectedOrg
            $cloned = 0
            $failed = 0
            foreach ($r in $displayRepos) {
                Write-Host "  [$($cloned + $failed + 1)/$($displayRepos.Count)] Cloning $($r.name)..." -ForegroundColor DarkGray
                git clone $r.clone_url *>$null
                if ($LASTEXITCODE -eq 0) {
                    $cloned++
                } else {
                    Write-Host "  ❌ Failed: $($r.name)" -ForegroundColor Red
                    $failed++
                }
            }
            Pop-Location

            Write-Host "✅ Done — $cloned cloned, $failed failed  →  .\$selectedOrg\" -ForegroundColor Green
        }
        "3" {
            Start-Process $repoUrl
            Write-Host "🌐 Opened in browser." -ForegroundColor Cyan
        }
        "4" {
            Set-Clipboard $repoUrl
            Write-Host "📋 Copied HTTPS URL: $repoUrl" -ForegroundColor Green
        }
        "5" {
            Set-Clipboard $sshUrl
            Write-Host "📋 Copied SSH URL: $sshUrl" -ForegroundColor Green
        }
        default {
            Write-Host "✅ HTTPS URL already on clipboard: $repoUrl" -ForegroundColor Green
        }
    }
}
