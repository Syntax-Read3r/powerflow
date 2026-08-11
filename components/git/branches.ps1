# ==============================================================================
# PowerFlow — Git Branch Management
# ==============================================================================
# Domain   : Git
# File     : components/git/branches.ps1
# Purpose  : Interactive branch creation, switching, and deletion with fzf interface
# Functions: git-branch, Invoke-DeleteBranch, git-b, git-cm, git-bd, git-bD, git-c.sb
# Depends  : none
# ==============================================================================

function git-branch {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Get current branch
    $currentBranch = git branch --show-current

    # Get main branch name (main or master)
    $mainBranch = $null
    if (git show-ref --verify --quiet refs/heads/main) {
        $mainBranch = "main"
    } elseif (git show-ref --verify --quiet refs/heads/master) {
        $mainBranch = "master"
    }

    # Create branch list with simple markers (avoiding emoji encoding issues)
    $branches = @()
    git branch -a --format="%(refname:short)|%(HEAD)|local" | ForEach-Object {
        $parts = $_ -split '\|'
        $branchName = $parts[0]
        $isCurrent = $parts[1] -eq '*'
        $marker = if ($isCurrent) { "* " } else { "  " }
        $branches += [PSCustomObject]@{
            DisplayName = "$marker$branchName"
            ActualName = $branchName
            IsCurrent = $isCurrent
            IsRemote = $false
        }
    }

    # Add remote branches
    git branch -r --format="%(refname:short)" | Where-Object { $_ -notmatch '/HEAD' } | ForEach-Object {
        $branchName = $_
        $localName = $branchName -replace '^origin/', ''
        # Only add if no local branch exists with same name
        if ($branches.ActualName -notcontains $localName) {
            $branches += [PSCustomObject]@{
                DisplayName = "  $branchName (remote)"
                ActualName = $branchName
                IsCurrent = $false
                IsRemote = $true
            }
        }
    }

    # Use fzf to select branch
    $selected = $branches.DisplayName | fzf --reverse --height=40% --border --prompt="Select branch: " --header="↑↓ navigate, Enter to select, Esc to cancel"

    if (-not $selected) {
        Write-Host "No branch selected" -ForegroundColor DarkGray
        return
    }

    # Find the selected branch object
    $selectedBranch = $branches | Where-Object { $_.DisplayName -eq $selected }
    $branchName = $selectedBranch.ActualName
    $isRemote = $selectedBranch.IsRemote
    $isCurrent = $selectedBranch.IsCurrent

    # Copy branch name to clipboard (clean name without remote prefix for local operations)
    $cleanBranchName = $branchName -replace '^origin/', ''
    Copy-ToClipboard $cleanBranchName
    Write-Host "📋 Copied branch: $cleanBranchName" -ForegroundColor Green

    # Don't allow operations on current branch
    if ($isCurrent) {
        Write-Host "⚠️  Cannot perform operations on current branch" -ForegroundColor Yellow
        return
    }

    # Show action menu
    $actions = @(
        "1. Switch to branch",
        "2. Delete branch locally",
        "3. Delete branch remotely",
        "4. Delete branch locally AND remotely",
        "5. Cancel"
    )

    Write-Host "`nAvailable actions:" -ForegroundColor Cyan
    $actions | ForEach-Object { Write-Host $_ -ForegroundColor White }
    $choice = Read-Host "`nSelect action (1-5)"

    switch ($choice) {
        "1" {
            # Switch to branch
            if ($isRemote) {
                $localName = $branchName -replace '^origin/', ''
                Write-Host "Creating local tracking branch: $localName" -ForegroundColor Yellow
                git checkout -b $localName $branchName
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Created and switched to local branch: $localName" -ForegroundColor Green
                }
            } else {
                git checkout $branchName
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Switched to branch: $branchName" -ForegroundColor Green
                }
            }
        }
        "2" {
            # Delete locally
            if ($isRemote) {
                Write-Host "⚠️  Cannot delete remote branch locally. Use option 3 or 4." -ForegroundColor Yellow
                return
            }
            Invoke-DeleteBranch -BranchName $branchName -Location "local" -MainBranch $mainBranch
        }
        "3" {
            # Delete remotely
            $remoteBranchName = if ($isRemote) { $branchName -replace '^origin/', '' } else { $branchName }
            Invoke-DeleteBranch -BranchName $remoteBranchName -Location "remote" -MainBranch $mainBranch
        }
        "4" {
            # Delete both
            $remoteBranchName = if ($isRemote) { $branchName -replace '^origin/', '' } else { $branchName }
            Invoke-DeleteBranch -BranchName $remoteBranchName -Location "both" -MainBranch $mainBranch
        }
        "5" {
            Write-Host "Cancelled" -ForegroundColor DarkGray
        }
        default {
            Write-Host "Invalid choice" -ForegroundColor Red
        }
    }
}

