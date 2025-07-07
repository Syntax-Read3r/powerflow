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

# ============================================================================
# 🎯 USER CONFIGURATION - EASILY CUSTOMIZABLE SETTINGS
# ============================================================================

# Starting directory - Change this to your preferred startup location
# Examples: 
#   export WSL_START_DIRECTORY="/mnt/c/Users/_munya/Code"           # Windows Code folder
#   export WSL_START_DIRECTORY="$HOME/projects"                    # Linux projects folder  
#   export WSL_START_DIRECTORY="/mnt/c/Users/_munya/Documents"     # Windows Documents
#   export WSL_START_DIRECTORY=""                                  # Disable auto-navigation (stay in $HOME)
export WSL_START_DIRECTORY="/mnt/c/Users/_munya/Code"

# Profile behavior settings
export WSL_PROFILE_VERSION="1.0.0"
export CHECK_DEPENDENCIES=true          # Auto-install missing tools
export CHECK_UPDATES=true               # Check for profile updates
export SHOW_STARTUP_MESSAGE=true        # Show welcome message on first load

# Enhanced color support and profile version
export TERM=xterm-256color
export CLICOLOR=1

# Suppress progress bars for faster installation
export DEBIAN_FRONTEND=noninteractive

# ============================================================================
# WINDOWS TERMINAL DETECTION & INTEGRATION
# ============================================================================

# Check if we're running in Windows Terminal
is_windows_terminal() {
    [[ -n "$WT_SESSION" ]] || [[ -n "$WT_PROFILE_ID" ]]
}

# ============================================================================
# ENHANCED PREDICTIVE TEXT & READLINE CONFIGURATION
# ============================================================================

# Enhanced readline configuration for better predictive text
if [[ -f /etc/inputrc ]]; then
    bind -f /etc/inputrc
fi

# Advanced readline configuration for PowerShell-like experience
bind 'set show-all-if-ambiguous on'           # Show completions immediately
bind 'set completion-ignore-case on'          # Case-insensitive completion
bind 'set completion-map-case on'             # Treat - and _ as equivalent
bind 'set show-all-if-unmodified on'          # Show completions without bell
bind 'set menu-complete-display-prefix on'    # Show common prefix in menu
bind 'set colored-stats on'                   # Color completion stats
bind 'set visible-stats on'                   # Show file type indicators
bind 'set mark-symlinked-directories on'      # Mark symlinked directories
bind 'set colored-completion-prefix on'       # Color the completion prefix
bind 'set menu-complete-display-prefix on'    # Display prefix in menu completion

# History-based predictive autocompletion (like PowerShell)
bind '"\e[A": history-search-backward'        # Up arrow for history search
bind '"\e[B": history-search-forward'         # Down arrow for history search
bind '"\C-p": history-search-backward'        # Ctrl+P for history search
bind '"\C-n": history-search-forward'         # Ctrl+N for history search

# Enhanced tab completion behavior
bind 'TAB:menu-complete'                      # Tab cycles through completions
bind '"\e[Z": menu-complete-backward'         # Shift+Tab cycles backward

# Better history handling
export HISTSIZE=10000                         # Increased history size
export HISTFILESIZE=20000                     # Increased history file size
export HISTCONTROL=ignoreboth:erasedups       # Ignore duplicates and spaces
export HISTTIMEFORMAT='%F %T '                # Add timestamps to history
shopt -s histappend                            # Append to history file
shopt -s cmdhist                               # Store multi-line commands as one
shopt -s histreedit                            # Allow re-editing of failed history substitution
shopt -s histverify                            # Verify history expansion before executing

# Immediately save history after each command (for multi-session sync)
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a; history -c; history -r"

# ============================================================================
# FZF INTEGRATION & CONFIGURATION
# ============================================================================

