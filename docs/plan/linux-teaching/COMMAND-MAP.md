# Linux Command & Flag Map

> The complete inventory. What Linux has, what PowerFlow has, and where they **conflict**.
> Source of truth for the teaching layer — see [README.md](README.md) for the plan.

**Legend**

| | |
|---|---|
| ✅ | PowerFlow implements it and the behaviour matches |
| ⚠️ | PowerFlow implements it but **flags are missing** (silently ignored) |
| 💥 | PowerFlow implements it and the flags **mean something different** — silently wrong |
| ❌ | Not implemented; the native tool is used |
| 🔜 | Planned |

---

## 🚨 The conflicts (fix these first)

These are not gaps — they are **traps**. PowerFlow accepts the flag and does the wrong thing.

| Command | Flag | GNU means | PowerFlow means | Result |
|---|---|---|---|---|
| `ls` | `-t` | sort by **t**ime | **t**ree view | 💥 tree instead of time-sorted |
| `ls` | `-d` | the **d**irectory itself, not contents | tree **d**epth | 💥 wrong output entirely |
| `ls` | `-l`, `-a`, `-h`, `-R`, `-S`, `-r`, `-i`, `-F`, `-1` | long / all / human / recursive / size / reverse / inode / classify / one-per-line | *not a parameter* | 💥 **silently swallowed into `$args` and discarded** |
| `rm` | `-r`, `-i`, `-v`, `-d` | recursive / interactive / verbose / empty-dir | *not a parameter* | ⚠️ ignored (rm is always recursive) |
| `mv` | `-i`, `-n`, `-v`, `-f` | interactive / no-clobber / verbose / force | *not a parameter* | ⚠️ ignored |
| `mkdir` | `-p`, `-m`, `-v` | parents / mode / verbose | *not a parameter* | ⚠️ ignored |
| `touch` | `-a`, `-m`, `-c`, `-d`, `-r` | atime / mtime / no-create / date / reference | *not a parameter* | ⚠️ ignored |

**Root cause:** none of these functions declare `[CmdletBinding()]`. Without it, PowerShell
silently dumps unrecognised arguments into `$args` and discards them — no error, no warning.

---

## 1. Files & Directories

| Linux | Brother name | Key flags | Status |
|---|---|---|---|
| `ls` | `listfiles` | `-l -a -A -h -d -R -t -S -r -i -F -1 --color` | 💥 |
| `cd` | `changedir` | `-` (previous dir) | ✅ (`back`, `cd-`) |
| `pwd` | `printdir` | `-P` (resolve symlinks) | ✅ |
| `cp` | `copyfile` | `-r -i -v -p -a -u -n` | ⚠️ (alias to `Copy-Item`) |
| `mv` | `movefile` | `-i -n -v -u -f` | 💥 (cut/paste model — different semantics) |
| `rm` | `removefile` | `-r -f -i -v -d` | 💥 (always recursive) |
| `mkdir` | `makedir` | `-p -m -v` | ⚠️ |
| `rmdir` | `removedir` | `-p -v` | ⚠️ |
| `touch` | `touchfile` | `-a -m -c -d -r` | ⚠️ |
| `ln` | `linkfile` | `-s -f -v -r` | ❌ 🔜 |
| `find` | `findfile` | `-name -iname -type -size -mtime -perm -user -exec -delete` | ❌ 🔜 |
| `tree` | `treeview` | `-L -d -a` | ✅ (`ls -t`) |
| `stat` | `filestat` | `-c -f` | ❌ 🔜 |
| `file` | `filetype` | `-b -i` | ❌ |
| `du` | `diskusage` | `-h -s -a -c --max-depth` | ❌ 🔜 (`disk-big` is adjacent) |
| `df` | `diskfree` | `-h -T -i` | ❌ 🔜 |
| `basename` / `dirname` | — | — | ❌ |

## 2. Permissions & Ownership  ← **the teaching centrepiece**

| Linux | Brother name | Key flags / syntax | Status |
|---|---|---|---|
| `chmod` | `changemode` | `u g o a` · `+ - =` · `r w x` · numeric `755` · `-R -v --reference` | ❌ 🔜 |
| `chown` | `changeowner` | `user:group` · `-R -v --reference` | ❌ 🔜 |
| `chgrp` | `changegroup` | `-R -v` | ❌ 🔜 |
| `umask` | `defaultmode` | `-S` | ❌ 🔜 |
| `getfacl` / `setfacl` | `getacl` / `setacl` | `-m -x -R -b` | ❌ |
| `lsattr` / `chattr` | — | `+i +a` | ❌ |
| `id` | `whoamifull` | `-u -g -G -n` | ❌ 🔜 |
| `groups` | `mygroups` | — | ❌ 🔜 |
| `getent` | `lookupentry` | `passwd group hosts` | ❌ 🔜 |

### The permission model to teach

```
d rwx rwx r-x
│  │   │   │
│  │   │   └─ others  (everyone else)
│  │   └───── group   (members of the file's group)
│  └───────── owner   (the user who owns it)
└──────────── type: -  file
                    d  directory
                    l  symlink
                    c  character device
                    b  block device
                    s  socket
                    p  named pipe
```

| Numeric | Symbolic | Meaning |
|---|---|---|
| `4` | `r--` | read |
| `2` | `-w-` | write |
| `1` | `--x` | execute (for a directory: *enter* it) |
| `7` | `rwx` | 4+2+1 |
| `5` | `r-x` | 4+1 |
| `6` | `rw-` | 4+2 |

