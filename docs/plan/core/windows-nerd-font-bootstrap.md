# Windows Nerd Font Bootstrap and Detection

**Status:** Implemented and locally verified; awaiting user confirmation and patch release.

## Goal

Make Windows font setup genuinely automatic and accurately reported: `pwsh-font` and the
installer should bootstrap their existing Scoop prerequisite when necessary, recognise the
font names Scoop actually registers, and explain real failures without claiming Scoop is
missing when it is not.

## Scope

This change covers the Windows font/package adapters, installer ownership metadata, focused
regressions, and affected user documentation. It does not add another package manager, change
the Linux direct-download path, or select a terminal font automatically. Scoop is an explicit
Windows prerequisite. PowerFlow keeps it by default during uninstall because it may contain
unrelated user packages; interactive uninstall offers a separate opt-in, explains the risks
after a yes answer, and preserves Scoop's own final confirmation.

## Chunks

1. **Correct detection and bootstrap behaviour**
   - Update `platform/windows/adapters/fonts.ps1` to recognise both human-readable family
     labels and Scoop's filename-derived `FiraCodeNerdFontMono-*` registry names.
   - Reuse `Test-PackageManager` / `Install-PackageManager` so `pwsh-font` can bootstrap Scoop
     just as the main dependency installer does.
   - Preserve the exact failed command/result and return a truthful recovery hint.
   - Harden `platform/windows/adapters/packages.ps1` so a newly bootstrapped Scoop shim is
     immediately available in the current PowerShell process.

2. **Preserve ownership and uninstall safety**
   - Review `install.ps1` and `uninstall.ps1` manifest behaviour against the corrected success
     signal.
   - Record ownership only after the font is both installed and detected.
   - Keep Scoop itself outside automatically removable dependencies; only the font package
     PowerFlow successfully installed may be removed without an additional choice.
   - Ask interactive Windows users separately whether to remove Scoop. After yes, warn that
     every Scoop-managed application, bucket and shim is affected, then require Scoop's own
     final confirmation. `-Yes` always keeps Scoop.

3. **Add regressions and release documentation**
   - Add a Windows fixture-based test for spaced family names, Scoop registry names, absent
     fonts, package-manager bootstrap, failed commands, and ownership-safe results without
     installing or removing a real font.
   - Wire the regression into Windows release validation.
   - Update installation/troubleshooting text, the issue tracker, session log, and the next
     patch entry in `CHANGELOG.md`.

## Rollback

Revert the Windows font/package adapter changes and remove the new test/workflow wiring. No
font or Scoop state is changed by the regression suite. On a real installation, Scoop remains
installed and the font can be removed independently with `scoop uninstall FiraCode-NF-Mono`.

## Testing

- Run the fixture-based Windows font regression in a clean `pwsh -NoProfile` process.
- Confirm `Test-NerdFont` returns true for the actual HKCU property names reported by Scoop.
- Exercise the missing-Scoop bootstrap path with mocked package-manager functions.
- Verify install failures retain actionable diagnostics and do not report ownership.
- Run all `.ps1` parser, architecture, adapter-parity, help-registry, privacy and whitespace
  release gates.
- Run an isolated Windows installer upgrade and confirm it reports the font as present rather
  than attempting to reinstall it.

## Result

All chunks were implemented. Tests are split into font/prerequisite, Scoop-removal safety, and
isolated installer-roundtrip files behind `tests/windows/run.ps1`. The real HKCU registrations
are detected, automated uninstall is proven unable to invoke Scoop removal, and every local
release gate passes.
