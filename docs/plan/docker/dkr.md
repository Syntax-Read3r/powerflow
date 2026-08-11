# PowerFlow for Docker — `dkr`

**Status: IMPLEMENTED 2026-08-11, shipping in v5.0.0.** Lives in
[components/containers/containers.ps1](../../../components/containers/containers.ps1) with the
engine calls in `platform/<os>/adapters/container.ps1`; tests in `tests/containers/` (707
assertions).

**Deviations from this design, all deliberate:**

- **A second entry point, `pman`, drives podman.** Not in this document. One implementation,
  two names — the command NAME is the engine selector, so there is no `--engine` flag to
  remember. A switchable alias was rejected because it would make `dkr` mean different things
  on different machines, so help text, docs and muscle memory would all become
  machine-dependent. (`pman`, not `pdm`: that is a widely used Python package manager.)
- **The adapter contract is `*-Container*`, not `*-Docker*`,** for the same reason.
- **A store and machine model this design does not mention.** Podman has *machines* (a Linux VM),
  each with *two stores* (rootless and rootful) holding different containers, images, volumes and
  networks, reached by *connections* matched on SSH **port** rather than name. `dkr`/`pman stores`
  exists because a container can be invisible while plainly running: the engine can answer
  truthfully that there are none here while five sit one connection away.
- **No `param()` block.** PowerShell would bind `-a`/`-f` as parameter *names*, and prefix
  matching makes single letters ambiguous. Arguments are parsed by hand.
- **Zero containers re-probes engine health before reporting "none".** Podman can report a usable
  client version while the service is unreachable, and a confident wrong answer is worse than a
  slow one.
**Provenance:** The body of this document is a design by ChatGPT, reconciled against decisions
the owner made in conversation. Where the two disagreed, the owner's decision wins and the
change is marked inline. The original is preserved in git history.

---

## Decisions that override the body

These were settled with the owner directly. The rest of the document stands.

### 1 · The command is `dkr`, not `dock`

*"dock is a bit lazy, what about dkr"* — owner. Renamed throughout (105 occurrences).
§10 originally listed `dkr` among aliases to avoid; that conflated **alias proliferation**
(`dk` `dku` `dkd` `dkl` `dks` — still rejected) with **choosing a name** (one name, then words).
§10 is corrected inline.

### 2 · Bare `dkr` is a PICKER, and multi-select is not optional

*"i could enter dkr and have a list of all running dockers in fzf and then from there i can
choose what to do with them such as stopping them"* — owner.

The body proposes bare `dkr` as a read-only dashboard. That becomes **`dkr status`**. Bare `dkr`
is the picker, following the house pattern (`srv` bare = picker; `srv list` = table;
`pmx disk` bare = picker; `start-folder` bare = picker-as-manager).

**Multi-select is a hard requirement, not a nicety.** The command this replaces is:

```
sudo docker stop qbittorrent radarr sonarr jellyfin
```

Four containers in one call. A single-select picker would be **worse than what the owner types
today**. fzf `--multi`, Tab to mark, the count shown in the header, one action applied to every
marked container with **one** confirmation naming all of them — never a per-container prompt loop.

### 3 · One table, and it is the owner's own format

*"If there is only need for one table there so be it"* — owner. So: one, not a family.

`dkr list` renders exactly what the owner hand-rolls today, without the Go template:

