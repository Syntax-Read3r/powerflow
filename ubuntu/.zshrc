# ============================================================================
# PowerFlow - Enhanced zsh Profile for WSL
# ============================================================================
# A beautiful, intelligent zsh profile that supercharges your terminal 
# experience with smart navigation, enhanced Git workflows, and productivity-
# focused tools. zsh equivalent of PowerFlow PowerShell profile.
# 
# Repository: https://github.com/Syntax-Read3r/powerflow
# Documentation: See README.md for complete feature list and usage examples
# Version: 1.0.5
# Release Date: 15-07-2025
# ============================================================================

# Oh My Zsh installation path
export ZSH="$HOME/.oh-my-zsh"

# Theme (will be overridden by Starship)
ZSH_THEME="robbyrussell"

# Plugins
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Override any aliases that Oh My Zsh might have set
unalias ls 2>/dev/null || true

# Version management
export POWERFLOW_VERSION="1.0.5"
export POWERFLOW_REPO="Syntax-Read3r/powerflow"
export CHECK_PROFILE_UPDATES=true
export CHECK_DEPENDENCIES=true
export CHECK_UPDATES=true

# Database credentials configuration (if needed)
export DB_USERNAME="changes"
export DB_PASSWORD="@change"

# PATH setup
export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# Environment
export WSL_START_DIRECTORY="/mnt/c/Users/_munya/Code"
export TERM="xterm-256color"
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1

# zsh configuration
setopt AUTO_CD
setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY
setopt APPEND_HISTORY
export HISTSIZE=10000
export SAVEHIST=10000

# ============================================================================
# CLAUDE CODE
# ============================================================================