# FZF configuration for enhanced fuzzy finding
export FZF_DEFAULT_OPTS='
  --height 40% 
  --layout=reverse 
  --border
  --margin=1 
  --padding=1
  --color=fg:#e4e4e4,bg:#1e1e1e,hl:#569cd6
  --color=fg+:#ffffff,bg+:#333333,hl+:#4ec9b0
  --color=info:#ce9178,prompt:#4ec9b0,pointer:#f44747
  --color=marker:#f44747,spinner:#ce9178,header:#569cd6
  --prompt="🔍 "
  --pointer="→"
  --marker="✓"
  --bind="ctrl-u:preview-up,ctrl-d:preview-down"
  --bind="ctrl-/:toggle-preview"
  --bind="alt-up:preview-page-up,alt-down:preview-page-down"
'

# FZF for file search (Ctrl+T)
export FZF_CTRL_T_OPTS="
  --preview 'if [ -d {} ]; then lsd --tree --depth=2 --color=always {} 2>/dev/null || ls -la {} 2>/dev/null; else bat --style=numbers --color=always {} 2>/dev/null || cat {} 2>/dev/null; fi'
  --preview-window=right:50%
  --bind='ctrl-/:toggle-preview'
  --header='📁 Files & Directories | Ctrl+T: Select | Ctrl+/: Toggle Preview'
"

# FZF for command history (Ctrl+R) 
export FZF_CTRL_R_OPTS="
  --preview 'echo {}'
  --preview-window=down:3:wrap
  --header='📚 Command History | Ctrl+R: Select | Enter: Execute'
  --color=header:italic
"

# FZF for directory navigation (Alt+C)
export FZF_ALT_C_OPTS="
  --preview 'lsd --tree --depth=2 --color=always {} 2>/dev/null || ls -la {} 2>/dev/null'
  --preview-window=right:50%
  --header='📂 Directory Navigation | Alt+C: Select | Ctrl+/: Toggle Preview'
"

