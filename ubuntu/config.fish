# ============================================================================
# PowerFlow - Enhanced Fish Profile for WSL
# ============================================================================
# A beautiful, intelligent Fish profile that supercharges your terminal 
# experience with smart navigation, enhanced Git workflows, and productivity-
# focused tools. Fish equivalent of PowerFlow PowerShell profile.
# 
# Repository: https://github.com/Syntax-Read3r/powerflow
# Documentation: See README.md for complete feature list and usage examples
# Version: 1.0.4
# Release Date: 13-07-2025
# ============================================================================

# Version management
set -g POWERFLOW_VERSION "1.0.4"
set -g POWERFLOW_REPO "Syntax-Read3r/powerflow"
set -g CHECK_PROFILE_UPDATES true
set -g CHECK_DEPENDENCIES true
set -g CHECK_UPDATES true

# Database credentials configuration (if needed)
set -g DB_USERNAME "changes"
set -g DB_PASSWORD "@change"

# Clean startup
set -g fish_greeting ""

# PATH setup
set -gx PATH ~/.npm-global/bin $PATH
set -gx PATH /usr/local/bin $PATH
set -gx PATH $HOME/.local/bin $PATH

# Environment
set -gx WSL_START_DIRECTORY "/mnt/c/Users/_munya/Code"
set -gx TERM xterm-256color
set -gx GIT_DISCOVERY_ACROSS_FILESYSTEM 1

# Fish colors and completion
set -g fish_autosuggestion_enabled 1
set -g fish_color_autosuggestion brblack
set -g fish_color_command blue
set -g fish_color_error red
set -g fish_color_param cyan
set -g fish_color_quote yellow
set -g fish_color_redirection magenta

# Enhanced prompt with Git status
function fish_prompt
    set -l last_status $status
    set -l cwd (basename (pwd))

    set -l branch ""
    set -l git_status ""
    if command git rev-parse --is-inside-work-tree >/dev/null 2>&1
        set branch (command git rev-parse --abbrev-ref HEAD 2>/dev/null)
        set -l git_changes (command git status --porcelain 2>/dev/null | wc -l)
        if test $git_changes -gt 0
            set git_status "*"
        end
        set branch " ($branch$git_status)"
    end

    set -l symbol "❯"
    if test $last_status -ne 0
        set_color red
    else
        set_color green
    end

    echo -n "$cwd$branch $symbol "
    set_color normal
end

# ============================================================================
# CLAUDE CODE
# ============================================================================

function cc
    claude $argv
end

function explain
    if test (count $argv) -eq 0
        echo "Usage: explain <file>"
        return 1
    end
    claude "Explain what this code does in $argv[1]"
end

function fix
    if test (count $argv) -eq 0
        echo "Usage: fix 'describe the problem'"
        return 1
    end
    claude "Fix this issue: $argv[1]"
end

function build
    if test (count $argv) -eq 0
        echo "Usage: build 'describe what to build'"
        return 1
    end
    claude "Help me build: $argv[1]"
end

function review
    claude "Review the current code for improvements"
end

# ============================================================================
# GIT FUNCTIONS
# ============================================================================

# Enhanced git add with rich preview and confirmation (matches PowerShell version)
function git-a
    # Check if we're in a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "❌ Not in a Git repository"
        return 1
    end

    # Check for changes
    set -l status_output (git status --short)
    if test -z "$status_output"
        echo "✅ No changes to commit - working tree is clean"
        return 0
    end

    # Get current branch and commit history
    set -l branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    set -l commits (git log --oneline --color=always -n 2 2>/dev/null)
    
    # Enhanced file status formatting with icons
    echo ""
    echo "🌿 Branch: $branch"
    echo ""
    echo "📚 Recent commit history:"
    
    if test -n "$commits"
        set -l commit_number 1
        for commit in $commits
            echo "   $commit_number. $commit"
            set commit_number (math $commit_number + 1)
        end
    else
        echo "   (No previous commits)"
    end
    
    echo ""
    echo "📁 Current file status:"
    
    # Process each status line with proper icons
    echo "$status_output" | while read -l status_line
        set -l status_code (string sub -l 2 "$status_line")
        set -l file_name (string sub -s 4 "$status_line")
        
        switch (string trim "$status_code")
            case "M"
                echo "   📝 $file_name (modified)"
            case "A"
                echo "   ➕ $file_name (added)"
            case "D"
                echo "   🗑️  $file_name (deleted)"
            case "R"
                echo "   🔄 $file_name (renamed)"
            case "C"
                echo "   📋 $file_name (copied)"
            case "??"
                echo "   ❓ $file_name (untracked)"
            case "MM"
                echo "   📝 $file_name (modified, staged and unstaged)"
            case "AM"
                echo "   ➕📝 $file_name (added, then modified)"
            case "*"
                echo "   📄 $file_name ($status_code)"
        end
    end
    
    echo ""
    
    # Handle different argument patterns
    if test (count $argv) -eq 0
        echo "📝 Usage: git-a <files> or git-a . (for all)"
        echo "Examples:"
        echo "  git-a .              → Add all changes"
        echo "  git-a file.txt       → Add specific file"
        echo "  git-a *.js           → Add all JS files"
        return 1
    end
    
    # Show what will be added
    echo "📋 Will add: $argv"
    echo ""
    
    # Perform the add operation
    if git add $argv
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
    end
