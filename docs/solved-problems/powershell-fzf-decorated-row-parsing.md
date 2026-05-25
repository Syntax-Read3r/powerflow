# PowerShell fzf — decorated row parsing fails after selection

## Problem

An fzf picker shows a valid row, but after pressing Enter the script fails to parse the selected item. In PowerFlow this appeared as:

```text
Could not parse organisation name from selection.
```

## Root cause

The parser extracted data from decorative display text:

```powershell
if ($selection -match '🏢\s+(\S+)') {
    $value = $Matches[1]
}
```

This is brittle because terminal rendering, font fallback, fzf output handling, ANSI settings, or future UI text changes can alter the decorative prefix while the underlying selected row is still valid.

## Solution

Keep machine-readable data separate from display text. Emit rows as `value<TAB>display`, tell fzf to display only the human-readable columns, then parse the stable value column from the returned row:

```powershell
$choices = $items | ForEach-Object {
    "$($_.id)`t$($_.displayText)"
}

$selection = $choices | fzf --with-nth=2.. --delimiter="`t"
$selectedId = ($selection -split "`t", 2)[0].Trim()
```

Validate the parsed value against the original API/object list before using it.

## Notes

- This pattern also protects descriptions, names, or labels that contain spaces.
- It allows UI decoration to change without changing parser logic.
- Fix applied — awaiting confirmation.