# Initialize FZF key bindings and completion
setup_fzf_integration() {
    # Check if fzf is available
    if command -v fzf >/dev/null 2>&1; then
        # Try to source fzf key bindings from common locations
        local fzf_keybindings=""
        local fzf_completion=""
        
        # Common locations for fzf files
        local fzf_locations=(
            "/usr/share/fzf"
            "/usr/share/doc/fzf/examples"
            "$HOME/.fzf"
            "/opt/fzf"
        )
        
        for location in "${fzf_locations[@]}"; do
            if [[ -f "$location/key-bindings.bash" ]]; then
                fzf_keybindings="$location/key-bindings.bash"
            fi
            if [[ -f "$location/completion.bash" ]]; then
                fzf_completion="$location/completion.bash"
            fi
        done
        
        # Source the files if found
        if [[ -n "$fzf_keybindings" ]]; then
            source "$fzf_keybindings"
            echo "🎯 FZF key bindings loaded: Ctrl+T (files), Ctrl+R (history), Alt+C (dirs)" >&2
        else
            echo "⚠️  FZF key bindings not found. Manual setup required." >&2
        fi
        
        if [[ -n "$fzf_completion" ]]; then
            source "$fzf_completion"
        fi
        
    else
        echo "⚠️  FZF not found. Will be installed on next profile load." >&2
    fi
}

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
        "xdotool:xdotool"
    )
    
    local optional_tools=(
        "starship:starship"
        "zoxide:zoxide"
        "lsd:lsd"
        "bat:bat"
    )
    
    local missing_required=()
    local missing_optional=()
    
    # Check required tools
    for tool_info in "${required_tools[@]}"; do
        local tool_name="${tool_info%%:*}"
        local command_name="${tool_info##*:}"
        
        if ! command -v "$command_name" >/dev/null 2>&1; then
            missing_required+=("$tool_info")
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
    
    # Prompt for required tools installation
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        echo "" >&2
        echo "⚠️  Missing required tools for full functionality:" >&2
        for tool_info in "${missing_required[@]}"; do
            local tool_name="${tool_info%%:*}"
            echo "   ❌ $tool_name" >&2
        done
        echo "" >&2
        echo "🔧 These tools enable:" >&2
        echo "   • fzf: Fuzzy file/history search (Ctrl+T, Ctrl+R, Alt+C)" >&2
        echo "   • xdotool: Terminal tab switching (next-t, prev-t)" >&2
        echo "   • jq: Bookmark management" >&2
        echo "   • xclip: Clipboard integration" >&2
        echo "" >&2
        
        read -p "📦 Install required tools now? (y/n): " install_required >&2
        
        if [[ "$install_required" =~ ^[Yy]$ ]]; then
            echo "🔄 Installing required tools..." >&2
            echo "   Updating package list..." >&2
            if sudo apt update >/dev/null 2>&1; then
                local install_success=true
                for tool_info in "${missing_required[@]}"; do
                    local tool_name="${tool_info%%:*}"
                    install_tool "$tool_name" || install_success=false
                done
                
                if [[ "$install_success" == "true" ]]; then
                    echo "✅ Required tools installed successfully!" >&2
                else
                    echo "⚠️  Some required tools failed to install. Check output above." >&2
                fi
            else
                echo "❌ Failed to update package list. Installation skipped." >&2
            fi
        else
            echo "⏭️  Required tools installation skipped." >&2
            echo "💡 Run 'force_install_deps' anytime to install them later." >&2
        fi
    fi
    
    # Prompt for optional tools installation
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        echo "" >&2
        echo "🛠️  Optional tools available for enhanced experience:" >&2
        for tool_info in "${missing_optional[@]}"; do
            local tool_name="${tool_info%%:*}"
            echo "   📦 $tool_name" >&2
        done
        echo "" >&2
        echo "🌟 These tools provide:" >&2
        echo "   • starship: Beautiful prompt with Git info" >&2
        echo "   • lsd: Modern directory listings with icons" >&2
        echo "   • bat: Syntax-highlighted file preview" >&2
        echo "   • zoxide: Smart directory jumping" >&2
        echo "" >&2
        
        read -p "🎨 Install optional tools for enhanced experience? (y/n): " install_optional >&2
        
        if [[ "$install_optional" =~ ^[Yy]$ ]]; then
            echo "🔄 Installing optional tools..." >&2
            local install_success=true
            for tool_info in "${missing_optional[@]}"; do
                local tool_name="${tool_info%%:*}"
                install_optional_tool "$tool_name" || install_success=false
            done
            
            if [[ "$install_success" == "true" ]]; then
                echo "✅ Optional tools installed successfully!" >&2
            else
                echo "⚠️  Some optional tools failed to install. Check output above." >&2
            fi
        else
            echo "⏭️  Optional tools installation skipped." >&2
            echo "💡 Run 'force_install_deps' anytime to install them later." >&2
        fi
    fi
    
    # Show completion message
    if [[ ${#missing_required[@]} -gt 0 ]] || [[ ${#missing_optional[@]} -gt 0 ]]; then
        echo "" >&2
        echo "🔄 Restart your terminal or run 'source ~/.bashrc' to use new tools" >&2
        echo "💡 Type 'wsl_help' to see all available commands" >&2
    fi
}

# Install a required tool
install_tool() {
    local tool="$1"
    
    echo "   Installing $tool..." >&2
    
    case "$tool" in
        "curl"|"wget"|"git"|"jq"|"fzf"|"xclip"|"xdotool")
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
        "bat")
            if sudo apt install -y bat >/dev/null 2>&1; then
                echo "   ✅ bat installed" >&2
                # Create alias for bat if it's installed as batcat
                if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
                    echo "alias bat='batcat'" >> ~/.bash_aliases
                fi
            else
                echo "   ❌ Failed to install bat" >&2
            fi
            ;;
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

# Force install dependencies function
force_install_deps() {
    echo "🔄 Force installing all dependencies..." >&2
    rm -f ~/.wsl_init_check
    initialize_dependencies
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

# Main nav function (simplified version for core functionality)
nav() {
    local command="$1"
    local param1="$2"
    local param2="$3"
    
    # Initialize bookmarks on first run
    initialize_default_bookmarks
    
    # If no command provided, show help
    if [[ -z "$command" ]]; then
        echo "💡 Navigation Commands:"
        echo "═════════════════════"
        echo "  nav <project-name>           Navigate to project"
        echo "  nav b <bookmark>             Navigate to bookmark"
        echo "  nav create-b <name> | cb     Create bookmark (current dir)"
        echo "  nav delete-b <name> | db     Delete bookmark"
        echo "  nav list | l                 Show bookmarks"
        return
    fi
    
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
        list|l)
            if ! command -v jq >/dev/null 2>&1; then
                echo "❌ Error: jq is required for bookmark management"
                return 1
            fi
            
            local bookmarks=$(get_bookmarks)
            echo "📚 Available Bookmarks:"
            echo "═══════════════════════"
            echo "$bookmarks" | jq -r 'to_entries[] | "\(.key) → \(.value)"' | sort
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
                return 1
            fi
        else
            echo "❌ Bookmark '$param1' not found"
            return 1
        fi
    fi
    
    # Simple project search - check if it's a direct path first
    if [[ -d "$command" ]]; then
        cd "$command"
        echo "📁 Navigated to: $command"
        return
    fi
    
    # Search in Code directory if available
    if command -v jq >/dev/null 2>&1; then
        local code_path=$(echo "$(get_bookmarks)" | jq -r '.code // empty')
        if [[ -n "$code_path" ]] && [[ -d "$code_path" ]]; then
            # Look for project in code directory
            local found_path=""
            while IFS= read -r -d '' dir; do
                local dir_name=$(basename "$dir")
                if [[ "$dir_name" == "$command" ]] || [[ "$dir_name" == *"$command"* ]]; then
                    found_path="$dir"
                    break
                fi
            done < <(find "$code_path" -maxdepth 2 -type d -print0 2>/dev/null)
            
            if [[ -n "$found_path" ]]; then
                cd "$found_path"
                echo "🎯 Found project: $(basename "$found_path")"
                return
            fi
        fi
    fi
    
    echo "❌ No matches found for: $command"
}

# ============================================================================
# ENHANCED NAVIGATION SHORTCUTS
# ============================================================================

# Parent directory shortcuts
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
    
    echo
    echo "📍 Current Location Info:"
    echo "  📁 Path: $location"
    echo "  📊 Contents: $dirs directories, $files files"
    
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
    else
        echo "📋 Path: $path (clipboard not available)"
    fi
}