```
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

```
NAME          STATUS                  PORTS
jellyfin      up 15h (healthy)        :8096
sonarr        up 13h                  :8989
radarr        up 13h                  :7878
prowlarr      up 14h                  :9696
qbittorrent   up 14h                  :8080 :6881
seerr         up 3h                   :5055
```

`dkr list` exists alongside the picker for a real reason, not as a synonym: **a picker cannot be
piped, scripted, or read over a slow SSH link.** `-l` / `-list` are accepted because the owner
reached for them, but `list` is the documented spelling.

Ports are the noisy column — the owner's six containers produced **nine** mappings, several of
them the same host IP repeated per protocol. Collapse to the published port; the full mapping is
available on the container's detail view and under `--show-native`.

### 4 · `--show-native` applies here too

*"dont forget to apply the --show-native flag incase user want to see the long format"* — owner.

This is a **PowerFlow-wide convention**, not a pmx feature: any command that translates a native
tool owes the user a way to see what it actually ran.

```
dkr stop sonarr radarr --show-native   →   docker stop sonarr radarr
```

* **Off by default**, matching the fix already made to pmx (`ShowNative = $false`), so the two
  commands behave identically.
* For the picker, show the command built from the marked selection — which doubles as the
  teaching device: you learn the raw docker *by using dkr*.
* For compose-managed containers it must show the **compose** command actually used
  (`docker compose -f … restart sonarr`), never a plain-docker approximation. Showing a command
  that is not what ran is worse than showing nothing.

This is distinct from the body's `dkr raw` passthrough — `raw` runs arbitrary docker,
`--show-native` reports what was just run. **`raw` is dropped**: the body itself says do not
shadow `docker`, so the escape hatch is `docker`, already on PATH.

### 5 · Eighteen named verbs, staged — not collapsed into flags

The owner considered and rejected compressing the surface: *"I think 18 is better than 50 with
flags etc."* That is correct, and the reasoning is worth recording, because it looks like it
contradicts the creed and does not:

**Subcommands are not flags.** The creed's enemy is `docker ps --format "table {{.Names}}…"` —
encoded syntax you cannot guess and must look up every time. `dkr logs sonarr` is vocabulary,
and vocabulary is learnable in ways flag grammar is not:

* `dkr <tab>` shows you all of them. `--format <tab>` shows you nothing.
* Named verbs are greppable in your own shell history, scriptable, and diffable.
* Each verb can carry its own `--help`. A flag combination cannot.

An earlier proposal here collapsed 18 → 5 by moving actions into the picker. It was rejected,
rightly: the actions do not disappear, they just lose their names — which makes them *less*
discoverable, not more, and you cannot tab-complete or script what has no name.

**The picker is the discovery layer on top of the verbs, not a replacement for them.** Same
relationship as `pmx help`: 37 invocations exist, one entry point teaches them, nobody memorises
37 to get started.

Ship them **staged** per the body's own P0–P3 table — not because 18 is too many, but because 18
half-built verbs is worse than 6 solid ones. P0 is the daily loop:

```
dkr · dkr up · dkr down · dkr restart · dkr logs · dkr shell
```

### 6 · Reuse the existing resolver — do not build a second one

The body's *"Don't build a second project discovery system"* is the sharpest call in it, and it
is already satisfied. As of 2026-08-07 PowerFlow has **`Resolve-PFRootedDirectory`** in
`components/navigation/roots.ps1`, shared by `nav` and `ls`, with named roots, user-defined
anchors (`nav --anchor . mon`), and a pruned walk that skips `node_modules`/`.git`/`dist`/
`build`/`target`. `dkr up kok` finding compose projects must use it — including the owner's own
anchors, so `dkr up @mon` works for free.

### 7 · Compose is the engine, and labels make it work from anywhere

Every running compose container carries `com.docker.compose.project`, `.service`,
`.working_dir` and `.config_files`. That is what lets `dkr restart sonarr` do the
**compose-correct** thing from any directory, rather than demanding the user `cd` to the project
first — which is compose's single biggest friction and the reason plain `docker restart` on a
compose container quietly does the wrong thing.

Detect `docker compose` (v2 plugin) vs `docker-compose` (v1 standalone) rather than assuming.

### 8 · sudo, and the adapter boundary

The owner's transcript shows a password prompt **mid-listing**. Use the elevation adapter
(`Test-Admin` / `Assert-Admin`) and detect docker-group membership, so a correctly configured
host never prompts at all. Never elevate silently.

All docker invocation lives in `platform/<os>/adapters/docker.ps1`; the component renders only.
Windows must implement the same contract (Docker Desktop) or degrade honestly — **CI enforces
adapter parity**, and the contract names must be added to the hardcoded regex in
`release-validate.yml` or they ship unchecked.

### 9 · Safety

`dkr clean` and anything reaching `system prune -a` or `down -v` **destroys data**. PowerFlow's
standard applies: confirm by typing something specific back, name exactly what will be removed
and how much space it frees, and never fabricate safety that is not there. Non-interactive
sessions refuse rather than assume yes.

---

## Research findings (merged 2026-08-07)

The six-lens pass completed: **123 findings**, of which 21 went through adversarial
verification against a **live Docker 29.6.2 / Compose v5.3.1** host. **14 were refuted.**
That refutation rate is the useful part of this section — most of what follows is here
because a verifier tried to kill it and could not.

### What was refuted, and what it changes

- **"lazydocker has no ports column."** False. It has had one for roughly four years
  (`jesseduffield/lazydocker`). The argument for `dkr` is therefore *not* that prior art
  cannot show you ports. It is narrower and still holds: lazydocker is a full-screen TUI
  you enter and leave, whereas the daily question — *what is up, on which port* — wants a
  line of output in the scrollback you already have. `dkr ui` handing off to lazydocker
  stays the right call precisely because lazydocker is good.

- **Several claims overstated prune/`down -v` risk**, and one was "wrong in the direction
  that inflates the risk". `docker compose down` does **not** remove named volumes unless
  `-v/--volumes` is passed, and that flag is scoped to volumes declared in the compose
  file's `volumes:` section. Guardrails should be built to the measured behaviour, not to
  the folklore — an over-warned command trains people to click through warnings.

- **`docker exec -it sonar sh` does not print the error the finder quoted.** The
  near-miss-name pain is real, but the proposed message was invented. `dkr` should show
  what the daemon actually said and add its own suggestion, rather than fabricating
  daemon output.

- **One proposal "reproduced the exact defect it claimed to fix"** — a good reminder that
  a wrapper is only worth having if it is measurably better than the line it replaces.

### What survived verification

These are the confirmed findings, and they are what P0 was built to:

- **Bare `dkr` must show stopped containers, not just running ones.** When the list holds
  only what is running, "it is not there" and "it is dead" look identical — and the second
  is the one worth knowing about. *(Implemented: exited containers are listed, greyed.)*

- **Names must resolve through compose labels.** `com.docker.compose.project`, `.service`
  and `.config_files` come back from `docker ps --format '{{json .}}'`, which is what makes
  `dkr restart sonarr` correct **from any directory**. Compose's single biggest friction is
  that it otherwise demands you `cd` first. *(Implemented: name → service → project →
  substring.)*

- **`docker restart` on a compose-managed container ignores an edited compose file.** This
  is the classic "I changed the yml and nothing happened". When the labels are present the
  compose form must be used. *(Implemented, and asserted in `tests/docker/`.)*

- **`dkr logs` with no name should open a picker**; with a name, 200 lines, and follow only
  when asked. *(Implemented.)*

- **The engine state is a four-way answer, not a pass/fail** — `missing` /
  `unreachable` / `needs-sudo` / `ready`. Each needs different advice, and on Windows the
  usermod line is meaningless. *(Implemented in both adapters.)*

- **Never silently elevate.** The docker socket is root-equivalent: anyone who can reach it
  can start a privileged container that mounts the host filesystem. `dkr` detects whether
  the socket is reachable and *says so*; it does not quietly prepend `sudo` and prompt
  mid-listing. The docker-group tradeoff is stated once, honestly, including that group
  membership is root-equivalent.

- **The header should report the effective endpoint, not just the context name.**
  *(Partially implemented — P0 shows the server version and whether it is elevated.)*

### Still deferred (P1+)

`dkr stack`, `dkr clean` (**bare = a read-only itemised report that deletes nothing**),
`dkr doctor` (the four-state answer above), `dkr why <name>` for restart loops, `dkr update`
for the compose pull/up dance, and the `dkr ui` / `dkr top` hand-offs to lazydocker/ctop.

---

For PowerFlow, I’d build Docker around **applications and intent**, not around Docker’s object model.

PowerFlow already does this well elsewhere: `pc-whoami` gives you machine “vitals” rather than exposing raw system plumbing, while `pmx` turns several Proxmox/Linux utilities into one human-readable interface with previews, verification, dry-runs, and safe mutations.  Docker should get exactly that treatment.

I also **would not replace or shadow `docker`**. PowerFlow deliberately leaves native GNU commands intact on Linux, so the same philosophy should apply here: keep `docker` as the escape hatch, and create a PowerFlow-native command such as `dkr`. 

### The command surface I'd build

```text
dkr                       # Docker dashboard

