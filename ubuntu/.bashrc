#!/bin/bash

# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt.
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your aliases in a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Load NVM (Node Version Manager) if available
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# ============================================================================
# ENHANCED WSL PROFILE - NAVIGATION & BOOKMARK SYSTEM
# Added: PowerShell-style navigation with auto-installation
# Version: 1.0.0
# ============================================================================

# Enhanced color support and profile version
export TERM=xterm-256color
export CLICOLOR=1
export WSL_PROFILE_VERSION="1.0.0"
export CHECK_DEPENDENCIES=true
export CHECK_UPDATES=true

# Suppress progress bars for faster installation
export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# DEPENDENCY MANAGEMENT & AUTO-INSTALLATION
# ============================================================================

# Check if we've already checked dependencies today
check_daily_init() {
    local init_check_file="$HOME/.wsl_init_check"
    local today=$(date +%Y-%m-%d)
    
    if [[ -f "$init_check_file" ]]; then
        local last_check=$(cat "$init_check_file" 2>/dev/null)
        if [[ "$last_check" == "$today" ]]; then
            return 1  # Already checked today
        fi
    fi
    
    echo "$today" > "$init_check_file"
    return 0  # Need to check
}

# Initialize and install dependencies
initialize_dependencies() {
    if [[ "$CHECK_DEPENDENCIES" != "true" ]]; then
        return
    fi
    
    # Only check once per day to avoid slowing down shell startup
    if ! check_daily_init; then
        return
    fi
    
    echo "🔍 Checking WSL profile dependencies..." >&2
    
    # Required tools for this profile
    local required_tools=(
        "curl:curl"
        "wget:wget" 
        "git:git"
        "jq:jq"
        "fzf:fzf"
        "xclip:xclip"
    )
    
    local optional_tools=(
        "starship:starship"
        "zoxide:zoxide"
        "lsd:lsd"
    )
    
    local missing_tools=()
    local missing_optional=()
    
    # Check required tools
    for tool_info in "${required_tools[@]}"; do
        local tool_name="${tool_info%%:*}"
        local command_name="${tool_info##*:}"
        
        if ! command -v "$command_name" >/dev/null 2>&1; then
            missing_tools+=("$tool_info")
        fi
    done
    
    # Check optional tools
    for tool_info in "${optional_tools[@]}"; do
        local tool_name="${tool_info%%:*}"
        local command_name="${tool_info##*:}"
        
        if ! command -v "$command_name" >/dev/null 2>&1; then
            missing_optional+=("$tool_info")
        fi
    done
    
    # Install missing required tools
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "📦 Installing missing required tools: ${missing_tools[*]}" >&2
        
        # Update package list first
        echo "   Updating package list..." >&2
        sudo apt update >/dev/null 2>&1
        
        for tool_info in "${missing_tools[@]}"; do
            local tool_name="${tool_info%%:*}"
            install_tool "$tool_name"
        done
    fi
    
    # Install missing optional tools
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        echo "🛠️  Installing optional tools for enhanced experience..." >&2
        
        for tool_info in "${missing_optional[@]}"; do
            local tool_name="${tool_info%%:*}"
            install_optional_tool "$tool_name"
        done
    fi
    
    # Show completion message
    if [[ ${#missing_tools[@]} -gt 0 ]] || [[ ${#missing_optional[@]} -gt 0 ]]; then
        echo "✅ Dependency installation complete" >&2
        echo "🔄 Restart your terminal or run 'source ~/.bashrc' to use new tools" >&2
    fi
}

# Install a required tool
install_tool() {
    local tool="$1"
    
    echo "   Installing $tool..." >&2
    
    case "$tool" in
        "curl"|"wget"|"git"|"jq"|"fzf"|"xclip")
            if sudo apt install -y "$tool" >/dev/null 2>&1; then
                echo "   ✅ $tool installed" >&2
            else
                echo "   ❌ Failed to install $tool" >&2
            fi
            ;;
        *)
            echo "   ⚠️  Unknown tool: $tool" >&2
            ;;
    esac
}

# Install an optional tool with special handling
install_optional_tool() {
    local tool="$1"
    
    echo "   Installing $tool..." >&2
    
    case "$tool" in
        "starship")
            if curl -sS https://starship.rs/install.sh | sh -s -- --yes >/dev/null 2>&1; then
                echo "   ✅ starship installed" >&2
            else
                echo "   ❌ Failed to install starship" >&2
            fi
            ;;
        "zoxide")
            if curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash >/dev/null 2>&1; then
                echo "   ✅ zoxide installed" >&2
            else
                echo "   ❌ Failed to install zoxide" >&2
            fi
            ;;
        "lsd")
            local temp_dir=$(mktemp -d)
            if wget -q -O "$temp_dir/lsd.deb" "https://github.com/Peltoche/lsd/releases/download/0.23.1/lsd_0.23.1_amd64.deb" 2>/dev/null && \
               sudo dpkg -i "$temp_dir/lsd.deb" >/dev/null 2>&1; then
                echo "   ✅ lsd installed" >&2
            else
                echo "   ❌ Failed to install lsd" >&2
            fi
            rm -rf "$temp_dir"
            ;;
        *)
            echo "   ⚠️  Unknown optional tool: $tool" >&2
            ;;
    esac
}

