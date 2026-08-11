# ==============================================================================
# PowerFlow — Git Rollback
# ==============================================================================
# Domain   : Git
# File     : components/git/rollback.ps1
# Purpose  : Safe rollback to previous commits using dedicated rollback branches
# Functions: git-rba, git-rb
# Depends  : none
# ==============================================================================

function git-rba {
    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Get current branch name
    $currentBranch = git branch --show-current

    # Check if current branch matches rollback-<alphanumeric> pattern
    if ($currentBranch -notmatch '^rollback-[a-zA-Z0-9]+$') {
        Write-Host "❌ Error: Not on a rollback branch" -ForegroundColor Red
        Write-Host "Current branch: $currentBranch" -ForegroundColor Yellow
        Write-Host "Expected pattern: rollback-<alphanumeric> (e.g., rollback-781, rollback-a27, rollback-fix123)" -ForegroundColor Yellow
        return
    }

    Write-Host "🔄 Working on rollback branch: $currentBranch" -ForegroundColor Cyan

    # Check for changes
    $status = git status --short
    if (-not $status) {
        Write-Host "ℹ️  No changes to commit, working tree clean" -ForegroundColor Yellow
        Write-Host "🚀 Pushing existing commits to origin..." -ForegroundColor Blue
        git push origin $currentBranch

        # Show the GitHub PR creation link
        $repoUrl = git config --get remote.origin.url
        if ($repoUrl -like "*github.com*") {
            if ($repoUrl -match 'github\.com[:/](.+?)(?:\.git)?/?$') {
                $repoPath = $matches[1] -replace '\.git$', ''
                Write-Host ""
                Write-Host "🔗 Create a pull request by visiting:" -ForegroundColor Magenta
                Write-Host "   https://github.com/$repoPath/pull/new/$currentBranch" -ForegroundColor Blue
            }
        }
        Write-Host "✅ Rollback branch operations completed!" -ForegroundColor Green
        return
    }

    # Get commit history for current rollback branch only
    $commits = git log --oneline --color=always -n 2 $currentBranch 2>$null

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

    # Minimalistic formatted display for fzf
    $formLines = @(
        "",
        "🔄 Rollback Branch: $currentBranch",
        "",
        "📋 Files to be committed:"
    ) + $fileLines + @(
        "",
        "📚 Recent commit history (this branch):"
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
        --header="🚀 Git Add → Commit → Push Workflow" `
        --header-first `
        --color="header:bold:blue,prompt:bold:green,border:cyan,spinner:yellow" `
        --margin=1 `
        --padding=1 `
        --print-query `
        --expect=enter

    # Extract the commit message from fzf output
    $commitMessage = ""
    if ($fzfOutput) {
        $lines = @($fzfOutput)
        if ($lines.Count -gt 0) {
            $commitMessage = $lines[0].Trim()
        }
    }

    # Validate commit message
    if ([string]::IsNullOrWhiteSpace($commitMessage) -or $commitMessage.Length -lt 3) {
        Write-Host "❌ Commit message too short or cancelled" -ForegroundColor Yellow
        return
    }

    # Execute the rollback workflow with progress indicators
    Write-Host "📂 Adding all changes..." -ForegroundColor Yellow
    git add .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git add failed" -ForegroundColor Red
        return
    }
    Write-Host "✅ Files staged successfully" -ForegroundColor Green

    Write-Host "💾 Committing changes..." -ForegroundColor Yellow
    git commit -m $commitMessage
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git commit failed" -ForegroundColor Red
        return
    }
    Write-Host "✅ Commit created successfully" -ForegroundColor Green

    Write-Host "🚀 Pushing to origin $currentBranch..." -ForegroundColor Yellow
    git push origin $currentBranch
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Successfully pushed to '$currentBranch'" -ForegroundColor Green
    } else {
        Write-Host "❌ git push failed" -ForegroundColor Red
        Write-Host "💡 You may need to resolve conflicts or check remote access" -ForegroundColor DarkGray
        return
    }

    # Show the GitHub PR creation link
    $repoUrl = git config --get remote.origin.url
    if ($repoUrl -like "*github.com*") {
        if ($repoUrl -match 'github\.com[:/](.+?)(?:\.git)?/?$') {
            $repoPath = $matches[1] -replace '\.git$', ''
            Write-Host ""
            Write-Host "🔗 Create a pull request by visiting:" -ForegroundColor Magenta
            Write-Host "   https://github.com/$repoPath/pull/new/$currentBranch" -ForegroundColor Blue
        }
    }

    Write-Host "✅ Rollback branch operations completed!" -ForegroundColor Green
}

