# ==============================================================================
# PowerFlow — Linux Lessons (data)
# ==============================================================================
# Domain   : Shell
# File     : components/shell/lessons.ps1
# Purpose  : The ONE source of truth for every Linux lesson
# Functions: Get-LinuxLesson, Show-Lesson, Get-LessonTopics
# Depends  : none
# ==============================================================================
#
# `lesson <command>`, `pwsh-h <topic>`, `<brother> -lesson`, and the inline hints all read
# from HERE. Add a lesson to $script:PF_Lessons and every surface picks it up for free.
# Write a lesson once and it appears everywhere; they can never drift apart.
# ==============================================================================

$script:PF_Lessons = @{

  'chmod' = @{
    Brother = 'changemode'
    Topic   = 'permissions'
    Short   = 'change a file or directory''s permissions'
    Body    = @'
  changemode  →  chmod   "change mode"

  WHO            WHAT              WHICH
  u  owner       +  add            r  read      (4)
  g  group       -  remove         w  write     (2)
  o  others      =  set exactly    x  execute   (1)
  a  all (ugo)

  chmod u+w  file       owner gains write
  chmod g-x  file       group loses execute
  chmod a=r  file       EVERYONE gets read only
  chmod 755  dir        owner rwx · group r-x · others r-x
  chmod -R 775 dir/     recurse into everything below

  NUMERIC:  add them up.   rwx = 4+2+1 = 7    r-x = 4+1 = 5    rw- = 4+2 = 6
      644  files you own          755  dirs and scripts
      775  shared group dirs      700  private
      600  private files          777  ⚠️ world-writable — almost never right

  💡 On a DIRECTORY, x means "may ENTER", not "may run".
  ⚠️  chmod 777 is almost never the correct fix. It usually means the GROUP is wrong.

  see also:  changeowner (chown) · changegroup (chgrp) · defaultmode (umask)
'@
  }

  'chown' = @{
    Brother = 'changeowner'
    Topic   = 'permissions'
    Short   = 'change who owns a file'
    Body    = @'
  changeowner  →  chown   "change owner"

  chown munya          file      new owner
  chown munya:media    file      new owner AND group
  chown :media         file      group only
  chown -R munya:media dir/      recurse

  The two names in `ls -l` are OWNER then GROUP:

      drwxrwxr-x  2  munya  media  ...  ward-a
                     ↑      ↑
                   owner  group

  💡 Usually needs sudo — you cannot give away a file you do not own.

  see also:  changemode (chmod) · changegroup (chgrp) · mygroups (groups)
'@
  }

  'chgrp' = @{
    Brother = 'changegroup'
    Topic   = 'permissions'
    Short   = 'change a file''s group'
    Body    = @'
  changegroup  →  chgrp   "change group"

  chgrp media       file
  chgrp -R media    dir/

  Same as `chown :media file`.

  💡 THE SHARED-FOLDER PATTERN — this is what a group is FOR:

      sudo groupadd media                 create the group
      sudo usermod -aG media munya        add yourself
      sudo usermod -aG media jellyfin     add the service
      sudo chgrp -R media /srv/movies     the folder belongs to the group
      sudo chmod -R 775 /srv/movies       group can read + write
      sudo chmod g+s /srv/movies          ⭐ NEW FILES INHERIT THE GROUP

  That last one (setgid) is the trick most people miss. Without it, every new file
  belongs to the creator's own group and Jellyfin loses access again.

  ⚠️  usermod -aG — the -a is CRITICAL. Without it, -G REPLACES every group you are in.
'@
  }

  'umask' = @{
    Brother = 'defaultmode'
    Topic   = 'permissions'
    Short   = 'the default permissions for new files'
    Body    = @'
  defaultmode  →  umask   "user mask"

  umask         show the current mask (e.g. 022)
  umask 002     new files become group-writable
  umask -S      show it symbolically

  It SUBTRACTS from the maximum:

      files      666 - umask
      dirs       777 - umask

      umask 022  ->  files 644, dirs 755    (default: group cannot write)
      umask 002  ->  files 664, dirs 775    (shared group work)

  💡 It only affects files created FROM NOW ON. It changes nothing that already exists.
'@
  }

  'ls' = @{
    Brother = 'listfiles'
    Topic   = 'files'
    Short   = 'list directory contents'
    Body    = @'
  listfiles  →  ls   "list"

  ls              names only
  ls -l           LONG: permissions, owner, group, size, date
  ls -a           ALL, including dotfiles
  ls -la          both
  ls -lh          human-readable sizes (4.0K not 4096)
  ls -ld  dir     the DIRECTORY ITSELF, not what is inside it   ← easy to miss
  ls -lt          sort by TIME, newest first
  ls -lS          sort by SIZE
  ls -lr          reverse the sort
  ls -R           recurse

  PowerFlow extras use LONG flags, so they can never collide with GNU:
      ls --tree            tree view
      ls --depth 3         how deep

  💡 -d is the one people forget. Without it, `ls -l somedir` lists what is INSIDE
     somedir. With it, you see somedir itself.
'@
  }

  'id' = @{
    Brother = 'whoamifull'
    Topic   = 'permissions'
    Short   = 'your user id, group id, and every group you are in'
    Body    = @'
  whoamifull  →  id

  id                   uid, gid, and all your groups
  id -u                just the numeric user id  (0 = root)
  id -un               just the username
  id -G                all group ids
  id munya             someone else's

  Typical output:

      uid=1000(munya) gid=1000(munya) groups=1000(munya),1001(media),27(sudo)
                                              ↑            ↑
                                        primary group   supplementary

  💡 After `usermod -aG media munya`, `id` will NOT show the new group until you
     log out and back in. The membership is real; your SESSION is stale.
'@
  }

  'getent' = @{
    Brother = 'lookupentry'
    Topic   = 'permissions'
    Short   = 'look up users, groups and hosts in the system databases'
    Body    = @'
  lookupentry  →  getent   "get entries"

  getent group media       does the 'media' group exist, and who is in it?
  getent passwd munya      a user account
  getent hosts debian.org  a hostname

  Output:

      media:x:1001:munya,jellyfin
      ↑     ↑ ↑    ↑
      name  │ GID  members
            password placeholder

  💡 Better than `cat /etc/group`: Linux can also pull users and groups from LDAP or
     Active Directory, and getent asks ALL sources. /etc/group is only one of them.
'@
  }

  'groups' = @{
    Brother = 'mygroups'
    Topic   = 'permissions'
    Short   = 'which groups you belong to'
    Body    = @'
  mygroups  →  groups

  groups           your groups
  groups munya     someone else's

  💡 If a group you just joined is missing, log out and back in. Group membership is
     attached to your LOGIN SESSION, not applied retroactively.
'@
  }

  'rm' = @{
    Brother = 'removefile'
    Topic   = 'files'
    Short   = 'remove files and directories'
    Body    = @'
  removefile  →  rm   "remove"

  rm  file            delete a file
  rm -i file          ask first
  rm -r dir/          RECURSIVE — a directory and everything in it
  rm -f file          force; no error if it does not exist
  rm -rf dir/         both. ⚠️ NO UNDO. NO RECYCLE BIN.

  💡 GNU rm REFUSES to delete a directory without -r. That refusal is a seatbelt.
  ⚠️  `rm -rf /` or `rm -rf $VAR/` where VAR is empty will destroy the machine.
     Always `echo` the variable before you `rm` it.

  PowerFlow's fzf-picker version is `del` — it never shadows GNU rm.
'@
  }

  'find' = @{
    Brother = 'findfile'
    Topic   = 'files'
    Short   = 'search for files by name, type, size, age or permission'
    Body    = @'
  findfile  →  find

  find . -name "*.log"            by name (case sensitive)
  find . -iname "*.LOG"           case-insensitive
  find . -type d                  directories only  (f = files, l = symlinks)
  find . -size +100M              bigger than 100 MB
  find . -mtime -7                modified in the last 7 days
  find . -perm 777                by permission
  find . -user munya              by owner
  find . -name "*.tmp" -delete    find AND delete
  find . -name "*.sh" -exec chmod +x {} \;    run a command on each hit

  💡 `.` means "start here". The tests come after the path, not before.
'@
  }

  'grep' = @{
    Brother = 'findtext'
    Topic   = 'text'
    Short   = 'search for text inside files'
    Body    = @'
  findtext  →  grep   "global regular expression print"

  grep "error" file           lines containing "error"
  grep -i "error" file        ignore case
  grep -r "error" dir/        recurse through a directory
  grep -n "error" file        show line numbers
  grep -v "error" file        INVERT — lines that do NOT match
  grep -c "error" file        just count them
  grep -l "error" *.log       just list the FILES that match
  grep -w "err" file          whole word only (not "error")
  grep -A3 -B3 "error" file   3 lines of context either side

  💡 `grep -rn "thing" .` is the one to remember: recursive, with line numbers.
'@
  }

  'tar' = @{
    Brother = 'archive'
    Topic   = 'archives'
    Short   = 'create and extract .tar.gz archives'
    Body    = @'
  archive  →  tar   "tape archive"

  tar -czf  out.tar.gz  dir/     CREATE   (c)
  tar -xzf  in.tar.gz            EXTRACT  (x)
  tar -tzf  in.tar.gz            LIST     (t) — look before you extract
  tar -xzf  in.tar.gz -C /opt    extract somewhere else

  The letters:
      c  create      x  extract     t  list
      z  gzip        f  file (must come LAST, right before the filename)
      v  verbose

  💡 Remember it as a sentence:  "eXtract Ze File"  =  -xzf
                                 "Create Ze File"   =  -czf
  💡 ALWAYS `-tzf` first. Some archives explode into the current directory instead
     of a single folder.
'@
  }

  'ps' = @{
    Brother = 'listprocs'
    Topic   = 'processes'
    Short   = 'list running processes'
    Body    = @'
  listprocs  →  ps   "process status"

  ps aux              EVERY process, every user
  ps -ef              the same thing, different tradition
  ps aux | grep node  find one

  In `ps aux`:
      USER  PID  %CPU  %MEM  ...  COMMAND
            ↑
          the number you pass to kill

  💡 `aux` has no dash. It is BSD style. `-ef` is UNIX style. Both are correct;
     everyone argues about it.
'@
  }

  'kill' = @{
    Brother = 'stopproc'
    Topic   = 'processes'
    Short   = 'stop a process'
    Body    = @'
  stopproc  →  kill

  kill  1234          ask it politely to stop   (signal 15, TERM)
  kill -9 1234        FORCE it to stop          (signal 9, KILL)
  killall node        by name
  pkill -f "my.js"    by command line

  💡 ALWAYS try plain `kill` first. -9 gives the process no chance to save, close
     files or flush a database. Reach for it only when TERM has failed.
'@
  }

  'systemctl' = @{
    Brother = 'service'
    Topic   = 'processes'
    Short   = 'control system services'
    Body    = @'
  service  →  systemctl

  systemctl status  jellyfin      is it running? why did it die?
  systemctl start   jellyfin      start it NOW
  systemctl stop    jellyfin
  systemctl restart jellyfin
  systemctl enable  jellyfin      start it AT BOOT
  systemctl disable jellyfin

  💡 start ≠ enable.
       start  = right now, this once.
       enable = every boot from now on.
     You almost always want BOTH:  systemctl enable --now jellyfin
'@
  }
}