end

# Git add all with enhanced preview
function git-aa
    echo "📋 Current unstaged changes:"
    git status --short
    echo ""
    read -P "🤔 Add all changes? (y/n): " confirm
    if test "$confirm" = "y" -o "$confirm" = "Y"
        git add .
        echo "✅ All changes added"
        git status --short
    else
        echo "❌ Operation cancelled"
    end
end

# Git commit with message
function git-cm
    if test (count $argv) -eq 0
        echo "💬 Usage: git-cm 'your commit message'"
        return 1
    end
    
    set -l message $argv[1]
    echo "💾 Committing with message: '$message'"
    git commit -m "$message"
end

# Git status (short format)
function git-s
    git status --short --branch
end

alias git-st git-s

# Git log (pretty format)
function git-l
    git log --oneline --graph --decorate -10
end

function git-log
    git log --oneline --graph --decorate --all
end

# Git branch operations
function git-b
    if test (count $argv) -eq 0
        git branch -a
    else
        git checkout -b $argv[1]
        echo "🌱 Created and switched to branch: $argv[1]"
    end
end

function git-branch
    git branch -a
end

# Git push
function git-p
    set -l current_branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if test -n "$current_branch"
        echo "🚀 Pushing branch: $current_branch"
        git push origin $current_branch
    else
        echo "❌ Not in a git repository"
        return 1
    end
end

# Git pull
function git-pull
    echo "⬇️  Pulling latest changes..."
    git pull
end

# Git stash operations
function git-stash
    if test (count $argv) -eq 0
        git stash list
    else
        switch $argv[1]
            case save
                git stash push -m "$argv[2..-1]"
            case pop
                git stash pop
            case apply
                git stash apply
            case list
                git stash list
            case '*'
                git stash $argv
        end
    end
end

alias git-sh git-stash

# Git remote
function git-remote
    if test (count $argv) -eq 0
        git remote -v
    else
        git remote $argv
    end
end

alias git-r git-remote

# Git flush - nuclear reset and clean
function git-f
    echo "⚠️  This will:"
    echo "   • Reset to HEAD (lose all uncommitted changes)"
    echo "   • Remove all untracked files and directories"  
    echo "   • Fetch latest and prune deleted branches"
    echo ""
    
    read -P "⚠️  Flush all changes and clean repo? (y/n): " confirm
    if test "$confirm" = "y" -o "$confirm" = "Y"
        echo "🧹 Flushing..."
        git reset --hard HEAD        # Reset to last commit
        git clean -fdx              # Remove all untracked files and directories
        git fetch --all --prune     # Fetch latest and prune deleted branches
        echo "✅ Repository cleaned and updated"
    else
        echo "❌ Cancelled."
    end
end

# Enhanced git branch management
function git-branch
    # Check if we're in a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "❌ Not in a Git repository"
        return 1
    end

    # Get current branch
    set -l current_branch (git branch --show-current)
    
    # Get main branch name (main or master)
    set -l main_branch
    if git show-ref --verify --quiet refs/heads/main
        set main_branch "main"
    else if git show-ref --verify --quiet refs/heads/master
        set main_branch "master"
    else
        set main_branch "main"  # Default fallback
    end
    
    echo ""
    echo "🌿 Git Branch Information"
    echo "═════════════════════════"
    echo "📍 Current branch: $current_branch"
    echo "🏠 Main branch: $main_branch"
    echo ""
    echo "🌳 All branches:"
    git branch -a --color=always
end

# Git rollback to specific commit
function git-rb
    if test (count $argv) -eq 0
        echo "❌ Usage: git-rb <commit-hash>"
        echo "Example: git-rb abc123"
        return 1
    end
    
    set -l commit_hash $argv[1]
    set -l force_flag false
    
    # Check for force flag
    if test (count $argv) -gt 1; and test "$argv[2]" = "--force"
        set force_flag true
    end
    
    # Check if we're in a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "❌ Not in a Git repository"
        return 1
    end
    
    # Validate commit hash
    set -l full_hash (git rev-parse $commit_hash 2>/dev/null)
    if test -z "$full_hash"
        echo "❌ Invalid commit hash: $commit_hash"
        return 1
    end
    
    # Get short hash and create branch name
    set -l short_hash (git rev-parse --short $commit_hash)
    set -l last3_chars (string sub -s -2 $short_hash)
    set -l branch_name "rollback-$last3_chars"
    
    # Get commit info and current branch
    set -l commit_info (git log --oneline -n 1 $commit_hash)
    set -l current_branch (git rev-parse --abbrev-ref HEAD)
    
    # Safety confirmation (unless forced)
    if test "$force_flag" != "true"
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
        
        read -P "Continue with rollback? (y/n): " confirm
        if test "$confirm" != "y" -a "$confirm" != "Y"
            echo "❌ Rollback cancelled"
            return 0
        end
    end
    
    # Perform rollback
    echo ""
    echo "🔄 Creating rollback branch..."
    
    # Create and switch to new branch
    if git checkout -b $branch_name
        echo "✅ Created and switched to branch: $branch_name"
        
        # Reset to target commit
        echo "🔄 Resetting to commit: $short_hash"
        if git reset --hard $commit_hash
            echo "✅ Successfully rolled back to: $commit_info"
            echo ""
            echo "💡 Next steps:"
            echo "  git-s                → View current status"
            echo "  git-rba              → Add changes and create rollback PR"
            echo "  git push origin $branch_name  → Push rollback branch"
        else
            echo "❌ Failed to reset to commit"
            return 1
        end
    else
        echo "❌ Failed to create rollback branch"
        return 1
    end