function Invoke-DeleteBranch {
    param(
        [string]$BranchName,
        [string]$Location, # "local", "remote", or "both"
        [string]$MainBranch
    )

    # Check if branches exist
    $localExists = git branch --list $BranchName | ForEach-Object { $_.Trim() -replace '^\*?\s*', '' } | Where-Object { $_ -eq $BranchName }
    $remoteExists = git branch -r --list "origin/$BranchName" | ForEach-Object { $_.Trim() -replace 'origin/', '' } | Where-Object { $_ -eq $BranchName }

    # Check if branch is merged into main
    $isMerged = $false
    if ($MainBranch -and $localExists) {
        try {
            $mergeBase = git merge-base $BranchName $MainBranch 2>$null
            $branchCommit = git rev-parse $BranchName 2>$null
            $isMerged = $mergeBase -eq $branchCommit
        } catch {
            # If we can't determine, assume not merged for safety
            $isMerged = $false
        }
    }

    # Show what exists
    Write-Host "`n📍 Branch status:" -ForegroundColor Cyan
    Write-Host "   Local: $(if ($localExists) { '✅ Exists' } else { '❌ Not found' })" -ForegroundColor $(if ($localExists) { 'Green' } else { 'Red' })
    Write-Host "   Remote: $(if ($remoteExists) { '✅ Exists' } else { '❌ Not found' })" -ForegroundColor $(if ($remoteExists) { 'Green' } else { 'Red' })

    # Adjust location based on what actually exists
    $originalLocation = $Location
    if ($Location -eq "both") {
        if (-not $localExists -and -not $remoteExists) {
            Write-Host "❌ Branch doesn't exist locally or remotely" -ForegroundColor Red
            return
        } elseif (-not $localExists) {
            $Location = "remote"
            Write-Host "ℹ️  Only remote branch exists, will delete remotely only" -ForegroundColor Yellow
        } elseif (-not $remoteExists) {
            $Location = "local"
            Write-Host "ℹ️  Only local branch exists, will delete locally only" -ForegroundColor Yellow
        }
    } elseif ($Location -eq "local" -and -not $localExists) {
        Write-Host "❌ Local branch doesn't exist" -ForegroundColor Red
        return
    } elseif ($Location -eq "remote" -and -not $remoteExists) {
        Write-Host "❌ Remote branch doesn't exist" -ForegroundColor Red
        return
    }

    # Show warnings
    Write-Host "`n⚠️  WARNING: You are about to DELETE branch '$BranchName'" -ForegroundColor Red

    if ($originalLocation -eq "both") {
        Write-Host "🔥 This will delete the branch BOTH locally AND remotely (where it exists)!" -ForegroundColor Red
    } elseif ($Location -eq "remote") {
        Write-Host "🌐 This will delete the branch from the remote repository!" -ForegroundColor Red
    } else {
        Write-Host "💻 This will delete the local branch!" -ForegroundColor Yellow
    }

    if (-not $isMerged -and $MainBranch -and $localExists) {
        Write-Host "🚨 DANGER: This branch does NOT appear to be merged into '$MainBranch'!" -ForegroundColor Red
        Write-Host "🚨 You may lose commits that exist only on this branch!" -ForegroundColor Red
    } elseif ($isMerged) {
        Write-Host "✅ Branch appears to be merged into '$MainBranch'" -ForegroundColor Green
    }

    # Final confirmation
    $confirmation = Read-Host "`nType 'DELETE' to confirm deletion, or anything else to cancel"

    if ($confirmation -ne "DELETE") {
        Write-Host "Deletion cancelled" -ForegroundColor Green
        return
    }

    # Perform deletion
    $localSuccess = $true
    $remoteSuccess = $true

    if (($Location -eq "local" -or $Location -eq "both") -and $localExists) {
        Write-Host "Deleting local branch..." -ForegroundColor Yellow
        if ($isMerged) {
            git branch -d $BranchName
        } else {
            git branch -D $BranchName  # Force delete unmerged branch
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Local branch deleted successfully" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to delete local branch" -ForegroundColor Red
            $localSuccess = $false
        }
    }

    if (($Location -eq "remote" -or $Location -eq "both") -and $remoteExists) {
        Write-Host "Deleting remote branch..." -ForegroundColor Yellow
        git push origin --delete $BranchName
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Remote branch deleted successfully" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to delete remote branch" -ForegroundColor Red
            $remoteSuccess = $false
        }
    }

    # Final status
    $overallSuccess = $localSuccess -and $remoteSuccess
    if ($overallSuccess) {
        Write-Host "`n🎉 Branch deletion completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Branch deletion completed with some issues (see details above)" -ForegroundColor Yellow
    }
}

function git-b {
    git-branch
}

function git-cm {
    git checkout main
    Write-Host "🔄 Switched to main branch" -ForegroundColor Cyan
}

