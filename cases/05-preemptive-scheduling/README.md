# Case 5 — cooperative fibers vs preemptive processes

**Category C — Elixir wins, narrowed hard at 0.104.0, and with a
retraction.** The same two-task program — one pure-CPU Collatz hog (~340 ms
of crunch), one heartbeat that prints and sleeps 50 ms — still separates
the two runtimes, but on a thinner line than this case previously claimed:
kaikai 0.104 turns multi-threading **on by default** (worker count = host
cores), and with any spare worker the heartbeat now lands on perfect
cadence. What remains Elixir's is the *guarantee*: under saturation
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

## The claim (0.104.0)

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

## Measured (kaikai 0.104.0, warm binary, t0 = the program's `start` line)

[`kaikai/starve.kai`](kaikai/starve.kai) built `--release` (1 hog + heartbeat):

```text
-- KAI_THREADS=1 --        -- KAI_THREADS=2 --        -- default (14 = ncpu) --
[  341ms] heartbeat 3      [    0ms] heartbeat 3      [    0ms] heartbeat 3
[  392ms] heartbeat 2      [   49ms] heartbeat 2      [   50ms] heartbeat 2
[  444ms] heartbeat 1      [   99ms] heartbeat 1      [  101ms] heartbeat 1
[  494ms] hog done         [  344ms] hog done         [  351ms] hog done
```

[`kaikai/starve_saturate.kai`](kaikai/starve_saturate.kai) — 16 hogs over
the 14 default workers, and the cancellation probe (repro in kai#1268):

```text
-- 16 hogs, default(14) --      -- Spawn.cancel of a pure-CPU fiber --
[  423ms] heartbeat 3           [    6ms] cancel requested
[  473ms] heartbeat 2           [  343ms] nursery exited   (fiber ran to completion)
[  524ms] heartbeat 1
[  761ms] hogs done
```

(all runs: `acc=428343355`; each column stable across 3+ warm runs)

[`elixir/starve.exs`](elixir/starve.exs), same anchor:

```text
-- 14 schedulers --               -- +S 1 (single scheduler) --
[    2ms] heartbeat 3             [    2ms] heartbeat 3
[   53ms] heartbeat 2             [   52ms] heartbeat 2
[  104ms] heartbeat 1             [  103ms] heartbeat 1
[ 1120ms] hog done                [ 1641ms] hog done: acc=428343355
```

`+S 1` **is** the saturated shape — one hog fully occupies the only
scheduler — and every beat still lands on its 50 ms cadence, ~1.5 s before
the hog ends. The BEAM charges every call against a reduction budget
(~4000) and deschedules mid-computation; no yield point needs to exist. In
kaikai the saturated beat waits until a hog *finishes* (~350–420 ms here);
the wait scales with the crunch, unbounded in general. The open upstream
proposal to close this for real — compiler-inserted safepoints, a
BEAM-style reduction budget — is
[kai#1269](https://github.com/lnds/kaikai/issues/1269)
([kai#1268](https://github.com/lnds/kaikai/issues/1268), the cancellation
measurement, was folded into it; re-verified unchanged on 0.104).

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