end

# Git rollback add - for rollback branches
function git-rba
    # Check if we're in a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "❌ Not in a Git repository"
        return 1
    end

    # Get current branch name
    set -l current_branch (git branch --show-current)
    
    # Check if current branch matches rollback-<alphanumeric> pattern
    if not string match -q -r '^rollback-[a-zA-Z0-9]+$' $current_branch
        echo "❌ Error: Not on a rollback branch"
        echo "Current branch: $current_branch"
        echo "Expected pattern: rollback-<alphanumeric> (e.g., rollback-781, rollback-a27, rollback-fix123)"
        return 1
    end

    echo "🔄 Working on rollback branch: $current_branch"

    # Check for changes
    set -l status_output (git status --short)
    if test -z "$status_output"
        echo "ℹ️  No changes to commit, working tree clean"
        echo "🚀 Pushing existing commits to origin..."
        git push origin $current_branch
        
        # Show GitHub PR creation link
        set -l repo_url (git config --get remote.origin.url)
        if string match -q "*github.com*" $repo_url
            set -l repo_path (string replace -r '.*github\.com[:/](.+?)(?:\.git)?/?$' '$1' $repo_url)
            echo ""
            echo "🔗 Create a pull request by visiting:"
            echo "   https://github.com/$repo_path/pull/new/$current_branch"
        end
        echo "✅ Rollback branch operations completed!"
        return 0
    end

    # Get commit history for current rollback branch
    set -l commits (git log --oneline --color=always -n 2 $current_branch 2>/dev/null)
    
    echo ""
    echo "🌿 Branch: $current_branch"
    echo ""
    echo "📚 Recent rollback commits:"
    
    if test -n "$commits"
        set -l commit_number 1
        for commit in $commits
            echo "   $commit_number. $commit"
            set commit_number (math $commit_number + 1)
        end
    else
        echo "   (No commits yet)"
    end
    
    echo ""
    echo "📁 Current changes to add:"
    
    # Enhanced file status formatting
    echo "$status_output" | while read -l status_line
        set -l status_code (string sub -l 2 "$status_line")
        set -l file_name (string sub -s 4 "$status_line")
        
        switch (string trim "$status_code")
            case "M"
                echo "   📝 $file_name (modified)"
            case "A"
                echo "   ➕ $file_name (added)"
            case "D"
                echo "   🗑️  $file_name (deleted)"
            case "??"
                echo "   ❓ $file_name (untracked)"
            case "*"
                echo "   📄 $file_name ($status_code)"
        end
    end
    
    echo ""
    read -P "📋 Add all changes to rollback? (y/n): " confirm
    if test "$confirm" = "y" -o "$confirm" = "Y"
        echo "📋 Adding all changes..."
        git add .
        
        echo "💬 Enter rollback commit message (or press Enter for default):"
        read -l commit_msg
        if test -z "$commit_msg"
            set commit_msg "Rollback changes for branch $current_branch"
        end
        
        echo "💾 Committing changes..."
        if git commit -m "$commit_msg"
            echo "✅ Changes committed successfully"
            echo ""
            echo "🚀 Pushing to origin..."
            if git push origin $current_branch
                # Show GitHub PR creation link
                set -l repo_url (git config --get remote.origin.url)
                if string match -q "*github.com*" $repo_url
                    set -l repo_path (string replace -r '.*github\.com[:/](.+?)(?:\.git)?/?$' '$1' $repo_url)
                    echo ""
                    echo "🔗 Create a pull request by visiting:"
                    echo "   https://github.com/$repo_path/pull/new/$current_branch"
                end
                echo "✅ Rollback branch operations completed!"
            else
                echo "❌ Failed to push changes"
                return 1
            end
        else
            echo "❌ Failed to commit changes"
            return 1
        end
    else
        echo "❌ Operation cancelled"
    end
end

# Git branch delete (safe)
function git-bd
    if test (count $argv) -eq 0
        echo "❌ Usage: git-bd <branch-name>"
        return 1
    end
    
    set -l branch_name $argv[1]
    set -l current_branch (git branch --show-current)
    
    # Prevent deleting current branch
    if test "$branch_name" = "$current_branch"
        echo "❌ Cannot delete current branch: $branch_name"
        echo "💡 Switch to another branch first"
        return 1
    end
    
    echo "🗑️  Deleting branch: $branch_name"
    if git branch -d $branch_name
        echo "✅ Branch deleted successfully"
    else
        echo "❌ Failed to delete branch (try git-bD for force delete)"
        return 1
    end
end

# Git branch delete (force)
function git-bD
    if test (count $argv) -eq 0
        echo "❌ Usage: git-bD <branch-name>"
        return 1
    end
    
    set -l branch_name $argv[1]
    set -l current_branch (git branch --show-current)
    
    # Prevent deleting current branch
    if test "$branch_name" = "$current_branch"
        echo "❌ Cannot delete current branch: $branch_name"
        echo "💡 Switch to another branch first"
        return 1
    end
    
    echo "⚠️  Force deleting branch: $branch_name"
    read -P "Continue with force delete? (y/n): " confirm
    if test "$confirm" = "y" -o "$confirm" = "Y"
        if git branch -D $branch_name
            echo "✅ Branch force deleted successfully"
        else
            echo "❌ Failed to force delete branch"
            return 1
        end
    else
        echo "❌ Force delete cancelled"
    end