dkr up                    # Bring this application up
dkr down                  # Bring it down
dkr restart [service]     # Restart whole app or one service

dkr logs [service]        # Smart logs
dkr shell [service]       # Enter a service
dkr open [service]        # Open exposed app/port in browser

dkr status                # Detailed app status
dkr stats                 # CPU/RAM/network
dkr doctor                # Diagnose why Docker/app isn't working

dkr apps                  # All Compose applications
dkr containers            # Raw containers
dkr images                # Images
dkr volumes               # Volumes
dkr network               # Networks

dkr clean                 # Safe reclaim workflow
dkr inspect <thing>       # Human-readable inspection

dkr raw ...               # Explicit passthrough to native Docker
```

The important rearrangement is that **containers/images/networks/volumes are not the front door**.

Docker itself historically makes you think:

```text
container
image
volume
network
compose
context
system
```

PowerFlow should make you think:

```text
What is running?
Start my app.
Why is it broken?
Show me its logs.
Let me inside it.
Where is it exposed?
How much is it consuming?
Stop it.
Clean up the junk.
```

Compose is already Docker's application-level abstraction, with lifecycle operations such as `up`, `down`, `logs`, `exec`, `ps`, and `stats`, so I'd make Compose the primary engine underneath PowerFlow rather than treating it as an optional sub-feature. ([Docker Documentation][1])

## 1. `dkr` should be the killer feature

Running bare:

```powershell
dkr
```

should answer everything you're normally about to run another command to find out.

Something along these lines:

```text
🐳 PowerFlow Docker

