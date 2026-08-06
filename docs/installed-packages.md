# Installed Packages and Prerequisites

| Package | Date Added | Use Case | Status |
|---------|------------|----------|--------|
| `scoop` | 2026-08-06 | Required Windows package-manager prerequisite; bootstraps PowerFlow's managed tools and Nerd Font | Active |
| `starship` | 2026-05-19 | Cross-shell prompt with Git integration | Active |
| `fzf` | 2026-05-19 | Interactive fuzzy-search pickers | Active |
| `zoxide` | 2026-05-19 | Smart directory navigation | Active |
| `lsd` | 2026-05-19 | Enhanced directory listing | Active |
| `git` | 2026-05-19 | Version-control workflows | Active |
| `FiraCode-NF-Mono` | 2026-07-21 | Single-cell Nerd Font glyphs for Starship and lsd | Active |

## Ownership policy

PowerFlow records whether it installed each managed tool or font and removes only owned items.
Scoop is different: it is shared infrastructure and may later contain unrelated user packages.
Automated uninstall always keeps it. Interactive uninstall offers a separate opt-in, displays
the all-applications/buckets/shims risk after yes, and leaves Scoop's final confirmation intact.