end

# ============================================================================
# NAVIGATION
# ============================================================================

function nav
    set -l cmd $argv[1]
    set -l param $argv[2]

    if test -z "$cmd"
        echo "Usage: nav <project> | nav b <bookmark>"
        echo "Examples:"
        echo "  nav powerflow     → Search for project containing 'powerflow'"
        echo "  nav b code        → Go to 'code' bookmark"
        echo "  nav list          → List bookmarks"
        return
    end

    switch $cmd
        case b bookmark
            # Bookmark navigation
            if test -z "$param"
                echo "📖 Available bookmarks:"
                if test -f "$HOME/.wsl_bookmarks.json"; and command -v jq >/dev/null 2>&1
                    jq -r 'to_entries[] | "  \(.key) → \(.value)"' "$HOME/.wsl_bookmarks.json"
                else
                    echo "  code → /mnt/c/Users/_munya/Code"
                    echo "  docs → /mnt/c/Users/_munya/Documents"
                    echo "  home → $HOME"
                end
                return
            end
            
            # Try to navigate to bookmark
            if test -f "$HOME/.wsl_bookmarks.json"; and command -v jq >/dev/null 2>&1
                set -l bookmark_path (jq -r --arg name "$param" '.[$name] // empty' "$HOME/.wsl_bookmarks.json" 2>/dev/null)
                if test -n "$bookmark_path"; and test -d "$bookmark_path"
                    cd "$bookmark_path"
                    echo "📖 → "(basename "$bookmark_path")
                    return
                end
            end
            
            # Fallback to hardcoded bookmarks
            switch $param
                case code
                    cd /mnt/c/Users/_munya/Code
                    echo "📖 → Code"
                case docs
                    cd /mnt/c/Users/_munya/Documents
                    echo "📖 → Documents"
                case home
                    cd "$HOME"
                    echo "📖 → Home"
                case '*'
                    echo "❌ Bookmark not found: $param"
            end
            
        case list l
            # List bookmarks
            if test -f "$HOME/.wsl_bookmarks.json"; and command -v jq >/dev/null 2>&1
                echo "📖 Available bookmarks:"
                jq -r 'to_entries[] | "  \(.key) → \(.value)"' "$HOME/.wsl_bookmarks.json"
            else
                echo "📖 Default bookmarks:"
                echo "  code → /mnt/c/Users/_munya/Code"
                echo "  docs → /mnt/c/Users/_munya/Documents"
                echo "  home → $HOME"
            end
            
        case '*'
            # Project navigation with smart search
            
            # First, try exact directory match
            if test -d "$cmd"
                cd "$cmd"
                echo "📁 → $cmd"
                return
            end
            
            # Search in code directory with multiple strategies
            set -l search_base "/mnt/c/Users/_munya/Code"
            if not test -d "$search_base"
                echo "❌ Code directory not found: $search_base"
                return 1
            end
            
            # Strategy 1: Exact name match (case insensitive)
            set -l exact_matches (find "$search_base" -maxdepth 4 -type d -iname "$cmd" 2>/dev/null)
            if test (count $exact_matches) -gt 0
                cd $exact_matches[1]
                echo "🎯 → "(basename $exact_matches[1])
                if test (count $exact_matches) -gt 1
                    echo "💡 Found "(count $exact_matches)" matches, selected first one"
                end
                return
            end
            
            # Strategy 2: Fuzzy search - contains the search term
            set -l fuzzy_matches (find "$search_base" -maxdepth 4 -type d -iname "*$cmd*" 2>/dev/null)
            if test (count $fuzzy_matches) -gt 0
                # Prefer shorter paths (likely more relevant)
                set -l best_match $fuzzy_matches[1]
                for match in $fuzzy_matches
                    if test (string length (basename "$match")) -lt (string length (basename "$best_match"))
                        set best_match $match
                    end
                end
                
                cd "$best_match"
                echo "🎯 Found similar project: "(basename "$best_match")
                set -l relative_path (string replace "$search_base/" "" "$best_match")
                if test "$relative_path" != (basename "$best_match")
                    echo "📍 Location: $relative_path"
                end
                echo "💡 Searched for: $cmd"
                
                if test (count $fuzzy_matches) -gt 1
                    echo "📝 Other matches found: "(count $fuzzy_matches)" total"
                end
                return
            end
            
            # Strategy 3: Partial word match (for abbreviations)
            set -l partial_matches (find "$search_base" -maxdepth 4 -type d 2>/dev/null | grep -i "$cmd")
            if test (count $partial_matches) -gt 0
                cd $partial_matches[1]
                echo "🎯 Found partial match: "(basename $partial_matches[1])
                echo "💡 Searched for: $cmd"
                return
            end
            
            # No matches found
            echo "❌ Not found: $cmd"
            echo "💡 Try:"
            echo "  nav list          → See available bookmarks"
            echo "  nav b code        → Go to code directory"
            echo "  nav <partial>     → Search will find partial matches"
    end
end

# ============================================================================
# UTILITIES
# ============================================================================

# Directory navigation shortcuts
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'

# Screen management
alias clr 'clear'

