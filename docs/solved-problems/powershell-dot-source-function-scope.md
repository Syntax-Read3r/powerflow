# PowerShell — functions defined via dot-source inside a helper function disappear after the helper returns

## Problem

A PowerShell profile bootloader uses a helper function to dot-source component files:

```powershell
function _pf_source {
    param([string]$relativePath)
    $fullPath = Join-Path $root $relativePath
    if (Test-Path $fullPath) { . $fullPath }   # ← dot-source inside a function
}

_pf_source "components\core\version.ps1"   # defines Check-PowerFlowUpdates
# ...
Check-PowerFlowUpdates   # ❌ "not recognized" — function is gone
```

After loading, none of the component functions are available. Side effects of
those scripts (alias removals via `Remove-Item Alias:*`) do persist because
they modify global state via a cmdlet, but `function foo { }` definitions are
silently lost.

## Root cause

In PowerShell, dot-sourcing (`. script.ps1`) runs the script in the **current
scope**. When called from inside a function, the current scope is that
function's local scope — a child of the caller's scope. All items defined by
the dot-sourced script are placed in that local scope. The local scope is
destroyed when the function returns, taking every `function` definition with it.

Shell-level init scripts (e.g. `starship init powershell`) often survive this
because they explicitly write to global scope with `function global:prompt { }`.
Standard user-defined functions without the `global:` modifier do not.

## Solution

Never dot-source inside a function if the definitions must be visible to the
caller. Move the actual dot-source call to the bootloader body (which runs at
global scope when the profile is dot-sourced):

```powershell
# Resolve path only — no dot-source inside the function
function _pf_path {
    param([string]$relativePath)
    $fullPath = Join-Path $root $relativePath
    if (Test-Path $fullPath) { return $fullPath }
    Write-Warning "Component not found: $fullPath"
    return $null
}

# Dot-source happens here, at bootloader (global) scope
$_p = _pf_path "components\core\version.ps1"; if ($_p) { . $_p }
```

## Notes

- `foreach` statement loops do NOT create a new scope in PowerShell, so
  dot-sourcing inside a `foreach` block at global scope also works correctly.
- `-ErrorAction SilentlyContinue` on `Remove-Item Alias:name` prevents errors
  on profile reload when the alias was already replaced by a function on the
  first load.
- Fix applied — awaiting confirmation.
