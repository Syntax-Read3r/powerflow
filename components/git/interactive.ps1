# ==============================================================================
# PowerFlow — Git Interactive Tools
# ==============================================================================
# Domain   : Git
# File     : components/git/interactive.ps1
# Purpose  : Interactive fzf-based git log, status, stash, remote, and cherry-pick tools
# Functions: git-l, git-log, git-s, git-st, git-pick, git-p, git-stash, git-remote, git-sh, git-r
# Depends  : none
# ==============================================================================

function git-l {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Simplified git log command - no preview to avoid Unix command issues
    git log --oneline --graph --all --decorate --color=always |
        fzf --ansi --reverse --height=70% --border --prompt="🔍 Git Log: " `
            --header="📋 Enter: Copy hash & choose action | Esc: Cancel" |
        ForEach-Object {
            # Extract commit hash more reliably
            if ($_ -match '\b([a-f0-9]{7,40})\b') {
                $hash = $matches[1]
                Copy-ToClipboard $hash
                Write-Host "📋 Copied commit hash: $hash" -ForegroundColor Green

                # Show the selected line for context
                Write-Host "📝 Selected: $_" -ForegroundColor DarkGray

                # Offer additional actions
                Write-Host "`n🔧 What would you like to do with this commit?" -ForegroundColor Cyan
                Write-Host "  1. Show full details (git show)" -ForegroundColor DarkGray
                Write-Host "  2. Create branch from this commit" -ForegroundColor DarkGray
                Write-Host "  3. Cherry-pick this commit" -ForegroundColor DarkGray
                Write-Host "  4. Nothing (just copied hash)" -ForegroundColor DarkGray

                $action = Read-Host "Choose action (1-4)"
                switch ($action) {
                    "1" {
                        Write-Host "`n🔍 Showing commit details..." -ForegroundColor Cyan
                        git show $hash --color=always
                    }
                    "2" {
                        $branchName = Read-Host "🌿 Enter new branch name"
                        if ($branchName) {
                            git checkout -b $branchName $hash
                            Write-Host "✅ Created and switched to branch: $branchName" -ForegroundColor Green
                        }
                    }
                    "3" {
                        $confirm = Read-Host "🍒 Cherry-pick commit ${hash}? (y/n)"
                        if ($confirm -eq 'y') {
                            git cherry-pick $hash
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host "🍒 Cherry-picked commit: $hash" -ForegroundColor Green
                            } else {
                                Write-Host "❌ Cherry-pick failed. Check for conflicts." -ForegroundColor Red
                            }
                        }
                    }
                    default {
                        Write-Host "✅ Hash copied to clipboard" -ForegroundColor Green
                    }
                }
            } else {
                Write-Host "❌ Could not extract commit hash from: $_" -ForegroundColor Red
            }
        }
}

function git-log {
    git-l
}

function git-s {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Get git status with formatting
    git status --porcelain |
        ForEach-Object {
            $status = $_.Substring(0,2)
            $file = $_.Substring(3)

            switch ($status) {
                "??" { "❓ $file (untracked)" }
                " M" { "📝 $file (modified)" }
                "M " { "✅ $file (staged)" }
                "A " { "➕ $file (added)" }
                "D " { "🗑 $file (deleted)" }
                " D" { "❌ $file (deleted, unstaged)" }
                "R " { "🔄 $file (renamed)" }
                default { "📄 $file ($status)" }
            }
        } |
        fzf --ansi --reverse --height=60% --border --prompt="📊 Git Status: " `
            --header="Space: Stage/Unstage | Ctrl-D: Diff | Ctrl-R: Reset | Enter: Select | Esc: Cancel" `
            --multi |
        ForEach-Object {
            # Extract filename from formatted line
            $line = $_
            if ($line -match '^[📄📝✅➕🗑❌🔄❓]\s+(.+?)\s+\(') {
                $filename = $matches[1]
                Write-Host "📋 Selected: $filename" -ForegroundColor Green

                # Ask what to do with the file - FIXED: Use ${} to delimit variable
                Write-Host "`n🔧 Actions for ${filename}:" -ForegroundColor Cyan
                Write-Host "  1. Stage file (git add)" -ForegroundColor DarkGray
                Write-Host "  2. Unstage file (git reset)" -ForegroundColor DarkGray
                Write-Host "  3. Show diff" -ForegroundColor DarkGray
                Write-Host "  4. Discard changes" -ForegroundColor DarkGray

                $action = Read-Host "Choose action (1-4)"
                switch ($action) {
                    "1" {
                        git add $filename
                        Write-Host "✅ Staged: $filename" -ForegroundColor Green
                    }
                    "2" {
                        git reset HEAD $filename
                        Write-Host "📤 Unstaged: $filename" -ForegroundColor Yellow
                    }
                    "3" {
                        git diff $filename --color=always | less -R
                    }
                    "4" {
                        $confirm = Read-Host "⚠️  Discard all changes to ${filename}? (y/n)"
                        if ($confirm -eq 'y') {
                            git checkout -- $filename
                            Write-Host "🗑 Discarded changes: $filename" -ForegroundColor Red
                        }
                    }
                }
            }
        }
}

# Shorthand alias
function git-st { git-s }