# Enhanced directory info
function here
    set location (pwd)
    echo "📍 "(basename $location)

    if git rev-parse --git-dir >/dev/null 2>&1
        echo "🌳 "(git rev-parse --abbrev-ref HEAD)
        set -l git_changes (git status --porcelain 2>/dev/null | wc -l)
        if test $git_changes -gt 0
            echo "📝 $git_changes changes"
        end
    end

    test -f "package.json"; and echo "📦 Node.js"
    test -f "requirements.txt"; and echo "🐍 Python"
    test -f "Cargo.toml"; and echo "🦀 Rust"
    test -f "go.mod"; and echo "🐹 Go"
    test -f "composer.json"; and echo "🐘 PHP"
    test -f ".env"; and echo "⚙️  Environment"
end

# File operations
function copy-pwd
    set path (pwd)
    if command -v xclip >/dev/null 2>&1
        echo -n $path | xclip -selection clipboard
        echo "📋 Copied: $path"
    else if command -v clip.exe >/dev/null 2>&1
        echo -n $path | clip.exe
        echo "📋 Copied: $path"
    else
        echo "📋 $path"
    end
end

function copy-file
    if test (count $argv) -eq 0
        echo "📝 Usage: copy-file <filename>"
        return 1
    end
    
    if test -f $argv[1]
        if command -v xclip >/dev/null 2>&1
            cat $argv[1] | xclip -selection clipboard
            echo "📋 Copied contents of $argv[1]"
        else if command -v clip.exe >/dev/null 2>&1
            cat $argv[1] | clip.exe
            echo "📋 Copied contents of $argv[1]"
        else
            echo "❌ No clipboard utility available"
        end
    else
        echo "❌ File not found: $argv[1]"
    end
end

alias cf copy-file

# Paste file from clipboard (Fish equivalent of PowerShell paste-file)
function paste-file
    set -l force_flag false
    set -l target_path (pwd)
    
    # Parse arguments
    for arg in $argv
        switch $arg
            case "--force" "-f"
                set force_flag true
            case "*"
                if test -d "$arg"
                    set target_path "$arg"
                end
        end
    end
    
    # Check if we have clipboard content (using xclip or clip.exe)
    set -l clipboard_content
    if command -v xclip >/dev/null 2>&1
        set clipboard_content (xclip -selection clipboard -o 2>/dev/null)
    else if command -v clip.exe >/dev/null 2>&1
        # Note: clip.exe only writes, doesn't read. We'll use a file-based approach
        echo "❌ Cannot read from Windows clipboard in WSL"
        echo "💡 Use copy-file then manually specify the source file"
        return 1
    else
        echo "❌ No clipboard utility available"
        return 1
    end
    
    # Check if clipboard contains file path with FILE: prefix
    if not string match -q "FILE:*" "$clipboard_content"
        echo "❌ No file found in clipboard"
        echo "💡 Use 'copy-file <filename>' to copy a file first"
        return 1
    end
    
    # Extract file path (remove 'FILE:' prefix)
    set -l source_file (string sub -s 6 "$clipboard_content")
    
    if not test -f "$source_file"
        echo "❌ Source file no longer exists: $source_file"
        return 1
    end
    
    # Ensure destination directory exists
    if not test -d "$target_path"
        echo "❌ Destination directory not found: $target_path"
        return 1
    end
    
    set -l file_name (basename "$source_file")
    set -l destination_path "$target_path/$file_name"
    
    # Check if file already exists
    if test -f "$destination_path"; and test "$force_flag" != "true"
        echo "⚠️  File already exists: $file_name"
        read -P "Overwrite? (y/n): " confirm
        if test "$confirm" != "y" -a "$confirm" != "Y"
            echo "❌ Paste cancelled"
            return 0
        end
    end
    
    # Copy the file
    if cp "$source_file" "$destination_path"
        echo "✅ File pasted: $file_name"
        echo "📁 Location: $destination_path"
    else
        echo "❌ Failed to paste file"
        return 1
    end
end

alias pf paste-file

# Open current directory
function open-pwd
    if command -v explorer.exe >/dev/null 2>&1
        set windows_path (wslpath -w (pwd) 2>/dev/null)
        if test -n "$windows_path"
            explorer.exe $windows_path
            echo "📁 Opened"
        end
    else if command -v xdg-open >/dev/null 2>&1
        xdg-open .
        echo "📁 Opened"
    end
end

alias op open-pwd

# Enhanced ls with colors and formatting
function ls
    if command -v lsd >/dev/null 2>&1
        lsd $argv
    else if command -v exa >/dev/null 2>&1
        exa --color=always --group-directories-first $argv
    else
        command ls --color=auto $argv
    end
end

alias la 'ls -la'
alias ll 'ls -l'

# File creation and manipulation
function touch
    if test (count $argv) -eq 0
        echo "📝 Usage: touch <filename>"
        return 1
    end
    
    for file in $argv
        if test -f $file
            command touch $file
            echo "⏰ Updated: $file"
        else
            command touch $file
            echo "📄 Created: $file"
        end
    end
end

function mkdir
    if test (count $argv) -eq 0
        echo "📁 Usage: mkdir <directory>"
        return 1
    end
    
    command mkdir -p $argv
    echo "📁 Created: $argv"
end

