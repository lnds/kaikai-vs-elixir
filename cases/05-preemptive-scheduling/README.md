# Case 5 — cooperative fibers vs preemptive processes

**Category C — Elixir wins, narrowed hard at 0.104.0, with a retraction,
and re-verified unchanged on 0.114.0 — where upstream closed the fix
proposal as not planned.** The same two-task program — one pure-CPU Collatz hog (~340 ms
of crunch), one heartbeat that prints and sleeps 50 ms — still separates
the two runtimes, but on a thinner line than this case previously claimed:
kaikai 0.104 turns multi-threading **on by default** (worker count = host
cores), and with any spare worker a *spawned* fiber's heartbeat now lands
on perfect cadence. What remains Elixir's is the *guarantee*: under saturation
(runnable CPU fibers ≥ workers) kaikai's beat waits out a hog's full
crunch, and `Spawn.cancel` on a pure-CPU fiber never lands — the BEAM
holds its 50 ms cadence under any load on any scheduler count, `+S 1`
included.

**The retraction first.** The 0.100.0 revision of this case claimed a beat
waking from `sleep` parks *behind* the hog with a worker idle
(`[0/337/389 ms]` at `=2`), plus an 858 ms saturation figure — filed
upstream as kai#1267. Upstream closed it as not reproducible, and they
were right: re-running the **exact 0.100.0-built binary**, warm, gave 6/6
runs on perfect cadence. The artifact was ours — the timestamp origin was
the pipeline start, and a cold kaikai binary takes ~250–350 ms to its
first print on macOS (page faults + first-launch signature validation).
Full forensics in [`discarded/wake-path-parking/`](../../discarded/wake-path-parking/).
The harness now prints `start` and all timestamps anchor there; runs are
warm.

