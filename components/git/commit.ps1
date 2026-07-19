# ==============================================================================
# PowerFlow — Git Commit Workflow
# ==============================================================================
# Domain   : Git
# File     : components/git/commit.ps1
# Purpose  : Interactive add→commit→push workflow with fzf interface
# Functions: git-a, git-a-plus, git-aa, git-aq, git-ad, git-am
# Depends  : components/git/remote.ps1
# ==============================================================================

function git-a {

    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        Write-Host "📁 Current directory: $(Get-Location)" -ForegroundColor Cyan

        # Offer to initialize git repository
        $initChoice = Read-Host "Would you like to initialize a Git repository here? (y/N)"
        if ($initChoice -eq 'y') {
            Write-Host "🚀 Initializing Git repository..." -ForegroundColor Yellow
            git init
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Git repository initialized successfully" -ForegroundColor Green
                # Continue with the workflow
            } else {
                Write-Host "❌ Failed to initialize Git repository" -ForegroundColor Red
                return
            }
        } else {
            return
        }
    }

    # Check for changes
    $status = git status --short
    if (-not $status) {
        Write-Host "✅ No changes to commit - working tree is clean" -ForegroundColor Green
        return
    }

    # Get current branch and check remote status
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    if (-not $branch) {
        # Fresh repo, no commits yet - default to main
        $branch = "main"
        git checkout -b main 2>$null
    }

    $remoteUrl = git remote get-url origin 2>$null

    # Display repository status
    if ($remoteUrl) {
        Write-Host "📡 Remote: $remoteUrl" -ForegroundColor DarkCyan
    } else {
        Write-Host "📁 Local repository (no remote configured)" -ForegroundColor Yellow
    }

    $commits = git log --oneline --color=always -n 2 2>$null

    # Format commits with numbering (latest first)
    $commitLines = @()
    if ($commits) {
        $commitArray = @($commits)
        for ($i = 0; $i -lt $commitArray.Count; $i++) {
            $commitLines += "   $($i + 1). $($commitArray[$i])"
        }
    } else {
        $commitLines += "   (No previous commits)"
    }

    # Enhanced file status formatting
    $fileLines = @()
    $status | ForEach-Object {
        $statusCode = $_.Substring(0, 2)
        $fileName = $_.Substring(3)

        switch ($statusCode.Trim()) {
            "M"  { $fileLines += "   📝 $fileName (modified)" }
            "A"  { $fileLines += "   ➕ $fileName (added)" }
            "D"  { $fileLines += "   🗑 $fileName (deleted)" }
            "R"  { $fileLines += "   🔄 $fileName (renamed)" }
            "C"  { $fileLines += "   📋 $fileName (copied)" }
            "??" { $fileLines += "   ❓ $fileName (untracked)" }
            default { $fileLines += "   📄 $fileName ($statusCode)" }
        }
    }

    $workflowHeader = "🚀 Git Add → Commit → Push Workflow"

    # Minimalistic formatted display for fzf
    $formLines = @(
        "",
        "🌿 Branch: $branch"
    )

    # Add remote status to the display
    if ($remoteUrl) {
        $formLines += "📡 Remote: $($remoteUrl -replace 'https://github.com/', '')"
    } else {
        $formLines += "📁 Status: Local-only (no remote)"
    }

    $formLines += @(
        "",
        "📋 Files to be committed:"
    ) + $fileLines + @(
        "",
        "📚 Recent commit history:"
    ) + $commitLines + @(
        "",
        "💬 Type your commit message above and press Enter"
    )

    # Launch fzf with --print-query to get typed input, not selected line
    $fzfOutput = $formLines | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=80% `
        --prompt="📝 Commit Message: " `
        --header="$workflowHeader" `
        --header-first `
        --color="header:bold:blue,prompt:bold:green,border:cyan,spinner:yellow" `
        --margin=1 `
        --padding=1 `
        --print-query `
        --expect=enter

    # Extract the commit message from fzf output
    $userMessage = ""
    if ($fzfOutput) {
        $lines = @($fzfOutput)
        if ($lines.Count -gt 0) {
            $userMessage = $lines[0].Trim()
        }
    }

    # Validate user message
    if ([string]::IsNullOrWhiteSpace($userMessage) -or $userMessage.Length -lt 3) {
        Write-Host "❌ Commit message too short or cancelled" -ForegroundColor Yellow
        return
    }

    $commitMessage = "commit - $userMessage"

    # Execute the workflow with progress indicators
    Write-Host "📂 Adding all changes..." -ForegroundColor Yellow
    git add .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git add failed" -ForegroundColor Red
        return
    }
    Write-Host "✅ Files staged successfully" -ForegroundColor Green

    Write-Host "💾 Committing changes..." -ForegroundColor Yellow
    Write-Host "📝 Full commit message: $commitMessage" -ForegroundColor DarkGray
    git commit -m $commitMessage
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git commit failed" -ForegroundColor Red
        return
    }
    Write-Host "✅ Commit created successfully" -ForegroundColor Green

    # Check if remote exists BEFORE attempting to push
    $remoteUrl = git remote get-url origin 2>$null
    $hasUpstream = git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null
    $hadRemoteInitially = [bool]$remoteUrl

    if (-not $remoteUrl) {
        Write-Host "⚠️  No remote repository configured" -ForegroundColor Yellow
        Write-Host "🔍 This appears to be a local-only repository" -ForegroundColor Cyan

        # Check if GitHub CLI is available BEFORE offering to create remote
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Write-Host "❌ GitHub CLI (gh) is not installed - cannot create remote repository" -ForegroundColor Red
            Write-Host "📦 Install it from: https://cli.github.com" -ForegroundColor Cyan
            Write-Host "💡 After installing, run: gh auth login" -ForegroundColor DarkGray
            Write-Host "🔄 Then run git-a again to push your changes" -ForegroundColor Yellow
            return
        }

        # Offer to create remote repository
        if (Create-RemoteRepository) {
            # Re-check remote URL after creation
            $remoteUrl = git remote get-url origin 2>$null
            $hasUpstream = $null  # Force setting upstream on first push
        } else {
            Write-Host "❌ Cannot push without a remote repository" -ForegroundColor Red
            return
        }
    } elseif (-not $hasUpstream) {
        Write-Host "📡 Remote exists but no upstream branch set" -ForegroundColor Yellow
    }

    # Now attempt the push
    Write-Host "🚀 Pushing to remote..." -ForegroundColor Yellow

    if ($hasUpstream) {
        # Normal push if upstream is set
        git push
    } else {
        # Set upstream on first push to this branch
        Write-Host "🔗 Setting upstream branch..." -ForegroundColor Cyan
        git push -u origin $branch
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git push failed" -ForegroundColor Red

        # If push fails, check if it's because remote doesn't actually exist (e.g., deleted on GitHub)
        $pushError = git push 2>&1 | Out-String
        if ($pushError -match "repository not found|remote.*does not exist") {
            Write-Host "⚠️  Remote repository no longer exists on GitHub" -ForegroundColor Yellow
            Write-Host "💡 The remote URL is configured but the repository may have been deleted" -ForegroundColor DarkGray

            $recreate = Read-Host "Would you like to create a new repository? (y/N)"
            if ($recreate -eq 'y') {
                git remote remove origin
                if (Create-RemoteRepository) {
                    Write-Host "🚀 Retrying push to newly created remote..." -ForegroundColor Yellow
                    git push -u origin $branch
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Successfully pushed to '$branch'" -ForegroundColor Green
                    }
                }
            }
        } else {
            Write-Host "💡 You may need to resolve conflicts or check your permissions" -ForegroundColor DarkGray
        }
        return
    }

    Write-Host "✅ Successfully pushed to '$branch'" -ForegroundColor Green

    # Show summary if this was a new remote creation
    if ($remoteUrl -and -not $hadRemoteInitially) {
        Write-Host "`n🎊 Complete! Your project is now live on GitHub!" -ForegroundColor Magenta
        Write-Host "📍 URL: $remoteUrl" -ForegroundColor Cyan
    }

}

