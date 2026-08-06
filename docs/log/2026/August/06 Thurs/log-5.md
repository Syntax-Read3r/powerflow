# Log 5 — August 6, 2026 — SRV interactive-session repair

**Work performed:**
- Investigated the released v3.18.0 report that the fzf server picker rendered as cramped,
  interleaved text and that password authentication produced no usable remote shell.
- Traced the missing shell to `Connect-PFServer` piping the native SSH invocation into
  `Out-Null`, which redirected the interactive process streams along with its exit-code object.
- Restored a direct terminal-attached SSH call and simplified the picker to a taller layout with
  an ASCII prompt/header.
- Confirmed from upstream OpenSSH source that its password prompt hard-codes the authenticated
  username and host. PowerFlow will not capture passwords merely to rewrite that native prompt.
- Added the v3.18.1 patch release notes and dated the verified v3.18.0 GitHub release.

**Files modified:**
- `components/network/server-privacy.ps1`, `components/network/servers.ps1` (session and picker)
- `tests/network/public-output.ps1` (remote output must remain visible)
- `docs/instructions.md` (interactive native-process rule)
- `docs/plan/issues/resolved-issues.md` (Issue 14)
- `docs/solved-problems/ssh-saved-endpoint-preauth-display.md` (follow-up cause and fix)
- `CHANGELOG.md` (v3.18.1 patch notes; v3.18.0 release date)
- `docs/log/2026/August/06 Thurs/log-5.md` (created)

**Decisions:**
- Normal connections keep native OpenSSH attached directly to the terminal.
- PowerFlow continues to hide endpoints in its own list, picker, status, and banner output, but
  does not claim control over OpenSSH's native password prompt.
- An askpass/password-capture layer is rejected because hiding native prompt text is not worth
  taking custody of the user's password.

**Bug status:** Follow-up fix applied — awaiting user confirmation on a real server.

**Verification:** Focused SRV privacy/session, PMX, and Windows prerequisite suites pass. Every
PowerShell file parses; component architecture, automatic-variable, help registry (134 commands),
fzf option compatibility, workflow YAML, v3.18.1 changelog extraction, and whitespace gates pass.

**Commit message:** `fix(network): preserve interactive srv SSH sessions`
