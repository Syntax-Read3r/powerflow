# ==============================================================================
# PowerFlow — Git Remote Repository Creation
# ==============================================================================
# Domain   : Git
# File     : components/git/remote.ps1
# Purpose  : Creates GitHub remote repositories via gh CLI with naming convention selection
# Functions: Create-RemoteRepository
# Depends  : components/shared/strings.ps1
# ==============================================================================

function Create-RemoteRepository {
    # Check if authenticated
    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Not authenticated with GitHub" -ForegroundColor Red
        Write-Host "🔐 Run: gh auth login" -ForegroundColor Cyan
        return $false
    }

    # Get the authenticated user
    $ghUser = gh api user --jq .login 2>$null
    if ($ghUser) {
        Write-Host "🔐 Authenticated as: @$ghUser" -ForegroundColor DarkCyan
    }

    # Ask if user wants to create a remote repository
    $createOptions = @(
        "✅ Yes - Create a GitHub repository and continue pushing",
        "❌ No - Keep this as a local-only repository"
    )

    $createChoice = $createOptions | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=30% `
        --prompt="🤔 Create remote repository? " `
        --header="No GitHub repository found for this project" `
        --header-first `
        --color="header:bold:yellow,prompt:bold:green,border:cyan,pointer:green" `
        --margin=1 `
        --padding=1

    $fzfExit = $LASTEXITCODE
    if (-not $createChoice -and $fzfExit -ne 130) { Write-PFNothingFound 'No option matched what you typed.' }
    if (-not $createChoice -or $createChoice -match "No -") {
        Write-Host "📁 Keeping as local repository" -ForegroundColor Cyan
        return $false
    }

    # Get the current directory name as default repo name
    $defaultRepoName = (Get-Item .).Name

    # First, clean the name of any special characters for processing
    $cleanedName = $defaultRepoName -replace '[^a-zA-Z0-9\s\-_]', ' '
    $cleanedName = $cleanedName -replace '\s+', ' '
    $cleanedName = $cleanedName.Trim()

    # Generate naming convention options
    $kebabName = Convert-ToKebabCase $cleanedName
    $snakeName = Convert-ToSnakeCase $cleanedName
    $pascalName = Convert-ToPascalCase $cleanedName
    $camelName = Convert-ToCamelCase $cleanedName

    # Prepare naming options with descriptions
    $namingOptions = @(
        "🥙 $kebabName`t(kebab-case)",
        "🐍 $snakeName`t(snake_case)",
        "🐪 $pascalName`t(PascalCase)",
        "🐫 $camelName`t(camelCase)",
        "✏️ Type custom name..."
    )

    Write-Host "📁 Current directory: '$defaultRepoName'" -ForegroundColor Cyan
    Write-Host "🎨 Choose a naming convention for your repository:" -ForegroundColor Yellow

    # Ask for repository name using fzf
    $nameChoice = $namingOptions | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=40% `
        --prompt="📝 Select naming style: " `
        --header="Repository Naming Convention" `
        --header-first `
        --color="header:bold:blue,prompt:bold:green,border:cyan,pointer:green" `
        --margin=1 `
        --padding=1

    $fzfExit = $LASTEXITCODE
    if (-not $nameChoice) {
        if ($fzfExit -eq 1) { Write-PFNothingFound 'No naming style matched what you typed.' }
        Write-Host "↩ Repository creation cancelled" -ForegroundColor DarkGray
        return $false
    }

    # Extract the repository name from the choice
    $repoName = ""
    if ($nameChoice -match "Type custom name") {
        # If custom name was selected, prompt for input
        $customPrompt = @(
            "",
            "📁 Current directory: $defaultRepoName",
            "",
            "Type your custom repository name below:"
        )

        $customNameOutput = $customPrompt | fzf `
            --ansi `
            --reverse `
            --border=rounded `
            --height=30% `
            --prompt="📝 Custom name: " `
            --header="Enter Custom Repository Name" `
            --header-first `
            --color="header:bold:blue,prompt:bold:green,border:cyan" `
            --margin=1 `
            --padding=1 `
            --print-query `
            --expect=enter

        $fzfExit = $LASTEXITCODE
        if ($customNameOutput) {
            $lines = @($customNameOutput)
            if ($lines.Count -gt 0 -and $lines[0].Trim()) {
                $repoName = $lines[0].Trim()
            } else {
                Write-Host "❌ No custom name provided" -ForegroundColor Yellow
                return $false
            }
        } else {
            Write-Host "↩ Repository creation cancelled" -ForegroundColor DarkGray
            return $false
        }
    } else {
        # Extract the name from the selected option (before the tab character)
        $repoName = ($nameChoice -split "`t")[0] -replace '^[🥙🐍🐪🐫]\s*', ''
    }

    # Final sanitization for GitHub compatibility
    $repoName = $repoName -replace '[^a-zA-Z0-9._\-]', '-'
    $repoName = $repoName -replace '^[\-._]+|[\-._]+$', ''
    $repoName = $repoName -replace '[\-._]{2,}', '-'

    Write-Host "📌 Final repository name: $repoName" -ForegroundColor Cyan

    # Ask for visibility using fzf
    Write-Host "`n🔐 Choose repository visibility:" -ForegroundColor Cyan

    $visibilityOptions = @(
        "🔒 Private - Only you and collaborators can see this repository",
        "🌍 Public - Anyone can see this repository"
    )

    $visibilityChoice = $visibilityOptions | fzf `
        --ansi `
        --reverse `
        --border=rounded `
        --height=30% `
        --prompt="👁️ Visibility: " `
        --header="Repository Visibility" `
        --header-first `
        --color="header:bold:blue,prompt:bold:green,border:cyan,pointer:green" `
        --margin=1 `
        --padding=1 `
        --bind="enter:accept"

    $fzfExit = $LASTEXITCODE
    if (-not $visibilityChoice) {
        if ($fzfExit -eq 1) { Write-PFNothingFound 'No visibility option matched what you typed.' }
        Write-Host "↩ Repository creation cancelled" -ForegroundColor DarkGray
        return $false
    }

    $visibility = if ($visibilityChoice -match "Private") { "--private" } else { "--public" }
    $visibilityText = if ($visibilityChoice -match "Private") { "Private 🔒" } else { "Public 🌍" }
    Write-Host "✅ Selected: $visibilityText repository" -ForegroundColor Green

    # Create the repository
    Write-Host "🌐 Creating GitHub repository '$repoName'..." -ForegroundColor Cyan

    # First check if we already have a remote (shouldn't happen here, but just in case)
    $existingRemote = git remote get-url origin 2>$null

    if ($existingRemote) {
        Write-Host "⚠️  Remote 'origin' already exists: $existingRemote" -ForegroundColor Yellow
        $overwrite = Read-Host "Do you want to replace it? (y/N)"
        if ($overwrite -ne 'y') {
            return $false
        }
        git remote remove origin
    }

    # Create repo and add remote
    Write-Host "`n🚧 Creating repository..." -ForegroundColor Yellow
    $ghOutput = gh repo create $repoName $visibility --source=. --remote=origin 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Repository '$repoName' created successfully!" -ForegroundColor Green

        # Extract the repository URL from output
        $repoUrl = $ghOutput | Where-Object { $_ -match "https://github.com" } | Select-Object -First 1
        if ($repoUrl) {
            Write-Host "🔗 Repository URL: $repoUrl" -ForegroundColor Cyan
            Write-Host "`n🎉 Your local project is now connected to GitHub!" -ForegroundColor Magenta
        }

        return $true
    } else {
        Write-Host "❌ Failed to create repository" -ForegroundColor Red
        Write-Host "💡 Error: $ghOutput" -ForegroundColor DarkGray

        # Check if repo already exists
        if ($ghOutput -match "already exists") {
            Write-Host "💡 You might want to use a different name or delete the existing repository first" -ForegroundColor Yellow
        }

        return $false
    }
}