function git-pick {
    git log --oneline --all --graph --color=always |
        fzf --ansi --reverse |
        ForEach-Object {
            # Extract commit hash using regex pattern matching
            if ($_ -match '^\*? ?([a-f0-9]{7,40})') {
                Copy-ToClipboard $matches[1]
                Write-Host "📋 Copied commit: $($matches[1])" -ForegroundColor Green
            }
        }
}

function git-p {
    git-pick
}

function git-stash {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Check if there are any stashes
    $stashes = git stash list
    if (-not $stashes) {
        Write-Host "📭 No stashes found" -ForegroundColor Yellow
        return
    }

    # Format stashes beautifully - PowerShell compatible version
    git stash list --color=always |
        fzf --ansi --reverse --height=50% --border --prompt="📦 Git Stash: " `
            --header="Enter: Apply | 1-4: Choose action | Esc: Cancel" |
        ForEach-Object {
            # Extract stash reference
            if ($_ -match '^(stash@\{\d+\})') {
                $stashRef = $matches[1]
                Write-Host "📦 Selected stash: $stashRef" -ForegroundColor Green

                Write-Host "`n🔧 Stash actions:" -ForegroundColor Cyan
                Write-Host "  1. Apply (keep stash)" -ForegroundColor DarkGray
                Write-Host "  2. Pop (apply and remove)" -ForegroundColor DarkGray
                Write-Host "  3. Show contents" -ForegroundColor DarkGray
                Write-Host "  4. Drop (delete)" -ForegroundColor DarkGray

                $action = Read-Host "Choose action (1-4)"
                switch ($action) {
                    "1" {
                        git stash apply $stashRef
                        Write-Host "✅ Applied stash: $stashRef" -ForegroundColor Green
                    }
                    "2" {
                        git stash pop $stashRef
                        Write-Host "📤 Popped stash: $stashRef" -ForegroundColor Green
                    }
                    "3" {
                        git stash show -p $stashRef --color=always
                    }
                    "4" {
                        $confirm = Read-Host "⚠️  Drop stash $stashRef? (y/n)"
                        if ($confirm -eq 'y') {
                            git stash drop $stashRef
                            Write-Host "🗑 Dropped stash: $stashRef" -ForegroundColor Red
                        }
                    }
                }
            }
        }
}

function git-remote {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Get remotes with URLs
    git remote -v |
        ForEach-Object {
            if ($_ -match '^(\w+)\s+(.+?)\s+\((fetch|push)\)') {
                $name = $matches[1]
                $url = $matches[2]
                $type = $matches[3]

                if ($type -eq "fetch") {
                    if ($url -match "github\.com") {
                        "🐙 $name → $url"
                    } elseif ($url -match "gitlab\.com") {
                        "🦊 $name → $url"
                    } elseif ($url -match "bitbucket\.org") {
                        "🪣 $name → $url"
                    } else {
                        "🌐 $name → $url"
                    }
                }
            }
        } |
        fzf --ansi --reverse --height=40% --border --prompt="🌐 Git Remotes: " `
            --header="Enter: Choose action | Esc: Cancel" |
        ForEach-Object {
            # Extract remote name
            if ($_ -match '^[🐙🦊🪣🌐]\s+(\w+)\s+→') {
                $remoteName = $matches[1]
                Write-Host "🌐 Selected remote: $remoteName" -ForegroundColor Green

                Write-Host "`n🔧 Remote actions:" -ForegroundColor Cyan
                Write-Host "  1. Fetch from remote" -ForegroundColor DarkGray
                Write-Host "  2. Push to remote" -ForegroundColor DarkGray
                Write-Host "  3. Show remote info" -ForegroundColor DarkGray
                Write-Host "  4. Set new URL" -ForegroundColor DarkGray

                $action = Read-Host "Choose action (1-4)"
                switch ($action) {
                    "1" {
                        git fetch $remoteName
                        Write-Host "📥 Fetched from: $remoteName" -ForegroundColor Green
                    }
                    "2" {
                        $branch = git rev-parse --abbrev-ref HEAD
                        git push $remoteName $branch
                        Write-Host "📤 Pushed to: $remoteName" -ForegroundColor Green
                    }
                    "3" {
                        git remote show $remoteName
                    }
                    "4" {
                        $newUrl = Read-Host "Enter new URL for $remoteName"
                        if ($newUrl) {
                            git remote set-url $remoteName $newUrl
                            Write-Host "✅ Updated URL for: $remoteName" -ForegroundColor Green
                        }
                    }
                }
            }
        }
}

# Add shorthand aliases
function git-sh { git-stash }      # Shorthand for git stash
function git-r { git-remote }      # Shorthand for git remote

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'git-l'     -Aliases @('git-log') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'interactive log viewer with per-commit actions'
Register-PFCommand -Name 'git-s'     -Aliases @('git-st') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'interactive status viewer'
Register-PFCommand -Name 'git-p'     -Aliases @('git-pick') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'fuzzy-pick commits for cherry-pick'
Register-PFCommand -Name 'git-stash' -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'interactive stash manager'
Register-PFCommand -Name 'git-r'     -Aliases @('git-remote') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'interactive remote manager'
Register-PFCommand -Name 'git-sh'    -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'show a commit, interactively chosen'