Common modes: `755` (dirs/scripts) · `644` (files) · `775` (shared group dirs) ·
`700` (private) · `600` (private files) · `777` (⚠️ never — world-writable)

Special bits: `setuid 4xxx` · `setgid 2xxx` (**inherit group** — the Jellyfin case) ·
`sticky 1xxx` (`/tmp`)

## 3. Users & Groups

| Linux | Brother name | Key flags | Status |
|---|---|---|---|
| `whoami` | — | — | ❌ 🔜 |
| `useradd` / `usermod` / `userdel` | `adduser` / `modifyuser` / `deluser` | `-aG -s -d -m -L -U` | ❌ 🔜 |
| `groupadd` / `groupmod` / `groupdel` | `addgroup` / … | `-g` | ❌ 🔜 |
| `passwd` | `setpassword` | `-l -u -e` | ❌ |
| `su` / `sudo` | — | `-i -u -s` | ✅ (adapter) |
| `newgrp` / `sg` | — | — | ❌ |

> ⚠️ **`usermod -aG` — the classic footgun.** Without `-a`, `-G` **replaces** every
> supplementary group. This deserves a loud lesson.

## 4. Text & Content

| Linux | Brother name | Key flags | Status |
|---|---|---|---|
| `cat` | `showfile` | `-n -A -b -s` | ⚠️ (alias to `Get-Content`) |
| `less` / `more` | `pagefile` | `-N -S` | ✅ (Windows only) |
| `head` / `tail` | `showtop` / `showbottom` | `-n -c -f` | ❌ 🔜 |
| `grep` | `findtext` | `-i -r -v -n -c -l -w -E -A -B -C` | ⚠️ (Windows alias only) |
| `sed` | `streamedit` | `-i -e -n` | ❌ |
| `awk` | — | `-F` | ❌ |
| `cut` / `sort` / `uniq` / `wc` / `tr` | — | `-d -f` / `-n -r -k -u` / `-c -d` / `-l -w -c` | ❌ |
| `diff` | `comparefiles` | `-u -r -q` | ❌ 🔜 |

## 5. Processes & Services

| Linux | Brother name | Key flags | Status |
|---|---|---|---|
| `ps` | `listprocs` | `aux` `-ef` | ❌ 🔜 |
| `top` / `htop` | `procmonitor` | — | ❌ |
| `kill` / `killall` / `pkill` | `stopproc` | `-9 -15 -l` | ❌ 🔜 |
| `jobs` / `fg` / `bg` / `nohup` / `&` | — | — | ❌ |
| `systemctl` | `service` | `start stop restart enable disable status` | ❌ 🔜 |
| `journalctl` | `viewlogs` | `-u -f -n --since` | ❌ 🔜 |

## 6. Networking

| Linux | Brother name | Key flags | Status |
|---|---|---|---|
| `ip a` / `ifconfig` | `netinfo` | `a` `link` `route` | ❌ 🔜 |
| `ping` | — | `-c -i` | ❌ |
| `ss` / `netstat` | `listports` | `-tulpn` | ❌ 🔜 (`kill-port` is planned) |
| `curl` / `wget` | — | `-fsSL -o -O` | ❌ |
| `ssh` / `scp` / `rsync` | — | `-i -p -avz` | ❌ |
| `dig` / `nslookup` | `dnslookup` | `+short` | ❌ |

## 7. Archives & Compression

| Linux | Brother name | Key flags | Status |
|---|---|---|---|
| `tar` | `archive` | `-czf -xzf -tzf -C` | ❌ 🔜 |
| `gzip` / `gunzip` | — | `-k -d` | ❌ |
| `zip` / `unzip` | `zipfiles` / `unzipfiles` | `-r -d` | 🔜 (in future-dev-plan) |

> `tar -czf` vs `-xzf` is one of the most-Googled commands in existence. Prime lesson material.

## 8. Disks & Mounts

| Linux | Brother name | Key flags | Status |
|---|---|---|---|
| `lsblk` | `listdisks` | `-f -o` | ❌ 🔜 |
| `mount` / `umount` | `mountdisk` | `-t -o` | ❌ |
| `fdisk` / `blkid` | — | `-l` | ❌ |
| `fstab` (file) | — | — | ❌ (lesson only) |

## 9. System Info

| Linux | Brother name | Key flags | Status |
|---|---|---|---|
| `uname` | `systeminfo` | `-a -r -m` | ❌ 🔜 |
| `uptime` / `free` / `lscpu` | `sysinfo` | `-h` | 🔜 (in future-dev-plan) |
| `hostnamectl` | — | — | ❌ |
| `env` / `export` / `$PATH` | `showenv` | — | 🔜 (in future-dev-plan) |
| `history` / `alias` | — | — | ❌ |
| `man` | `manual` | — | ❌ 🔜 |

---

## Priority

Ordered by *how often a beginner hits it* × *how badly PowerFlow currently behaves*.

| Tier | Commands | Why |
|---|---|---|
| **0 — fix the traps** | `ls`, `rm`, `mv`, `mkdir`, `touch`, `rmdir` | Silently wrong **today**. Not a feature — a bug. |
| **1 — permissions** | `chmod`, `chown`, `chgrp`, `id`, `groups`, `getent`, `umask` | The user's actual lesson path. The teaching centrepiece. |
| **2 — daily** | `find`, `grep`, `cat`, `head`, `tail`, `du`, `df`, `ln`, `stat` | Constant use |
| **3 — sysadmin** | `ps`, `kill`, `systemctl`, `journalctl`, `ss`, `lsblk` | Server work |
| **4 — the rest** | `tar`, `sed`, `awk`, networking, mounts | Lower frequency |
