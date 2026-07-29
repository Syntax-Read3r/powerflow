# Log 2 — July 29, 2026 — memory levels: 167 rows become a five-row map (v3.15.0)

**User:** "you mentions -ram lists 529 processes. can we refine it so that we cut that num down.
i.e. -ram lv1 would be equal to 0.0gb-0.25gb… first you must find where the majority of the
process are congregated meaning the most memory they occupy and then create the level system
equally dividing the processes to mitigate session killing. im thing we can have 5 levels…
having a lv1 might be poor naming, i will leave for you to decide… since we've decided that
-ram on its own would be session killer, it must be accompanied by an additional flag."

## Measuring first — and the measurement changed the design

The instruction was to find where processes congregate and divide them **equally**. So the
first thing built was not a feature but a histogram of the real machine:

```
POPULATION: 162 program groups, 31 GB total
  < 25 MB        76 groups   0.8 GB   ██████████████████████████████████████
  25 - 50 MB     32 groups   1.1 GB   ████████████████
  50 - 100 MB    23 groups   1.5 GB   ████████████
  100 - 250 MB   15 groups   2.4 GB   ████████
  250 - 500 MB    4 groups   1.4 GB   ██
  500 MB - 1 GB   4 groups   2.6 GB   ██
  1 - 2 GB        5 groups   6.8 GB   ██
  > 2 GB          3 groups  14.4 GB   ██

  top  5 groups ( 3.1% of the list) hold 56.4% of the memory
  top 20 groups (12.3% of the list) hold 84.0% of the memory
```

**Equal-count bands are demonstrably wrong on this shape.** Five slices of ~33 produce:

```
  band 1:  33 groups   6,239 MB down to 86 MB  = 89.5% of RAM
  band 5:  30 groups       7 MB down to  0 MB  =  0.4% of RAM
```

Band 1 would sit a 6 GB editor next to an 86 MB helper — a 72× range inside one "level" — and
bands 4–5 would be sixty-odd entries under 18 MB: noise, not levels. The count axis is the
wrong axis when 3% of the population holds 56% of the resource.

Put to the user with the numbers, who chose memory-scale bands. That is the right call, and it
also serves the stated goal better: the levels people actually act on stay short, and a short
list is a small blast radius.

## The result

```
🧠 MEMORY — 167 programs, 24 GB in use of 32 GB

   huge    1 GB and up        5 programs     13 GB   ██████████████████████
   large   250 MB – 1 GB     10 programs      6 GB   ██████████
   medium  50 – 250 MB       28 programs      3 GB   █████
   small   10 – 50 MB        69 programs      2 GB   ███
   tiny    under 10 MB       55 programs    239 MB
```

`pc-whoami -ram` alone is now a **map, not a list** — which is exactly the "must be accompanied
by an additional flag" requirement, met without a dead end: the bare command still answers
"where is my memory?" and names the flag for each level. `-ram huge` then opens six rows
holding 13 of the 24 GB in use.

Naming was delegated. `lv1..lv5` was rejected for the reason given — it carries no meaning and
the user has to remember a mapping. `huge / large / medium / small / tiny` is self-ordering and
self-documenting; the flag says what you will get.

Levels are half-open `[Min, Max)`, so a program of exactly 1 GB lands in `huge` and in nothing
else — the counts and byte totals of the five levels reconcile to the whole population, which
is asserted rather than assumed.

`-min N` survives as the custom cut-off for when a preset is not the cut you want.

## `--ram` retired one release after shipping

It meant "below 0.5 GB", which `small` and `tiny` now say more precisely, and two overlapping
ways to ask one question is clutter. This was put to the user rather than decided unilaterally,
since it shipped an hour earlier. Running `--ram` prints what to use instead — PowerShell binds
it as a plain string, so without that branch it would have reached the drill-in and reported
"nothing called '--ram' is running".

## Verified

Bands partition the population exactly (counts **and** bytes reconcile); each boundary value
belongs to exactly one level; 0 bytes lands in `tiny` and a hypothetical 99 GB process in
`huge`. The index prints five level rows and no program rows. Every level opens; a level with
more than 25 groups declares its hidden remainder and one under the cap makes no such claim.
Levels are case-insensitive. `--ram` redirects. The drill-in and all its guards are untouched —
wildcard refusal, two-word names, bare-name routing, `-min`, and the identity check before any
kill. Linux: same, with the bands reconciling on a one-process container.

Three assertions in the older suite failed after this change and were **updated, not worked
around** — they asserted the previous meaning of bare `-ram`, which this release deliberately
replaced.
