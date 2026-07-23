# PowerFlow — Future Development Plan

> Backlog of high-value commands not yet in PowerFlow, grouped by priority tier.
> Existing coverage: navigation, git, files, github, terminal, system (config, shutdown, path), projects (create-next), help.

---

## Tier 1 — High-impact, frequent daily pain points

### `kill-port <port>`
**Problem:** Finding and killing the process on a port requires `netstat -ano | findstr :<port>`, reading a PID, then `taskkill /PID <pid> /F`. Devs do this constantly when a local server hangs.
**Solution:** One command. Uses `Get-NetTCPConnection` to find the PID, shows the process name for confirmation, then kills it.
```powershell
kill-port 3000        # kill whatever is on :3000
kill-port 3000 -force # skip confirmation
```
**Component:** `components/system/ports.ps1`

---

### `which-port <port>`
**Problem:** Same lookup as above but just to inspect — "what's running on 8080?" — without killing it.
**Solution:** Pretty-prints process name, PID, and state for any port.
```powershell
which-port 8080       # → node.exe (PID 14832) — LISTEN
```
**Component:** `components/system/ports.ps1` (same file as `kill-port`)

---

### `show-path`
**Problem:** `$env:Path` is a single semicolon-delimited wall of text. Unreadable.
**Solution:** Split and print one entry per line, numbered, with a note if the directory doesn't exist on disk.
```powershell
show-path             # list all PATH entries (current session)
show-path -user       # list only User PATH entries
show-path -system     # list only System PATH entries
```
**Component:** `components/system/path.ps1` (extend existing file)

---

### `load-env [file]`
**Problem:** `.env` files are universal in every project. Loading them into the current session requires manual parsing.
**Solution:** Parse a `.env` file (defaults to `.env` in CWD) and set each `KEY=VALUE` pair as `$env:KEY`.
```powershell
load-env              # loads .env from current directory
load-env .env.local   # loads a specific file
```
**Component:** `components/system/env.ps1`

---

### `show-env [filter]`
**Problem:** `Get-ChildItem Env:` dumps everything in a hard-to-read table. No easy way to filter.
**Solution:** Pretty-print all env vars, optional filter string.
```powershell
show-env              # all environment variables, formatted
show-env NODE         # only vars containing "NODE"
```
**Component:** `components/system/env.ps1` (same file as `load-env`)

---

### `pwsh-r` / `reload-profile`
**Problem:** After editing the profile you have to type `. $PROFILE` — easy to forget the dot-source syntax.
**Solution:** Alias to `. $PROFILE` with a confirmation message.
```powershell
pwsh-r                # reloads $PROFILE in current session
```
**Component:** `components/system/config-files.ps1` (extend existing file)

---

### `elevate [command]`
**Problem:** Relaunching a terminal as Administrator or running a single command elevated requires right-clicking or a verbose `Start-Process` incantation.
**Solution:** Without args, reopens Windows Terminal as Administrator in the same directory. With args, runs that command elevated.
```powershell
elevate               # new admin terminal tab at current path
elevate scoop update  # run one command as admin
```
**Component:** `components/system/elevation.ps1`

---

## Tier 2 — Moderately common, meaningful friction reduction

### `kill-proc [name]`
**Problem:** `Stop-Process -Name foo` requires the exact name. `Get-Process` dumps a wall.
**Solution:** fzf picker over all running processes, filterable by name. Select one or more and kill them.
```powershell
kill-proc             # fzf picker of all processes
kill-proc node        # pre-filter to processes matching "node"
```
**Component:** `components/system/processes.ps1`

---

### `find-proc [name]`
**Problem:** No quick way to see CPU/memory for a process by partial name.
**Solution:** Pretty-print matching processes with name, PID, CPU %, memory.
```powershell
find-proc chrome      # all processes matching "chrome"
find-proc             # fzf picker
```
**Component:** `components/system/processes.ps1` (same file as `kill-proc`)

---

### `zip <path> [output]`
**Problem:** `Compress-Archive -Path . -DestinationPath out.zip` is verbose and hard to remember.
**Solution:** Sensible defaults — if no output given, names the zip after the folder/file.
```powershell
zip ./dist            # → dist.zip in current directory
zip ./dist release    # → release.zip
```
**Component:** `components/files/archive.ps1`

---

### `unzip <file> [destination]`
**Problem:** `Expand-Archive -Path file.zip -DestinationPath .` — verbose.
**Solution:** Defaults to extracting into current directory.
```powershell
unzip release.zip     # extracts to ./release/
unzip release.zip out # extracts to ./out/
```
**Component:** `components/files/archive.ps1` (same file as `zip`)

