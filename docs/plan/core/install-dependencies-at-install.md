# Plan — Install Dependencies at Install Time

> **Status: Implemented** — Approved and completed 2026-05-19.

## Goal

`install.ps1` installs Scoop and all required tools (starship, fzf, zoxide, lsd, git)
during the installation run, so the environment is fully functional the moment PowerFlow
is installed — no dependency on first profile load.

## Scope

**Changing:**
- `install.ps1` — add Scoop bootstrap and tool installation after profile download
- `components/core/dependencies.ps1` — minor: `Initialize-Dependencies` should become
  a no-op (or quick "already installed" check) when all tools are present, to avoid
  redundant install attempts on profile load

**Not changing:**
- `Microsoft.PowerShell_profile.ps1` — still calls `Initialize-Dependencies` as a
  safety net for environments where `install.ps1` was not used
- `components/core/dependencies.ps1` — tool list (`$requiredTools`) stays as the
  canonical source; `install.ps1` will reference the same set of tools

## Chunks

### Chunk 1 — `install.ps1`: Bootstrap Scoop
After the profile download succeeds, add:
```powershell
# Install Scoop if missing
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "📦 Installing Scoop package manager..." -ForegroundColor Yellow
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
}
```

### Chunk 2 — `install.ps1`: Install required tools via Scoop
After Scoop is confirmed:
```powershell
$tools = @('starship', 'fzf', 'zoxide', 'lsd', 'git')
foreach ($tool in $tools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "   Installing $tool..." -ForegroundColor DarkGray
        scoop install $tool *>$null
        Write-Host "   ✅ $tool installed" -ForegroundColor Green
    }
}
# Refresh PATH so newly installed tools are immediately available
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH","User")
```

### Chunk 3 — `install.ps1`: Final message update
Update the completion message to confirm tools were installed, not just the profile.

### Chunk 4 — Log
Create `docs/log/2026/May/19 Tue/log-4.md` recording this change.

## Rollback

`install.ps1` is idempotent — running it again is safe. If tool installation fails,
the profile is already downloaded and `Initialize-Dependencies` on first load still
installs any missing tools. No data loss risk.

## Testing

1. Simulate a fresh install: uninstall fzf (`scoop uninstall fzf`), run `install.ps1`
2. After install completes, verify: `Get-Command fzf`, `Get-Command starship`, etc.
3. Reload profile — `Initialize-Dependencies` should output "already installed" or skip
   silently (no duplicate install attempts)
4. Run `nav power` immediately — should work without a "installing dependencies" prompt
