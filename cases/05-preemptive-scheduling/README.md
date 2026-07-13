# Case 5 — cooperative fibers vs preemptive processes

**Category C — Elixir wins.** The same two-task program — one pure-CPU loop,
one heartbeat — behaves oppositely on the two runtimes, and the difference is
the scheduler, not the code. kaikai's fibers are cooperative: a fiber that
never yields starves its siblings. The BEAM preempts on reduction count: no
process can starve another, and no yield point needs to exist.

## The claim

> Spawn a CPU-bound loop (300M iterations, no I/O, no yields) next to a
> heartbeat printer. In kaikai the heartbeat prints **nothing until the hog
> finishes** (~0.5 s of starvation here; a 60 s hog means 60 s of silence).
> In Elixir the heartbeats print **first, immediately — even pinned to a
> single scheduler thread** (`+S 1`), because the BEAM preempts the hog every
> few thousand reductions. Latency under CPU load is a property Elixir's
> runtime guarantees and kaikai's does not.

## kaikai — the hog owns the thread

[`kaikai/starve.kai`](kaikai/starve.kai), built `--release`:

```text
hog done: 300000000
heartbeat 3
heartbeat 2
heartbeat 1
```

The heartbeat fiber was spawned and ready the whole time; it ran only after
the hog's ~0.5 s of pure CPU ended. Cancellation is cooperative too — the
docs are explicit that `Spawn.cancel` is delivered "at its next yield point"
and "there is no preemption" — so a runaway fiber also cannot be stopped
until it yields. The reactor parks fibers on I/O, so *I/O-bound* fibers
interleave fine; the starvation is specifically CPU-shaped work.

## Elixir — reductions preempt everything

[`elixir/starve.exs`](elixir/starve.exs), same shape:

```text
heartbeat 3
heartbeat 2
heartbeat 1
hog done: 300000000
```

And the sharper version — force a single scheduler thread so multi-core
cannot explain it, `elixir --erl "+S 1" starve.exs`:

```text
heartbeat 3
heartbeat 2
heartbeat 1
hog done: 300000000
```

Same interleaving. The BEAM charges every function call against a reduction
budget (~4000); when it runs out, the process is descheduled mid-
computation, whether or not it ever calls anything that yields. That budget
is why an Erlang node stays responsive to its shell, its distribution
heartbeats, and its supervisors while saturated with work — soft-realtime
as a runtime property, not a coding discipline.

## Reproduce

```sh
kai build --release kaikai/starve.kai -o /tmp/starve && /tmp/starve
elixir elixir/starve.exs
elixir --erl "+S 1" elixir/starve.exs   # still interleaves: preemption, not parallelism
```

## Where kaikai wins / the trade-off

- **Preemption costs throughput.** The reduction accounting and process
  switching are part of why the same serial loop runs ~3.5× slower on the
  BEAM (case 6). kaikai's cooperative fibers spend zero cycles on
  preemption machinery; when your workload has no latency requirement, that
  is the right trade.
- **Cooperative scheduling is predictable.** No context switch can land
  between two arbitrary instructions, which makes reasoning about
  interleavings (and writing lock-free structures) simpler. The BEAM buys
  its guarantee by making *every* call a potential switch point.
- **The mitigation is real but manual:** in kaikai you can salt a hot loop
  with `spawn.yield()` — at the cost of remembering to, which is exactly
  the kind of discipline-over-guarantee this repo dings Elixir for
  elsewhere. Stated symmetrically: on latency, Elixir has the guarantee
  and kaikai has the discipline.