---

### `symlink <link-name> <target>`
**Problem:** `New-Item -ItemType SymbolicLink -Path <link> -Target <target>` is one of the most verbose commands in PowerShell. Also requires admin, which needs a clear error.
**Solution:** Short syntax, admin check, confirmation output.
```powershell
symlink node_modules ../shared/node_modules
```
**Component:** `components/files/operations.ps1` (extend existing file) or `components/system/elevation.ps1`

---

### `sysinfo`
**Problem:** CPU, RAM, disk, OS version are spread across `Get-CimInstance`, `Get-PSDrive`, `$PSVersionTable` — no single command.
**Solution:** Beautiful one-pager: OS, PowerShell version, CPU name + usage, RAM total + free, disk usage per drive, uptime.
```powershell
sysinfo
```
**Component:** `components/system/sysinfo.ps1`

---

### `hosts list` / `hosts add <ip> <name>` / `hosts remove <name>`
**Problem:** Editing `C:\Windows\System32\drivers\etc\hosts` manually requires admin, notepad, and knowing the path.
**Solution:** Read/write wrapper with admin elevation, validation, and duplicate detection.
```powershell
hosts list                      # pretty-print all entries
hosts add 127.0.0.1 myapp.local # add an entry (admin required)
hosts remove myapp.local        # remove entry by hostname
```
**Component:** `components/system/hosts.ps1`

---

## Tier 3 — Useful quality-of-life additions

### `http-get <url>` / `http-post <url> [body]`
**Problem:** `Invoke-RestMethod -Uri <url> -Method GET -Headers @{...}` is long. Developers frequently test APIs from the terminal.
**Solution:** Sensible defaults (JSON content-type, pretty-printed response).
```powershell
http-get https://api.example.com/users
http-post https://api.example.com/users '{"name":"test"}'
```
**Component:** `components/shared/http.ps1`

---

### `json [file]`
**Problem:** `Get-Content file.json | ConvertFrom-Json | ConvertTo-Json -Depth 10` is the incantation for pretty-printing JSON.
**Solution:** Accept file path or piped input, pretty-print with color via `ConvertTo-Json`.
```powershell
json response.json          # pretty-print a file
cat data.json | json        # pipe support
```
**Component:** `components/shared/json.ps1`

---

### `watch <seconds> <command>`
**Problem:** PowerShell has no equivalent of Linux `watch`. Repeatedly running `git status` or `docker ps` manually is tedious.
**Solution:** Re-run a command every N seconds, clearing the screen each iteration. `Ctrl+C` to stop.
```powershell
watch 2 git status
watch 5 docker ps
```
**Component:** `components/terminal/watch.ps1`

---

### `scoop-up` / `pkg-update`
**Problem:** `scoop update *` doesn't check for errors per-package or give a clean summary.
**Solution:** Update all Scoop packages with per-package status output and a final summary.
```powershell
scoop-up              # update all scoop packages with clean output
```
**Component:** `components/system/packages.ps1`

---

### `new-script <name>`
**Problem:** Starting a new `.ps1` script means opening VS Code and writing the header boilerplate manually every time.
**Solution:** Scaffold a `.ps1` file with the standard PowerFlow header comment block and `param()` block, then open it in VS Code.
```powershell
new-script deploy     # creates deploy.ps1 with boilerplate, opens in VS Code
```
**Component:** `components/projects/create-script.ps1`

---

## Implementation notes

- Each Tier 1 item should get its own plan doc in `docs/plan/` before implementation.
- `ports.ps1` and `env.ps1` are the most self-contained starting points.
- ✅ **Done (v3.0.0)** — `hosts.ps1`, `elevation.ps1` and `symlink` all require admin, so the shared
  `Assert-Admin` / `Test-Admin` helper now lives in `components/shared/admin.ps1`. `set-path -System`
  already uses it. Build the admin-dependent commands on top of it rather than re-checking inline.
- `watch` needs to be interruptible via `Ctrl+C` — use a `try/finally` loop with `[Console]::TreatControlCAsInput = $false`.

## Docker 

docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"

docker-list

## System Variables

$adbPath = "C:\Users\you\AppData\Local\Android\Sdk\platform-tools"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")

if ($userPath -notlike "*$adbPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$adbPath", "User")
}

$env:Path += ";$adbPath"
adb version

# Confirm

[Environment]::GetEnvironmentVariable("Path", "User") -split ";" | Select-String "Android\\Sdk\\platform-tools"

set-SV or set-systemvariable path||"path"... this must auth verify that the path is legit before setting and if not, is to throw an error and inform the user