# ==============================================================================
# PowerFlow — GitHub Repository Browser
# ==============================================================================
# Domain   : GitHub
# File     : components/github/browser.ps1
# Purpose  : Browse, clone, open, and delete GitHub repositories via API with fzf interface
# Functions: gh-l, gh-l-reset, gh-l-status
# Depends  : none
# ==============================================================================

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

    # Function to securely store token in Windows Credential Manager
    function Set-GitHubToken {
        param([string]$Token)
        try {
            # Store in Windows Credential Manager using cmdkey
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

    # Function to retrieve token from Windows Credential Manager
    function Get-GitHubToken {
        try {
            # Check if credential exists
            $result = & cmdkey /list:$credentialName 2>&1
            if ($LASTEXITCODE -eq 0 -and $result -match "GENERIC") {
                # Use .NET CredentialManager to retrieve the password
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

    # Function to get commit count for a repo in specified timeframe
    function Get-CommitCount {
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

    # Get token from various sources
    if (-not $Token) {
        # Try environment variable first
        $Token = $env:GITHUB_TOKEN

        # If no env token, check credential manager
        if (-not $Token) {
            $Token = Get-GitHubToken
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
                Set-GitHubToken -Token $Token
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

    # Get ALL repositories first, then sort manually to ensure correct order
    # GitHub API sometimes doesn't sort reliably, so we'll fetch everything and sort ourselves
    $allRepos = @()
    $page = 1
    $perPage = 100  # Max per page

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
        } while ($pageRepos.Count -eq $perPage)  # Continue while we get full pages

        Write-Host "✅ Found $($allRepos.Count) total repositories" -ForegroundColor Green

        # Now sort ALL repos by pushed_at date (most recent first) and take only what we need
        Write-Host "🔍 Debugging: Sorting $($allRepos.Count) repositories by push date..." -ForegroundColor Yellow

        # Add sorting with explicit date conversion and debugging
        $sortedRepos = $allRepos | ForEach-Object {
            $pushDate = try {
                [DateTime]$_.pushed_at
            } catch {
                [DateTime]"1900-01-01"  # Fallback for invalid dates
            }

            [PSCustomObject]@{
                Repo = $_
                PushDate = $pushDate
                PushDateString = $pushDate.ToString("yyyy-MM-dd HH:mm")
            }
        } | Sort-Object PushDate -Descending

        # Show top 3 for debugging
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

        # Get terminal width for dynamic sizing
        $terminalWidth = try {
            $Host.UI.RawUI.WindowSize.Width
        } catch {
            120  # fallback width
        }

        # Calculate fzf height based on available repos and terminal size
        $maxHeight = [Math]::Min($repos.Count + 5, 25)  # +5 for headers/borders, max 25

        $choices = $repos | ForEach-Object {
            $repoName = $_.name
            $privacy = if ($_.private) { "🔒" } else { "🌐" }
            $language = if ($_.language) { $_.language } else { "Text" }

            # Get the last push date - show full date for debugging
            $lastPush = ([DateTime]$_.pushed_at).ToString("yyyy-MM-dd")

            # Get commit counts (this adds some delay but provides valuable info)
            $commits24h = Get-CommitCount -RepoFullName $_.full_name -Since $yesterday -Headers $headers
            $commits1w = Get-CommitCount -RepoFullName $_.full_name -Since $lastWeek -Headers $headers

            # Format with proper spacing - adjust column widths based on terminal
            $nameWidth = [Math]::Min(30, [Math]::Max(20, $terminalWidth * 0.25))
            $langWidth = [Math]::Min(12, [Math]::Max(8, $terminalWidth * 0.12))

            "{0} {1,-$nameWidth}  📅{2}  📊24h:{3,2}  📈1w:{4,2}  💻{5,-$langWidth}" -f `
                $privacy, $repoName, $lastPush, $commits24h, $commits1w, $language
        }

        # Header for the display
        $header = "🔒=Private 🌐=Public | 📅=Last Push (YYYY-MM-DD) | 📊=Commits 24h | 📈=Commits 1w | 💻=Language"

        $selection = $choices | fzf --ansi --reverse --height=$maxHeight --border --no-sort `
            --prompt="📦 Recent Repos ($Count shown): " --header="$header"

        if ($selection) {
            # Extract repo name from selection - handle emoji encoding issues
            # The emojis might display as different Unicode characters in different terminals
            # So we'll match more flexibly: any character(s) followed by spaces, then the repo name

            Write-Host "🔍 Debug: Selection = '$selection'" -ForegroundColor Yellow

            # More flexible pattern: skip the first few characters (emoji), then capture the repo name
            # Pattern explanation: ^\S*\s+(\S+) = start of line, non-spaces (emoji), spaces, then repo name
            if ($selection -match '^\S+\s+(\S+)') {
                $selectedRepoName = $matches[1].Trim()
                Write-Host "🔍 Debug: Extracted repo name = '$selectedRepoName'" -ForegroundColor Yellow

                # Find the full repo object to get URL and details
                $selectedRepo = $repos | Where-Object { $_.name -eq $selectedRepoName }
                if ($selectedRepo) {
                    $repoUrl = $selectedRepo.html_url
                    $repoFullName = $selectedRepo.full_name  # owner/repo format

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
                            # Convert HTTPS URL to SSH
                            $sshUrl = $repoUrl -replace "https://github.com/", "git@github.com:" -replace "\.git$", "" + ".git"
                            Set-Clipboard $sshUrl
                            Write-Host "📋 Copied SSH URL: $sshUrl" -ForegroundColor Green
                        }
                        "4" {
                            # DANGEROUS: Delete repository with triple confirmation
                            Write-Host "`n⚠️ WARNING: YOU ARE ABOUT TO DELETE A REPOSITORY!" -ForegroundColor Red -BackgroundColor Yellow
                            Write-Host "Repository: $repoFullName" -ForegroundColor White -BackgroundColor Red
                            Write-Host "This action is PERMANENT and CANNOT be undone!" -ForegroundColor Red
                            Write-Host "All code, issues, pull requests, and history will be lost forever!" -ForegroundColor Red

                            # First confirmation
                            Write-Host "`n🔴 CONFIRMATION 1 of 3:" -ForegroundColor Red
                            $confirm1 = Read-Host "Type the repository name '$selectedRepoName' to continue"
                            if ($confirm1 -ne $selectedRepoName) {
                                Write-Host "❌ Repository name mismatch. Deletion cancelled." -ForegroundColor Green
                                break
                            }

                            # Second confirmation
                            Write-Host "`n🔴 CONFIRMATION 2 of 3:" -ForegroundColor Red
                            $confirm2 = Read-Host "Type 'DELETE' (in capitals) to confirm you want to delete this repository"
                            if ($confirm2 -ne "DELETE") {
                                Write-Host "❌ Confirmation failed. Deletion cancelled." -ForegroundColor Green
                                break
                            }

                            # Third confirmation
                            Write-Host "`n🔴 FINAL CONFIRMATION 3 of 3:" -ForegroundColor Red
                            Write-Host "This is your LAST CHANCE to cancel!" -ForegroundColor Red
                            $confirm3 = Read-Host "Type 'I UNDERSTAND THIS IS PERMANENT' to proceed with deletion"
                            if ($confirm3 -ne "I UNDERSTAND THIS IS PERMANENT") {
                                Write-Host "❌ Final confirmation failed. Deletion cancelled." -ForegroundColor Green
                                break
                            }

                            # Proceed with deletion
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
            # Optionally remove saved token if it's invalid
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

# Helper function to remove saved token from Credential Manager
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

# Helper function to check if token is saved
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