function git-a-plus {
    param(
        [switch]$Quick,
        [switch]$DryRun,
        [switch]$AmendLast
    )

    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    if ($AmendLast) {
        # Amend last commit workflow with beautiful styling
        $branch = git rev-parse --abbrev-ref HEAD
        $lastCommit = git log --oneline --color=always -n 1 2>$null
        $commits = git log --oneline --color=always -n 3 2>$null

        # Format recent commits for context
        $commitLines = @()
        if ($commits) {
            $commitArray = @($commits)
            for ($i = 0; $i -lt [Math]::Min($commitArray.Count, 3); $i++) {
                if ($i -eq 0) {
                    $commitLines += "   👑 $($commitArray[$i]) (current)"
                } else {
                    $commitLines += "   $($i + 1). $($commitArray[$i])"
                }
            }
        }

        # Beautiful formatted display for amend
        $formLines = @(
            "",
            "🌿 Branch: $branch",
            "",
            "🔄 Amending last commit:",
            "   👑 $lastCommit",
            "",
            "📚 Recent commit history:"
        ) + $commitLines + @(
            "",
            "💬 Type new commit message (or press Enter to keep current)"
        )

        # Launch fzf for amend message input
        $fzfOutput = $formLines | fzf `
            --ansi `
            --reverse `
            --border=rounded `
            --height=70% `
            --prompt="📝 New Message: " `
            --header="🔄 Amend Last Commit" `
            --header-first `
            --color="header:bold:yellow,prompt:bold:cyan,border:yellow" `
            --margin=1 `
            --padding=1 `
            --print-query `
            --expect=enter

        # Extract the new message
        $newMessage = ""
        if ($fzfOutput) {
            $lines = @($fzfOutput)
            if ($lines.Count -gt 0) {
                $newMessage = $lines[0].Trim()
            }
        }

        Write-Host "🔄 Amending commit..." -ForegroundColor Yellow

        if ([string]::IsNullOrWhiteSpace($newMessage)) {
            git add .
            git commit --amend --no-edit
            Write-Host "✅ Amended with original message" -ForegroundColor Green
        } else {
            git add .
            git commit --amend -m $newMessage
            Write-Host "✅ Amended with new message: $newMessage" -ForegroundColor Green
        }

        if ($LASTEXITCODE -eq 0) {
            $pushConfirm = Read-Host "🚀 Force push amended commit? (y/n)"
            if ($pushConfirm -eq 'y') {
                Write-Host "🚀 Force pushing..." -ForegroundColor Yellow
                git push --force-with-lease
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Successfully force-pushed amended commit" -ForegroundColor Green
                } else {
                    Write-Host "❌ Failed to push amended commit" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "❌ Failed to amend commit" -ForegroundColor Red
        }
        return
    }

    if ($DryRun) {
        # Dry run mode with beautiful file status display
        $branch = git rev-parse --abbrev-ref HEAD
        $status = git status --short

        if (-not $status) {
            Write-Host ""
            Write-Host "╭─ 🔍 DRY RUN PREVIEW ─────────────────────────────────────────────────╮" -ForegroundColor Cyan
            Write-Host "│                                                                      │" -ForegroundColor Cyan
            Write-Host "│  ✅ No changes to commit - working tree is clean                    │" -ForegroundColor Cyan
            Write-Host "│                                                                      │" -ForegroundColor Cyan
            Write-Host "╰──────────────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
            Write-Host ""
            return
        }

        # Enhanced file status formatting (same as git-a)
        $fileLines = @()
        $status | ForEach-Object {
            $statusCode = $_.Substring(0, 2)
            $fileName = $_.Substring(3)

            switch ($statusCode.Trim()) {
                "M"  { $fileLines += "   📝 $fileName (modified)" }
                "A"  { $fileLines += "   ➕ $fileName (added)" }
                "D"  { $fileLines += "   🗑 $fileName (deleted)" }
                "R"  { $fileLines += "   🔄 $fileName (renamed)" }
                "C"  { $fileLines += "   📋 $fileName (copied)" }
                "??" { $fileLines += "   ❓ $fileName (untracked)" }
                default { $fileLines += "   📄 $fileName ($statusCode)" }
            }
        }

        # Beautiful dry run display
        Write-Host ""
        Write-Host "╭─ 🔍 DRY RUN PREVIEW ─────────────────────────────────────────────────╮" -ForegroundColor Cyan
        Write-Host "│                                                                      │" -ForegroundColor Cyan
        Write-Host "│  🌿 Branch: $branch".PadRight(69) + "│" -ForegroundColor Cyan
        Write-Host "│                                                                      │" -ForegroundColor Cyan
        Write-Host "╰──────────────────────────────────────────────────────────────────────╯" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "📋 Files that would be added:" -ForegroundColor Yellow
        $fileLines | ForEach-Object { Write-Host $_ -ForegroundColor White }
        Write-Host ""
        Write-Host "💡 Run 'git-a' to execute the actual workflow" -ForegroundColor Cyan
        Write-Host ""
        return
    }

    if ($Quick) {
        # Quick mode with minimal but beautiful styling
        $branch = git rev-parse --abbrev-ref HEAD
        $status = git status --short

        if (-not $status) {
            Write-Host "✅ No changes to commit - working tree is clean" -ForegroundColor Green
            return
        }

        # Show quick preview
        $fileCount = @($status).Count
        Write-Host ""
        Write-Host "╭─ ⚡ QUICK COMMIT MODE ───────────────────────────────────────────────╮" -ForegroundColor Yellow
        Write-Host "│                                                                      │" -ForegroundColor Yellow
        Write-Host "│  🌿 Branch: $branch".PadRight(69) + "│" -ForegroundColor Yellow
        Write-Host "│  📂 Files: $fileCount file(s) to commit".PadRight(69) + "│" -ForegroundColor Yellow
        Write-Host "│                                                                      │" -ForegroundColor Yellow
        Write-Host "╰──────────────────────────────────────────────────────────────────────╯" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "💬 Commit message: " -NoNewline -ForegroundColor Cyan
        $commitMessage = Read-Host

        if ([string]::IsNullOrWhiteSpace($commitMessage) -or $commitMessage.Length -lt 3) {
            Write-Host "❌ Commit message too short or empty" -ForegroundColor Red
            return
        }

        Write-Host ""
        Write-Host "⚡ Executing quick workflow..." -ForegroundColor Yellow

        git add .
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ git add failed" -ForegroundColor Red
            return
        }
        Write-Host "✅ Files staged" -ForegroundColor Green

        git commit -m $commitMessage
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ git commit failed" -ForegroundColor Red
            return
        }
        Write-Host "✅ Commit created" -ForegroundColor Green

        git push
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Quick commit completed and pushed to '$branch'!" -ForegroundColor Green
        } else {
            Write-Host "❌ git push failed" -ForegroundColor Red
        }
        Write-Host ""
        return
    }

    # Default to standard git-a workflow
    git-a
}

function git-aa { git-a-plus -Quick }
function git-aq { git-a-plus -Quick }
function git-ad { git-a-plus -DryRun }
function git-am { git-a-plus -AmendLast }

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'git-a'      -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'add - commit - push, interactively' -Example 'git-a'
Register-PFCommand -Name 'git-a-plus' -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'git-a with modes: -Quick, -DryRun, -AmendLast'
Register-PFCommand -Name 'git-aa'  -Aliases @('git-aq') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'quick add-commit-push, minimal prompts'
Register-PFCommand -Name 'git-ad'  -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'dry run - preview what would be committed'
Register-PFCommand -Name 'git-am'  -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'amend the last commit with a new message'
