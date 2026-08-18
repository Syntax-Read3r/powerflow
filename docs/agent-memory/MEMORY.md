# PowerFlow Memory Index

- [Project Architecture](project-architecture.md) — Component-based refactor: 7726-line monolith split into 28 .ps1 files across 10 domain folders; bootloader pattern
- [User Profile](user-profile.md) — PowerFlow author, experienced PowerShell dev, React-influenced architecture sensibility
- [Future Dev Wave Plan](future-dev-wave-plan.md) — Agreed build order for the future-dev backlog; Wave 0 (shared/admin.ps1) done 2026-07-06
- [Linux Module Rebuild](linux-module-rebuild.md) — Old ubuntu/ port deleted in v3.0.0; rebuilding as pwsh-on-Linux with a platform adapter layer. Keep wsl.ps1 (it's Windows-side).
- [Privacy History Scrub Pending](privacy-history-scrub-pending.md) — v3.9.0 scrubbed the real username from the tree; older git-history blobs still carry it — a rewrite is an open, user-decided follow-up
- [CI Parity Regex Is Hardcoded](ci-parity-regex-is-hardcoded.md) — the adapter-parity gate checks a hand-maintained list of contract names; new adapter functions must be added to it by hand or they ship unchecked
- [Adapters Make Code Runnable Off-Target](adapters-make-code-runnable-off-target.md) — "only runs on Linux/Proxmox" is rarely a reason to skip executing it: fake the adapter contract, shim `& tool` as a function
- [PowerFlow Creed: Convenience](powerflow-creed-convenience.md) — never make users memorise flags; bare command does the useful thing, refinement is a word, ambiguity gets a picker, native detail only behind --show-native
- [Do Not Block-Poll Background Tasks](dont-block-poll-background-tasks.md) — keep working while workflows run; a blocking TaskOutput reads as being stuck
- [Flag Ethos Uniformity](flag-ethos-uniformity.md) — owner called flag style a major problem; audit logs it, convention is their call. Don't invent a style for new commands
- [Surface Existing Mechanisms Before Building](surface-existing-mechanisms-before-building.md) — name the existing flow before implementing a sketch; bare commands report and point, never write on an unconfirmed target
