# Log 4 — July 19, 2026 — privacy scrub: a real username+address had been used as example text

**The mistake (mine):** the `srv` feature's example text — runtime hints, docstrings,
README, CHANGELOG, session logs, and one commit message — used the author's real
username and LAN server address, where a documentation placeholder (`you@192.168.1.50`)
would have taught identically. It shipped in the v3.5.0 and v3.6.0 releases. The author
spotted it in `srv`'s own "No servers yet" hint after reinstalling.

**Severity, honestly:** RFC1918 private space — unreachable from the internet. What
leaked is internal addressing plus a valid SSH username: useless to a drive-by, useful
recon to someone already inside the network. Low severity, zero justification.

**The scrub (user chose the full option):**

1. Working tree: all 8 file occurrences replaced with the placeholder; pushed.
2. GitHub release bodies: v3.5.0's edited in place.
3. **v3.6.1 cut from the cleaned tree** so `latest` assets are clean end to end — the
   new zip was downloaded and grepped before claiming so.
4. **v3.5.0 and v3.6.0 releases + tags deleted** (both superseded within the hour;
   their zips carried the address inside `servers.ps1`).
5. **History rewritten**: `filter-branch --msg-filter` over the five affected commits,
   backup refs purged, reflog expired, gc'd, force-pushed. GitHub's commit listing for
   main verified clean via the API.
6. v3.6.1 re-tagged on the rewritten history; CI rebuilt and republished it (5 assets).

**Residual, stated plainly:** GitHub retains unreachable objects server-side for a
while — anyone holding an old commit SHA URL may still render it until GitHub GCs, and
a support ticket can force-purge if it ever matters. Local clones made in the ~40-minute
exposure window would also carry the old history (there are none known besides the
author's machines).

**The durable fix:** release checklist §4 now opens with a private-data grep — staged
diff AND release description, real IPs/usernames/hostnames — run before every cut. It
ran green on 3.6.1's own cut, its first outing.

**Lesson for the log:** example text never needs real data to teach. The moment a real
identifier improves an example's realism, that realism is the leak.