**Status at 0.114.0.** Ten releases later (front-end work: symbol table,
module resolution, Perceus) the scheduler is untouched and every number
below re-measures identically. What *did* change is upstream's answer:
[kai#1269](https://github.com/lnds/kaikai/issues/1269), the
safepoint/reduction-budget proposal, is **CLOSED as not planned** —
"the cooperative-scheduler design position is preserved; adopting a
reduction budget would be a deliberate position change warranting its own
proposal when a measured need reappears". Note the bookkeeping: #1268
(cancellation) had been closed earlier as a corollary that "closes when
#1269 ships", and #1269 then closed citing #1268 as "addressed directly".
Neither shipped, and the probe still measures the original behaviour: the
fiber runs its full ~330 ms after the cancel. So this case's gap is not a
pending fix — it is a **stated design position**, which is the more honest
framing anyway: kaikai chooses cooperative scheduling, and the latency
guarantee is the price. Re-measuring that probe did turn up one thing the
0.104 write-up got wrong, and a finding underneath it — both below.

## The claim (0.104.0, re-verified on 0.114.0)

> kaikai schedules cooperatively at every thread count — the docs are
> explicit: cancellation lands "at the next yield point", "there is no
> preemption". With spare workers this is invisible: beats land on
> cadence. It becomes visible exactly when capacity runs out or control
> must be taken away: (a) `KAI_THREADS=1` — one worker, the beat waits out
> the full crunch; (b) saturation — 16 hogs on 14 default workers, first
> beat at ~420 ms; (c) `Spawn.cancel` on a pure-CPU fiber — requested at
> ~6 ms, the fiber runs its full ~340 ms anyway. The BEAM preempts on
> reduction count: every beat on time under all three shapes, even
> `+S 1`. Parallelism buys latency only while capacity is spare;
> preemption is a guarantee.

## Measured (kaikai 0.114.0, warm binary, t0 = the program's `start` line)

[`kaikai/starve.kai`](kaikai/starve.kai) built `--release` (1 hog + heartbeat):

```text
-- KAI_THREADS=1 --        -- KAI_THREADS=2 --        -- default (14 = ncpu) --
[  320ms] heartbeat 3      [    0ms] heartbeat 3      [    0ms] heartbeat 3
[  372ms] heartbeat 2      [   49ms] heartbeat 2      [   47ms] heartbeat 2
[  424ms] heartbeat 1      [  101ms] heartbeat 1      [   99ms] heartbeat 1
[  476ms] hog done         [  327ms] hog done         [  331ms] hog done
```

[`kaikai/starve_saturate.kai`](kaikai/starve_saturate.kai) — 16 hogs over
the 14 default workers, and [`kaikai/cancel_probe.kai`](kaikai/cancel_probe.kai)
(the repro in kai#1268):

```text
-- 16 hogs, default(14) --      -- Spawn.cancel of a pure-CPU fiber --
[  434ms] heartbeat 3           [    2ms] cancel requested   (best of 15; see below)
[  484ms] heartbeat 2           [  331ms] nursery exited     (fiber ran to completion)
[  535ms] heartbeat 1
[  764ms] hogs done
```

(all runs: `acc=428343355`; each column stable across 3+ warm runs)

[`elixir/starve.exs`](elixir/starve.exs), same anchor:

```text
-- 14 schedulers --               -- +S 1 (single scheduler) --
[    2ms] heartbeat 3             [    2ms] heartbeat 3
[   54ms] heartbeat 2             [   53ms] heartbeat 2
[  105ms] heartbeat 1             [  104ms] heartbeat 1
[ 1022ms] hog done                [ 1512ms] hog done: acc=428343355
```

`+S 1` **is** the saturated shape — one hog fully occupies the only
scheduler — and every beat still lands on its 50 ms cadence, ~1.5 s before
the hog ends. The BEAM charges every call against a reduction budget
(~4000) and deschedules mid-computation; no yield point needs to exist. In
kaikai the saturated beat waits until a hog *finishes* (~330–430 ms here);
the wait scales with the crunch, unbounded in general. The proposal to
close this for real — compiler-inserted safepoints, a BEAM-style
reduction budget — was
[kai#1269](https://github.com/lnds/kaikai/issues/1269), and upstream
**closed it as not planned** (with
[kai#1268](https://github.com/lnds/kaikai/issues/1268), the cancellation
measurement, folded into it and closed first). Re-verified unchanged on
0.114: this is settled design, not pending work.

### A correction and a new finding: the entry fiber is pinned

The `[2ms] cancel requested` above is the *lucky* half of a race, and the
0.104 revision printed it as if it were the rule. Measured 15× on the same
warm binary, that line lands at ~2 ms in 4 runs and at ~330 ms in 11 — in
the common case the cancel is not even *requested* until the hog has
finished. (The `nursery exited` figure is unaffected either way: the fiber
runs to completion in all 15.) Isolating it (no `cancel`
involved) shows why, and it is not about cancellation at all:
[`kaikai/wake_entry_fiber.kai`](kaikai/wake_entry_fiber.kai) sleeps twice
on a spawned fiber and twice on the nursery's own body, with one hog and
13 workers free:

```text
-- run 1 --              -- run 2 --              -- run 3 --
[    2ms] child woke     [    3ms] child woke     [    3ms] child woke
[   52ms] child woke 2   [   54ms] child woke 2   [   54ms] child woke 2
[   59ms] parent woke    [  336ms] parent woke    [  336ms] parent woke
[  109ms] parent woke 2  [  387ms] parent woke 2  [  386ms] parent woke 2
```

A **spawned** fiber wakes on cadence every time. The **nursery's body**
runs on the entry fiber, which upstream pins to the process main thread
(kai#1556), so it cannot migrate: when the hog is scheduled onto that same
worker, the sleeper waits out the full crunch — with 13 workers idle. It
is a coin flip on where the hog lands, which is why the same binary gives
both shapes.

Note what this is and is not. It is *not* the retracted parking claim
resurfacing: that one alleged spawned fibers park behind hogs, was
measured off a cold binary, and is [conceded](../../discarded/wake-path-parking/)
— spawned fibers are on cadence in every run above. This is narrower and
survives the corrected protocol (warm binary, in-program anchor, variance
reported rather than a best run): it costs latency only on the entry
fiber, and the workaround is one line — do latency-sensitive work in a
spawned fiber, not in the nursery body. Reported here rather than filed
as a bug, since pinning the entry fiber is a deliberate upstream choice
whose latency cost may simply be accepted.

Both languages compute the same `acc=428343355` (the hog is a Collatz scan
precisely so LLVM cannot fold it — a bare counter loop it *did* fold in an
earlier draft, which would have measured nothing).

## Reproduce

```sh
kai build --release kaikai/starve.kai          -o /tmp/starve
kai build --release kaikai/starve_saturate.kai -o /tmp/starve_sat
# t0 anchors on the program's own "start" line; discard the first (cold) run
TSA='my $t0; while (<>) { if (/^start/) { $t0 = time; next }
     printf "[%5dms] %s", (time-$t0)*1000, $_ }'
/tmp/starve; KAI_THREADS=1 /tmp/starve | perl -MTime::HiRes=time -e "$TSA"  # starves
KAI_THREADS=2 /tmp/starve             | perl -MTime::HiRes=time -e "$TSA"  # cadence
/tmp/starve                           | perl -MTime::HiRes=time -e "$TSA"  # cadence (default = ncpu)
/tmp/starve_sat                       | perl -MTime::HiRes=time -e "$TSA"  # saturated: beat waits
kai build --release kaikai/wake_entry_fiber.kai -o /tmp/wef
for i in 1 2 3 4 5; do /tmp/wef | perl -MTime::HiRes=time -e "$TSA"; done  # entry fiber: ~4/5 late
elixir elixir/starve.exs               | perl -MTime::HiRes=time -e "$TSA"
elixir --erl "+S 1" elixir/starve.exs  | perl -MTime::HiRes=time -e "$TSA"
```

## Where kaikai wins / the trade-off

- **Preemption costs throughput.** Reduction accounting is part of why the
  same serial loop runs ~3.4× slower on the BEAM (case 6). Cooperative
  fibers spend zero cycles on it; with no latency requirement that is the
  right trade.
- **The common case is now covered by default.** Since 0.104 the worker
  pool is on without an env var, and any spare worker gives the latency
  BEAM users expect. The gap is real but conditional — it opens under
  saturation and under cancellation, where the BEAM's answer is
  unconditional.
- **This case bit its author.** The 0.100 revision over-claimed from a
  cold-start measurement artifact, upstream refuted it with warm runs and
  a code read, and the refutation is [conceded in full](../../discarded/wake-path-parking/).
  The surviving claims above were re-measured with the corrected protocol
  — warm binaries, in-program anchor — on both runtimes.
- **The mitigation is real but manual:** salt hot loops with
  `spawn.yield()` — discipline where the BEAM has a guarantee, which is
  the symmetric mirror of cases 1–3 (Elixir's discipline vs kaikai's
  guarantee). Stated both ways, on purpose.
