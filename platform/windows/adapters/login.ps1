# ==============================================================================
# PowerFlow — Login-Launch Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/login.ps1
# Purpose  : Report, honestly, that Windows has no login-shell hook to manage
# Contract : Get-LoginLaunchState, Enable-LoginLaunch, Disable-LoginLaunch
# Depends  : none
# ==============================================================================
#
# The whole "auto-login" problem is a Linux one: there, the login shell is bash and
# PowerFlow (a PowerShell profile) is not loaded until `pwsh` runs, so a ~/.bashrc
# hook is needed. On Windows there is no such split — every PowerShell 7 session
# sources $PROFILE automatically, so PowerFlow is ALWAYS loaded when pwsh starts.
# There is nothing to enable; this adapter says so rather than pretending otherwise
# (the same honesty as perms.ps1 returning $null for POSIX modes on Windows).
# ==============================================================================

# 'always' — a distinct state from Linux's 'on'/'off', so the component can explain
# the Windows semantics rather than claim a hook it did not write.
function Get-LoginLaunchState { return 'always' }

# Nothing to do — PowerFlow already loads on every pwsh start. Report success so a
# caller's "make sure it auto-loads" intent is satisfied.
function Enable-LoginLaunch { return $true }

# There is no hook to remove. Refuse rather than imply we disabled something.
function Disable-LoginLaunch { return $false }
