# PowerFlow Ethos — the flag convention

**Status: adopted.** This is the rule for every command, existing and new.

---

## The rule

```
-x   -xy        one dash, one or two letters    short form
--word          two dashes, a word              long form, kebab-case
-xvf            a bundle of short letters       only where a GNU tool is being impersonated
```

**One dash is for short forms. A word takes two.** That is the whole rule, and it is the one
every command-line tool a user has already met follows.

A short form is **one or two letters** — `-s`, and `-sh` for `--short-hand`. Two letters is
deliberate rather than a loophole: it is how the convention was asked for, and it means the GNU
bundles (`-rf`, `-la`, `-lh`) and native pass-throughs like `du -sh` need no special case. Three
or more characters is a word, and words take two dashes.

```powershell
storage --status          # ✅ a word takes two dashes
storage -s                # ✅ its short form takes one
del -rf build             # ✅ a bundle, on a command that impersonates a GNU tool
pc-whoami -power          # ⚠️  the legacy spelling — still works, says so once
```

### Corollaries

| | |
|---|---|
| **A verb is a word, never a flag** | `srv list`, not `srv --list`. `pman stores volumes`, not `pman stores --volumes`. |
| **Refinement is a word** | `storage big`, `dkr logs`. If it selects *what the command is doing*, it is a subcommand. |
| **A target is positional** | `storage D:`, not `storage -D`. A drive is not a flag. |
| **Long flags are kebab-case** | `--dry-run`, not `--dryRun` or `--dryrun`. |
| **An unknown flag is refused** | Never dropped, never guessed. See below — this one has teeth. |

---

## Why not the other way round

The tree used to say the opposite. `components/files/listing.ps1` carried the note *"single
dash belongs to Linux, long dash belongs to PowerFlow"*, and about forty commands with
`param()` blocks quietly implemented the reverse: single-dash words like `-Force` and
`-Status`, because that is what PowerShell gives you for free.

Both halves were defensible and the combination was not. Measured across the tree before this
was settled:

- **`help` had four spellings** across seven commands, and only `pmx` accepted all four.
  `pwsh-h --help` printed *"Nothing called '--help'"* — from the command whose entire job is
  help.
- **`-f` had three meanings**: force, *follow*, and "a filename follows".
- **"skip the prompt" had six spellings**, two of which were silently ignored.
- **`-v` was accepted by nine commands, meant four things, and in two meant nothing at all.**
- **18% of dashed tokens (54 of 301) were never authored** — they could not appear in any help
  text because nothing implemented them.

A user carrying one habit from one command to the next was wrong most of the time. Picking
GNU resolves it in the direction the rest of the world already went.

---

## What this cost, and why the cost is not what it looks like

**A PowerShell `param()` block cannot bind `--word`.** This is the single fact that shapes the
implementation, and it is worse than "unsupported" — it *misbinds*:

```powershell
function T { param([switch]$Force, [string]$Name) }
T --force       #  Force=False, Name='--force'
T --name bob    #  Name='--name',  and 'bob' falls into $args
```

The flag does not fail loudly. It lands in whichever value parameter comes next and takes the
real value's place. Declaring `[Alias('-force')]` does not help either — that was tested, and
`--force` still arrives as a positional string.

The obvious fix — rewrite twelve commands as hand-parsers — was rejected. A hand parser gets
no case-insensitivity and no prefix matching, so `-Stat`, `-status` and `-STATUS` would all
stop working, and every parser would have to reimplement the forgiveness `param()` gives away.

So the spelling is translated **at the door** instead, in
[components/shared/flags.ps1](../../../components/shared/flags.ps1). The user-facing name
becomes a one-line shim; the implementation keeps its `param()` block and every bit of
PowerShell's tolerance:

```powershell
function pwsh-font { Invoke-PFParamCommand -Target 'Invoke-PFNerdFont' -Command 'pwsh-font' -Argv $args }
```

`Invoke-PFParamCommand` reads the target's *own* parameter list, so adding a switch there
needs no change anywhere else. Two details it gets right that are easy to get wrong:

- It builds a **hashtable** splat, not an array one. Splatting an array passes every element
  *positionally*, so a rewritten `-Status` arrives as a string value rather than a parameter
  name. That means the parser must know which flags take a value — it reads that from the
  declared parameter types.
- It compares `ParameterType -eq [switch]`, not the type's string form. Interpolating a
  `[Type]` in PowerShell yields the *accelerator* (`switch`), so matching on
  `'SwitchParameter'` is always false and every switch would be mistaken for a value
  parameter.

---

## Unknown flags are refused

This is not politeness, it is the fix for a real defect. `pwsh-font --status` **installed a
font**: the unbindable token vanished into `$args`, the switch stayed `$false`, and the command
ran its default action — which was the install.

So a flag that cannot be bound now stops the command:

```
❌ pwsh-font: unknown option '--stauts'
   did you mean --status ?
   accepts: --status
```

A command must never do something other than what its arguments asked for. Refusing costs a
retype; guessing cost a font install nobody requested.

---

## Migrating a spelling

The legacy single-dash word keeps working, and says once per session where it went:

```
   note: pc-whoami -power is now --power (one dash is for single letters). Both still work.
```

Once per session per command+flag — a daily driver should not be lectured on every run. Nothing
is removed in this change; the old spelling still binds. Removal, if ever, is a separate
decision with its own major version.

---

## Adding a flag to a new command

1. **Is it really a flag?** If it selects what the command *does*, it is a subcommand word. If
   it names a target, it is positional. Most new options are one of those two.
2. Give it a **`--kebab-case`** long form. Add a one-letter short form only if it will be typed
   often — an unused short form is a letter you cannot give to anything else later.
3. If the command has a `param()` block, route it through `Invoke-PFParamCommand` so `--long`
   binds at all.
4. If the command is hand-parsed, accept both dash forms and refuse an unknown token **by
   name**. `Split-GnuArgs` already does this for the file commands.
5. Register it in `pwsh-h` with the **canonical** spelling in the `-Example`. Help text is how
   the convention actually propagates; teaching the old spelling undoes the work.

---

## The one deliberate exception

Commands that exist to **impersonate a GNU tool** keep GNU's bundling: `del -rf`, `git-f -fdx`,
`ls -la`. Bundling is only accepted where every letter is known — `del -force` is refused by
name rather than shredded into `-f -o -r -c -e`, which is how `-force` used to perform a
recursive force delete. See `tests/files/gnu-args.ps1`.

`ls`, `la` and `ll` also keep single-dash *words* for their named starting points (`ls -srv`)
because those are root anchors rather than flags, and `--srv` would read as an option. They
accept the double-dash form too.