# Enhanced which command
function which
    if test (count $argv) -eq 0
        echo "🔍 Usage: which <command>"
        return 1
    end
    
    set -l result (command -v $argv[1])
    if test -n "$result"
        echo "📍 $argv[1] → $result"
        if test -f "$result"
            ls -la "$result"
        end
    else
        echo "❌ Command not found: $argv[1]"
    end
end

# Process and system information
function back
    if test (count $argv) -eq 0
        cd -
    else
        for i in (seq $argv[1])
            cd ..
        end
    end
    echo "📍 "(basename (pwd))
end

# Enhanced move operations (cut and paste for files)
set -g MOVE_IN_HAND ""
set -g MOVE_SOURCE_DIR ""

function mv
    # If no arguments, show current status and help
    if test (count $argv) -eq 0
        if test -n "$MOVE_IN_HAND"
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
        end
        return
    end
    
    set -l file_name $argv[1]
    
    # Smart file search
    set -l found_file ""
    
    # Try exact match first
    if test -f "$file_name"
        set found_file "$file_name"
    else
        # Try fuzzy search in current directory
        set -l matches (find . -maxdepth 1 -type f -iname "*$file_name*" 2>/dev/null)
        if test (count $matches) -eq 1
            set found_file $matches[1]
        else if test (count $matches) -gt 1
            echo "📁 Multiple files found:"
            for match in $matches
                echo "   📄 "(basename $match)
            end
            echo "💡 Be more specific with the filename"
            return 1
        else
            echo "❌ File not found: $file_name"
            return 1
        end
    end
    
    # If we had a previous file in hand, drop it
    if test -n "$MOVE_IN_HAND"
        echo "🗑️  Dropped previous file: $MOVE_IN_HAND"
    end
    
    # Hold the new file
    set -g MOVE_IN_HAND (basename "$found_file")
    set -g MOVE_SOURCE_DIR (dirname (realpath "$found_file"))
    
    echo "✂️  Cut file for moving: $MOVE_IN_HAND"
    echo "📁 Source: $MOVE_SOURCE_DIR"
    echo "💡 Use 'mv-t' to paste in target directory"
end

function mv-t
    if test -z "$MOVE_IN_HAND"
        echo "❌ No file currently held for moving"
        echo "💡 Use 'mv <filename>' first to cut a file for moving"
        return 1
    end
    
    set -l source_file "$MOVE_SOURCE_DIR/$MOVE_IN_HAND"
    set -l current_dir (pwd)
    
    # Check if source file still exists
    if not test -f "$source_file"
        echo "❌ Source file no longer exists: $MOVE_IN_HAND"
        echo "📁 Expected location: $source_file"
        set -g MOVE_IN_HAND ""
        set -g MOVE_SOURCE_DIR ""
        return 1
    end
    
    # Check if we're trying to move to the same directory
    if test "$MOVE_SOURCE_DIR" = "$current_dir"
        echo "⚠️  Source and destination are the same directory"
        echo "📁 Directory: $current_dir"
        echo "💡 Navigate to a different directory first"
        return 1
    end
    
    # Check if file already exists in destination
    set -l destination_path "$current_dir/$MOVE_IN_HAND"
    if test -f "$destination_path"
        echo "⚠️  File already exists in destination: $MOVE_IN_HAND"
        read -P "Overwrite? (y/n): " confirm
        if test "$confirm" != "y" -a "$confirm" != "Y"
            echo "❌ Move cancelled"
            return 0
        end
    end
    
    # Perform the move
    echo "📦 Moving file..."
    if mv "$source_file" "$destination_path"
        echo "✅ File moved successfully: $MOVE_IN_HAND"
        echo "📁 From: $MOVE_SOURCE_DIR"
        echo "📁 To: $current_dir"
        
        # Clear the move queue
        set -g MOVE_IN_HAND ""
        set -g MOVE_SOURCE_DIR ""
    else
        echo "❌ Failed to move file"
        return 1
    end
end

function mv-c
    if test -z "$MOVE_IN_HAND"
        echo "ℹ️  No file currently held for moving"
        return 0
    end
    
    echo "🗑️  Dropped file from move queue: $MOVE_IN_HAND"
    set -g MOVE_IN_HAND ""
    set -g MOVE_SOURCE_DIR ""
    echo "✅ Move operation cancelled"
end

# Enhanced rename function
function rn
    if test (count $argv) -eq 0
        echo "📝 Usage: rn <current-name> [new-name]"
        echo "Examples:"
        echo "  rn oldfile.txt newfile.txt   → Rename file directly"
        echo "  rn oldfile                   → Interactive rename"
        return 1
    end
    
    set -l current_name $argv[1]
    set -l new_name ""
    
    if test (count $argv) -gt 1
        set new_name $argv[2]
    end
    
    # Find the file (smart search)
    set -l found_file ""
    if test -f "$current_name"
        set found_file "$current_name"
    else
        # Try fuzzy search
        set -l matches (find . -maxdepth 1 -type f -iname "*$current_name*" 2>/dev/null)
        if test (count $matches) -eq 1
            set found_file $matches[1]
        else if test (count $matches) -gt 1
            echo "📁 Multiple files found:"
            for match in $matches
                echo "   📄 "(basename $match)
            end
            echo "💡 Be more specific with the filename"
            return 1
        else
            echo "❌ File not found: $current_name"
            return 1
        end
    end
    
    set -l old_name (basename "$found_file")
    
    # If no new name provided, prompt for it
    if test -z "$new_name"
        echo "📝 Renaming: $old_name"
        read -P "New name: " new_name
        if test -z "$new_name"
            echo "❌ Rename cancelled"
            return 0
        end
    end
    
    # Check if new file already exists
    if test -f "$new_name"
        echo "⚠️  File already exists: $new_name"
        read -P "Overwrite? (y/n): " confirm
        if test "$confirm" != "y" -a "$confirm" != "Y"
            echo "❌ Rename cancelled"
            return 0
        end
    end
    
    # Perform the rename
    if mv "$found_file" "$new_name"
        echo "✅ File renamed successfully"
        echo "📝 $old_name → $new_name"
    else
        echo "❌ Failed to rename file"
        return 1
    end
