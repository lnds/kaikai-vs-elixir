# Discarded — "a fiber waking from sleep parks behind a CPU hog"

The claim, measured on kaikai 0.100.0 and filed upstream as
[kai#1267](https://github.com/lnds/kaikai/issues/1267):

> With `KAI_THREADS=2` the heartbeat's *first* beat escapes via
> work-stealing (~0 ms), but the beat waking from `sleep(millis(50))`
> re-enqueues on the wake path and parks **behind the hog** until ~337 ms —
> with one worker idle the whole time. Not thread-count-specific: 4 hogs +
> `=8` parks the same way, and 4 hogs saturating `=4` push the first beat
> to 858 ms.

**Refuted — by our own binary.** Upstream closed #1267 as not reproducible
(45 warm runs on pre-fix code held cadence; a code read found no mechanism
that could hold a stealable fiber for 287 ms). The decisive test was ours
to run: the exact `starve` binary built by kaikai 0.100.0 on July 18 was
still in `/tmp`, runtime baked in. Re-run **warm**:

```text
-- /tmp/starve (0.100.0), KAI_THREADS=2, 6 warm runs --
[    0ms] heartbeat 3 | [   47ms] heartbeat 2 | [   99ms] heartbeat 1 | [  338ms] hog done
(6/6 on cadence; starve4 at =8: 4/4 on cadence; starve4 at =4: ~350 ms, not 858)
```

The parking never happened. The measurement error: the timestamp origin was
the *pipeline* start (`perl -ne 'BEGIN{$t0=time}'`), and a cold kaikai
binary on macOS takes ~250–350 ms to its first print (page faults +
first-launch signature validation). A cold-start offset landing between
beats produced the `[0/337/389]` shape and it was read as a scheduler
fault. The corrected protocol — the program prints `start` and the
timestamper anchors `t0` on that line, warm runs only — is now baked into
[`cases/05-preemptive-scheduling/`](../../cases/05-preemptive-scheduling/).

Two things survive, stated there with fresh measurements:

- **Saturation is real**: with runnable CPU fibers ≥ worker threads the
  heartbeat waits out a hog's full crunch at any version measured; the BEAM
  holds cadence even at `+S 1`. That is the preemption guarantee, and it is
  still Elixir's.
- **Cancellation is cooperative** ([kai#1268](https://github.com/lnds/kaikai/issues/1268),
  folded into the still-open
  [kai#1269](https://github.com/lnds/kaikai/issues/1269) safepoint
  proposal): `Spawn.cancel` on a pure-CPU fiber never lands — re-verified
  on 0.104.0.

One accidental find from the forensics: the 0.100.0 runtime hung once in
~12 warm runs of the 4-hog repro at `KAI_THREADS=4` (a real intermittent
deadlock — 0.104 ships global-quiescence deadlock detection upstream, and
no hang reproduced there).

Kept, not deleted, for the same reason as the struct-typo entry: conceding
a refuted claim is worth more than a fragile one — especially when the
refuted party is this repo.