function Get-LessonTopics {
    return ($script:PF_Lessons.Values.Topic | Sort-Object -Unique)
}

function Get-LinuxLesson {
    param([Parameter(Mandatory)][string]$Command)

    $key = $Command.ToLower()
    if ($script:PF_Lessons.ContainsKey($key)) { return $script:PF_Lessons[$key] }

    # Allow lookup by brother name too: `changemode` finds chmod.
    foreach ($k in $script:PF_Lessons.Keys) {
        if ($script:PF_Lessons[$k].Brother -eq $key) { return $script:PF_Lessons[$k] }
    }
    return $null
}

<#
.SYNOPSIS
    Print a command's lesson and do nothing else. Always safe to run.
#>
function Show-Lesson {
    param([Parameter(Mandatory)][string]$Command)

    $lesson = Get-LinuxLesson -Command $Command
    if (-not $lesson) {
        Write-Host "❌ No lesson for '$Command'." -ForegroundColor Red
        Write-Host "   Topics: $((Get-LessonTopics) -join ', ')" -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host $lesson.Body -ForegroundColor White
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  lesson — THE way to ask for a lesson
# ══════════════════════════════════════════════════════════════════════════════
#
# WHY A VERB, AND NOT `chmod -lesson`
#
# `chmod -lesson` would need PowerFlow to define a FUNCTION called `chmod` that
# intercepts the flag and forwards everything else to the real binary. PowerShell offers
# no other way to see a native command's arguments. That approach was tried and removed,
# because a function is not a transparent stand-in for a binary:
#
#   • It does not forward stdin. `cat access.log | grep ERROR` would start the native grep
#     with no input and sit there — a HANG, not an error.
#   • So grep/rm/cp/cat/mkdir/touch had to be denylisted — meaning the commands a beginner
#     most needs were exactly the ones that could not have a lesson.
#   • And it needed a CI backstop to catch anyone re-adding one by accident.
#
# `lesson <command>` needs none of that. It shadows nothing, so it works for EVERY command
# — grep and rm included — and there is no failure mode to defend against.
#
# Brothers keep their -lesson flag (`changemode -lesson`): `changemode` is not a real
# command, so wrapping it shadows nothing.

<#
.SYNOPSIS
    lesson <command>  — learn a Linux command. Runs nothing; always safe.
.DESCRIPTION
    Accepts the real name, the brother name, or a topic:
        lesson chmod          the real command
        lesson changemode     its brother — same lesson
        lesson permissions    every lesson in that topic
        lesson                the full index
.EXAMPLE
    lesson grep
    l chmod
    lesson permissions
#>
function lesson {
    param([string]$Name)

    # No argument: the index, grouped by topic.
    if (-not $Name) { Show-LessonIndex; return }

    $key = $Name.ToLower()

    # A topic? Show every lesson under it.
    if ($key -in (Get-LessonTopics)) {
        $inTopic = $script:PF_Lessons.GetEnumerator() |
                   Where-Object { $_.Value.Topic -eq $key } | Sort-Object Key
        Write-Host ""
        Write-Host "📚 $key — $($inTopic.Count) lesson(s)" -ForegroundColor Cyan
        foreach ($e in $inTopic) { Show-Lesson -Command $e.Key }
        return
    }

    # A command (real name or brother).
    if (Get-LinuxLesson -Command $key) { Show-Lesson -Command $key; return }

    # Nothing matched — help rather than just refusing.
    Write-Host ""
    Write-Host "❌ No lesson for '$Name'." -ForegroundColor Red

    $near = @($script:PF_Lessons.Keys | Where-Object { $_ -like "*$key*" -or $key -like "*$_*" })
    if ($near.Count -gt 0) {
        Write-Host "   Did you mean:  $($near -join ' · ')" -ForegroundColor Yellow
    }
    Write-Host "   All lessons:   lesson" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-LessonIndex {
    Write-Host ""
    Write-Host "📚 Linux lessons" -ForegroundColor Cyan
    Write-Host "════════════════" -ForegroundColor Cyan
    Write-Host "  lesson <command>   learn it — runs nothing, always safe" -ForegroundColor DarkGray
    Write-Host "  l <command>        same thing, less typing" -ForegroundColor DarkGray
    Write-Host "  lesson <topic>     every lesson in a topic" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($topic in (Get-LessonTopics)) {
        Write-Host "  $topic" -ForegroundColor Yellow
        $inTopic = $script:PF_Lessons.GetEnumerator() |
                   Where-Object { $_.Value.Topic -eq $topic } | Sort-Object Key
        foreach ($e in $inTopic) {
            Write-Host ("    {0,-11}" -f $e.Key) -NoNewline -ForegroundColor Cyan
            Write-Host ("{0,-13}" -f $e.Value.Brother) -NoNewline -ForegroundColor DarkGray
            Write-Host $e.Value.Short -ForegroundColor White
        }
        Write-Host ""
    }
}

Set-Alias l lesson

# Tab-completion: `lesson ch<Tab>` offers chmod, chown, chgrp, changemode…
# Completing over commands, brothers AND topics, because all three are valid arguments.
Register-ArgumentCompleter -CommandName lesson, l -ParameterName Name -ScriptBlock {
    param($cmd, $param, $wordToComplete)

    $all = @($script:PF_Lessons.Keys) +
           @($script:PF_Lessons.Values.Brother) +
           @(Get-LessonTopics)

    $all | Sort-Object -Unique |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