Engine
  ✅ Docker running
  Version      29.x
  CPU          4.2%
  Memory       5.8 / 32 GB
  Disk         46.2 GB

Current App
  kokoro
  ~/Code/kokoro

  SERVICE       STATE       CPU      RAM       PORT
  api           ● running   2.1%     1.8 GB    localhost:8880
  redis         ● running   0.1%     72 MB     internal
  postgres      ● running   0.3%     310 MB    5432

  Health        ✅ 3/3 healthy
  Images        8.3 GB
  Volumes       4.1 GB

Other Apps
  whisper       ● 2 running
  powerflow     ○ stopped
  dev-db        ⚠ 1 unhealthy

Issues
  ⚠ 13.2 GB reclaimable
  ⚠ whisper-api restarted 7 times today

Enter   service actions
Ctrl-L  logs
Ctrl-S  shell
Ctrl-O  open
Ctrl-D  stop
```

That fits PowerFlow much better than making users memorize:

```bash
docker ps
docker compose ps
docker stats
docker system df
docker inspect ...
```

And Docker Compose now provides essentially all of the primitives needed underneath, including status, stats, logs, exec and lifecycle management. ([Docker Documentation][1])

---

## 2. Make `dkr up` context-aware

This should be the most seamless part.

If I'm sitting inside:

```text
~/Code/kokoro/
```

and there's:

```text
compose.yaml
```

then:

```powershell
dkr up
```

should just work.

No:

```bash
docker compose -f compose.yaml up -d
```

PowerFlow should:

```text
1. Find Compose file
2. Parse services
3. Validate config
4. Show what is changing
5. Start application
6. Wait for health state
7. Show exposed URLs
```

Example:

```text
$ dkr up

🐳 kokoro

Starting
  api       create → start
  redis     already running
  worker    create → start

✅ 3 services running

API
  http://localhost:8880

Logs
  dkr logs

Shell
  dkr shell api
```

Docker itself recommends validating the effective Compose configuration with `docker compose config`, and Compose supports dry-run behaviour, so PowerFlow can perform useful validation rather than blindly calling `up`. ([Docker Documentation][1])

### Discovery should reuse `nav`

This is where your existing PowerFlow architecture becomes useful.

You already have intelligent project discovery across configured roots. 

So:

```powershell
dkr up kokoro
```

could search those same roots for:

```text
compose.yaml
compose.yml
docker-compose.yaml
docker-compose.yml
```

Then:

```text
$ dkr up kok