# Check for WSL profile updates
check_wsl_profile_updates() {
    if [[ "$CHECK_UPDATES" != "true" ]]; then
        return
    fi
    
    # Check if we've already prompted for this version today
    local update_check_file="$HOME/.wsl_profile_update_check"
    local today=$(date +%Y-%m-%d)
    
    if [[ -f "$update_check_file" ]]; then
        local last_check=$(cat "$update_check_file" 2>/dev/null)
        if [[ "$last_check" == "$today" ]]; then
            return  # Already checked today
        fi
    fi
    
    # For now, just mark as checked (in future versions, we can add GitHub update checking)
    echo "$today" > "$update_check_file"
}

# ============================================================================
# VERSION MANAGEMENT & RECOVERY
# ============================================================================

# WSL Profile version management
get_wsl_profile_version() {
    echo "📦 WSL Enhanced Profile v$WSL_PROFILE_VERSION"
    echo "🔧 Dependencies: $(check_dependency_status)"
    echo "📁 Bookmarks: $(get_bookmark_count) configured"
}

check_dependency_status() {
    local tools=("curl" "wget" "git" "jq" "fzf" "xclip" "starship" "zoxide" "lsd")
    local installed=0
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            ((installed++))
        fi
    done
    
    echo "$installed/${#tools[@]} installed"
}

get_bookmark_count() {
    if [[ -f "$BOOKMARK_FILE" ]]; then
        jq 'length' "$BOOKMARK_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# WSL Profile recovery and diagnostics
wsl_recovery() {
    echo
    echo "🚑 WSL Profile Recovery Options:"
    echo "════════════════════════════════"
    echo
    echo "🔄 Quick Fixes:"
    echo "  1. Reload profile: source ~/.bashrc"
    echo "  2. Check dependencies: check_dependency_status"
    echo "  3. Reinstall tools: rm ~/.wsl_init_check && source ~/.bashrc"
    echo
    echo "🔧 Recovery Actions:"
    echo "  4. Reset bookmarks: rm ~/.wsl_bookmarks.json && source ~/.bashrc"
    echo "  5. Full dependency reinstall: sudo apt update && sudo apt install curl wget git jq fzf xclip"
    echo "  6. Edit profile manually: nano ~/.bashrc"
    echo
    echo "📋 Diagnostics:"
    echo "  7. Version info: get_wsl_profile_version"
    echo "  8. Test navigation: nav list"
    echo "  9. Full help: wsl_help"
    echo
    
    read -p "Choose an option (1-9) or 'q' to quit: " choice
    
    case "$choice" in
        1)
            echo "🔄 Reloading profile..."
            source ~/.bashrc
            ;;
        2)
            echo "🔍 Checking dependencies..."
            local tools=("curl" "wget" "git" "jq" "fzf" "xclip" "starship" "zoxide" "lsd")
            for tool in "${tools[@]}"; do
                if command -v "$tool" >/dev/null 2>&1; then
                    echo "  $tool : ✅ Found"
                else
                    echo "  $tool : ❌ Missing"
                fi
            done
            ;;
        3)
            echo "📦 Reinstalling dependencies..."
            rm -f ~/.wsl_init_check
            initialize_dependencies
            ;;
        4)
            read -p "⚠️  Remove all bookmarks? This will reset your navigation bookmarks. (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                rm -f ~/.wsl_bookmarks.json
                initialize_default_bookmarks
                echo "✅ Bookmarks reset to defaults"
            fi
            ;;
        5)
            echo "🔄 Full dependency reinstall..."
            sudo apt update
            sudo apt install -y curl wget git jq fzf xclip
            ;;
        6)
            if command -v nano >/dev/null 2>&1; then
                nano ~/.bashrc
            else
                echo "💡 Edit ~/.bashrc with your preferred editor"
            fi
            ;;
        7)
            get_wsl_profile_version
            ;;
        8)
            nav list
            ;;
        9)
            wsl_help
            ;;
        q|Q)
            echo "👋 Recovery menu closed"
            ;;
        *)
            echo "❌ Invalid option"
            ;;
    esac
}

# ============================================================================
# NAVIGATION SYSTEM CONFIGURATION
# ============================================================================

# Navigation history and bookmark files
export NAV_HISTORY_FILE="$HOME/.nav_history"
export BOOKMARK_FILE="$HOME/.wsl_bookmarks.json"

# Create history file if it doesn't exist
touch "$NAV_HISTORY_FILE"

# ============================================================================
# BOOKMARK MANAGEMENT SYSTEM
# ============================================================================

# Initialize default bookmarks
initialize_default_bookmarks() {
    if [[ ! -f "$BOOKMARK_FILE" ]]; then
        cat > "$BOOKMARK_FILE" << 'EOF'
{
  "code": "/mnt/c/Users/_munya/Code",
  "documents": "/mnt/c/Users/_munya/Documents",
  "docs": "/mnt/c/Users/_munya/Documents",
  "pictures": "/mnt/c/Users/_munya/Pictures",
  "pics": "/mnt/c/Users/_munya/Pictures",
  "downloads": "/mnt/c/Users/_munya/Downloads",
  "download": "/mnt/c/Users/_munya/Downloads",
  "videos": "/mnt/c/Users/_munya/Videos",
  "home": "/home/munya",
  "winhome": "/mnt/c/Users/_munya"
}
EOF
        echo "📚 Initialized default bookmarks" >&2
    fi
}

# Get bookmarks from JSON file
get_bookmarks() {
    initialize_default_bookmarks
    if [[ -f "$BOOKMARK_FILE" ]]; then
        cat "$BOOKMARK_FILE"
    else
        echo "{}"
    fi
}

# Save bookmarks to JSON file
save_bookmarks() {
    local bookmarks="$1"
    echo "$bookmarks" > "$BOOKMARK_FILE"
}