function git-bd {
    param([Parameter(Mandatory = $true)][string]$branchName)

    # Get current branch for safety check
    $currentBranch = git rev-parse --abbrev-ref HEAD

    if ($branchName -eq $currentBranch) {
        Write-Host "⚠️  You are currently on '$branchName'. Switch to another branch before deleting." -ForegroundColor Yellow
        return
    }

    # Attempt safe deletion (only if merged)
    git branch -d $branchName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "🗑 Deleted branch: $branchName" -ForegroundColor Green
    } else {
        Write-Host "❌ Could not delete branch: $branchName (not fully merged?)" -ForegroundColor Red
        Write-Host "💡 Use git-bd-force to force delete unmerged branches" -ForegroundColor DarkGray
    }
}

# RENAMED FROM `git-bD`. PowerShell's function table is case-insensitive, so `git-bD` and
# `git-bd` were the SAME name: whichever loaded second won, and that was this one. Typing the
# documented-safe `git-bd` therefore ran `git branch -D` and force-deleted unmerged work, while
# git-bd's own hint pointed at a name that no longer differed from itself.
#
# `git-bD` cannot be kept as an alias — that is precisely the collision. The safe spelling keeps
# the short name; the destructive one has to be spelled out.
function git-bd-force {
    param([Parameter(Mandatory = $true)][string]$branchName)

    # Get current branch name for safety check
    $currentBranch = git rev-parse --abbrev-ref HEAD

    # Prevent deletion of currently checked out branch
    if ($branchName -eq $currentBranch) {
        Write-Host "⚠️  You are currently on '$branchName'. Switch to another branch before force-deleting." -ForegroundColor Yellow
        return
    }

    # Attempt force deletion
    git branch -D $branchName
    if ($LASTEXITCODE -eq 0) {
        Write-Host "💥 Force-deleted branch: $branchName" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Could not force delete branch: $branchName (may not exist)" -ForegroundColor Red
    }
}

function git-c.sb {
    param([string]$label, [string]$suffixOrCommit)

    # Interactive mode: beautiful fuzzy branch picker
    if (-not $label) {
        # Check if we're in a git repository
        if (-not (git rev-parse --git-dir 2>$null)) {
            Write-Host "❌ Not in a Git repository" -ForegroundColor Red
            return
        }

        # Get current branch for highlighting
        $currentBranch = git rev-parse --abbrev-ref HEAD

        # Get all branches with enhanced formatting
        git branch -a --format="%(refname:short)" |
            ForEach-Object {
                $branch = $_
                if ($branch -eq $currentBranch) {
                    "🌟 $branch (current)"
                } elseif ($branch -like "origin/*") {
                    "🌐 $branch"
                } elseif ($branch -like "remotes/*") {
                    "📡 $branch"
                } else {
                    "🌿 $branch"
                }
            } |
            fzf --ansi --reverse --height=50% --border --prompt="🔀 Switch Branch: " `
                --header="🌟 Current | 🌿 Local | 🌐 Remote | Enter: Switch | Esc: Cancel" |
            ForEach-Object {
                # Extract clean branch name
                $selected = $_ -replace '^[🌟🌐📡🌿]\s*', ''
                $selected = $selected -replace '\s*\(current\)$', ''
                $selected = $selected -replace '^origin/', ''

                if ($selected -and $selected -ne $currentBranch) {
                    git switch $selected
                    Write-Host "🔄 Switched to branch: $selected" -ForegroundColor Cyan
                } else {
                    Write-Host "❌ No branch change needed" -ForegroundColor DarkGray
                }
            }
        return
    }

    # Construct branch name
    $branchName = if ($suffixOrCommit) { "$label-$suffixOrCommit" } else { $label }

    # Check if branch already exists
    $exists = git branch --list $branchName

    if ($exists) {
        # Switch to existing branch
        git switch $branchName
        Write-Host "🔄 Switched to existing branch: $branchName" -ForegroundColor Cyan
    } else {
        # Create new branch
        if ($suffixOrCommit -match '^[a-f0-9]{6,40}$') {
            # Create from specific commit
            git checkout -b $branchName $suffixOrCommit
            Write-Host "🌿 Created from $suffixOrCommit and switched to: $branchName" -ForegroundColor Green
        } else {
            # Create from current HEAD
            git checkout -b $branchName
            Write-Host "🌿 Created and switched to new branch: $branchName" -ForegroundColor Green
        }
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'git-b'    -Aliases @('git-branch') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'interactive branch picker: switch, create, delete'
Register-PFCommand -Name 'git-cm'   -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'checkout main/master, whichever exists'
# `git-bD` is NOT listed as an alias any more, and must never be re-added. PowerShell function
# names are case-insensitive, so `git-bD` and `git-bd` are the same name — declaring one as an
# alias of the other described a distinction the language cannot make, and the force variant
# silently replaced the safe one.
Register-PFCommand -Name 'git-bd'       -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'delete a merged branch; refuses if unmerged'
Register-PFCommand -Name 'git-bd-force' -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'DESTRUCTIVE: delete a branch even if unmerged (was git-bD)'
Register-PFCommand -Name 'git-c.sb' -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'create and switch to a new branch'
