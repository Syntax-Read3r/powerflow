# ==============================================================================
# PowerFlow — Git Release Workflow
# ==============================================================================
# Domain   : Git
# File     : components/git/release.ps1
# Purpose  : Interactive semver bump → settings update → commit → tag → push
#            workflow. Reads the current version from config/PowerFlow.settings.ps1
#            (falls back to latest git tag), lets you pick patch/minor/major/custom
#            via fzf, updates the settings file automatically, then commits,
#            pushes, tags, and pushes the tag — triggering the CI release pipeline.
# Functions: git-release, git-rl
# Depends  : config/PowerFlow.settings.ps1
# ==============================================================================

function git-release {

    # ── Guard: must be in a git repo ─────────────────────────────────────────
    if (-not (git rev-parse --git-dir 2>$null)) {
        Write-Host "❌ Not in a Git repository" -ForegroundColor Red
        return
    }

    $branch   = git rev-parse --abbrev-ref HEAD 2>$null
    $repoRoot = git rev-parse --show-toplevel 2>$null

    # ── Resolve current version ───────────────────────────────────────────────
    # Priority: config/PowerFlow.settings.ps1 → latest git tag → 0.0.0
    $settingsPath   = Join-Path $repoRoot "config\PowerFlow.settings.ps1"
    $currentVersion = $null
    $versionSource  = $null

    if (Test-Path $settingsPath) {
        $raw = Get-Content $settingsPath -Raw
        if ($raw -match '\$script:POWERFLOW_VERSION = "([^"]+)"') {
            $currentVersion = $matches[1]
            $versionSource  = "settings"
        }
    }

    if (-not $currentVersion) {
        $latestTag = git describe --tags --abbrev=0 2>$null
        if ($latestTag -match '^v?(\d+\.\d+\.\d+)$') {
            $currentVersion = $matches[1]
            $versionSource  = "tag"
        }
    }

    if (-not $currentVersion) {
        $currentVersion = "0.0.0"
        $versionSource  = "default"
        Write-Host "⚠️  No existing version found — starting from v0.0.0" -ForegroundColor Yellow
    }

    # ── Parse version parts ───────────────────────────────────────────────────
    if ($currentVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        Write-Host "❌ Cannot parse version '$currentVersion' — expected X.Y.Z" -ForegroundColor Red
        return
    }
    $maj = [int]$matches[1]
    $min = [int]$matches[2]
    $pat = [int]$matches[3]

    $candidates = @{
        patch  = "$maj.$min.$($pat + 1)"
        minor  = "$maj.$($min + 1).0"
        major  = "$($maj + 1).0.0"
    }

    # ── Stage 1: fzf bump-type selector ──────────────────────────────────────
    $sourceLabel = if ($versionSource -eq "settings") { "config/PowerFlow.settings.ps1" }
                   elseif ($versionSource -eq "tag")   { "latest git tag" }
                   else                                { "default (no version found)" }

    $choices = @(
        "patch    v$currentVersion  →  v$($candidates.patch)    bug fixes, dependency updates",
        "minor    v$currentVersion  →  v$($candidates.minor)    new features, non-breaking changes",
        "major    v$currentVersion  →  v$($candidates.major)    breaking changes",
        "custom   enter a specific version number"
    )

    $selected = $choices | fzf `
        --ansi `
        --no-multi `
        --reverse `
        --border=rounded `
        --height=35% `
        --prompt="  Bump type: " `
        --header="🚀 Release Workflow   Current: v$currentVersion ($sourceLabel)   Branch: $branch" `
        --header-first `
        --color="header:bold:magenta,prompt:bold:cyan,border:magenta,pointer:yellow,hl:green" `
        --margin=1 `
        --padding=1

    if (-not $selected) {
        Write-Host "❌ Release cancelled" -ForegroundColor Yellow
        return
    }

    # ── Resolve new version ───────────────────────────────────────────────────
    $newVersion = switch -Regex ($selected) {
        '^patch'  { $candidates.patch }
        '^minor'  { $candidates.minor }
        '^major'  { $candidates.major }
        '^custom' {
            $input = Read-Host "📦 Version (X.Y.Z, without the v)"
            if ($input -notmatch '^\d+\.\d+\.\d+$') {
                Write-Host "❌ Invalid format — use semantic versioning: X.Y.Z" -ForegroundColor Red
                return
            }
            $input
        }
    }

    $newTag = "v$newVersion"

    # ── Guard: tag must not already exist ─────────────────────────────────────
    if (git tag -l $newTag 2>$null) {
        Write-Host "❌ Tag $newTag already exists locally" -ForegroundColor Red
        Write-Host "💡 Run: git tag -d $newTag   to remove it first" -ForegroundColor DarkGray
        return
    }

    # ── Stage 2: fzf release description ─────────────────────────────────────
    $status = git status --short
    $fileLines = if ($status) {
        @($status) | ForEach-Object {
            $code = $_.Substring(0, 2).Trim()
            $file = $_.Substring(3)
            switch ($code) {
                "M"  { "   📝 $file (modified)" }
                "A"  { "   ➕ $file (added)" }
                "D"  { "   🗑  $file (deleted)" }
                "R"  { "   🔄 $file (renamed)" }
                "??" { "   ❓ $file (untracked)" }
                default { "   📄 $file ($code)" }
            }
        }
    } else { @("   (no uncommitted changes — tagging HEAD)") }

    $recentCommits = git log --oneline --color=always -n 5 2>$null
    $commitLines = if ($recentCommits) {
        $arr = @($recentCommits)
        for ($i = 0; $i -lt $arr.Count; $i++) { "   $($i+1). $($arr[$i])" }
    } else { @("   (no commits yet)") }

    $settingsNote = if ($versionSource -eq "settings") {
        "   📄 config/PowerFlow.settings.ps1 will be updated to $newVersion"
    } else { "" }

    $formLines = @(
        "",
        "   🏷️  Tag      :  $newTag",
        "   📦 Version  :  v$currentVersion  →  v$newVersion",
        "   🌿 Branch   :  $branch",
        $settingsNote,
        "",
        "   📋 Files to commit:"
    ) + $fileLines + @(
        "",
        "   📚 Recent commits:"
    ) + $commitLines + @(
        "",
        "   💬 Type your release description above and press Enter"
    )

    $fzfOut = $formLines | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=85% `
        --prompt="  Description: " `
        --header="🚀 Release $newTag — Commit → Push → Tag → Push Tag" `
        --header-first `
        --color="header:bold:magenta,prompt:bold:green,border:magenta,spinner:yellow" `
        --margin=1 `
        --padding=1 `
        --print-query `
        --expect=enter

    $description = if ($fzfOut) { @($fzfOut)[0].Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($description) -or $description.Length -lt 3) {
        Write-Host "❌ Description too short — release cancelled" -ForegroundColor Yellow
        return
    }

    $commitMsg = "vr-commit ($newTag) - $description"

    # ── Update settings.ps1 ───────────────────────────────────────────────────
    if ($versionSource -eq "settings" -and (Test-Path $settingsPath)) {
        Write-Host "📄 Updating POWERFLOW_VERSION to $newVersion..." -ForegroundColor Yellow
        $raw     = Get-Content $settingsPath -Raw
        $updated = $raw -replace '\$script:POWERFLOW_VERSION = "[^"]+"',
                                 "`$script:POWERFLOW_VERSION = `"$newVersion`""
        Set-Content $settingsPath $updated -Encoding UTF8
        Write-Host "✅ v$currentVersion → v$newVersion" -ForegroundColor Green
    }

    # ── git add ───────────────────────────────────────────────────────────────
    Write-Host "📂 Staging changes..." -ForegroundColor Yellow
    git add .
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ git add failed" -ForegroundColor Red; return }
    Write-Host "✅ Files staged" -ForegroundColor Green

    # ── git commit ────────────────────────────────────────────────────────────
    Write-Host "💾 Committing..." -ForegroundColor Yellow
    Write-Host "   $commitMsg" -ForegroundColor DarkGray
    git commit -m $commitMsg
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ git commit failed" -ForegroundColor Red; return }
    Write-Host "✅ Commit created" -ForegroundColor Green

    # ── git push (commit) ─────────────────────────────────────────────────────
    Write-Host "🚀 Pushing commit..." -ForegroundColor Yellow
    $hasUpstream = git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>$null
    if ($hasUpstream) { git push } else { git push -u origin $branch }
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ git push failed" -ForegroundColor Red; return }
    Write-Host "✅ Commit pushed to $branch" -ForegroundColor Green

    # ── git tag ───────────────────────────────────────────────────────────────
    Write-Host "🏷️  Creating tag $newTag..." -ForegroundColor Cyan
    git tag $newTag
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ git tag failed" -ForegroundColor Red
        Write-Host "💡 Run: git tag -d $newTag   then try again" -ForegroundColor DarkGray
        return
    }
    Write-Host "✅ Tag $newTag created" -ForegroundColor Green

    # ── git push tag ──────────────────────────────────────────────────────────
    Write-Host "🚀 Pushing tag $newTag..." -ForegroundColor Cyan
    git push origin $newTag
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to push tag" -ForegroundColor Red
        Write-Host "💡 Run manually: git push origin $newTag" -ForegroundColor DarkGray
        return
    }

    # ── Success ───────────────────────────────────────────────────────────────
    $remoteUrl = git remote get-url origin 2>$null
    $releaseUrl = if ($remoteUrl -match 'github\.com[:/](.+?)(?:\.git)?$') {
        "https://github.com/$($matches[1])/releases/tag/$newTag"
    } else { $null }

    Write-Host ""
    Write-Host "🎉 Release $newTag is live!" -ForegroundColor Magenta
    Write-Host "🔄 GitHub Actions release pipeline triggered" -ForegroundColor Cyan
    if ($releaseUrl) {
        Write-Host "📦 $releaseUrl" -ForegroundColor DarkCyan
    }
    Write-Host ""
}

function git-rl { git-release @args }