end

# ============================================================================
# WINDOWS TERMINAL
# ============================================================================

function next-t
    if command -v powershell.exe >/dev/null 2>&1
        powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^{TAB}')" 2>/dev/null
    else
        echo "Use Ctrl+Tab"
    end
end

function prev-t
    if command -v powershell.exe >/dev/null 2>&1
        powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^+{TAB}')" 2>/dev/null
    else
        echo "Use Ctrl+Shift+Tab"
    end
end

alias next_tab next-t

# Send keys to Windows (WSL-specific)
function send-keys
    if test (count $argv) -eq 0
        echo "📝 Usage: send-keys <keys>"
        echo "Example: send-keys '^{TAB}' (Ctrl+Tab)"
        return 1
    end
    
    set -l keys $argv[1]
    if command -v powershell.exe >/dev/null 2>&1
        powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('$keys')" 2>/dev/null
    else
        echo "❌ PowerShell not available"
        return 1
    end
end

# Open new Windows Terminal tab
function open-nt
    set -l shell_type "pwsh"
    if test (count $argv) -gt 0
        set shell_type $argv[1]
    end
    
    set -l current_dir (pwd)
    
    # Convert WSL path to Windows path if needed
    if string match -q "/mnt/*" $current_dir
        set current_dir (wslpath -w $current_dir)
    end
    
    switch $shell_type
        case "ubuntu" "u" "wsl"
            if command -v wt.exe >/dev/null 2>&1
                wt.exe new-tab --profile "Ubuntu" --startingDirectory "$current_dir" 2>/dev/null &
                echo "🐧 Opening new Ubuntu tab..."
            else
                echo "❌ Windows Terminal not found"
            end
        case "pwsh" "powershell"
            if command -v wt.exe >/dev/null 2>&1
                wt.exe new-tab --profile "PowerShell" --startingDirectory "$current_dir" 2>/dev/null &
                echo "🔷 Opening new PowerShell tab..."
            else
                echo "❌ Windows Terminal not found"
            end
        case "cmd"
            if command -v wt.exe >/dev/null 2>&1
                wt.exe new-tab --profile "Command Prompt" --startingDirectory "$current_dir" 2>/dev/null &
                echo "📟 Opening new Command Prompt tab..."
            else
                echo "❌ Windows Terminal not found"
            end
        case "*"
            echo "❌ Unknown shell type: $shell_type"
            echo "Available: ubuntu, u, wsl, pwsh, powershell, cmd"
            return 1
    end
end

# Open new terminal tab (smart detection)
function open-t
    if command -v wt.exe >/dev/null 2>&1
        open-nt "ubuntu"  # Default to Ubuntu in WSL
    else if command -v gnome-terminal >/dev/null 2>&1
        gnome-terminal --tab --working-directory=(pwd) &
        echo "📟 Opening new terminal tab..."
    else if command -v konsole >/dev/null 2>&1
        konsole --new-tab --workdir (pwd) &
        echo "📟 Opening new terminal tab..."
    else
        echo "❌ No supported terminal found"
        return 1
    end
end

# Close current terminal
function close-t
    exit
end

alias close-ct close-t

# ============================================================================
# PROJECT CREATION
# ============================================================================

function create-next
    if test (count $argv) -eq 0
        echo "📦 Usage: create-next <project-name>"
        return 1
    end
    
    set -l project_name $argv[1]
    echo "🚀 Creating Next.js project: $project_name"
    
    npx create-next-app@latest $project_name --typescript --tailwind --eslint --app
    
    if test $status -eq 0
        cd $project_name
        echo "✅ Project created successfully!"
        echo "📍 Current directory: "(pwd)
        echo "🏃 To start development: npm run dev"
    else
        echo "❌ Failed to create project"
    end
end

alias create-n create-next

# ============================================================================
# POWERFLOW FUNCTIONS
# ============================================================================

function powerflow-version
    echo "🚀 PowerFlow Fish Profile"
    echo "Version: $POWERFLOW_VERSION"
    echo "Repository: https://github.com/$POWERFLOW_REPO"
    echo "Shell: "(fish --version)
    echo "Platform: WSL "(uname -r)
end

function powerflow-update
    echo "🔄 Updating PowerFlow..."
    set -l current_dir (pwd)
    
    if test -d "$HOME/.powerflow"
        cd "$HOME/.powerflow"
        git pull origin main
        echo "✅ PowerFlow updated successfully!"
    else
        echo "❌ PowerFlow directory not found. Please reinstall."
    end
    
    cd $current_dir
end

# ============================================================================
# HELP
# ============================================================================

