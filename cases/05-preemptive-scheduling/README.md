# Case 5 — cooperative fibers vs preemptive processes

**Category C — Elixir wins, re-verified after kaikai 0.99.11 shipped
multi-threading.** The same two-task program — one pure-CPU Collatz hog
(~340 ms of crunch), one heartbeat that prints and sleeps 50 ms — behaves
differently on the two runtimes, and the difference survives kaikai's new
M:N scheduler: parallelism is not preemption.

kaikai 0.99.11 added an M:N work-stealing scheduler (`KAI_THREADS=N`,
opt-in, default 1). That moved case 6's numbers dramatically — and this
case's only partially, which is exactly the point.

## The claim

> Under kaikai's default (1 scheduler thread) the heartbeat prints
> **nothing until the hog finishes** — 338 ms of starvation, timestamped.
> With `KAI_THREADS=2` the *first* beat escapes via work-stealing (10 ms),
> but the beat that wakes from `sleep` re-queues **behind the hog** and
> waits out the crunch (340 ms) — even with idle threads (same at
> `KAI_THREADS=4`). The BEAM preempts on reduction count: every beat lands
> on time, ~1 s before the hog ends, **even pinned to a single scheduler**
> (`+S 1`). Latency under CPU load is a guarantee in Elixir and remains
> best-effort in kaikai at any thread count.

## Measured (timestamps = ms since process start)

[`kaikai/starve.kai`](kaikai/starve.kai) built `--release`, kaikai 0.99.11:

```text
-- default (1 thread) --          -- KAI_THREADS=2 --
[  338ms] heartbeat 3             [   10ms] heartbeat 3
[  390ms] heartbeat 2             [  340ms] heartbeat 2
[  442ms] heartbeat 1             [  391ms] heartbeat 1
[  494ms] hog done: acc=428343355 [  443ms] hog done: acc=428343355
```

Default: the first beat waits out the entire crunch — cooperative
scheduling, no preemption (the docs are explicit: cancellation lands "at
the next yield point", "there is no preemption"). With 2 threads: the
ready heartbeat is stolen by the idle worker immediately (10 ms — real
parallelism), but after its 50 ms sleep it wakes on the reactor path and
parks behind the hog until 340 ms. `KAI_THREADS=4` reproduces it with
2–3 workers idle: the wake-path re-enqueue is not stolen. So threads mask
starvation for *ready* fibers and not for *waking* ones.

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
KAI_THREADS=4 /tmp/starve   | perl -MTime::HiRes=time -ne "$TS"   # same, with idle workers
elixir elixir/starve.exs               | perl -MTime::HiRes=time -ne "$TS"
elixir --erl "+S 1" elixir/starve.exs  | perl -MTime::HiRes=time -ne "$TS"
```

## Where kaikai wins / the trade-off

- **Preemption costs throughput.** Reduction accounting is part of why the
  same serial loop runs ~3.5× slower on the BEAM (case 6). Cooperative
  fibers spend zero cycles on it; with no latency requirement that is the
  right trade.
- **M:N is one release old and moving fast.** Work-stealing already
  rescues the ready-fiber case (10 ms); the wake-path gap is the kind of
  scheduler follow-up that ships in a point release — re-run this case on
  the next upgrade (the sibling repos' verdicts moved exactly this way).
- **The mitigation is real but manual:** salt hot loops with
  `spawn.yield()` — discipline where the BEAM has a guarantee, which is
  the symmetric mirror of cases 1–3 (Elixir's discipline vs kaikai's
  guarantee). Stated both ways, on purpose.