Found:
> kokoro-fastapi     ~/Code/kokoro-fastapi
  kokoro-ui          ~/Code/kokoro-ui
```

Don't build a second project discovery system.

Have one PowerFlow service:

```text
ProjectResolver
```

used by:

```text
nav
git-*
dkr
```

That would make PowerFlow itself substantially cleaner.

---

# 3. `dkr logs` should replace the horrible part of Docker UX

I'd prioritize this extremely highly.

```powershell
dkr logs
```

If one service exists:

```text
show it
```

If several exist:

```text
fzf service selector
```

Then:

```text
dkr logs api
dkr logs api -f
dkr logs api --errors
dkr logs api --since 10m
```

I'd add PowerFlow semantics Docker doesn't give you cleanly:

```powershell
dkr logs api --errors
```

could highlight:

```text
error
fatal
exception
panic
traceback
segfault
OOM
connection refused
```

And:

```powershell
dkr logs --problems
```

could combine recent logs from all services and present likely failures:

```text
Problems detected

api
  ❌ Connection refused → postgres:5432
     14 occurrences · first 13:04 · last 13:11

worker
  ⚠ OOMKilled
     restarted 3 times

postgres
  ✅ no obvious errors
```

That's very PowerFlow.

---

# 4. `dkr shell` instead of `docker exec -it ...`

This should be trivial:

```powershell
dkr shell api
```

instead of:

```bash
docker compose exec api bash
```

PowerFlow could probe in order:

```text
pwsh
bash
zsh
ash
sh
```

and choose what's actually present.

Docker Compose `exec` already supplies an interactive TTY by default, so there isn't much machinery PowerFlow needs to reinvent underneath. ([Docker Documentation][2])

If no service is specified:

```text
$ dkr shell

Choose service

> api        running
  postgres   running
  redis      running
```

This would probably become one of the most frequently used commands.

---

# 5. `dkr open` would be deceptively useful

Docker port mapping is another area where users shouldn't have to think in infrastructure terms.

```powershell
dkr open
```

PowerFlow resolves:

```text
container 8880
      ↓
host 8880
      ↓
http://localhost:8880
```

If there are several:

```text
Choose endpoint

> API          http://localhost:8880
  Frontend     http://localhost:3000
  Postgres     localhost:5432
```

Browser-compatible endpoint:

```powershell
dkr open api
```

Non-browser endpoint:

```text
postgres
localhost:5432

Copy connection string?
```

I'd probably have:

```powershell
dkr ports
```

too.

But `open` is the human command.

---

# 6. Make `dkr doctor` a first-class feature

I'd put this surprisingly high in the priority list.

```powershell
dkr doctor
```

should diagnose:

```text
Docker engine
Compose
WSL2
virtualisation
disk space
DNS
ports
health checks
container restart loops
missing env vars
missing volumes
network conflicts
image architecture
GPU visibility
```

Example:

```text
$ dkr doctor

🐳 Docker Doctor

Engine             ✅ running
Compose            ✅ v2.x
Virtualisation     ✅ available
Disk               ⚠ 91% full

Application: kokoro

api                 ❌ unhealthy
redis               ✅ healthy
postgres            ✅ healthy

Cause
  api cannot bind port 8880.

Port 8880
  Used by PID 18304
  python.exe
  C:\Code\old-api\server.py

Fix
> stop process
  change Compose port
  show details
  cancel
```

That would fit naturally beside `pc-whoami`.

PowerFlow already takes raw system information and turns it into actionable diagnostics rather than dumping IDs and low-level values. 

---

# 7. Treat cleanup like `disk-big`, not `docker system prune`

This one matters.

I **would not** make:

```powershell
dkr clean
```

equivalent to:

```bash
docker system prune -a --volumes
```

That's too dangerous.

You already have the right pattern in PowerFlow's disk reclaim functionality: categorize things, show size and age, prevent giant unreviewable deletion lists, and protect dangerous objects. 

So:

```text
$ dkr clean

Docker Storage