# Add bookmark
add_bookmark() {
    local name="$1"
    local path="${2:-$(pwd)}"
    
    if [[ -z "$name" ]]; then
        echo "❌ Error: Bookmark name is required"
        echo "💡 Usage: nav create-b <name> or nav cb <name>"
        return 1
    fi
    
    if [[ ! -d "$path" ]]; then
        echo "❌ Error: Path does not exist: $path"
        return 1
    fi
    
    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required for bookmark management"
        echo "💡 Install with: sudo apt install jq"
        return 1
    fi
    
    local bookmarks=$(get_bookmarks)
    local updated_bookmarks=$(echo "$bookmarks" | jq --arg name "${name,,}" --arg path "$path" '. + {($name): $path}')
    
    save_bookmarks "$updated_bookmarks"
    echo "📌 Bookmark '$name' created → $path"
}

# Remove bookmark
remove_bookmark() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        echo "❌ Error: Bookmark name is required"
        echo "💡 Usage: nav delete-b <name> or nav db <name>"
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required for bookmark management"
        return 1
    fi
    
    local bookmarks=$(get_bookmarks)
    local bookmark_path=$(echo "$bookmarks" | jq -r --arg name "${name,,}" '.[$name] // empty')
    
    if [[ -z "$bookmark_path" ]]; then
        echo "❌ Bookmark '$name' not found"
        return 1
    fi
    
    echo "🗑️  Delete bookmark '$name' → $bookmark_path?"
    read -p "Confirm (y/n): " confirmation
    
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        local updated_bookmarks=$(echo "$bookmarks" | jq --arg name "${name,,}" 'del(.[$name])')
        save_bookmarks "$updated_bookmarks"
        echo "✅ Bookmark '$name' deleted"
    else
        echo "❌ Deletion cancelled"
    fi
}

# Rename bookmark
rename_bookmark() {
    local old_name="$1"
    local new_name="$2"
    
    if [[ -z "$old_name" ]] || [[ -z "$new_name" ]]; then
        echo "❌ Error: Both old and new bookmark names are required"
        echo "💡 Usage: nav rename-b <oldname> <newname> or nav rb <oldname> <newname>"
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required for bookmark management"
        return 1
    fi
    
    local bookmarks=$(get_bookmarks)
    local old_path=$(echo "$bookmarks" | jq -r --arg name "${old_name,,}" '.[$name] // empty')
    local new_exists=$(echo "$bookmarks" | jq -r --arg name "${new_name,,}" '.[$name] // empty')
    
    if [[ -z "$old_path" ]]; then
        echo "❌ Bookmark '$old_name' not found"
        return 1
    fi
    
    if [[ -n "$new_exists" ]]; then
        echo "❌ Bookmark '$new_name' already exists"
        return 1
    fi
    
    local updated_bookmarks=$(echo "$bookmarks" | jq --arg old "${old_name,,}" --arg new "${new_name,,}" '. + {($new): .[$old]} | del(.[$old])')
    save_bookmarks "$updated_bookmarks"
    echo "📝 Bookmark renamed: '$old_name' → '$new_name'"
}

# Show interactive bookmark list
show_bookmark_list() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required for bookmark management"
        echo "💡 Install with: sudo apt install jq"
        return 1
    fi
    
    local bookmarks=$(get_bookmarks)
    
    if [[ $(echo "$bookmarks" | jq 'length') -eq 0 ]]; then
        echo "📚 No bookmarks found"
        return
    fi
    
    echo "📚 Available Bookmarks:"
    echo "═══════════════════════"
    
    local bookmark_array=()
    local index=1
    
    while IFS= read -r line; do
        local name=$(echo "$line" | cut -d: -f1)
        local path=$(echo "$line" | cut -d: -f2-)
        local status="❌"
        [[ -d "$path" ]] && status="✅"
        
        echo "$index. $status $name → $path"
        bookmark_array+=("$name:$path")
        ((index++))
    done < <(echo "$bookmarks" | jq -r 'to_entries[] | "\(.key):\(.value)"' | sort)
    
    echo
    echo "💡 Actions:"
    echo "   Enter number to navigate | 'c <name>' to create | 'd <name>' to delete | 'r <old> <new>' to rename | 'q' to quit"
    
    while true; do
        echo
        read -p "Choice: " input
        
        case "$input" in
            q|Q)
                break
                ;;
            [0-9]*)
                if [[ "$input" -ge 1 ]] && [[ "$input" -le "${#bookmark_array[@]}" ]]; then
                    local selected="${bookmark_array[$((input-1))]}"
                    local selected_name=$(echo "$selected" | cut -d: -f1)
                    local selected_path=$(echo "$selected" | cut -d: -f2-)
                    
                    if [[ -d "$selected_path" ]]; then
                        cd "$selected_path"
                        echo "📍 Navigated to: $selected_name"
                        break
                    else
                        echo "❌ Path no longer exists: $selected_path"
                    fi
                else
                    echo "❌ Invalid choice. Please enter a number between 1 and ${#bookmark_array[@]}"
                fi
                ;;
            c\ *)
                local bookmark_name="${input#c }"
                add_bookmark "$bookmark_name"
                ;;
            d\ *)
                local bookmark_name="${input#d }"
                remove_bookmark "$bookmark_name"
                ;;
            r\ *)
                local names="${input#r }"
                local old_name=$(echo "$names" | cut -d' ' -f1)
                local new_name=$(echo "$names" | cut -d' ' -f2)
                rename_bookmark "$old_name" "$new_name"
                ;;
            *)
                echo "❌ Invalid input. Try again or 'q' to quit."
                ;;
        esac
    done
}