# Create shorter alias
Set-Alias -Name grba -Value git-rba

function Invoke-GitRollbackTo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$commitHash,
        [switch]$Force
    )

    # Check if we're in a git repository
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    # Resolve the commit hash to full hash and validate it exists
    try {
        $fullHash = git rev-parse $commitHash 2>$null
        if (-not $fullHash) {
            Write-Host "❌ Invalid commit hash: $commitHash" -ForegroundColor Red
            return
        }
    } catch {
        Write-Host "❌ Could not resolve commit: $commitHash" -ForegroundColor Red
        return
    }

    # Get short hash for display and branch naming
    $shortHash = git rev-parse --short $commitHash
    $last3Chars = $shortHash.Substring([Math]::Max(0, $shortHash.Length - 3))
    $branchName = "rollback-$last3Chars"

    # Get commit info for confirmation
    $commitInfo = git log --oneline -n 1 $commitHash
    $currentBranch = git rev-parse --abbrev-ref HEAD

    # Safety confirmation
    if (-not $Force) {
        Write-Host ""
        Write-Host "🔄 Git Rollback Operation" -ForegroundColor Cyan
        Write-Host "═══════════════════════════" -ForegroundColor Cyan
        Write-Host "📍 Current branch: $currentBranch" -ForegroundColor Yellow
        Write-Host "🎯 Target commit: $commitInfo" -ForegroundColor Green
        Write-Host "🌿 New branch: $branchName" -ForegroundColor Green
        Write-Host ""
        Write-Host "⚠️  This will:" -ForegroundColor Yellow
        Write-Host "   • Create new branch '$branchName'" -ForegroundColor DarkGray
        Write-Host "   • Switch to that branch" -ForegroundColor DarkGray
        Write-Host "   • Reset ALL code to match commit $shortHash" -ForegroundColor DarkGray
        Write-Host ""

        $confirm = Read-Host "Continue with rollback? (y/n)"
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "❌ Rollback cancelled" -ForegroundColor Yellow
            return
        }
    }

    # Check if branch already exists
    $existingBranch = git branch --list $branchName
    if ($existingBranch) {
        if (-not $Force) {
            Write-Host "⚠️  Branch '$branchName' already exists!" -ForegroundColor Yellow
            $overwrite = Read-Host "Delete existing branch and recreate? (y/n)"
            if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
                Write-Host "❌ Rollback cancelled" -ForegroundColor Yellow
                return
            }
        }

        # Delete existing branch (force delete in case it's not merged)
        Write-Host "🗑 Deleting existing branch: $branchName" -ForegroundColor Yellow
        git branch -D $branchName
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ Failed to delete existing branch" -ForegroundColor Red
            return
        }
    }

    # Create new branch from the target commit and switch to it
    Write-Host "🌿 Creating rollback branch: $branchName" -ForegroundColor Cyan
    git checkout -b $branchName $commitHash

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ Rollback successful!" -ForegroundColor Green
        Write-Host "📍 Current branch: $branchName" -ForegroundColor Cyan
        Write-Host "🎯 Code state: $commitInfo" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "💡 Your code is now exactly as it was at commit $shortHash" -ForegroundColor DarkGray
        Write-Host "💡 Original branch '$currentBranch' remains unchanged" -ForegroundColor DarkGray
        Write-Host "💡 Use 'git checkout $currentBranch' to return to original state" -ForegroundColor DarkGray

        # Show current status
        Write-Host ""
        Write-Host "📊 Current status:" -ForegroundColor Cyan
        git status --short

    } else {
        Write-Host "❌ Failed to create rollback branch" -ForegroundColor Red
        Write-Host "💡 Check if the commit hash is valid and try again" -ForegroundColor DarkGray
    }
}

# ── git-rb ──────────────────────────────────────────────────────────
# The user-facing name is a shim so that --long flags bind at all: a param() block
# cannot bind them, and worse, misbinds them into the next value parameter. The shim
# must not declare param() of its own, or $args would not hold the whole line.
# See docs/plan/ethos/ETHOS.md.
function git-rb { Invoke-PFParamCommand -Target 'Invoke-GitRollbackTo' -Command 'git-rb' -Argv $args }

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'git-rb'  -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'create a rollback branch from any commit, safely'
Register-PFCommand -Name 'git-rba' -Aliases @('grba') -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'rollback branch add-commit-push'
