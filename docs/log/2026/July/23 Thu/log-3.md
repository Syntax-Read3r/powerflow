# Log 3 — July 23, 2026 — the PowerShell-update prompt: two Windows fixes (staged for v3.9.1)

**User (on Windows):** the PowerShell update prompt fired, they ran the winget update, it
said "✅ Update successful! Restart your terminal" — but a new window still showed the old
version. And separately: pressing `4` to disable the prompt didn't stick; it kept coming
back. "This may not be a powerflow issue."

Diagnosed live on the machine (same box). Two distinct causes:

## 1. Disable (option 4) silently no-opped — a real PowerFlow bug

`Disable-PowerShellUpdateCheck` (Windows adapter) rewrote `$PROFILE`, searching for
`$script:CHECK_UPDATES = $true`. But since the v3.0.0 monolith split, that flag lives in
`config/PowerFlow.settings.ps1`, **not** the bootloader `$PROFILE`. The `-replace` matched
nothing, wrote nothing, threw nothing — so option 4 did nothing and the prompt returned
next session. Confirmed on the user's box: the string is absent from `$PROFILE`, present in
the settings file.

The **Linux** adapter already did this correctly (`Join-Path $script:PowerFlowRoot
'config/PowerFlow.settings.ps1'`), so the fix is parity, not invention: point the Windows
function at the settings file the same way. (No marker-file mechanism — that would diverge
from the working Linux path for no gain.) Added an "already disabled" hint to both.

Immediate relief: flipped `$script:CHECK_UPDATES = $false` directly in the user's installed
settings (`…\OneDrive\Documents\PowerShell\config\PowerFlow.settings.ps1`).

## 2. Version reverting on new windows — NOT PowerFlow, but the messaging was misleading

The real cause was the user's Windows setup: **two** PowerShell 7 installs — an MSI 7.5.4 in
Program Files and a **Store/MSIX 7.6.3** (what the terminal launches via the WindowsApps
app-execution alias). `winget upgrade` on an MSIX package can't hot-swap while any process
of that package runs; it *stages* the new version and applies it only once every instance
closes. The user had 5 live MSIX `pwsh` processes, so the swap never happened and each new
window relaunched 7.6.3 — and PowerFlow kept (correctly) re-detecting 7.6.3 < 7.6.4 and
re-prompting. "Restart the application" means close *every* window, not open a new tab.

PowerFlow's part in it: because winget *lists* MSIX packages, the Store install fell into
the `elseif ($isWingetListed)` branch — "🔧 Winget-managed installation detected" — and got
the "✅ Update successful! Restart your terminal" message, which is wrong for MSIX. Fixed by
adding a **Microsoft Store / MSIX branch before the winget branch** (order matters: winget
lists MSIX, so Store must be checked first). It stages via winget but says the update
applies once every PowerShell window is closed / after a reboot, and offers the Store
(`ms-windows-store://…`) as an alternative. The user's own cleanup — consolidating onto one
install — was recommended separately.

## Verified

Both adapters parse. `Disable-PowerShellUpdateCheck` now edits the settings file (not
`$PROFILE`), leaves `$PROFILE` untouched, and is idempotent (second call → "already
disabled", no revert). Branch routing: a Store-and-winget-listed install now resolves to
the `store` branch (was `winget`); MSI-conflict / MSI-clean / winget-only branches
unchanged; `WindowsApps` PSHOME classifies as "Microsoft Store".

Held — no version bump, no release. Staged as `[3.9.1] - Unreleased`; v3.9.0 shipped hours
ago and these batch into the next cut on the green light.