# ============================================================================
# SMART PROJECT SEARCH SYSTEM
# ============================================================================

# Search for nested projects (advanced search with fuzzy matching)
search_nested_projects() {
    local project_name="$1"
    local base_dir="$2"
    local verbose="$3"
    
    [[ "$verbose" == "true" ]] && echo "🔍 Starting nested search for '$project_name' in: $base_dir"
    
    if [[ ! -d "$base_dir" ]]; then
        [[ "$verbose" == "true" ]] && echo "❌ Base directory not found: $base_dir"
        return 1
    fi
    
    # Convert search term for parent folder matching (chess-guru -> chess guru)
    local parent_search_term="${project_name//-/ }"
    [[ "$verbose" == "true" ]] && echo "🔄 Parent search term: '$parent_search_term'"
    
    # Search subdirectories
    while IFS= read -r -d '' subdir; do
        local subdir_name=$(basename "$subdir")
        [[ "$verbose" == "true" ]] && echo "  📂 Checking: $subdir_name"
        
        # Check if this subdirectory name matches our parent search term
        if [[ "$subdir_name" == *"$parent_search_term"* ]] || [[ "$subdir_name" == "$parent_search_term" ]]; then
            [[ "$verbose" == "true" ]] && echo "  ⚡ Found potential parent: $subdir_name"
            
            # Look inside this subdirectory for the actual project
            while IFS= read -r -d '' innerdir; do
                local inner_name=$(basename "$innerdir")
                [[ "$verbose" == "true" ]] && echo "    🔍 Inner dir: $inner_name"
                
                # Check for exact match first
                if [[ "$inner_name" == "$project_name" ]]; then
                    [[ "$verbose" == "true" ]] && echo "    ⭐ EXACT MATCH FOUND!"
                    echo "$innerdir"
                    return 0
                fi
                
                # Check for fuzzy match
                if [[ "$inner_name" == *"$project_name"* ]]; then
                    [[ "$verbose" == "true" ]] && echo "    ⚡ FUZZY MATCH FOUND!"
                    echo "$innerdir"
                    return 0
                fi
            done < <(find "$subdir" -maxdepth 1 -type d -print0 2>/dev/null)
        fi
    done < <(find "$base_dir" -maxdepth 1 -type d -print0 2>/dev/null)
    
    return 1
}

# ============================================================================
# MAIN NAVIGATION FUNCTION
# ============================================================================