# Open current directory in Windows Explorer
open-pwd() {
    local current_path="$(pwd)"
    
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

# ============================================================================
# ENHANCED WINDOWS TERMINAL TAB MANAGEMENT
# ============================================================================

# Enhanced send-keys function with better error handling
send-keys() {
    local keys="$1"
    
    # First try PowerShell SendKeys if in Windows Terminal (more reliable)
    if is_windows_terminal && command -v powershell.exe >/dev/null 2>&1; then
        case "$keys" in
            "^{TAB}")
                if powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^{TAB}')" 2>/dev/null; then
                    return 0
                fi
                ;;
            "^+{TAB}")
                if powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^+{TAB}')" 2>/dev/null; then
                    return 0
                fi
                ;;
            "^+w")
                if powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^+w')" 2>/dev/null; then
                    return 0
                fi
                ;;
        esac
    fi
    
    # Fallback to xdotool
    if command -v xdotool >/dev/null 2>&1; then
        case "$keys" in
            "^{TAB}")
                xdotool key ctrl+Tab
                ;;
            "^+{TAB}")
                xdotool key ctrl+shift+Tab
                ;;
            "^+w")
                xdotool key ctrl+shift+w
                ;;
            *)
                echo "⚠️  Unsupported key combination: $keys" >&2
                return 1
                ;;
        esac
    else
        echo "⚠️  No automation tools available. Use manual keyboard shortcuts:" >&2
        case "$keys" in
            "^{TAB}")
                echo "   Press Ctrl+Tab to switch to next tab" >&2
                ;;
            "^+{TAB}")
                echo "   Press Ctrl+Shift+Tab to switch to previous tab" >&2
                ;;
            "^+w")
                echo "   Press Ctrl+Shift+W to close current tab" >&2
                ;;
        esac
        return 1
    fi
}

