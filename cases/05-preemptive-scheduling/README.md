# Case 5 — cooperative fibers vs preemptive processes

**Category C — Elixir wins, re-verified on kaikai 0.99.11 and again on
0.100.0.** The same two-task program — one pure-CPU Collatz hog (~340 ms of
crunch), one heartbeat that prints and sleeps 50 ms — behaves differently
on the two runtimes, and the difference survives kaikai's M:N scheduler:
parallelism is not preemption.

kaikai 0.99.11 added an M:N work-stealing scheduler (`KAI_THREADS=N`,
opt-in, default 1). That moved case 6's numbers dramatically — and this
case's only partially, which is exactly the point. 0.100.0 moved it a bit
further (the `KAI_THREADS=4` column below), and the core verdict still
holds.

## The claim

> Under kaikai's default (1 scheduler thread) the heartbeat prints
> **nothing until the hog finishes** — ~330 ms of starvation, timestamped.
> With `KAI_THREADS=2` the *first* beat escapes via work-stealing (~0 ms),
> but the beat that wakes from `sleep` re-queues **behind the hog** and
> waits out the crunch (~337 ms) — with one worker idle the whole time. At
> `KAI_THREADS=4` (0.100.0) the waking beat does get picked up and all
> beats land on cadence — but that is scheduling luck scaling with spare
> threads, not a guarantee. The BEAM preempts on reduction count: every
> beat lands on time, ~1 s before the hog ends, **even pinned to a single
> scheduler** (`+S 1`). Latency under CPU load is a guarantee in Elixir
> and remains best-effort in kaikai at any thread count.

## Measured (timestamps = ms since process start)

[`kaikai/starve.kai`](kaikai/starve.kai) built `--release`, kaikai 0.100.0:

```text
-- default (1 thread) --   -- KAI_THREADS=2 --        -- KAI_THREADS=4 --
[  330ms] heartbeat 3      [    0ms] heartbeat 3      [    0ms] heartbeat 3
[  382ms] heartbeat 2      [  337ms] heartbeat 2      [   49ms] heartbeat 2
[  434ms] heartbeat 1      [  389ms] heartbeat 1      [   99ms] heartbeat 1
[  486ms] hog done         [  441ms] hog done         [  341ms] hog done
```

(all runs: `acc=428343355`; each column stable across 3 runs)

Default: the first beat waits out the entire crunch — cooperative
scheduling, no preemption (the docs are explicit: cancellation lands "at
the next yield point", "there is no preemption"). With 2 threads: the
ready heartbeat is stolen by the idle worker immediately (real
parallelism), but after its 50 ms sleep it wakes on the reactor path and
parks behind the hog until ~337 ms — while the other worker sits idle.
At 4 threads the waking beat does get picked up (this changed between
0.99.11 and 0.100.0 — at 0.99.11, `=4` parked exactly like `=2`). But
that is placement luck, not a fix: with **four** hogs and `KAI_THREADS=8`
(4 workers idle), the woken beat parks again until ~335 ms, and with 4
hogs saturating `=4` the first beat waits **858 ms** — worse than the
1-thread column. Two further measurements complete the picture, filed
upstream with their repros: the wake-path re-enqueue is not stealable by
idle workers ([kai#1267](https://github.com/lnds/kaikai/issues/1267)),
and `Spawn.cancel` on a pure-CPU fiber never lands at all — requested at
9 ms, the fiber runs its remaining ~310 ms and the nursery blocks on it
([kai#1268](https://github.com/lnds/kaikai/issues/1268)). The proposed
fix for the guarantee itself — a BEAM-style reduction budget as
compiler-inserted safepoints — is
[kai#1269](https://github.com/lnds/kaikai/issues/1269).

[`elixir/starve.exs`](elixir/starve.exs) (first ~0.2–0.4 s is BEAM boot +
script compile; what matters is beats-vs-hog ordering):

```text
-- 14 schedulers --               -- +S 1 (single scheduler) --
[  401ms] heartbeat 3             [  221ms] heartbeat 3
[  451ms] heartbeat 2             [  272ms] heartbeat 2
[  502ms] heartbeat 1             [  323ms] heartbeat 1
[ 1478ms] hog done: acc=428343355 [ 1690ms] hog done: acc=428343355
```

All three beats land on their 50 ms cadence while the hog is
mid-crunch, finishing ~1 s before it — on one scheduler thread too. The
BEAM charges every call against a reduction budget (~4000) and
deschedules mid-computation; no yield point needs to exist.

Both languages compute the same `acc=428343355` (the hog is a Collatz
scan precisely so LLVM cannot fold it — a bare counter loop it *did*
fold in an earlier draft, which would have measured nothing).

## Reproduce

```sh
kai build --release kaikai/starve.kai -o /tmp/starve
TS='BEGIN{$t0=time} printf "[%5dms] %s", (time-$t0)*1000, $_'
/tmp/starve                 | perl -MTime::HiRes=time -ne "$TS"   # starves
KAI_THREADS=2 /tmp/starve   | perl -MTime::HiRes=time -ne "$TS"   # beat 1 escapes, beat 2 parks
KAI_THREADS=4 /tmp/starve   | perl -MTime::HiRes=time -ne "$TS"   # on cadence since 0.100.0
elixir elixir/starve.exs               | perl -MTime::HiRes=time -ne "$TS"
elixir --erl "+S 1" elixir/starve.exs  | perl -MTime::HiRes=time -ne "$TS"
```

## Where kaikai wins / the trade-off

- **Preemption costs throughput.** Reduction accounting is part of why the
  same serial loop runs ~3.6× slower on the BEAM (case 6). Cooperative
  fibers spend zero cycles on it; with no latency requirement that is the
  right trade.
- **M:N is young and moving fast — measurably.** Work-stealing rescued the
  ready-fiber case at 0.99.11; between 0.99.11 and 0.100.0 the waking-fiber
  case at `=4` went from parked to on-cadence. The remaining gaps are now
  filed with repros (kai#1267 fairness, kai#1268 cancellation, kai#1269
  the reduction-budget proposal) — re-run this case on every upgrade (its
  numbers have moved on each one so far).
- **The mitigation is real but manual:** salt hot loops with
  `spawn.yield()` — discipline where the BEAM has a guarantee, which is
  the symmetric mirror of cases 1–3 (Elixir's discipline vs kaikai's
  guarantee). Stated both ways, on purpose.