# Main nav function (complete port from PowerShell)
nav() {
    local command="$1"
    local param1="$2"
    local param2="$3"
    local verbose=false
    
    # Initialize bookmarks on first run
    initialize_default_bookmarks
    
    # Check for verbose flag
    for arg in "$@"; do
        if [[ "$arg" == "-verbose" ]]; then
            verbose=true
            break
        fi
    done
    
    # If no command provided, show help
    if [[ -z "$command" ]]; then
        echo "💡 Navigation Commands:"
        echo "═════════════════════"
        echo "  nav <project-name>           Navigate to project"
        echo "  nav b <bookmark>             Navigate to bookmark"
        echo "  nav create-b <name> | cb     Create bookmark (current dir)"
        echo "  nav delete-b <name> | db     Delete bookmark"
        echo "  nav rename-b <old> <new>     Rename bookmark"
        echo "  nav list | l                 Show interactive bookmark list"
        echo "  Use -verbose for detailed output"
        return
    fi
    
    [[ "$verbose" == "true" ]] && echo "=== NAV FUNCTION ==="
    [[ "$verbose" == "true" ]] && echo "Command: '$command'"
    [[ "$verbose" == "true" ]] && echo "Param1: '$param1'"
    [[ "$verbose" == "true" ]] && echo "Param2: '$param2'"
    
    # Handle bookmark management commands
    case "$command" in
        create-b|cb)
            add_bookmark "$param1"
            return
            ;;
        delete-b|db)
            remove_bookmark "$param1"
            return
            ;;
        rename-b|rb)
            rename_bookmark "$param1" "$param2"
            return
            ;;
        list|l)
            show_bookmark_list
            return
            ;;
    esac
    
    # Handle bookmark navigation (nav b <bookmark>)
    if [[ "$command" == "b" ]]; then
        if [[ -z "$param1" ]]; then
            echo "❌ Error: Bookmark name is required"
            echo "💡 Usage: nav b <bookmark-name>"
            return 1
        fi
        
        if ! command -v jq >/dev/null 2>&1; then
            echo "❌ Error: jq is required for bookmark navigation"
            echo "💡 Install with: sudo apt install jq"
            return 1
        fi
        
        local bookmarks=$(get_bookmarks)
        local bookmark_path=$(echo "$bookmarks" | jq -r --arg name "${param1,,}" '.[$name] // empty')
        
        if [[ -n "$bookmark_path" ]]; then
            if [[ -d "$bookmark_path" ]]; then
                cd "$bookmark_path"
                echo "📌 Navigated to bookmark: $param1"
                echo "📍 Location: $bookmark_path"
                return
            else
                echo "❌ Bookmark path no longer exists: $bookmark_path"
                echo "💡 Use 'nav delete-b $param1' to remove invalid bookmark"
                return 1
            fi
        else
            echo "❌ Bookmark '$param1' not found"
            echo "💡 Use 'nav list' to see available bookmarks"
            return 1
        fi
    fi
    
    # === PROJECT SEARCH LOGIC ===
    
    local current_path="$(pwd)"
    local search_dir="$current_path"
    
    # Check if we're in a bookmarked location
    if command -v jq >/dev/null 2>&1; then
        local bookmarks=$(get_bookmarks)
        local is_in_bookmarked_location=false
        local parent_bookmark=""
        
        while IFS= read -r line; do
            local bookmark_name=$(echo "$line" | cut -d: -f1)
            local bookmark_path=$(echo "$line" | cut -d: -f2-)
            
            if [[ "$current_path" == "$bookmark_path"* ]]; then
                is_in_bookmarked_location=true
                parent_bookmark="$bookmark_path"
                break
            fi
        done < <(echo "$bookmarks" | jq -r 'to_entries[] | "\(.key):\(.value)"')
        
        # Only default to Code bookmark if we're in a completely unrelated location
        if [[ "$is_in_bookmarked_location" == "false" ]]; then
            local code_bookmark=$(echo "$bookmarks" | jq -r '.code // empty')
            if [[ -n "$code_bookmark" ]]; then
                search_dir="$code_bookmark"
                [[ "$verbose" == "true" ]] && echo "Not in bookmarked location, defaulting to Code directory"
            fi
        else
            [[ "$verbose" == "true" ]] && echo "In bookmarked location ($parent_bookmark), searching from current directory: $current_path"
        fi
    fi
    
    local path="$command"  # The project name to search for
    
    # Handle special shortcuts first
    case "$path" in
        "~")
            cd "$HOME"
            echo "🏠 Navigated to Home"
            return
            ;;
        "code")
            if command -v jq >/dev/null 2>&1; then
                local code_path=$(echo "$(get_bookmarks)" | jq -r '.code // empty')
                if [[ -n "$code_path" ]]; then
                    cd "$code_path"
                    echo "💻 Navigated to Code"
                else
                    echo "❌ Code bookmark not found"
                fi
            else
                echo "❌ jq required for bookmark navigation"
            fi
            return
            ;;
        "projects")
            if command -v jq >/dev/null 2>&1; then
                local code_path=$(echo "$(get_bookmarks)" | jq -r '.code // empty')
                if [[ -n "$code_path" ]]; then
                    cd "$code_path/Projects"
                    echo "📂 Navigated to Projects"
                else
                    echo "❌ Code bookmark not found"
                fi
            else
                echo "❌ jq required for bookmark navigation"
            fi
            return
            ;;
    esac
    
    # Try direct path first
    if [[ -d "$path" ]]; then
        cd "$path"
        echo "📁 Navigated to: $path"
        return
    fi
    
    [[ "$verbose" == "true" ]] && echo "Search directory: $search_dir"
    [[ "$verbose" == "true" ]] && echo "Search directory exists: $(test -d "$search_dir" && echo "true" || echo "false")"
    
    if [[ ! -d "$search_dir" ]]; then
        echo "❌ Search directory not found!"
        return 1
    fi
    
    # First, check top-level directories in search location
    [[ "$verbose" == "true" ]] && echo
    [[ "$verbose" == "true" ]] && echo "Listing top-level directories in ${search_dir}:"
    
    local found_match=false
    
    # Check for direct matches in top-level directories
    while IFS= read -r -d '' topdir; do
        local topdir_name=$(basename "$topdir")
        [[ "$verbose" == "true" ]] && echo "  📁 $topdir_name"
        
        if [[ "$topdir_name" == "$path" ]]; then
            cd "$topdir"
            echo "🎯 Found project: $path"
            found_match=true
            break
        fi
        
        if [[ "$topdir_name" == *"$path"* ]]; then
            cd "$topdir"
            echo "🎯 Found similar project: $topdir_name"
            echo "💡 Searched for: $path"
            found_match=true
            break
        fi
    done < <(find "$search_dir" -maxdepth 1 -type d -print0 2>/dev/null)
    
    [[ "$found_match" == "true" ]] && return
    
    # === ADVANCED SEARCH LOGIC ===
    
    if command -v jq >/dev/null 2>&1; then
        local code_bookmark=$(echo "$(get_bookmarks)" | jq -r '.code // empty')
        if [[ "$search_dir" == "$code_bookmark" ]]; then
            [[ "$verbose" == "true" ]] && echo
            [[ "$verbose" == "true" ]] && echo "Searching for '$path' in Projects folder:"
            
            local projects_dir="$search_dir/Projects"
            if [[ -d "$projects_dir" ]]; then
                [[ "$verbose" == "true" ]] && echo "Projects directory exists: ✅"
                
                # Search in Projects subdirectories
                while IFS= read -r -d '' subdir; do
                    local subdir_name=$(basename "$subdir")
                    [[ "$verbose" == "true" ]] && echo "  📂 $subdir_name"
                    
                    while IFS= read -r -d '' innerdir; do
                        local inner_name=$(basename "$innerdir")
                        
                        if [[ "$inner_name" == "$path" ]]; then
                            cd "$innerdir"
                            echo "🎯 Found project: $path in $subdir_name"
                            found_match=true
                            break 2
                        fi
                        
                        [[ "$verbose" == "true" ]] && {
                            local match=""
                            [[ "$inner_name" == "$path" ]] && match=" ⭐ EXACT MATCH!"
                            [[ "$inner_name" == *"$path"* ]] && [[ "$inner_name" != "$path" ]] && match=" ⚡ FUZZY MATCH!"
                            echo "    💼 $inner_name$match"
                        }
                    done < <(find "$subdir" -maxdepth 1 -type d -print0 2>/dev/null)
                    
                    [[ "$found_match" == "true" ]] && break
                done < <(find "$projects_dir" -maxdepth 1 -type d -print0 2>/dev/null)
                
                [[ "$found_match" == "true" ]] && return
                
                # Fuzzy search if no exact match
                while IFS= read -r -d '' subdir; do
                    while IFS= read -r -d '' innerdir; do
                        local inner_name=$(basename "$innerdir")
                        if [[ "$inner_name" == *"$path"* ]]; then
                            cd "$innerdir"
                            echo "🎯 Found similar project: $inner_name in $(basename "$subdir")"
                            echo "💡 Searched for: $path"
                            found_match=true
                            break 2
                        fi
                    done < <(find "$subdir" -maxdepth 1 -type d -print0 2>/dev/null)
                done < <(find "$projects_dir" -maxdepth 1 -type d -print0 2>/dev/null)
                
                [[ "$found_match" == "true" ]] && return
                
                # Nested search
                [[ "$verbose" == "true" ]] && echo "🔍 Trying nested search in Projects..."
                local nested_result=$(search_nested_projects "$path" "$projects_dir" "$verbose")
                if [[ -n "$nested_result" ]]; then
                    cd "$nested_result"
                    local relative_path="${nested_result#$projects_dir/}"
                    echo "🎯 Found nested project: $path"
                    echo "📍 Location: Projects/$relative_path"
                    return
                fi
                
                # Search other directories
                local other_search_dirs=("Applications" "Learning Area" "React Native" "Deblotter" "pass-book")
                
                for dir_name in "${other_search_dirs[@]}"; do
                    local other_search_dir="$search_dir/$dir_name"
                    if [[ -d "$other_search_dir" ]]; then
                        [[ "$verbose" == "true" ]] && echo "Searching in $dir_name..."
                        
                        # Exact matches
                        while IFS= read -r -d '' subdir; do
                            local sub_name=$(basename "$subdir")
                            if [[ "$sub_name" == "$path" ]]; then
                                cd "$subdir"
                                echo "🎯 Found project: $path in $dir_name"
                                found_match=true
                                break 2
                            fi
                        done < <(find "$other_search_dir" -maxdepth 1 -type d -print0 2>/dev/null)
                        
                        [[ "$found_match" == "true" ]] && break
                        
                        # Fuzzy matches
                        while IFS= read -r -d '' subdir; do
                            local sub_name=$(basename "$subdir")
                            if [[ "$sub_name" == *"$path"* ]]; then
                                cd "$subdir"
                                echo "🎯 Found similar project: $sub_name in $dir_name"
                                echo "💡 Searched for: $path"
                                found_match=true
                                break 2
                            fi
                        done < <(find "$other_search_dir" -maxdepth 1 -type d -print0 2>/dev/null)
                        
                        [[ "$found_match" == "true" ]] && break
                        
                        # Nested search
                        [[ "$verbose" == "true" ]] && echo "🔍 Trying nested search in $dir_name..."
                        local nested_result=$(search_nested_projects "$path" "$other_search_dir" "$verbose")
                        if [[ -n "$nested_result" ]]; then
                            cd "$nested_result"
                            local relative_path="${nested_result#$other_search_dir/}"
                            echo "🎯 Found nested project: $path in $dir_name"
                            echo "📍 Location: $dir_name/$relative_path"
                            found_match=true
                            break
                        fi
                    fi
                done
                
                [[ "$found_match" == "true" ]] && return
            fi
        else
            # Search in non-Code bookmarks
            [[ "$verbose" == "true" ]] && echo "Searching for '$path' in current bookmark location:"
            
            # Direct search in current directory
            while IFS= read -r -d '' subdir; do
                local sub_name=$(basename "$subdir")
                if [[ "$sub_name" == "$path" ]] || [[ "$sub_name" == *"$path"* ]]; then
                    cd "$subdir"
                    echo "🎯 Found project: $sub_name"
                    [[ "$sub_name" != "$path" ]] && echo "💡 Searched for: $path"
                    found_match=true
                    break
                fi
            done < <(find "$search_dir" -maxdepth 1 -type d -print0 2>/dev/null)
            
            [[ "$found_match" == "true" ]] && return
            
            # Nested search
            local nested_result=$(search_nested_projects "$path" "$search_dir" "$verbose")
            if [[ -n "$nested_result" ]]; then
                cd "$nested_result"
                local relative_path="${nested_result#$search_dir/}"
                echo "🎯 Found nested project: $path"
                echo "📍 Location: $relative_path"
                return
            fi
        fi
    fi
    
    # If nothing found
    echo "❌ No matches found for: $path"
    echo "💡 Searched in: $search_dir"
    if command -v jq >/dev/null 2>&1; then
        local code_bookmark=$(echo "$(get_bookmarks)" | jq -r '.code // empty')
        if [[ "$search_dir" == "$code_bookmark" ]]; then
            echo "💡 Searched areas:"
            echo "   • Top-level Code directories"
            echo "   • Projects subdirectories (including nested)"
            echo "   • Applications, Learning Area, React Native, etc. (including nested)"
        fi
    fi
    echo "💡 Use 'nav $path -verbose' for detailed search output"
    echo "💡 Use 'nav b <bookmark>' to search in a different location"
}

