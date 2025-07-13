# ============================================================================
# Fish completions for the PowerFlow nav command
# ============================================================================
# Enhanced navigation completions with bookmark support, project detection,
# and intelligent directory suggestions for Fish shell.
# 
# This file provides auto-completion for:
# - Bookmark navigation (nav b <bookmark>)
# - Project directories from code folder
# - Bookmark management commands
# - Direct directory navigation
# 
# Save this as ~/.config/fish/completions/nav.fish
# ============================================================================

# Function to get bookmark names from JSON file
function __nav_get_bookmarks
    if test -f "$HOME/.wsl_bookmarks.json"; and command -v jq >/dev/null 2>&1
        cat "$HOME/.wsl_bookmarks.json" | jq -r 'keys[]' 2>/dev/null
    else
        # Fallback to common bookmark names if jq not available
        echo -e "code\ndocs\nhome"
    end
end

# Function to get project directories from code folder
function __nav_get_projects
    if test -f "$HOME/.wsl_bookmarks.json"; and command -v jq >/dev/null 2>&1
        set code_path (cat "$HOME/.wsl_bookmarks.json" | jq -r '.code // empty' 2>/dev/null)
        if test -n "$code_path"; and test -d "$code_path"
            find "$code_path" -maxdepth 2 -type d -not -path "$code_path" 2>/dev/null | while read dir
                basename "$dir"
            end
        end
    else
        # Fallback to default code directory if bookmarks not available
        if test -d "/mnt/c/Users/_munya/Code"
            find "/mnt/c/Users/_munya/Code" -maxdepth 2 -type d -not -path "/mnt/c/Users/_munya/Code" 2>/dev/null | while read dir
                basename "$dir"
            end
        end
    end
end

# Function to get recently accessed directories
function __nav_get_recent_dirs
    if test -f "$HOME/.nav_history"
        head -10 "$HOME/.nav_history" | cut -d'|' -f2
    end
end

# Main nav command completions (disable file completion by default)
complete -c nav -f

# Subcommands
complete -c nav -n '__fish_use_subcommand' -a 'b' -d 'Navigate to bookmark'
complete -c nav -n '__fish_use_subcommand' -a 'create-b cb' -d 'Create bookmark for current directory'
complete -c nav -n '__fish_use_subcommand' -a 'delete-b db' -d 'Delete existing bookmark'
complete -c nav -n '__fish_use_subcommand' -a 'list l' -d 'List all bookmarks'
complete -c nav -n '__fish_use_subcommand' -a 'recent r' -d 'Show recent navigation history'

# Bookmark completions for 'nav b <bookmark>'
complete -c nav -n '__fish_seen_subcommand_from b' -a '(__nav_get_bookmarks)' -d 'Bookmark location'

# Bookmark name completions for creation 'nav create-b <name>'
complete -c nav -n '__fish_seen_subcommand_from create-b cb' -f -d 'New bookmark name'

# Bookmark completions for deletion 'nav delete-b <bookmark>' and 'nav db <bookmark>'
complete -c nav -n '__fish_seen_subcommand_from delete-b db' -a '(__nav_get_bookmarks)' -d 'Bookmark to delete'

# No additional completions for list and recent commands
complete -c nav -n '__fish_seen_subcommand_from list l recent r' -f

# Project completions for direct navigation (project names)
complete -c nav -n '__fish_use_subcommand' -a '(__nav_get_projects)' -d 'Project directory'

# Recent directory completions
complete -c nav -n '__fish_use_subcommand' -a '(__nav_get_recent_dirs)' -d 'Recent directory'

# Directory path completions as fallback (for advanced users)
complete -c nav -n '__fish_use_subcommand' -a '(__fish_complete_directories)' -d 'Directory path'

# ============================================================================
# Additional completions for bookmark management commands
# ============================================================================

# Completions for standalone bookmark commands
complete -c create-bookmark -f -d 'Create bookmark name'
complete -c cb -f -d 'Create bookmark name'

complete -c delete-bookmark -a '(__nav_get_bookmarks)' -d 'Bookmark to delete'
complete -c db -a '(__nav_get_bookmarks)' -d 'Bookmark to delete'

complete -c list-bookmarks -f
complete -c lb -f

# ============================================================================
# Git command completions enhancement
# ============================================================================

# Enhanced git completions for our custom git functions
complete -c git-a -a '(__fish_git_files)' -d 'File to add'
complete -c git-cm -f -d 'Commit message'
complete -c git-b -a '(__fish_git_branches)' -d 'Branch name'