# Switch to next terminal tab (simplified and more reliable)
next-t() {
    echo "➡️ Switching to next tab..." >&2
    if send-keys "^{TAB}"; then
        echo "✅ Switched to next tab" >&2
    else
        echo "💡 Use Ctrl+Tab to switch to next tab manually" >&2
    fi
}

# Alias for next-t to match the goal of getting "next-tab" working
alias next-tab='next-t'

# Switch to previous terminal tab
prev-t() {
    echo "⬅️ Switching to previous tab..." >&2
    if send-keys "^+{TAB}"; then
        echo "✅ Switched to previous tab" >&2
    else
        echo "💡 Use Ctrl+Shift+Tab to switch to previous tab manually" >&2
    fi
}

# Close current terminal tab
close-ct() {
    echo "🗑️ Closing current tab..." >&2
    if send-keys "^+w"; then
        echo "✅ Tab closed" >&2
    else
        echo "💡 Use Ctrl+Shift+W to close the current tab manually" >&2
    fi
}

# Switch to specific terminal tab by index (1-9) - simplified
open-t() {
    local index="$1"
    
    if [[ -z "$index" ]] || [[ ! "$index" =~ ^[1-9]$ ]]; then
        echo "❌ Tab index must be between 1-9" >&2
        echo "💡 Usage: open-t <1-9>" >&2
        return 1
    fi
    
    echo "🔀 Switching to tab $index..." >&2
    
    # Try PowerShell first if in Windows Terminal
    if is_windows_terminal && command -v powershell.exe >/dev/null 2>&1; then
        if powershell.exe -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('%$index')" 2>/dev/null; then
            echo "✅ Switched to tab $index" >&2
            return 0
        fi
    fi
    
    # Fallback to xdotool
    if command -v xdotool >/dev/null 2>&1; then
        xdotool key alt+$index
        echo "✅ Switched to tab $index" >&2
    else
        echo "⚠️ Press Alt+$index manually to switch to tab $index" >&2
    fi
}

# Open new Windows Terminal tab
open-nt() {
    local shell="${1:-pwsh}"
    local current_path="$(pwd)"
    
    # Convert WSL path to Windows path for PowerShell tabs
    local windows_path=""
    if command -v wslpath >/dev/null 2>&1; then
        windows_path=$(wslpath -w "$current_path" 2>/dev/null)
    fi
    
    case "${shell,,}" in
        pwsh|powershell|ps|p)
            echo "💻 Opening PowerShell tab..." >&2
            if [[ -n "$windows_path" ]]; then
                if wt -w 0 nt -p "PowerShell" --startingDirectory "$windows_path" 2>/dev/null; then
                    echo "✅ Opened PowerShell tab in: $windows_path" >&2
                else
                    echo "❌ Failed to open PowerShell tab" >&2
                fi
            else
                wt -w 0 nt -p "PowerShell" 2>/dev/null
            fi
            ;;
        cmd|command)
            echo "⚡ Opening Command Prompt tab..." >&2
            if [[ -n "$windows_path" ]]; then
                wt -w 0 nt -p "Command Prompt" --startingDirectory "$windows_path" 2>/dev/null
                echo "✅ Opened Command Prompt tab in: $windows_path" >&2
            else
                wt -w 0 nt -p "Command Prompt" 2>/dev/null
            fi
            ;;
        ubuntu|u|wsl|bash)
            echo "🐧 Opening Ubuntu WSL tab..." >&2
            if wt -w 0 nt -p "Ubuntu-20.04" 2>/dev/null; then
                echo "✅ Opened Ubuntu tab" >&2
                echo "📁 To navigate to current directory, run: cd '$current_path'" >&2
            else
                echo "❌ Failed to open Ubuntu tab" >&2
            fi
            ;;
        *)
            echo "❌ Unknown shell: $shell" >&2
            echo "💡 Supported shells: pwsh|p, cmd, ubuntu|u" >&2
            return 1
            ;;
    esac
}