# ============================================================================
# ENHANCED NAVIGATION SHORTCUTS
# ============================================================================

# Parent directory shortcuts (fast!)
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ~='cd $HOME'

# Navigation aliases
alias z='nav'  # Main navigation function

# ============================================================================
# ENHANCED LOCATION UTILITIES
# ============================================================================

# Enhanced location info function
here() {
    local location="$(pwd)"
    local items=(*)
    local dirs=0
    local files=0
    
    for item in "${items[@]}"; do
        if [[ -d "$item" ]]; then
            ((dirs++))
        elif [[ -f "$item" ]]; then
            ((files++))
        fi
    done
    
    local total_size=0
    if command -v du >/dev/null 2>&1; then
        total_size=$(du -sh . 2>/dev/null | cut -f1)
    fi
    
    echo
    echo "📍 Current Location Info:"
    echo "  📁 Path: $location"
    echo "  📊 Contents: $dirs directories, $files files"
    [[ -n "$total_size" ]] && echo "  💾 Total Size: $total_size"
    
    # Show Git info if in repository
    if git rev-parse --git-dir >/dev/null 2>&1; then
        local git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        echo "  🌳 Git Branch: $git_branch"
    fi
    
    # Show project type
    [[ -f "package.json" ]] && echo "  📦 Node.js Project"
    [[ -f "Cargo.toml" ]] && echo "  🦀 Rust Project"
    [[ -f "requirements.txt" ]] && echo "  🐍 Python Project"
    [[ -f "go.mod" ]] && echo "  🐹 Go Project"
}

