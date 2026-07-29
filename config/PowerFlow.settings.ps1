# ==============================================================================
# PowerFlow — Settings
# ==============================================================================
# Domain   : Core
# File     : config/PowerFlow.settings.ps1
# Purpose  : Declares all top-level configuration variables used across the profile
# Functions: (none — variables only)
# Depends  : none
# ==============================================================================

# Version management
$script:POWERFLOW_VERSION = "3.15.0"
$script:POWERFLOW_REPO = "Syntax-Read3r/powerflow"
$script:CHECK_PROFILE_UPDATES = $true
$script:CHECK_DEPENDENCIES = $true
$script:CHECK_UPDATES = $true

# Database credentials configuration
# Update these values according to your database setup
$script:DB_USERNAME = "postgres"
$script:DB_PASSWORD = "password"

# Suppress progress bars for faster installation
$ProgressPreference = 'SilentlyContinue'