Images
  Active          12.4 GB
  Unused           8.2 GB
  Dangling         1.1 GB

Build Cache
  Reclaimable      9.7 GB

Volumes
  Attached        18.1 GB
  Unattached       6.4 GB

Containers
  Running             8
  Stopped            17

Potential reclaim
  25.4 GB
```

Then:

```text
> Safe clean
  Review images
  Review volumes
  Review build cache
  Advanced
```

And I would make volumes **harder to delete than images**.

Something like:

```text
⚠ Volume postgres-data

Size       12.8 GB
Created    8 months ago
Attached   no
Last app   nursing-api

Deleting this can permanently destroy application data.

Type DELETE postgres-data:
```

That's the same philosophy you've already established with virtual disks and destructive PMX operations.

---

# 8. Move Images/Volumes/Networks down a level

This is probably the biggest structural change I'd make from native Docker.

Instead of:

```text
dkr image ...
dkr container ...
dkr network ...
dkr volume ...
```

being what people learn first, those are **advanced inspection commands**.

Primary:

```text
dkr
dkr up
dkr down
dkr restart
dkr logs
dkr shell
dkr open
dkr doctor
dkr clean
```

Secondary:

```text
dkr apps
dkr status
dkr stats
dkr ports
dkr config
```

Advanced:

```text
dkr container
dkr image
dkr volume
dkr network
dkr context
dkr inspect
dkr raw
```

That's the rearrangement I'd use.

---

# 9. Introduce the concept of a PowerFlow "app"

Internally, I wouldn't model the primary object as a container.

I'd model:

```text
PowerFlowDockerApp
```

Something approximately like:

```text
App
├── Name
├── Path
├── ComposeFiles[]
├── Services[]
├── Status
├── Health
├── Ports[]
├── Images[]
├── Volumes[]
├── Networks[]
├── ResourceUsage
└── Host
```

Then:

```text
Service
├── Name
├── Container
├── Image
├── State
├── Health
├── Ports
├── Cpu
├── Memory
├── Restarts
└── Logs
```

This matters architecturally.

Otherwise you'll end up writing PowerShell functions directly around:

```powershell
docker ps
docker inspect
docker image ls
docker volume ls
```

and your presentation layer becomes tightly coupled to Docker CLI output.

Instead:

```text
Docker CLI
    ↓
Docker Provider
    ↓
normalized PowerFlow objects
    ↓
PowerFlow Docker functions
    ↓
UI
```

For example:

```powershell
Get-PFDockerApp
Get-PFDockerService
Get-PFDockerHealth
Get-PFDockerPort
Get-PFDockerUsage

Start-PFDockerApp
Stop-PFDockerApp
Restart-PFDockerService

Enter-PFDockerService
Watch-PFDockerLogs

Test-PFDockerEnvironment
Invoke-PFDockerCleanup
```

Then aliases/UX commands:

```powershell
dkr
dkr up
dkr logs
...
```

become thin controllers.

That's important if PowerFlow keeps growing.

---

# 10. Don't make every command magical

I'd resist one temptation.

Don't make:

```powershell
dkr api
```

mean five different things depending on state.

And don't create dozens of terse aliases like:

```text
dk
dku
dkd
dkl
dks
```

It saves three keystrokes and makes the product harder to understand.

> **Corrected 2026-08-07.** This section originally listed `dkr` among the aliases to avoid.
> That conflated two different things. The argument above is against **alias proliferation** —
> six one-off shortcuts for six verbs — and it is correct. Choosing `dkr` as *the single
> command name* does not violate it: there is one name, and the verbs after it are words.
> `dkr` is the decided name (the owner rejected `dock` as "a bit lazy"); `dku`/`dkd`/`dkl`
> are still rejected, exactly as this section argues.

The nice balance is:

```text
dkr up
dkr down
dkr logs
dkr shell
dkr restart
```

It's already short.

Tab completion does the rest.

---

# 11. Remote Docker should reuse `srv`

This could become exceptionally nice.

You already have:

```powershell
srv proxmox
```

with saved aliases that hide IP/user/port information. 

Use the exact same identity system.

For example:

```powershell
dkr @proxmox
```

Dashboard:

```text
🐳 Docker · proxmox