# Install xdotool for enhanced terminal control
install-xdotool() {
    echo "📦 Installing xdotool for terminal tab control..." >&2
    
    if sudo apt update && sudo apt install -y xdotool; then
        echo "✅ xdotool installed successfully!" >&2
        echo "🎯 You can now use next-t, prev-t, and other tab functions" >&2
    else
        echo "❌ Failed to install xdotool" >&2
        echo "💡 Tab functions will show manual instructions instead" >&2
    fi
}

# ============================================================================
# ENHANCED FILE OPERATIONS
# ============================================================================

# Enhanced ls functions
lsd-ls() {
    local path="${1:-.}"
    
    # Check if lsd is available
    if command -v lsd >/dev/null 2>&1; then
        lsd --group-dirs=first --icon=always --color=always "$path"
    else
        command ls -la --color=always "$path"
    fi
}

# Create aliases for enhanced ls functionality
alias lsl='lsd-ls'           # Enhanced ls with lsd
alias lst='lsd --tree --depth=3'        # Tree view
alias lsb='lsd-ls'           # Beautiful ls (same as lsl)

# ============================================================================
# COMPREHENSIVE HELP SYSTEM
# ============================================================================

wsl_help() {
    echo
    echo "🐧 WSL Enhanced Profile - Quick Reference"
    echo "═════════════════════════════════════════"
    echo
    echo "🧭 NAVIGATION:"
    echo "  nav <project>        → smart project search"
    echo "  nav b <bookmark>     → navigate to bookmark"
    echo "  nav create-b <name>  → create bookmark"
    echo "  nav list             → show bookmarks"
    echo "  ..  ...  ....        → go up directories"
    echo
    echo "🪟 WINDOWS TERMINAL TABS:"
    echo "  next-t               → switch to next tab"
    echo "  next-tab             → alias for next-t"
    echo "  prev-t               → switch to previous tab"
    echo "  open-t <1-9>         → switch to specific tab"
    echo "  close-ct             → close current tab"
    echo "  open-nt <shell>      → open new tab (pwsh|cmd|ubuntu)"
    echo
    echo "📁 UTILITIES:"
    echo "  here                 → current directory info"
    echo "  copy-pwd             → copy current path"
    echo "  open-pwd             → open in Windows Explorer"
    echo "  lsl                  → beautiful directory listing"
    echo "  lst                  → tree view"
    echo
    echo "🔍 FZF FUZZY FINDER:"
    echo "  Ctrl+T               → fuzzy file picker"
    echo "  Ctrl+R               → fuzzy history search"
    echo "  Alt+C                → fuzzy directory navigation"
    echo
    echo "⚙️ SYSTEM:"
    echo "  force_install_deps   → install missing tools"
    echo "  install-xdotool      → install tab switching tool"
    echo
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
    
    # Initialize FZF integration
    setup_fzf_integration
    
    # Add local bin to PATH
    export PATH="$HOME/.local/bin:$PATH"
    
    # Initialize bookmarks
    initialize_default_bookmarks
    
    # Auto-navigate to preferred starting directory when starting from HOME
    if [[ "$(pwd)" == "$HOME" ]] && [[ -n "$WSL_START_DIRECTORY" ]] && [[ -d "$WSL_START_DIRECTORY" ]]; then
        cd "$WSL_START_DIRECTORY"
        echo "🏠 Auto-navigated to $(basename "$WSL_START_DIRECTORY")" >&2
    fi
fi