# Copy current path to clipboard
copy-pwd() {
    local path="$(pwd)"
    if command -v xclip >/dev/null 2>&1; then
        echo -n "$path" | xclip -selection clipboard
        echo "📋 Copied path: $path"
    elif command -v pbcopy >/dev/null 2>&1; then
        echo -n "$path" | pbcopy
        echo "📋 Copied path: $path"
    else
        echo "📋 Path: $path (clipboard not available)"
    fi
}

# Open current directory in Windows Explorer
open-pwd() {
    local current_path="$(pwd)"
    
    if [[ ! -d "$current_path" ]]; then
        echo "❌ Current directory does not exist: $current_path"
        return 1
    fi
    
    # Convert WSL path to Windows path and open in Explorer
    if command -v explorer.exe >/dev/null 2>&1; then
        local windows_path=$(wslpath -w "$current_path" 2>/dev/null)
        if [[ -n "$windows_path" ]]; then
            explorer.exe "$windows_path"
            echo "📁 Opened File Explorer: $current_path"
        else
            echo "❌ Failed to convert path to Windows format"
        fi
    else
        echo "❌ Windows Explorer not available"
    fi
}

alias op='open-pwd'

# Back to previous directory
back() {
    if [[ -n "$OLDPWD" ]]; then
        cd "$OLDPWD"
        echo "🔙 Navigated back to: $(pwd)"
    else
        echo "❌ No previous directory in history"
    fi
}

alias cd-='back'

# ============================================================================
# ENHANCED FILE OPERATIONS
# ============================================================================

# Enhanced ls functions (avoiding conflicts with existing alias)
lsd-ls() {
    local path="${1:-.}"
    local tree_flag=false
    local depth=0
    
    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            -t|--tree)
                tree_flag=true
                ;;
            -d)
                shift
                depth="$1"
                ;;
        esac
    done
    
    # Check if lsd is available
    if command -v lsd >/dev/null 2>&1; then
        # Smart depth detection if not overridden
        if [[ "$depth" -eq 0 ]]; then
            # Check if we're dealing with node_modules or inside a Node.js project
            if [[ "$path" == *"node_modules"* ]] || [[ -f "$path/package.json" ]] || [[ -d "$path/node_modules" ]]; then
                depth=2
            else
                depth=3
            fi
        fi
        
        if [[ "$tree_flag" == "true" ]]; then
            echo "🌳 Tree view (depth: $depth)"
            lsd --tree --depth="$depth" --group-dirs=first --icon=always --color=always "$path"
        else
            echo "📁 Directory listing"
            lsd --group-dirs=first --icon=always --color=always "$path"
        fi
    else
        # Fallback to regular ls
        if [[ "$tree_flag" == "true" ]]; then
            if command -v tree >/dev/null 2>&1; then
                tree -L "$depth" "$path"
            else
                echo "⚠️ lsd and tree not found. Using standard ls"
                command ls -la --color=always "$path"
            fi
        else
            command ls -la --color=always "$path"
        fi
    fi
}

# Create aliases for enhanced ls functionality
alias lsl='lsd-ls'           # Enhanced ls with lsd
alias lst='lsd-ls -t'        # Tree view
alias lsb='lsd-ls'           # Beautiful ls (same as lsl)

# Enhanced file utilities
which() {
    command -v "$1"
}

touch() {
    local file="$1"
    if [[ -z "$file" ]]; then
        echo "❌ Usage: touch <filename>"
        return 1
    fi
    command touch "$file"
    echo "📄 Created file: $file"
}

mkdir() {
    local dir_name="$*"
    
    # Check if name is empty or whitespace only
    if [[ -z "$dir_name" ]] || [[ "$dir_name" =~ ^[[:space:]]*$ ]]; then
        echo "❌ Directory name cannot be empty or whitespace only"
        return 1
    fi
    
    # Check for leading or trailing spaces
    if [[ "$dir_name" =~ ^[[:space:]] ]] || [[ "$dir_name" =~ [[:space:]]$ ]]; then
        echo "❌ Directory name cannot start or end with spaces"
        return 1
    fi
    
    # Create the directory
    if command mkdir -p "$dir_name"; then
        echo "📁 Directory '$dir_name' created successfully"
    else
        echo "❌ Failed to create directory '$dir_name'"
        return 1
    fi
}

