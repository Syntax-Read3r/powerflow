# ==============================================================================
# PowerFlow — GitHub Credentials Adapter (Linux)
# Domain   : Platform / Linux
# File     : platform/linux/adapters/github.ps1
# Purpose  : Explicitly report that the legacy Windows credential store is unavailable
# Contract : Get-GitHubSavedToken, Set-GitHubSavedToken, Remove-GitHubSavedToken, Show-GitHubTokenStatus
# Depends  : none; components resolve GITHUB_TOKEN before the saved-token adapter
# ==============================================================================

function Get-GitHubSavedToken { return $null }
function Set-GitHubSavedToken {
    param([string]$Token)
    Write-Host 'No persistent GitHub token store is configured on Linux. Use GITHUB_TOKEN for this session.' -ForegroundColor Yellow
    return $false
}
function Remove-GitHubSavedToken {
    Write-Host 'No saved GitHub token store on Linux. GITHUB_TOKEN, if set, is unchanged.' -ForegroundColor DarkGray
}
function Show-GitHubTokenStatus {
    Write-Host 'No saved GitHub token store on Linux. Use GITHUB_TOKEN for this session.' -ForegroundColor DarkGray
}