Engine       ✅ online

APPS
immich       ● 6/6
homepage     ● 3/3
paperless    ⚠ 4/5
```

Then:

```powershell
dkr @proxmox logs paperless web
dkr @proxmox restart immich
dkr @proxmox stats
```

Or alternatively:

```powershell
dkr host proxmox
```

I slightly prefer `@alias` because it visually distinguishes **where** from **what**:

```text
dkr @proxmox logs immich
     └ host       └ app
```

But I'd still avoid persistent hidden host state.

A command should make it obvious when you're modifying a remote machine.

---

# 12. Connect it to `pc-whoami`

This would make the different parts of PowerFlow actually feel like one product.

Imagine:

```powershell
pc-whoami --ram
```

currently discovers Docker consuming 14 GB.

Instead of treating it as an opaque process:

```text
Docker / WSL           14.2 GB
```

you could drill into:

```text
Docker                 14.2 GB

kokoro-api              5.7 GB
ollama                   4.1 GB
postgres                 1.3 GB
redis                  203 MB
other                   2.9 GB

Open Docker dashboard? [Enter]
```

Then jump straight into:

```text
dkr stats
```

Similarly:

```powershell
disk-big
```

could identify:

```text
Docker data             84 GB
```

and hand off to:

```text
dkr clean
```

Instead of PowerFlow having isolated features, you get:

```text
pc-whoami
     │
     ├── dkr stats
     │
disk-big ── dkr clean
     │
nav ─────── dkr up
     │
srv ─────── dkr @server
```

**That's the part I'd prioritize architecturally.**

---

# What I'd actually build first

Not all of Docker.

I'd build it in four stages:

| Priority | Feature                      | Reason                                      |
| -------- | ---------------------------- | ------------------------------------------- |
| **P0**   | `dkr` dashboard             | Establishes the whole UX                    |
| **P0**   | `dkr up/down/restart`       | Daily lifecycle                             |
| **P0**   | `dkr logs`                  | Probably highest-frequency debugging action |
| **P0**   | `dkr shell`                 | Removes `exec -it` friction                 |
| **P0**   | Compose auto-discovery       | Makes everything seamless                   |
| **P1**   | `dkr open/ports`            | Huge convenience                            |
| **P1**   | `dkr doctor`                | Very PowerFlow-specific value               |
| **P1**   | `dkr stats`                 | Integrates with `pc-whoami`                 |
| **P1**   | `dkr clean`                 | Integrates with `disk-big`                  |
| **P2**   | images/volumes/networks      | Necessary, but not everyday UX              |
| **P2**   | `srv` remote integration     | Powerful after local model is stable        |
| **P3**   | building/publishing images   | Developer-specific                          |
| **P3**   | registry auth                | More complexity/security                    |
| **P3**   | advanced contexts/Swarm/etc. | Don't let edge cases design v1              |

And I'd deliberately leave things like exotic build flags available through:

```powershell
docker ...
```

rather than trying to PowerFlow-ify the entire Docker CLI.

## The final hierarchy

I think the finished command family should feel roughly this small:

```text
dkr
│
├── up [app/service]
├── down [app]
├── restart [service]
│
├── logs [service]
├── shell [service]
├── open [service]
│
├── status
├── stats
├── ports
├── doctor
│
├── apps
├── containers
├── images
├── volumes
├── network
│
├── clean
├── inspect
├── config
│
└── raw
```

And bare `dkr` plus interactive selection should make it possible to accomplish **80–90% of that without remembering the subcommands at all**.

The key design decision is this: **don't build a nicer Docker CLI. Build a PowerFlow application manager whose first backend happens to be Docker.** Then later the abstraction could potentially accommodate Podman or another container runtime without ripping apart the user-facing commands.

That direction is much more consistent with what PowerFlow is becoming than a collection of `docker-*` wrapper functions.

[1]: https://docs.docker.com/reference/cli/docker/compose/ "https://docs.docker.com/reference/cli/docker/compose/"
[2]: https://docs.docker.com/reference/cli/docker/compose/exec/ "https://docs.docker.com/reference/cli/docker/compose/exec/"
