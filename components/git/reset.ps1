# ==============================================================================
# PowerFlow — Git Reset and Clean
# ==============================================================================
# Domain   : Git
# File     : components/git/reset.ps1
# Purpose  : Hard reset, clean repo, and deep clean Next.js projects
# Functions: git-f, git-next
# Depends  : none
# ==============================================================================

function git-f {
    $confirm = Read-Host "⚠️  Flush all changes and clean repo? (y/n)"
    if ($confirm -eq 'y') {
        Write-Host "🧹 Flushing..." -ForegroundColor Yellow
        git reset --hard HEAD        # Reset to last commit
        git clean -fdx              # Remove all untracked files and directories
        git fetch --all --prune     # Fetch latest and prune deleted branches
        Write-Host "✅ Repository cleaned and updated" -ForegroundColor Green
    } else {
        Write-Host "❌ Cancelled." -ForegroundColor DarkGray
    }
}

function git-next {
    $confirm = Read-Host "🧼 Deep clean .next + node_modules + lockfile and reinstall? (y/n)"
    if ($confirm -eq 'y') {
        Write-Host "`n🚿 Cleaning..." -ForegroundColor Cyan
        try {
            # Remove build artifacts and dependencies
            Remove-Item -Recurse -Force .next,node_modules,package-lock.json -ErrorAction Stop
            Write-Host "✅ Removed .next, node_modules, and lockfile." -ForegroundColor Green
        } catch {
            Write-Warning "⚠️ Some files may be locked or in use. Try closing editors and rerunning."
        }

        Write-Host "`n📦 Reinstalling dependencies..." -ForegroundColor Cyan
        npm install
        Write-Host "✅ Reinstall complete." -ForegroundColor Green
    } else {
        Write-Host "❌ Cancelled." -ForegroundColor DarkGray
    }
}

# ── pwsh-h registration ───────────────────────────────────────────────────────
Register-PFCommand -Name 'git-f'    -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'fetch and fast-forward the current branch'
Register-PFCommand -Name 'git-next' -Section '🎯 ENHANCED GIT WORKFLOW' -Synopsis 'jump forward one commit (walk history upward)'