cc() {
    # Show help if no arguments provided
    if [[ $# -eq 0 ]]; then
        echo "🤖 Claude Code (cc) - AI Assistant Integration"
        echo "════════════════════════════════════════════"
        echo ""
        echo "Usage: cc [flag] [arguments]"
        echo ""
        echo "Flags:"
        echo "  -e, --explain <file>     Explain what the code does in a file"
        echo "  -f, --fix <problem>      Fix a specific issue or problem"
        echo "  -b, --build <task>       Help build or create something"
        echo "  -r, --review             Review current code for improvements"
        echo "  -h, --help               Show this help message"
        echo ""
        echo "Examples:"
        echo "  cc -e script.js          # Explain what script.js does"
        echo "  cc -f 'syntax error'     # Fix a syntax error"
        echo "  cc -b 'login form'       # Help build a login form"
        echo "  cc -r                    # Review current code"
        echo "  cc 'your question'       # Direct Claude Code interaction"
        echo ""
        return 0
    fi
    
    # Parse flags
    case "$1" in
        -e|--explain)
            if [[ $# -lt 2 ]]; then
                echo "❌ Usage: cc -e <file>"
                echo "💡 Example: cc -e script.js"
                return 1
            fi
            claude "Explain what this code does in $2"
            ;;
        -f|--fix)
            if [[ $# -lt 2 ]]; then
                echo "❌ Usage: cc -f 'describe the problem'"
                echo "💡 Example: cc -f 'syntax error in line 10'"
                return 1
            fi
            claude "Fix this issue: $2"
            ;;
        -b|--build)
            if [[ $# -lt 2 ]]; then
                echo "❌ Usage: cc -b 'describe what to build'"
                echo "💡 Example: cc -b 'user authentication system'"
                return 1
            fi
            claude "Help me build: $2"
            ;;
        -r|--review)
            claude "Review the current code for improvements"
            ;;
        -h|--help)
            cc  # Show help by calling with no args
            ;;
        *)
            # Direct Claude Code interaction
            claude "$@"
            ;;
    esac
}

# ============================================================================
# GIT FUNCTIONS
# ============================================================================

# Enhanced git add with rich preview and confirmation
git-a() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ Not in a Git repository"
        return 1
    fi

    # Check for changes
    local status_output=$(git status --short)
    if [[ -z "$status_output" ]]; then
        echo "✅ No changes to commit - working tree is clean"
        return 0
    fi

    # Get current branch and commit history
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    local commits=$(git log --oneline --color=always -n 2 2>/dev/null)
    
    # If arguments provided, use traditional workflow
    if [[ $# -gt 0 ]]; then
        # Enhanced file status formatting with icons
        echo ""
        echo "🌿 Branch: $branch"
        echo ""
        echo "📚 Recent commit history:"
        
        if [[ -n "$commits" ]]; then
            local commit_number=1
            while IFS= read -r commit; do
                echo "   $commit_number. $commit"
                ((commit_number++))
            done <<< "$commits"
        else
            echo "   (No previous commits)"
        fi
        
        echo ""
        echo "📁 Current file status:"
        
        # Process each status line with proper icons
        while IFS= read -r status_line; do
            local status_code="${status_line:0:2}"
            local file_name="${status_line:3}"
            
            case "${status_code// /}" in
                "M")
                    echo "   📝 $file_name (modified)"
                    ;;
                "A")
                    echo "   ➕ $file_name (added)"
                    ;;
                "D")
                    echo "   🗑️  $file_name (deleted)"
                    ;;
                "R")
                    echo "   🔄 $file_name (renamed)"
                    ;;
                "C")
                    echo "   📋 $file_name (copied)"
                    ;;
                "??")
                    echo "   ❓ $file_name (untracked)"
                    ;;
                "MM")
                    echo "   📝 $file_name (modified, staged and unstaged)"
                    ;;
                "AM")
                    echo "   ➕📝 $file_name (added, then modified)"
                    ;;
                *)
                    echo "   📄 $file_name ($status_code)"
                    ;;
            esac
        done <<< "$status_output"
        
        echo ""
        echo "📋 Will add: $*"
        echo ""
        
        # Perform the add operation
        if git add "$@"; then
            echo "✅ Files added successfully"
            echo ""
            echo "📋 Updated status:"
            git status --short
            echo ""
            echo "💡 Next steps:"
            echo "  git-cm 'message'     → Commit changes"
            echo "  git-s                → View status"
            echo "  git-l                → View log"
        else
            echo "❌ Failed to add files"
            return 1
        fi
        return
    fi
    
    # Interactive workflow with fzf (if available)
    if command -v fzf >/dev/null 2>&1; then
        # Format commits for display
        local commit_lines=()
        if [[ -n "$commits" ]]; then
            local commit_number=1
            while IFS= read -r commit; do
                commit_lines+=("   $commit_number. $commit")
                ((commit_number++))
            done <<< "$commits"
        else
            commit_lines+=("   (No previous commits)")
        fi
        
        # Format file status for display
        local file_lines=()
        while IFS= read -r status_line; do
            local status_code="${status_line:0:2}"
            local file_name="${status_line:3}"
            
            case "${status_code// /}" in
                "M")
                    file_lines+=("   📝 $file_name (modified)")
                    ;;
                "A")
                    file_lines+=("   ➕ $file_name (added)")
                    ;;
                "D")
                    file_lines+=("   🗑️  $file_name (deleted)")
                    ;;
                "R")
                    file_lines+=("   🔄 $file_name (renamed)")
                    ;;
                "C")
                    file_lines+=("   📋 $file_name (copied)")
                    ;;
                "??")
                    file_lines+=("   ❓ $file_name (untracked)")
                    ;;
                "MM")
                    file_lines+=("   📝 $file_name (modified, staged and unstaged)")
                    ;;
                "AM")
                    file_lines+=("   ➕📝 $file_name (added, then modified)")
                    ;;
                *)
                    file_lines+=("   📄 $file_name ($status_code)")
                    ;;
            esac
        done <<< "$status_output"
        
        # Create fzf interface
        local form_lines=(
            ""
            "🌿 Branch: $branch"
            ""
            "📁 Files to be added:"
        )
        form_lines+=("${file_lines[@]}")
        form_lines+=(
            ""
            "📚 Recent commit history:"
        )
        form_lines+=("${commit_lines[@]}")
        form_lines+=(
            ""
            "💬 Type your commit message above and press Enter"
        )
        
        # Launch fzf with commit message input
        local fzf_output
        fzf_output=$(printf "%s\n" "${form_lines[@]}" | fzf \
            --ansi \
            --reverse \
            --border=rounded \
            --height=80% \
            --prompt="📝 Commit Message: " \
            --header="🚀 Git Add → Commit → Push Workflow" \
            --header-first \
            --color="header:bold:blue,prompt:bold:green,border:cyan,spinner:yellow" \
            --margin=1 \
            --padding=1 \
            --print-query \
            --expect=enter)
        
        # Extract the commit message
        local commit_message=""
        if [[ -n "$fzf_output" ]]; then
            commit_message=$(echo "$fzf_output" | head -1 | xargs)
        fi
        
        # Validate commit message
        if [[ -z "$commit_message" || ${#commit_message} -lt 3 ]]; then
            echo "❌ Commit message too short or cancelled"
            return 1
        fi
        
        # Execute the workflow
        echo "📂 Adding all changes..."
        if git add .; then
            echo "✅ Files staged successfully"
            
            echo "💾 Committing changes..."
            if git commit -m "$commit_message"; then
                echo "✅ Commit created successfully"
                
                echo "🚀 Pushing to remote..."
                if git push; then
                    echo "✅ Successfully pushed to '$branch'"
                else
                    echo "❌ git push failed"
                    echo "💡 You may need to set upstream or resolve conflicts"
                fi
            else
                echo "❌ git commit failed"
                return 1
            fi
        else
            echo "❌ git add failed"
            return 1
        fi
    else
        # Fallback to traditional workflow
        echo "📝 Usage: git-a <files> or git-a . (for all)"
        echo "Examples:"
        echo "  git-a .              → Add all changes"
        echo "  git-a file.txt       → Add specific file"
        echo "  git-a *.js           → Add all JS files"
        echo ""
        echo "💡 Install fzf for interactive workflow: sudo apt install fzf"
        return 1
    fi
}

# Git add all with enhanced preview
git-aa() {
    echo "📋 Current unstaged changes:"
    git status --short
    echo ""
    echo -n "🤔 Add all changes? (y/n): "
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        git add .
        echo "✅ All changes added"
        git status --short
    else
        echo "❌ Operation cancelled"
    fi
}

# Git commit with message
git-cm() {
    if [[ $# -eq 0 ]]; then
        echo "💬 Usage: git-cm 'your commit message'"
        return 1
    fi
    
    local message="$1"
    echo "💾 Committing with message: '$message'"
    git commit -m "$message"
}

# Git status (short format)
git-s() {
    git status --short --branch
}

alias git-st=git-s

# Git log (pretty format)
git-l() {
    git log --oneline --graph --decorate -10
}

git-log() {
    git log --oneline --graph --decorate --all
}

# Git branch operations
git-b() {
    if [[ $# -eq 0 ]]; then
        git branch -a
    else
        git checkout -b "$1"
        echo "🌱 Created and switched to branch: $1"
    fi
}

git-branch() {
    git branch -a
}

# Git push
git-p() {
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ -n "$current_branch" ]]; then
        echo "🚀 Pushing branch: $current_branch"
        git push origin "$current_branch"
    else
        echo "❌ Not in a git repository"
        return 1
    fi
}

# Git pull
git-pull() {
    echo "⬇️  Pulling latest changes..."
    git pull
}

# Git stash operations
git-stash() {
    if [[ $# -eq 0 ]]; then
        git stash list
    else
        case "$1" in
            save)
                shift
                git stash push -m "$*"
                ;;
            pop)
                git stash pop
                ;;
            apply)
                git stash apply
                ;;
            list)
                git stash list
                ;;
            *)
                git stash "$@"
                ;;
        esac
    fi
}

alias git-sh=git-stash

# Git remote
git-remote() {
    if [[ $# -eq 0 ]]; then
        git remote -v
    else
        git remote "$@"
    fi
}

alias git-r=git-remote

# Git flush - nuclear reset and clean
git-f() {
    echo "⚠️  This will:"
    echo "   • Reset to HEAD (lose all uncommitted changes)"
    echo "   • Remove all untracked files and directories"  
    echo "   • Fetch latest and prune deleted branches"
    echo ""
    
    echo -n "⚠️  Flush all changes and clean repo? (y/n): "
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "🧹 Flushing..."
        git reset --hard HEAD        # Reset to last commit
        git clean -fdx              # Remove all untracked files and directories
        git fetch --all --prune     # Fetch latest and prune deleted branches
        echo "✅ Repository cleaned and updated"
    else
        echo "❌ Cancelled."
    fi
}

# Enhanced git branch management
git-branch() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ Not in a Git repository"
        return 1
    fi

    # Get current branch
    local current_branch=$(git branch --show-current)
    
    # Get main branch name (main or master)
    local main_branch
    if git show-ref --verify --quiet refs/heads/main; then
        main_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        main_branch="master"
    else
        main_branch="main"  # Default fallback
    fi
    
    echo ""
    echo "🌿 Git Branch Information"
    echo "═════════════════════════"
    echo "📍 Current branch: $current_branch"
    echo "🏠 Main branch: $main_branch"
    echo ""
    echo "🌳 All branches:"
    git branch -a --color=always
}

# Git rollback to specific commit
git-rb() {
    if [[ $# -eq 0 ]]; then
        echo "❌ Usage: git-rb <commit-hash>"
        echo "Example: git-rb abc123"
        return 1
    fi
    
    local commit_hash="$1"
    local force_flag=false
    
    # Check for force flag
    if [[ $# -gt 1 && "$2" == "--force" ]]; then
        force_flag=true
    fi
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ Not in a Git repository"
        return 1
    fi
    
    # Validate commit hash
    local full_hash=$(git rev-parse "$commit_hash" 2>/dev/null)
    if [[ -z "$full_hash" ]]; then
        echo "❌ Invalid commit hash: $commit_hash"
        return 1
    fi
    
    # Get short hash and create branch name
    local short_hash=$(git rev-parse --short "$commit_hash")
    local last3_chars="${short_hash: -3}"
    local branch_name="rollback-$last3_chars"
    
    # Get commit info and current branch
    local commit_info=$(git log --oneline -n 1 "$commit_hash")
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Safety confirmation (unless forced)
    if [[ "$force_flag" != "true" ]]; then
        echo ""
        echo "🔄 Git Rollback Operation"
        echo "═══════════════════════════"
        echo "📍 Current branch: $current_branch"
        echo "🎯 Target commit: $commit_info"
        echo "🌿 New branch: $branch_name"
        echo ""
        echo "⚠️  This will:"
        echo "   • Create new branch '$branch_name'"
        echo "   • Switch to that branch"
        echo "   • Reset ALL code to match commit $short_hash"
        echo ""
        
        echo -n "Continue with rollback? (y/n): "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "❌ Rollback cancelled"
            return 0
        fi
    fi
    
    # Perform rollback
    echo ""
    echo "🔄 Creating rollback branch..."
    
    # Create and switch to new branch
    if git checkout -b "$branch_name"; then
        echo "✅ Created and switched to branch: $branch_name"
        
        # Reset to target commit
        echo "🔄 Resetting to commit: $short_hash"
        if git reset --hard "$commit_hash"; then
            echo "✅ Successfully rolled back to: $commit_info"
            echo ""
            echo "💡 Next steps:"
            echo "  git-s                → View current status"
            echo "  git-rba              → Add changes and create rollback PR"
            echo "  git push origin $branch_name  → Push rollback branch"
        else
            echo "❌ Failed to reset to commit"
            return 1
        fi
    else
        echo "❌ Failed to create rollback branch"
        return 1
    fi
}

# Git rollback add - for rollback branches
git-rba() {
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ Not in a Git repository"
        return 1
    fi

    # Get current branch name
    local current_branch=$(git branch --show-current)
    
    # Check if current branch matches rollback-<alphanumeric> pattern
    if [[ ! "$current_branch" =~ ^rollback-[a-zA-Z0-9]+$ ]]; then
        echo "❌ Error: Not on a rollback branch"
        echo "Current branch: $current_branch"
        echo "Expected pattern: rollback-<alphanumeric> (e.g., rollback-781, rollback-a27, rollback-fix123)"
        return 1
    fi

    echo "🔄 Working on rollback branch: $current_branch"

    # Check for changes
    local status_output=$(git status --short)
    if [[ -z "$status_output" ]]; then
        echo "ℹ️  No changes to commit, working tree clean"
        echo "🚀 Pushing existing commits to origin..."
        git push origin "$current_branch"
        
        # Show GitHub PR creation link
        local repo_url=$(git config --get remote.origin.url)
        if [[ "$repo_url" == *"github.com"* ]]; then
            local repo_path=$(echo "$repo_url" | sed -E 's/.*github\.com[:/](.+?)(\.git)?/?$/\1/')
            echo ""
            echo "🔗 Create a pull request by visiting:"
            echo "   https://github.com/$repo_path/pull/new/$current_branch"
        fi
        echo "✅ Rollback branch operations completed!"
        return 0
    fi

    # Get commit history for current rollback branch
    local commits=$(git log --oneline --color=always -n 2 "$current_branch" 2>/dev/null)
    
    echo ""
    echo "🌿 Branch: $current_branch"
    echo ""
    echo "📚 Recent rollback commits:"
    
    if [[ -n "$commits" ]]; then
        local commit_number=1
        while IFS= read -r commit; do
            echo "   $commit_number. $commit"
            ((commit_number++))
        done <<< "$commits"
    else
        echo "   (No commits yet)"
    fi
    
    echo ""
    echo "📁 Current changes to add:"
    
    # Enhanced file status formatting
    while IFS= read -r status_line; do
        local status_code="${status_line:0:2}"
        local file_name="${status_line:3}"
        
        case "${status_code// /}" in
            "M")
                echo "   📝 $file_name (modified)"
                ;;
            "A")
                echo "   ➕ $file_name (added)"
                ;;
            "D")
                echo "   🗑️  $file_name (deleted)"
                ;;
            "??")
                echo "   ❓ $file_name (untracked)"
                ;;
            *)
                echo "   📄 $file_name ($status_code)"
                ;;
        esac
    done <<< "$status_output"
    
    echo ""
    echo -n "📋 Add all changes to rollback? (y/n): "
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo "📋 Adding all changes..."
        git add .
        
        echo "💬 Enter rollback commit message (or press Enter for default):"
        read -r commit_msg
        if [[ -z "$commit_msg" ]]; then
            commit_msg="Rollback changes for branch $current_branch"
        fi
        
        echo "💾 Committing changes..."
        if git commit -m "$commit_msg"; then
            echo "✅ Changes committed successfully"
            echo ""
            echo "🚀 Pushing to origin..."
            if git push origin "$current_branch"; then
                # Show GitHub PR creation link
                local repo_url=$(git config --get remote.origin.url)
                if [[ "$repo_url" == *"github.com"* ]]; then
                    local repo_path=$(echo "$repo_url" | sed -E 's/.*github\.com[:/](.+?)(\.git)?/?$/\1/')
                    echo ""
                    echo "🔗 Create a pull request by visiting:"
                    echo "   https://github.com/$repo_path/pull/new/$current_branch"
                fi
                echo "✅ Rollback branch operations completed!"
            else
                echo "❌ Failed to push changes"
                return 1
            fi
        else
            echo "❌ Failed to commit changes"
            return 1
        fi
    else
        echo "❌ Operation cancelled"
    fi
}

# Git branch delete (safe)
git-bd() {
    if [[ $# -eq 0 ]]; then
        echo "❌ Usage: git-bd <branch-name>"
        return 1
    fi
    
    local branch_name="$1"
    local current_branch=$(git branch --show-current)
    
    # Prevent deleting current branch
    if [[ "$branch_name" == "$current_branch" ]]; then
        echo "❌ Cannot delete current branch: $branch_name"
        echo "💡 Switch to another branch first"
        return 1
    fi
    
    echo "🗑️  Deleting branch: $branch_name"
    if git branch -d "$branch_name"; then
        echo "✅ Branch deleted successfully"
    else
        echo "❌ Failed to delete branch (try git-bD for force delete)"
        return 1
    fi
}

# Git branch delete (force)
git-bD() {
    if [[ $# -eq 0 ]]; then
        echo "❌ Usage: git-bD <branch-name>"
        return 1
    fi
    
    local branch_name="$1"
    local current_branch=$(git branch --show-current)
    
    # Prevent deleting current branch
    if [[ "$branch_name" == "$current_branch" ]]; then
        echo "❌ Cannot delete current branch: $branch_name"
        echo "💡 Switch to another branch first"
        return 1
    fi
    
    echo "⚠️  Force deleting branch: $branch_name"
    echo -n "Continue with force delete? (y/n): "
    read -r confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        if git branch -D "$branch_name"; then
            echo "✅ Branch force deleted successfully"
        else
            echo "❌ Failed to force delete branch"
            return 1
        fi
    else
        echo "❌ Force delete cancelled"
    fi
}

# ============================================================================
# NAVIGATION
# ============================================================================

nav() {
    local cmd="$1"
    local param="$2"

    if [[ -z "$cmd" ]]; then
        echo "Usage: nav <project> | nav b <bookmark>"
        echo "Examples:"
        echo "  nav powerflow     → Search for project containing 'powerflow'"
        echo "  nav b code        → Go to 'code' bookmark"
        echo "  nav list          → List bookmarks"
        return
    fi

    case "$cmd" in
        b|bookmark)
            # Bookmark navigation
            if [[ -z "$param" ]]; then
                echo "📖 Available bookmarks:"
                if [[ -f "$HOME/.wsl_bookmarks.json" ]] && command -v jq >/dev/null 2>&1; then
                    jq -r 'to_entries[] | "  \(.key) → \(.value)"' "$HOME/.wsl_bookmarks.json"
                else
                    echo "  code → /mnt/c/Users/_munya/Code"
                    echo "  docs → /mnt/c/Users/_munya/Documents"
                    echo "  home → $HOME"
                fi
                return
            fi
            
            # Try to navigate to bookmark
            if [[ -f "$HOME/.wsl_bookmarks.json" ]] && command -v jq >/dev/null 2>&1; then
                local bookmark_path=$(jq -r --arg name "$param" '.[$name] // empty' "$HOME/.wsl_bookmarks.json" 2>/dev/null)
                if [[ -n "$bookmark_path" && -d "$bookmark_path" ]]; then
                    cd "$bookmark_path"
                    echo "📖 → $(basename "$bookmark_path")"
                    return
                fi
            fi
            
            # Fallback to hardcoded bookmarks
            case "$param" in
                code)
                    cd /mnt/c/Users/_munya/Code
                    echo "📖 → Code"
                    ;;
                docs)
                    cd /mnt/c/Users/_munya/Documents
                    echo "📖 → Documents"
                    ;;
                home)
                    cd "$HOME"
                    echo "📖 → Home"
                    ;;
                *)
                    echo "❌ Bookmark not found: $param"
                    ;;
            esac
            ;;
            
        list|l)
            # List bookmarks
            if [[ -f "$HOME/.wsl_bookmarks.json" ]] && command -v jq >/dev/null 2>&1; then
                echo "📖 Available bookmarks:"
                jq -r 'to_entries[] | "  \(.key) → \(.value)"' "$HOME/.wsl_bookmarks.json"
            else
                echo "📖 Default bookmarks:"
                echo "  code → /mnt/c/Users/_munya/Code"
                echo "  docs → /mnt/c/Users/_munya/Documents"
                echo "  home → $HOME"
            fi
            ;;
            
        *)
            # Project navigation with smart search
            
            # First, try exact directory match
            if [[ -d "$cmd" ]]; then
                cd "$cmd"
                echo "📁 → $cmd"
                return
            fi
            
            # Search in code directory with multiple strategies
            local search_base="/mnt/c/Users/_munya/Code"
            if [[ ! -d "$search_base" ]]; then
                echo "❌ Code directory not found: $search_base"
                return 1
            fi
            
            # Strategy 1: Exact name match (case insensitive)
            local exact_matches=($(find "$search_base" -maxdepth 4 -type d -iname "$cmd" 2>/dev/null))
            if [[ ${#exact_matches[@]} -gt 0 ]]; then
                cd "${exact_matches[0]}"
                echo "🎯 → $(basename "${exact_matches[0]}")"
                if [[ ${#exact_matches[@]} -gt 1 ]]; then
                    echo "💡 Found ${#exact_matches[@]} matches, selected first one"
                fi
                return
            fi
            
            # Strategy 2: Fuzzy search - contains the search term
            local fuzzy_matches=($(find "$search_base" -maxdepth 4 -type d -iname "*$cmd*" 2>/dev/null))
            if [[ ${#fuzzy_matches[@]} -gt 0 ]]; then
                # Prefer shorter paths (likely more relevant)
                local best_match="${fuzzy_matches[0]}"
                for match in "${fuzzy_matches[@]}"; do
                    if [[ ${#$(basename "$match")} -lt ${#$(basename "$best_match")} ]]; then
                        best_match="$match"
                    fi
                done
                
                cd "$best_match"
                echo "🎯 Found similar project: $(basename "$best_match")"
                local relative_path="${best_match#$search_base/}"
                if [[ "$relative_path" != "$(basename "$best_match")" ]]; then
                    echo "📍 Location: $relative_path"
                fi
                echo "💡 Searched for: $cmd"
                
                if [[ ${#fuzzy_matches[@]} -gt 1 ]]; then
                    echo "📝 Other matches found: ${#fuzzy_matches[@]} total"
                fi
                return
            fi
            
            # Strategy 3: Partial word match (for abbreviations)
            local partial_matches=($(find "$search_base" -maxdepth 4 -type d 2>/dev/null | grep -i "$cmd"))
            if [[ ${#partial_matches[@]} -gt 0 ]]; then
                cd "${partial_matches[0]}"
                echo "🎯 Found partial match: $(basename "${partial_matches[0]}")"
                echo "💡 Searched for: $cmd"
                return
            fi
            
            # No matches found
            echo "❌ Not found: $cmd"
            echo "💡 Try:"
            echo "  nav list          → See available bookmarks"
            echo "  nav b code        → Go to code directory"
            echo "  nav <partial>     → Search will find partial matches"
            ;;
    esac
}

# ============================================================================
# UTILITIES
# ============================================================================

# Directory navigation shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Screen management
alias clr='clear'

# Enhanced directory info
here() {
    local location=$(pwd)
    echo "📍 $(basename "$location")"

    if git rev-parse --git-dir >/dev/null 2>&1; then
        echo "🌳 $(git rev-parse --abbrev-ref HEAD)"
        local git_changes=$(git status --porcelain 2>/dev/null | wc -l)
        if [[ $git_changes -gt 0 ]]; then
            echo "📝 $git_changes changes"
        fi
    fi

    [[ -f "package.json" ]] && echo "📦 Node.js"
    [[ -f "requirements.txt" ]] && echo "🐍 Python"
    [[ -f "Cargo.toml" ]] && echo "🦀 Rust"
    [[ -f "go.mod" ]] && echo "🐹 Go"
    [[ -f "composer.json" ]] && echo "🐘 PHP"
    [[ -f ".env" ]] && echo "⚙️  Environment"
}

# File operations
copy-pwd() {
    local path=$(pwd)
    if command -v xclip >/dev/null 2>&1; then
        echo -n "$path" | xclip -selection clipboard
        echo "📋 Copied: $path"
    elif command -v clip.exe >/dev/null 2>&1; then
        echo -n "$path" | clip.exe
        echo "📋 Copied: $path"
    else
        echo "📋 $path"
    fi
}

copy-file() {
    if [[ $# -eq 0 ]]; then
        echo "📝 Usage: copy-file <filename>"
        return 1
    fi
    
    if [[ -f "$1" ]]; then
        if command -v xclip >/dev/null 2>&1; then
            cat "$1" | xclip -selection clipboard
            echo "📋 Copied contents of $1"
        elif command -v clip.exe >/dev/null 2>&1; then
            cat "$1" | clip.exe
            echo "📋 Copied contents of $1"
        else
            echo "❌ No clipboard utility available"
        fi
    else
        echo "❌ File not found: $1"
    fi
}

alias cf=copy-file

# Paste file from clipboard
paste-file() {
    local force_flag=false
    local target_path=$(pwd)
    
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            "--force"|"-f")
                force_flag=true
                ;;
            *)
                if [[ -d "$arg" ]]; then
                    target_path="$arg"
                fi
                ;;
        esac
    done
    
    # Check if we have clipboard content (using xclip)
    local clipboard_content
    if command -v xclip >/dev/null 2>&1; then
        clipboard_content=$(xclip -selection clipboard -o 2>/dev/null)
    else
        echo "❌ No clipboard utility available"
        return 1
    fi
    
    # Check if clipboard contains file path with FILE: prefix
    if [[ "$clipboard_content" != FILE:* ]]; then
        echo "❌ No file found in clipboard"
        echo "💡 Use 'copy-file <filename>' to copy a file first"
        return 1
    fi
    
    # Extract file path (remove 'FILE:' prefix)
    local source_file="${clipboard_content#FILE:}"
    
    if [[ ! -f "$source_file" ]]; then
        echo "❌ Source file no longer exists: $source_file"
        return 1
    fi
    
    # Ensure destination directory exists
    if [[ ! -d "$target_path" ]]; then
        echo "❌ Destination directory not found: $target_path"
        return 1
    fi
    
    local file_name=$(basename "$source_file")
    local destination_path="$target_path/$file_name"
    
    # Check if file already exists
    if [[ -f "$destination_path" && "$force_flag" != "true" ]]; then
        echo "⚠️  File already exists: $file_name"
        echo -n "Overwrite? (y/n): "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "❌ Paste cancelled"
            return 0
        fi
    fi
    
    # Copy the file
    if cp "$source_file" "$destination_path"; then
        echo "✅ File pasted: $file_name"
        echo "📁 Location: $destination_path"
    else
        echo "❌ Failed to paste file"
        return 1
    fi
}

alias pf=paste-file

# Open current directory
open-pwd() {
    if command -v explorer.exe >/dev/null 2>&1; then
        local windows_path=$(wslpath -w "$(pwd)" 2>/dev/null)
        if [[ -n "$windows_path" ]]; then
            explorer.exe "$windows_path"
            echo "📁 Opened"
        fi
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open .
        echo "📁 Opened"
    fi
}

alias op=open-pwd

# Enhanced ls with colors and formatting
ls() {
    if command -v lsd >/dev/null 2>&1; then
        lsd "$@"
    elif command -v exa >/dev/null 2>&1; then
        exa --color=always --group-directories-first "$@"
    else
        command ls --color=auto "$@"
    fi
}

alias la='ls -la'
alias ll='ls -l'

# File creation and manipulation
touch() {
    if [[ $# -eq 0 ]]; then
        echo "📝 Usage: touch <filename>"
        return 1
    fi
    
    for file in "$@"; do
        if [[ -f "$file" ]]; then
            command touch "$file"
            echo "⏰ Updated: $file"
        else
            command touch "$file"
            echo "📄 Created: $file"
        fi
    done
}

mkdir() {
    if [[ $# -eq 0 ]]; then
        echo "📁 Usage: mkdir <directory>"
        return 1
    fi
    
    command mkdir -p "$@"
    echo "📁 Created: $*"
}

# Enhanced which command
which() {
    if [[ $# -eq 0 ]]; then
        echo "🔍 Usage: which <command>"
        return 1
    fi
    
    local result=$(command -v "$1")
    if [[ -n "$result" ]]; then
        echo "📍 $1 → $result"
        if [[ -f "$result" ]]; then
            ls -la "$result"
        fi
    else
        echo "❌ Command not found: $1"
    fi
}

# Process and system information
back() {
    if [[ $# -eq 0 ]]; then
        cd -
    else
        for ((i=1; i<=$1; i++)); do
            cd ..
        done
    fi
    echo "📍 $(basename "$(pwd)")"
}

# Enhanced move operations (cut and paste for files)
MOVE_IN_HAND=""
MOVE_SOURCE_DIR=""

mv() {
    # If no arguments, show current status and help
    if [[ $# -eq 0 ]]; then
        if [[ -n "$MOVE_IN_HAND" ]]; then
            echo "📦 Currently holding: $MOVE_IN_HAND"
            echo "💡 Use 'mv-t' to paste in current directory"
            echo "💡 Use 'mv <newfile>' to drop current and hold new file"
            echo "💡 Use 'mv-c' to cancel and drop current file"
        else
            echo "💡 Enhanced Move Commands:"
            echo "═════════════════════════"
            echo "  mv <filename>        Cut file for moving (smart search)"
            echo "  mv-t                 Paste held file in current directory"
            echo "  mv-c                 Cancel move operation (drop held file)"
        fi
        return
    fi
    
    local file_name="$1"
    
    # Smart file search
    local found_file=""
    
    # Try exact match first
    if [[ -f "$file_name" ]]; then
        found_file="$file_name"
    else
        # Try fuzzy search in current directory
        local matches=($(find . -maxdepth 1 -type f -iname "*$file_name*" 2>/dev/null))
        if [[ ${#matches[@]} -eq 1 ]]; then
            found_file="${matches[0]}"
        elif [[ ${#matches[@]} -gt 1 ]]; then
            echo "📁 Multiple files found:"
            for match in "${matches[@]}"; do
                echo "   📄 $(basename "$match")"
            done
            echo "💡 Be more specific with the filename"
            return 1
        else
            echo "❌ File not found: $file_name"
            return 1
        fi
    fi
    
    # If we had a previous file in hand, drop it
    if [[ -n "$MOVE_IN_HAND" ]]; then
        echo "🗑️  Dropped previous file: $MOVE_IN_HAND"
    fi
    
    # Hold the new file
    MOVE_IN_HAND="$(basename "$found_file")"
    MOVE_SOURCE_DIR="$(dirname "$(realpath "$found_file")")"
    
    echo "✂️  Cut file for moving: $MOVE_IN_HAND"
    echo "📁 Source: $MOVE_SOURCE_DIR"
    echo "💡 Use 'mv-t' to paste in target directory"
}

mv-t() {
    if [[ -z "$MOVE_IN_HAND" ]]; then
        echo "❌ No file currently held for moving"
        echo "💡 Use 'mv <filename>' first to cut a file for moving"
        return 1
    fi
    
    local source_file="$MOVE_SOURCE_DIR/$MOVE_IN_HAND"
    local current_dir=$(pwd)
    
    # Check if source file still exists
    if [[ ! -f "$source_file" ]]; then
        echo "❌ Source file no longer exists: $MOVE_IN_HAND"
        echo "📁 Expected location: $source_file"
        MOVE_IN_HAND=""
        MOVE_SOURCE_DIR=""
        return 1
    fi
    
    # Check if we're trying to move to the same directory
    if [[ "$MOVE_SOURCE_DIR" == "$current_dir" ]]; then
        echo "⚠️  Source and destination are the same directory"
        echo "📁 Directory: $current_dir"
        echo "💡 Navigate to a different directory first"
        return 1
    fi
    
    # Check if file already exists in destination
    local destination_path="$current_dir/$MOVE_IN_HAND"
    if [[ -f "$destination_path" ]]; then
        echo "⚠️  File already exists in destination: $MOVE_IN_HAND"
        echo -n "Overwrite? (y/n): "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "❌ Move cancelled"
            return 0
        fi
    fi
    
    # Perform the move
    echo "📦 Moving file..."
    if command mv "$source_file" "$destination_path"; then
        echo "✅ File moved successfully: $MOVE_IN_HAND"
        echo "📁 From: $MOVE_SOURCE_DIR"
        echo "📁 To: $current_dir"
        
        # Clear the move queue
        MOVE_IN_HAND=""
        MOVE_SOURCE_DIR=""
    else
        echo "❌ Failed to move file"
        return 1
    fi
}

mv-c() {
    if [[ -z "$MOVE_IN_HAND" ]]; then
        echo "ℹ️  No file currently held for moving"
        return 0
    fi
    
    echo "🗑️  Dropped file from move queue: $MOVE_IN_HAND"
    MOVE_IN_HAND=""
    MOVE_SOURCE_DIR=""
    echo "✅ Move operation cancelled"
}

# Enhanced rename function
rn() {
    if [[ $# -eq 0 ]]; then
        echo "📝 Usage: rn <current-name> [new-name]"
        echo "Examples:"
        echo "  rn oldfile.txt newfile.txt   → Rename file directly"
        echo "  rn oldfile                   → Interactive rename"
        return 1
    fi
    
    local current_name="$1"
    local new_name="$2"
    
    # Find the file (smart search)
    local found_file=""
    if [[ -f "$current_name" ]]; then
        found_file="$current_name"
    else
        # Try fuzzy search
        local matches=($(find . -maxdepth 1 -type f -iname "*$current_name*" 2>/dev/null))
        if [[ ${#matches[@]} -eq 1 ]]; then
            found_file="${matches[0]}"
        elif [[ ${#matches[@]} -gt 1 ]]; then
            echo "📁 Multiple files found:"
            for match in "${matches[@]}"; do
                echo "   📄 $(basename "$match")"
            done
            echo "💡 Be more specific with the filename"
            return 1
        else
            echo "❌ File not found: $current_name"
            return 1
        fi
    fi
    
    local old_name=$(basename "$found_file")
    
    # If no new name provided, prompt for it
    if [[ -z "$new_name" ]]; then
        echo "📝 Renaming: $old_name"
        echo -n "New name: "
        read -r new_name
        if [[ -z "$new_name" ]]; then
            echo "❌ Rename cancelled"
            return 0
        fi
    fi
    
    # Check if new file already exists
    if [[ -f "$new_name" ]]; then
        echo "⚠️  File already exists: $new_name"
        echo -n "Overwrite? (y/n): "
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "❌ Rename cancelled"
            return 0
        fi
    fi
    
    # Perform the rename
    if command mv "$found_file" "$new_name"; then
        echo "✅ File renamed successfully"
        echo "📝 $old_name → $new_name"
    else
        echo "❌ Failed to rename file"
        return 1
    fi
}

# ============================================================================
# WINDOWS TERMINAL
# ============================================================================

next-t() {
    if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^{TAB}')" 2>/dev/null
    else
        echo "Use Ctrl+Tab"
    fi
}

prev-t() {
    if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^+{TAB}')" 2>/dev/null
    else
        echo "Use Ctrl+Shift+Tab"
    fi
}

alias next_tab=next-t

# Send keys to Windows (WSL-specific)
send-keys() {
    if [[ $# -eq 0 ]]; then
        echo "📝 Usage: send-keys <keys>"
        echo "Example: send-keys '^{TAB}' (Ctrl+Tab)"
        return 1
    fi
    
    local keys="$1"
    if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('$keys')" 2>/dev/null
    else
        echo "❌ PowerShell not available"
        return 1
    fi
}

# Open new Windows Terminal tab
open-nt() {
    local shell_type="zsh"
    if [[ $# -gt 0 ]]; then
        shell_type="$1"
    fi
    
    local current_dir=$(pwd)
    
    # Convert WSL path to Windows path if needed
    if [[ "$current_dir" == /mnt/* ]]; then
        current_dir=$(wslpath -w "$current_dir")
    fi
    
    case "$shell_type" in
        "ubuntu"|"u"|"wsl"|"zsh")
            if command -v wt.exe >/dev/null 2>&1; then
                wt.exe new-tab --profile "Ubuntu" --startingDirectory "$current_dir" 2>/dev/null &
                echo "🐧 Opening new Ubuntu tab..."
            else
                echo "❌ Windows Terminal not found"
            fi
            ;;
        "pwsh"|"powershell"|"p")
            if command -v wt.exe >/dev/null 2>&1; then
                wt.exe new-tab --profile "PowerShell" --startingDirectory "$current_dir" 2>/dev/null &
                echo "🔷 Opening new PowerShell tab..."
            else
                echo "❌ Windows Terminal not found"
            fi
            ;;
        "cmd")
            if command -v wt.exe >/dev/null 2>&1; then
                wt.exe new-tab --profile "Command Prompt" --startingDirectory "$current_dir" 2>/dev/null &
                echo "📟 Opening new Command Prompt tab..."
            else
                echo "❌ Windows Terminal not found"
            fi
            ;;
        *)
            echo "❌ Unknown shell type: $shell_type"
            echo "Available: ubuntu, u, wsl, zsh, pwsh, powershell, p, cmd"
            return 1
            ;;
    esac
}

# Open new terminal tab (smart detection)
open-t() {
    if command -v wt.exe >/dev/null 2>&1; then
        open-nt "ubuntu"  # Default to Ubuntu in WSL
    elif command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --tab --working-directory="$(pwd)" &
        echo "📟 Opening new terminal tab..."
    elif command -v konsole >/dev/null 2>&1; then
        konsole --new-tab --workdir "$(pwd)" &
        echo "📟 Opening new terminal tab..."
    else
        echo "❌ No supported terminal found"
        return 1
    fi
}

# Close current terminal
close-t() {
    exit
}

alias close-ct=close-t

# ============================================================================
# PROJECT CREATION
# ============================================================================

create-next() {
    if [[ $# -eq 0 ]]; then
        echo "📦 Usage: create-next <project-name>"
        return 1
    fi
    
    local project_name="$1"
    echo "🚀 Creating Next.js project: $project_name"
    
    npx create-next-app@latest "$project_name" --typescript --tailwind --eslint --app
    
    if [[ $? -eq 0 ]]; then
        cd "$project_name"
        echo "✅ Project created successfully!"
        echo "📍 Current directory: $(pwd)"
        echo "🏃 To start development: npm run dev"
    else
        echo "❌ Failed to create project"
    fi
}

alias create-n=create-next

# ============================================================================
# POWERFLOW FUNCTIONS
# ============================================================================

powerflow-version() {
    echo "🚀 PowerFlow zsh Profile"
    echo "Version: $POWERFLOW_VERSION"
    echo "Repository: https://github.com/$POWERFLOW_REPO"
    echo "Shell: $(zsh --version)"
    echo "Platform: WSL $(uname -r)"
}

powerflow-update() {
    echo "🔄 Updating PowerFlow..."
    local current_dir=$(pwd)
    
    if [[ -d "$HOME/.powerflow" ]]; then
        cd "$HOME/.powerflow"
        git pull origin main
        echo "✅ PowerFlow updated successfully!"
    else
        echo "❌ PowerFlow directory not found. Please reinstall."
    fi
    
    cd "$current_dir"
}

# ============================================================================
# HELP
# ============================================================================

zsh-help() {
    echo ""
    echo "⚡ PowerFlow zsh Profile Commands"
    echo "═══════════════════════════════════"
    echo ""
    echo "🤖 AI Assistant:"
    echo "  cc <prompt>          Direct Claude Code interaction"
    echo "  cc -e <file>         Explain code in file"
    echo "  cc -f 'problem'      Fix specific problem"
    echo "  cc -b 'feature'      Build/create feature"
    echo "  cc -r                Review current code"
    echo "  cc -h                Show Claude Code help"
    echo ""
    echo "🌳 Git Operations:"
    echo "  git-s/git-st         git-a <files>       git-aa"
    echo "  git-cm 'message'     git-l/git-log       git-b [branch]"
    echo "  git-p                git-pull            git-stash/git-sh"
    echo "  git-r/git-remote     git-f (nuclear)     git-branch"
    echo ""
    echo "🔄 Git Advanced:"
    echo "  git-rb <commit>      git-rba             git-bd <branch>"
    echo "  git-bD <branch>      "
    echo ""
    echo "🧭 Navigation:"
    echo "  nav <project>        nav b <bookmark>    .. ... ...."
    echo "  here                 copy-pwd            open-pwd/op"
    echo "  back [levels]        clr (clear)         "
    echo ""
    echo "📁 File Operations:"
    echo "  ls/la/ll            copy-file/cf        paste-file/pf"
    echo "  mv <file>           mv-t                mv-c"
    echo "  rn <old> [new]      touch <file>        mkdir <dir>"
    echo "  which <command>     "
    echo ""
    echo "📖 Bookmarks:"
    echo "  create-bookmark/cb   delete-bookmark/db  list-bookmarks/lb"
    echo ""
    echo "🪟 Windows Terminal:"
    echo "  next-t              prev-t              open-nt [shell]"
    echo "  open-t              close-t/close-ct    send-keys <keys>"
    echo ""
    echo "🚀 Project Creation:"
    echo "  create-next/create-n <name>"
    echo ""
    echo "⚙️  PowerFlow:"
    echo "  powerflow-version   powerflow-update    zsh-help"
    echo ""
    echo "⚡ zsh Features:"
    echo "  • Auto-completion: Tab to complete commands and paths"
    echo "  • Auto-suggestions: Type and see historical suggestions (gray text)"
    echo "  • Syntax highlighting: Commands are colored as you type"
    echo "  • Smart history: Up/Down arrows for command history"
    echo "  • Fuzzy search: Ctrl+R for command history search"
    echo "  • Directory jumping: Type directory name to cd into it"
    echo ""
    echo "💡 Pro Tips:"
    echo "  • Use 'mv file' then 'mv-t' to cut/paste files"
    echo "  • 'git-rb abc123' creates rollback branch from commit"
    echo "  • 'nav powerflow' finds projects with smart search"
    echo "  • zsh auto-suggests based on your history"
    echo ""
}

alias wsl-help=zsh-help
alias help=zsh-help

# Recovery system similar to PowerShell version
powerflow-recovery() {
    echo ""
    echo "🔧 PowerFlow zsh Recovery System"
    echo "═══════════════════════════════════"
    echo ""
    echo "🔄 Quick Recovery Actions:"
    echo "  1. Reload profile: source ~/.zshrc"
    echo "  2. Check dependencies: which starship fzf zoxide lsd git jq"
    echo "  3. Reinstall tools: check_powerflow_dependencies"
    echo ""
    echo "🔧 Advanced Recovery:"
    echo "  4. Reset dependency check: rm ~/.wsl_dependency_check"
    echo "  5. Reinstall PowerFlow: curl -o ~/.zshrc https://raw.githubusercontent.com/$POWERFLOW_REPO/main/ubuntu/.zshrc"
    echo "  6. Edit profile manually: nano ~/.zshrc"
    echo ""
    echo "🆘 Emergency Recovery:"
    echo "  7. Restore from backup: ls ~/.zshrc.backup.* (then cp backup ~/.zshrc)"
    echo "  8. Remove PowerFlow: rm ~/.zshrc && cp ~/.zshrc.backup ~/.zshrc"
    echo ""
    
    echo -n "Choose recovery action (1-8): "
    read -r choice
    
    case $choice in
        1)
            echo "🔄 Reloading zsh profile..."
            source ~/.zshrc
            ;;
        2)
            echo "🔍 Checking dependencies..."
            for tool in starship fzf zoxide lsd git jq; do
                if command -v "$tool" >/dev/null 2>&1; then
                    echo "✅ $tool: $(which "$tool")"
                else
                    echo "❌ $tool: not found"
                fi
            done
            ;;
        3)
            echo "📦 Reinstalling dependencies..."
            rm -f ~/.wsl_dependency_check
            check_powerflow_dependencies
            ;;
        4)
            echo "🔄 Resetting dependency check..."
            rm -f ~/.wsl_dependency_check
            echo "✅ Dependency check reset. Restart terminal to recheck."
            ;;
        5)
            echo "🔄 Reinstalling PowerFlow..."
            curl -o ~/.zshrc "https://raw.githubusercontent.com/$POWERFLOW_REPO/main/ubuntu/.zshrc"
            echo "✅ PowerFlow reinstalled. Run 'source ~/.zshrc' to reload."
            ;;
        6)
            echo "✏️  Opening profile for editing..."
            "${EDITOR:-nano}" ~/.zshrc
            ;;
        7)
            echo "📋 Available backups:"
            ls -la ~/.zshrc.backup.* 2>/dev/null || echo "No backups found"
            ;;
        8)
            echo "🗑️  Removing PowerFlow..."
            if [[ -f ~/.zshrc.backup ]]; then
                cp ~/.zshrc.backup ~/.zshrc
                echo "✅ PowerFlow removed, backup restored"
            else
                echo "❌ No backup found. Manual recovery required."
            fi
            ;;
        *)
            echo "❌ Invalid choice"
            ;;
    esac
}

# Function to check dependency status
check_dependency_status() {
    echo ""
    echo "🔍 PowerFlow Dependency Status"
    echo "═══════════════════════════════"
    echo ""
    
    # Core dependencies
    echo "📦 Core Dependencies:"
    local core_deps=("git" "curl" "wget" "jq" "xclip")
    for tool in "${core_deps[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ✅ $tool: $(which "$tool")"
        else
            echo "  ❌ $tool: not installed"
        fi
    done
    
    echo ""
    echo "🔧 Optional Tools:"
    local optional_deps=("starship" "zoxide" "fzf" "lsd" "tree" "rg")
    for tool in "${optional_deps[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ✅ $tool: $(which "$tool")"
        else
            echo "  ❌ $tool: not installed"
        fi
    done
    
    echo ""
    echo "📊 System Info:"
    echo "  Shell: $SHELL"
    echo "  zsh version: $(zsh --version)"
    echo "  PowerFlow version: $POWERFLOW_VERSION"
    echo "  Oh My Zsh: $([[ -d ~/.oh-my-zsh ]] && echo "installed" || echo "not installed")"
    
    echo ""
    echo "💡 To install missing tools, run: check_powerflow_dependencies"
}

# Add aliases for recovery
alias recovery=powerflow-recovery
alias deps=check_dependency_status

# ============================================================================
# BOOKMARKS SYSTEM
# ============================================================================

BOOKMARKS_FILE="$HOME/.wsl_bookmarks.json"

create-bookmark() {
    if [[ $# -eq 0 ]]; then
        echo "📖 Usage: create-bookmark <name> [path]"
        return 1
    fi
    
    local name="$1"
    local path="$(pwd)"
    if [[ $# -gt 1 ]]; then
        path="$2"
    fi
    
    if [[ ! -d "$path" ]]; then
        echo "❌ Directory not found: $path"
        return 1
    fi
    
    # Create bookmarks file if it doesn't exist
    if [[ ! -f "$BOOKMARKS_FILE" ]]; then
        echo '{}' > "$BOOKMARKS_FILE"
    fi
    
    # Add bookmark using jq if available
    if command -v jq >/dev/null 2>&1; then
        jq --arg name "$name" --arg path "$path" '. + {($name): $path}' "$BOOKMARKS_FILE" > /tmp/bookmarks.tmp
        mv /tmp/bookmarks.tmp "$BOOKMARKS_FILE"
        echo "📖 Bookmark created: $name → $path"
    else
        echo "❌ jq not available. Please install jq for bookmark functionality."
    fi
}

alias cb=create-bookmark

delete-bookmark() {
    if [[ $# -eq 0 ]]; then
        echo "🗑️  Usage: delete-bookmark <name>"
        return 1
    fi
    
    local name="$1"
    
    if [[ ! -f "$BOOKMARKS_FILE" ]]; then
        echo "❌ No bookmarks file found"
        return 1
    fi
    
    if command -v jq >/dev/null 2>&1; then
        jq --arg name "$name" 'del(.[$name])' "$BOOKMARKS_FILE" > /tmp/bookmarks.tmp
        mv /tmp/bookmarks.tmp "$BOOKMARKS_FILE"
        echo "🗑️  Bookmark deleted: $name"
    else
        echo "❌ jq not available. Please install jq for bookmark functionality."
    fi
}

alias db=delete-bookmark

list-bookmarks() {
    if [[ ! -f "$BOOKMARKS_FILE" ]]; then
        echo "📖 No bookmarks found. Create one with: create-bookmark <name>"
        return
    fi
    
    if command -v jq >/dev/null 2>&1; then
        echo "📖 Available bookmarks:"
        jq -r 'to_entries[] | "  \(.key) → \(.value)"' "$BOOKMARKS_FILE"
    else
        echo "❌ jq not available. Please install jq for bookmark functionality."
    fi
}

alias lb=list-bookmarks

# ============================================================================
# DEPENDENCY MANAGEMENT
# ============================================================================

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install a package via apt with user confirmation
install_apt_package() {
    local package="$1"
    local description="$2"
    
    if ! command_exists "$package"; then
        echo "📦 $description ($package) is not installed."
        echo -n "🤔 Install $package? (y/n): "
        read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo "📦 Installing $package..."
            if sudo apt update >/dev/null 2>&1 && sudo apt install -y "$package" >/dev/null 2>&1; then
                echo "✅ $package installed successfully"
                return 0
            else
                echo "❌ Failed to install $package"
                return 1
            fi
        else
            echo "⏭️  Skipping $package installation"
            return 1
        fi
    fi
    return 0
}

# Function to install via curl with user confirmation
install_via_curl() {
    local name="$1"
    local description="$2"
    local install_command="$3"
    
    if ! command_exists "$name"; then
        echo "📦 $description ($name) is not installed."
        echo -n "🤔 Install $name? (y/n): "
        read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            echo "📦 Installing $name..."
            if eval "$install_command" >/dev/null 2>&1; then
                echo "✅ $name installed successfully"
                return 0
            else
                echo "❌ Failed to install $name"
                return 1
            fi
        else
            echo "⏭️  Skipping $name installation"
            return 1
        fi
    fi
    return 0
}

# Function to check and install PowerFlow dependencies
check_powerflow_dependencies() {
    if [[ "$CHECK_DEPENDENCIES" != "true" ]]; then
        return 0
    fi
    
    # Check for dependency check file to avoid daily prompts
    local dep_check_file="$HOME/.wsl_dependency_check"
    local today=$(date +%Y-%m-%d)
    
    if [[ -f "$dep_check_file" ]]; then
        local last_check=$(cat "$dep_check_file" 2>/dev/null || echo "")
        if [[ "$last_check" == "$today" ]]; then
            return 0  # Already checked today
        fi
    fi
    
    # Define critical PowerFlow tools that should be auto-installed
    local critical_tools=()
    local essential_tools=()
    local optional_tools=()
    
    # Critical tools (auto-install without prompt - essential for PowerFlow)
    if ! command_exists "git"; then
        critical_tools+=("git:Git version control system")
    fi
    if ! command_exists "fzf"; then
        critical_tools+=("fzf:Fuzzy finder for interactive workflows")
    fi
    if ! command_exists "zoxide"; then
        critical_tools+=("zoxide:Smart directory navigation")
    fi
    if ! command_exists "lsd"; then
        critical_tools+=("lsd:Modern ls replacement with colors")
    fi
    
    # Essential tools (with user prompt)
    if ! command_exists "curl"; then
        essential_tools+=("curl:Command line HTTP client")
    fi
    if ! command_exists "wget"; then
        essential_tools+=("wget:Command line HTTP client")
    fi
    if ! command_exists "jq"; then
        essential_tools+=("jq:Command line JSON processor")
    fi
    if ! command_exists "xclip"; then
        essential_tools+=("xclip:X11 clipboard utility")
    fi
    
    # Optional tools (with user prompts)
    if ! command_exists "starship"; then
        optional_tools+=("starship:Cross-shell prompt")
    fi
    if ! command_exists "tree"; then
        optional_tools+=("tree:Directory tree visualization")
    fi
    if ! command_exists "rg"; then
        optional_tools+=("ripgrep:Fast grep alternative")
    fi
    
    # Auto-install critical tools if any are missing
    if [[ ${#critical_tools[@]} -gt 0 ]]; then
        echo "🔧 PowerFlow critical tools missing. Auto-installing..."
        
        # Check if we have install-essentials.sh script
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local install_script="$script_dir/install-essentials.sh"
        
        # Try to find install-essentials.sh in common locations
        local possible_locations=(
            "$script_dir/install-essentials.sh"
            "$HOME/.powerflow/install-essentials.sh"
            "$(dirname "$HOME/.zshrc")/install-essentials.sh"
        )
        
        local found_script=""
        for location in "${possible_locations[@]}"; do
            if [[ -f "$location" ]]; then
                found_script="$location"
                break
            fi
        done
        
        if [[ -n "$found_script" ]]; then
            echo "📦 Running PowerFlow essential tools installer..."
            bash "$found_script"
        else
            echo "⚠️  Auto-installing critical tools manually..."
            
            # Manual installation of critical tools
            for tool_info in "${critical_tools[@]}"; do
                local tool_name="${tool_info%%:*}"
                local tool_desc="${tool_info##*:}"
                
                case "$tool_name" in
                    "git")
                        install_apt_package "$tool_name" "$tool_desc"
                        ;;
                    "fzf")
                        if ! install_apt_package "$tool_name" "$tool_desc"; then
                            echo "📦 Installing fzf via git..."
                            git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf 2>/dev/null || true
                            ~/.fzf/install --all --no-bash --no-fish >/dev/null 2>&1 || true
                        fi
                        ;;
                    "zoxide")
                        echo "📦 Installing zoxide..."
                        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash >/dev/null 2>&1 || true
                        ;;
                    "lsd")
                        if ! install_apt_package "$tool_name" "$tool_desc"; then
                            echo "📦 Installing lsd via .deb package..."
                            local lsd_version=$(curl -s "https://api.github.com/repos/Peltoche/lsd/releases/latest" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 2>/dev/null || echo "v0.23.1")
                            local lsd_url="https://github.com/Peltoche/lsd/releases/download/${lsd_version}/lsd_${lsd_version#v}_amd64.deb"
                            curl -sL "$lsd_url" -o /tmp/lsd.deb 2>/dev/null || true
                            sudo dpkg -i /tmp/lsd.deb >/dev/null 2>&1 || true
                            rm -f /tmp/lsd.deb
                        fi
                        ;;
                esac
            done
        fi
        
        echo "✅ Critical tools installation attempt completed"
    fi
    
    # Install missing essential tools with user prompt
    if [[ ${#essential_tools[@]} -gt 0 ]]; then
        echo ""
        echo "🔧 Essential tools for PowerFlow:"
        for tool_info in "${essential_tools[@]}"; do
            local tool_name="${tool_info%%:*}"
            local tool_desc="${tool_info##*:}"
            install_apt_package "$tool_name" "$tool_desc"
        done
    fi
    
    # Offer to install optional tools
    if [[ ${#optional_tools[@]} -gt 0 ]]; then
        echo ""
        echo "🌟 Optional tools for enhanced experience:"
        for tool_info in "${optional_tools[@]}"; do
            local tool_name="${tool_info%%:*}"
            local tool_desc="${tool_info##*:}"
            
            case "$tool_name" in
                "starship")
                    install_via_curl "starship" "$tool_desc" "curl -sS https://starship.rs/install.sh | sh -s -- --yes"
                    ;;
                "tree")
                    install_apt_package "tree" "$tool_desc"
                    ;;
                "ripgrep")
                    install_apt_package "ripgrep" "$tool_desc"
                    ;;
            esac
        done
    fi
    
    # Mark dependency check as completed for today
    echo "$today" > "$dep_check_file"
    
    # Refresh PATH after installations
    export PATH="$HOME/.local/bin:$PATH"
    
    echo "✅ Dependency check completed"
}

# Initialize dependencies on first run
if [[ "$POWERFLOW_LOADED" != "true" ]]; then
    check_powerflow_dependencies
fi

# ============================================================================
# DEPENDENCY INITIALIZATION
# ============================================================================

# Initialize starship prompt (if available)
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# Initialize zoxide (if available)
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
    alias cd=z
fi

# Initialize fzf (if available)
if command -v fzf >/dev/null 2>&1; then
    # FZF key bindings and completion
    if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
        source /usr/share/fzf/key-bindings.zsh
    fi
    if [[ -f /usr/share/fzf/completion.zsh ]]; then
        source /usr/share/fzf/completion.zsh
    fi
fi

# ============================================================================
# STARTUP
# ============================================================================

# Initialize default bookmarks if file doesn't exist
if [[ ! -f "$BOOKMARKS_FILE" ]] && command -v jq >/dev/null 2>&1; then
    cat > "$BOOKMARKS_FILE" << 'EOF'
{
  "code": "/mnt/c/Users/_munya/Code",
  "docs": "/mnt/c/Users/_munya/Documents", 
  "home": "/home/munya"
}
EOF
fi

# Auto-navigate to code directory on startup
if [[ "$(pwd)" == "$HOME" && -d "$WSL_START_DIRECTORY" ]]; then
    cd "$WSL_START_DIRECTORY"
    echo "🚀 PowerFlow zsh Profile loaded!"
    echo "📍 Starting in: $(basename "$(pwd)")"
    echo "💡 Type 'zsh-help' or 'help' for available commands"
fi

# Welcome message for new sessions
if [[ -z "$POWERFLOW_LOADED" ]]; then
    export POWERFLOW_LOADED=true
    echo ""
    echo "⚡ PowerFlow zsh Profile v$POWERFLOW_VERSION"
    echo "🌟 Enhanced shell with intelligent auto-completion and syntax highlighting"
    echo "💡 Type 'help' to see all available commands"
    echo ""
fi