function fish-help
    echo ""
    echo "🐠 PowerFlow Fish Profile Commands"
    echo "═══════════════════════════════════"
    echo ""
    echo "🤖 AI Assistant:"
    echo "  claude <prompt>      cc <prompt>         explain <file>"
    echo "  fix 'problem'        build 'feature'     review"
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
    echo "  powerflow-version   powerflow-update    fish-help"
    echo ""
    echo "🐠 Fish Features:"
    echo "  • Auto-completion: Tab to complete commands and paths"
    echo "  • Auto-suggestions: Type and see historical suggestions"
    echo "  • Syntax highlighting: Commands are colored as you type"
    echo "  • Smart history: Up/Down arrows for command history"
    echo "  • Fuzzy search: Ctrl+R for command history search"
    echo ""
    echo "💡 Pro Tips:"
    echo "  • Use 'mv file' then 'mv-t' to cut/paste files"
    echo "  • 'git-rb abc123' creates rollback branch from commit"
    echo "  • 'nav powerflow' finds projects with smart search"
    echo "  • Fish auto-suggests based on your history"
    echo ""
end

alias wsl-help fish-help
alias help fish-help

# ============================================================================
# DEPENDENCY INITIALIZATION
# ============================================================================

# Initialize starship prompt (if available)
if command -v starship >/dev/null 2>&1
    starship init fish | source
end

# Initialize zoxide (if available)
if command -v zoxide >/dev/null 2>&1
    zoxide init fish | source
    alias cd z
end

# Initialize fzf (if available)
if command -v fzf >/dev/null 2>&1
    # FZF key bindings and completion (if files exist)
    if test -f /usr/share/fish/vendor_functions.d/fzf_key_bindings.fish
        source /usr/share/fish/vendor_functions.d/fzf_key_bindings.fish
    end
end

# ============================================================================
# BOOKMARKS SYSTEM
# ============================================================================

set -g BOOKMARKS_FILE "$HOME/.wsl_bookmarks.json"

function create-bookmark
    if test (count $argv) -eq 0
        echo "📖 Usage: create-bookmark <name> [path]"
        return 1
    end
    
    set -l name $argv[1]
    set -l path (pwd)
    if test (count $argv) -gt 1
        set path $argv[2]
    end
    
    if not test -d "$path"
        echo "❌ Directory not found: $path"
        return 1
    end
    
    # Create bookmarks file if it doesn't exist
    if not test -f $BOOKMARKS_FILE
        echo '{}' > $BOOKMARKS_FILE
    end
    
    # Add bookmark using jq if available
    if command -v jq >/dev/null 2>&1
        jq --arg name "$name" --arg path "$path" '. + {($name): $path}' $BOOKMARKS_FILE > /tmp/bookmarks.tmp
        mv /tmp/bookmarks.tmp $BOOKMARKS_FILE
        echo "📖 Bookmark created: $name → $path"
    else
        echo "❌ jq not available. Please install jq for bookmark functionality."
    end
end

alias cb create-bookmark

function delete-bookmark
    if test (count $argv) -eq 0
        echo "🗑️  Usage: delete-bookmark <name>"
        return 1
    end
    
    set -l name $argv[1]
    
    if not test -f $BOOKMARKS_FILE
        echo "❌ No bookmarks file found"
        return 1
    end
    
    if command -v jq >/dev/null 2>&1
        jq --arg name "$name" 'del(.[$name])' $BOOKMARKS_FILE > /tmp/bookmarks.tmp
        mv /tmp/bookmarks.tmp $BOOKMARKS_FILE
        echo "🗑️  Bookmark deleted: $name"
    else
        echo "❌ jq not available. Please install jq for bookmark functionality."
    end
end

alias db delete-bookmark

function list-bookmarks
    if not test -f $BOOKMARKS_FILE
        echo "📖 No bookmarks found. Create one with: create-bookmark <name>"
        return
    end
    
    if command -v jq >/dev/null 2>&1
        echo "📖 Available bookmarks:"
        jq -r 'to_entries[] | "  \(.key) → \(.value)"' $BOOKMARKS_FILE
    else
        echo "❌ jq not available. Please install jq for bookmark functionality."
    end
end

alias lb list-bookmarks

# ============================================================================
# STARTUP
# ============================================================================

# Initialize default bookmarks if file doesn't exist
if not test -f $BOOKMARKS_FILE; and command -v jq >/dev/null 2>&1
    echo '{
  "code": "/mnt/c/Users/_munya/Code",
  "docs": "/mnt/c/Users/_munya/Documents", 
  "home": "/home/'(whoami)'"
}' > $BOOKMARKS_FILE
end

# Auto-navigate to code directory on startup
if test (pwd) = $HOME; and test -d $WSL_START_DIRECTORY
    cd $WSL_START_DIRECTORY
    echo "🚀 PowerFlow Fish Profile loaded!"
    echo "📍 Starting in: "(basename (pwd))
    echo "💡 Type 'fish-help' or 'help' for available commands"
end

# Welcome message for new sessions
if not set -q POWERFLOW_LOADED
    set -g POWERFLOW_LOADED true
    echo ""
    echo "🐠 PowerFlow Fish Profile v$POWERFLOW_VERSION"
    echo "🌟 Enhanced shell with intelligent auto-completion"
    echo "💡 Type 'help' to see all available commands"
    echo ""
end