# ============================================================================
# COMPREHENSIVE HELP SYSTEM
# ============================================================================

wsl_help() {
    local help_text=$(cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║                     🐧 WSL ENHANCED PROFILE REFERENCE                       ║
║                        Navigation & Bookmark System                          ║
╚══════════════════════════════════════════════════════════════════════════════╝

┌─ 🧭 SMART NAVIGATION & BOOKMARKS ────────────────────────────────────────────┐
│  🎯 CORE NAVIGATION:                                                         │
│  nav <project>       → smart project search in ~/Code and bookmarked dirs    │
│  nav -verbose        → detailed search output for troubleshooting            │
│  z <project>         → alias for nav                                         │
│                                                                              │
│  🔖 BOOKMARK MANAGEMENT:                                                     │
│  nav b <bookmark>    → navigate to bookmark                                  │
│  nav create-b <name> → create bookmark (current dir)                         │
│  nav cb <name>       → shorthand for create-b                                │
│  nav delete-b <name> → delete bookmark with confirmation                     │
│  nav db <name>       → shorthand for delete-b                                │
│  nav rename-b <old> <new> → rename existing bookmark                         │
│  nav rb <old> <new>  → shorthand for rename-b                                │
│  nav list            → interactive bookmark manager                          │
│  nav l               → shorthand for list                                    │
│                                                                              │
│  ⬆️ PARENT NAVIGATION:                                                       │
│  ..                  → go up one level                                       │
│  ...                 → go up two levels                                      │
│  ....                → go up three levels                                    │
│  ~                   → go to home directory                                  │
│                                                                              │
│  📍 LOCATION UTILITIES:                                                      │
│  here                → detailed info about current directory                 │
│  copy-pwd            → copy current path to clipboard                        │
│  open-pwd            → open current directory in Windows Explorer            │
│  op                  → alias for open-pwd                                    │
│  back                → go to previous directory                              │
│  cd-                 → alias for back                                        │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 📂 ENHANCED FILE OPERATIONS ────────────────────────────────────────────────┐
│  📋 DIRECTORY LISTING:                                                       │
│  ls [path]           → standard ls (keeps your original)                     │
│  lsl [path]          → beautiful directory listing with lsd                  │
│  lst [path]          → tree view with smart depth detection                  │
│  lsb [path]          → beautiful ls (same as lsl)                            │
│  la                  → list all files including hidden                       │
│  ll                  → long list format with details                         │
│                                                                              │
│  📄 FILE VIEWING & UTILITIES:                                                │
│  cat <file>          → display file contents                                 │
│  grep <pattern>      → search text in files                                  │
│  less <file>         → page through file content                             │
│  which <cmd>         → show command location                                 │
│  touch <file>        → create new empty file                                 │
│  mkdir <dir>         → create new directory                                  │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ ⚙️  SYSTEM MANAGEMENT ──────────────────────────────────────────────────────┐
│  get_wsl_profile_version → show WSL profile version and status                │
│  wsl_recovery        → recovery and diagnostics menu                         │
│  wsl_help            → show this help menu                                   │
│                                                                              │
│  🔧 DEPENDENCY MANAGEMENT:                                                   │
│  initialize_dependencies → manually check and install dependencies           │
│  check_dependency_status → show which tools are installed                    │
└──────────────────────────────────────────────────────────────────────────────┘

┌─ 🚀 KEY FEATURES ────────────────────────────────────────────────────────────┐
│  🔄 Auto-Installation    → Automatically installs missing dependencies       │
│  🔖 Persistent Bookmarks → Saved across sessions in JSON file               │
│  🎯 Smart Project Search → Fuzzy search with nested directory support        │
│  🌟 Beautiful Prompt     → Starship prompt with Git integration              │
│  📋 Clipboard Integration → Copy paths and results to clipboard              │
│  🛡️  Safety Checks       → Prevents accidental operations                    │
│  🎨 Consistent UI        → Emoji indicators and color schemes                │
│  ⚡ Context-Aware        → Adapts to current directory and project type      │
│  🔧 Self-Healing         → Recovery tools and dependency management          │
└──────────────────────────────────────────────────────────────────────────────┘

EOF
)
    
    echo "$help_text"
}

# ============================================================================
# INITIALIZATION & STARTUP
# ============================================================================

# Run initialization (only once per day to avoid slow startup)
if [[ "$-" == *i* ]]; then  # Only in interactive shells
    # Initialize dependencies if needed
    initialize_dependencies
    
    # Check for profile updates
    check_wsl_profile_updates
    
    # Initialize starship if available (override default PS1)
    if command -v starship >/dev/null 2>&1; then
        eval "$(starship init bash)"
    fi
    
    # Initialize zoxide if available
    if command -v zoxide >/dev/null 2>&1; then
        eval "$(zoxide init bash)"
    fi
    
    # Add local bin to PATH
    export PATH="$HOME/.local/bin:$PATH"
    
    # Initialize bookmarks
    initialize_default_bookmarks
    
    # Welcome message (only show if dependencies were just installed)
    if [[ ! -f "$HOME/.wsl_init_check" ]] || [[ "$(cat "$HOME/.wsl_init_check" 2>/dev/null)" != "$(date +%Y-%m-%d)" ]]; then
        echo "🚀 WSL Enhanced Profile loaded! Type 'wsl_help' for help" >&2
    fi
fi