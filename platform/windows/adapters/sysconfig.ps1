# ==============================================================================
# PowerFlow — System Config Adapter (Windows)
# ==============================================================================
# Domain   : Platform / Windows
# File     : platform/windows/adapters/sysconfig.ps1
# Purpose  : Declare, honestly, that pwsh-config's systemd settings don't apply here
# Contract : Test-SysConfigSupported, Get-SysConfigOptions, Get-SysConfigChoices,
#            Set-SysConfig
# Depends  : none
# ==============================================================================
#
# pwsh-config configures Linux system settings via systemd (localectl/timedatectl).
# Windows has no systemd; keyboard, timezone, locale and hostname live in Windows
# Settings and in separate cmdlets (Set-TimeZone, Rename-Computer, …) with entirely
# different models. Rather than fake a menu that can't act, this reports "unsupported"
# and the component points at Windows Settings — the same honesty as perms.ps1.
# ==============================================================================

function Test-SysConfigSupported { return $false }
function Get-SysConfigOptions    { return @() }
function Get-SysConfigChoices    { param([string]$Key)                return @() }
function Set-SysConfig           { param([string]$Key, [string]$Value) return $false }
