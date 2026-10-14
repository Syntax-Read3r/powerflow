# ==============================================================================
# PowerFlow — Stale GitHub Repository Review
# Domain   : GitHub
# File     : components/github/review.ps1
# Purpose  : Read-only oldest-first review; age is evidence, not a redundancy verdict
# Functions: Show-PFGitHubReview
# Depends  : repositories.ps1, browser.ps1
# ==============================================================================

function Show-PFGitHubReview {
    param([int]$Count = [int]::MaxValue, [string]$Token, [string]$OlderThan, [switch]$Pages)
    Show-PFGitHubBrowser -Count $Count -Token $Token -Oldest -OlderThan $OlderThan -Pages:$Pages -Review
}
