# ==============================================================================
# PowerFlow — Command Bindings (Linux)
# ==============================================================================
# Domain   : Platform / Linux
# File     : platform/linux/bindings.ps1
# Purpose  : Stop PowerFlow's commands from shadowing the GNU coreutils
# Functions: del, mvf  (renamed PowerFlow commands)
# Depends  : loaded AFTER components/ — it rebinds names the components define
# ==============================================================================
#
# ⚠️  THE MOST IMPORTANT FILE IN THE LINUX PORT.
#
# PowerShell resolves a bare name in this order:
#
#     Alias  ->  Function  ->  Cmdlet  ->  Native executable
#
# Two consequences, and BOTH have bitten this file already:
#
#   1. A FUNCTION beats a native binary. PowerFlow defines rm/mv/mkdir/touch as
#      functions, so on Linux they would hide /usr/bin/rm etc.
#   2. An ALIAS beats a FUNCTION. So it is not enough to define `del` — the
#      built-in `del` alias (-> Remove-Item) would still win. And PowerFlow's own
#      `cat`/`cp` ALIASES (components/files/listing.ps1) would hide GNU cat/cp
#      even after every conflicting function is removed.
#
# Why this matters, concretely:
#
#   * PowerFlow's `rm somedir` recursively deletes the whole tree after one
#     prompt. GNU `rm somedir` REFUSES without -r. That refusal is a seatbelt
#     Linux users rely on reflexively; silently removing it would burn someone
#     exactly once, unrecoverably.
#   * PowerFlow's `mv` is a cut/paste model, not GNU `mv <src> <dst>`.
#
# Policy — the feature is never the problem, the BINDING is:
#
#   OVERRIDE  PowerFlow adds real value and the semantics don't conflict  (ls/la/ll)
#   RENAME    the feature is valuable but the semantics differ            (rm->del, mv->mvf)
#   DEFER     PowerFlow merely reimplements a tool Linux already has      (cp, cat,
#             mkdir, touch, rmdir, which, grep, less, pwd)
# ==============================================================================

# ── 1. RENAME: copy the function bodies to safe names BEFORE anything is removed
if (Test-Path Function:\rm) { ${function:global:del} = ${function:rm} }   # fzf picker + confirm + recursive delete
if (Test-Path Function:\mv) { ${function:global:mvf} = ${function:mv} }   # "move-file": cut/paste workflow

# ── 2. Clear ALIASES that would out-rank our functions or shadow coreutils ─────
# `del`/`erase`/`rd`/`ri` are built-in aliases for Remove-Item and would beat the
# `del` function we just defined. `cat`/`cp` are PowerFlow's own aliases from
# components/files/listing.ps1 and would hide GNU cat/cp.
foreach ($a in @('del', 'erase', 'rd', 'ri', 'rm', 'rmdir', 'mv', 'cp', 'cat', 'ls')) {
    if (Test-Path "Alias:\$a") { Remove-Item "Alias:\$a" -Force -ErrorAction SilentlyContinue }
}

# ── 3. Remove FUNCTIONS that shadow a native tool ─────────────────────────────
# rm/mv are preserved above as del/mvf. cp/mkdir/touch/rmdir/which are pure
# reimplementations — Linux already ships better versions.
foreach ($fn in @('rm', 'mv', 'cp', 'mkdir', 'touch', 'rmdir', 'which')) {
    if (Test-Path "Function:\$fn") { Remove-Item "Function:\$fn" -Force -ErrorAction SilentlyContinue }
}

# ── 4. OVERRIDE (kept): ls / la / ll stay PowerFlow's — the pretty listing is the
#       whole point, and it degrades to Get-ChildItem when lsd is missing.
#       mv-t / mv-c are PowerFlow-only names and pair with `mvf`.
#       grep / less / pwd / which are never defined on Linux (they live in
#       platform/windows/bindings.ps1) — the real tools are already on PATH.

Write-Verbose "PowerFlow: Linux bindings applied — rm/mv/cp/cat/mkdir/touch defer to coreutils. Use 'del' and 'mvf'."
