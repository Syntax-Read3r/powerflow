# ==============================================================================
# PowerFlow — Projects Search
# ==============================================================================
# Domain   : Navigation
# File     : components/navigation/projects.ps1
# Purpose  : BFS project search up to a configurable depth within a base dir
# Functions: Search-Projects
# Depends  : none
# ==============================================================================

function Search-Projects {
    <#
    .SYNOPSIS
        Search for project directories using BFS up to MaxDepth levels.
    .DESCRIPTION
        Two modes:
          -All    Collect every directory as a relative path string (for fzf).
                  No name filtering — fzf handles matching.
          default Return the single best-matching full path using:
                  1=exact  2=prefix(starts-with)  3=contains
                  Shallowest wins among equal-quality matches.
    .EXAMPLE
        Search-Projects -Name "power" -BaseDir (Get-HomePath) -MaxDepth 4
        Search-Projects -BaseDir (Get-HomePath) -MaxDepth 4 -All
    #>
    param(
        [string]$Name    = "",
        [string]$BaseDir,
        [int]$MaxDepth   = 4,
        [switch]$All,
        [switch]$Verbose
    )

    if (-not (Test-Path $BaseDir)) {
        if ($Verbose) { Write-Host "❌ Search root not found: $BaseDir" -ForegroundColor Red }
        return $null
    }

    # Directories that are never worth traversing for project navigation
    $skipDirs = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@(
            'node_modules', '.git', 'dist', 'build', 'target',
            'bin', 'obj', '.next', '.nuxt', '__pycache__', '.venv', 'venv',
            '.cache', 'coverage', '.turbo', 'out',

            # Linux virtual/system filesystems. These matter only if a root above them
            # is in scope (someone ran `nav roots add /`), but when they are, they are
            # catastrophic: /proc alone is thousands of kernel-backed pseudo-dirs.
            'proc', 'sys', 'dev', 'run', 'lost+found', 'snap'
        ),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    # TrimEnd takes the platform's separator, not a hardcoded '\'. On Linux the old
    # code trimmed a backslash that was never there — harmless — but the paths it was
    # handed had backslashes baked in, which was not.
    $baseNorm = $BaseDir.TrimEnd([IO.Path]::DirectorySeparatorChar)
    $queue    = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([PSCustomObject]@{ Path = $baseNorm; Depth = 0 })

    # ------------------------------------------------------------------
    # -All mode: collect every traversable dir as a relative path string
    # ------------------------------------------------------------------
    if ($All) {
        $results = [System.Collections.Generic.List[string]]::new()

        while ($queue.Count -gt 0) {
            $node = $queue.Dequeue()
            if ($node.Depth -ge $MaxDepth) { continue }

            try {
                $children = Get-ChildItem -LiteralPath $node.Path -Directory -Force -ErrorAction SilentlyContinue
            } catch { continue }

            foreach ($child in $children) {
                # Skip build artifacts and hidden dirs
                if ($skipDirs.Contains($child.Name))    { continue }
                if ($child.Name.StartsWith('.'))         { continue }

                $rel = $child.FullName.Substring($baseNorm.Length + 1)
                $results.Add($rel)

                $queue.Enqueue([PSCustomObject]@{ Path = $child.FullName; Depth = $node.Depth + 1 })
            }
        }

        return $results
    }

    # ------------------------------------------------------------------
    # Best-match mode (fallback when fzf is unavailable)
    # ------------------------------------------------------------------
    if ($Verbose) {
        Write-Host "🔍 Searching '$Name' in: $BaseDir (depth limit: $MaxDepth)" -ForegroundColor Cyan
    }

    $bestMatch = $null
    $bestScore = 99

    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        if ($node.Depth -ge $MaxDepth) { continue }

        try {
            $children = Get-ChildItem -LiteralPath $node.Path -Directory -Force -ErrorAction SilentlyContinue
        } catch { continue }

        foreach ($child in $children) {
            if ($skipDirs.Contains($child.Name)) { continue }
            if ($child.Name.StartsWith('.'))      { continue }

            $score = if     ($child.Name -eq $Name)         { 1 }
                     elseif ($child.Name -like "$Name*")    { 2 }
                     elseif ($child.Name -like "*$Name*")   { 3 }
                     else                                   { 99 }

            if ($Verbose -and $score -lt 99) {
                $indent = '  ' * ($node.Depth + 1)
                $tag    = switch ($score) { 1 { 'exact' } 2 { 'prefix' } default { 'contains' } }
                Write-Host "$indent📁 $($child.Name)  [$tag]" -ForegroundColor Green
            }

            if ($score -lt $bestScore) {
                $bestScore = $score
                $bestMatch = $child.FullName
                if ($score -eq 1) { return $child.FullName }
            }

            $queue.Enqueue([PSCustomObject]@{ Path = $child.FullName; Depth = $node.Depth + 1 })
        }
    }

    return $bestMatch
}
