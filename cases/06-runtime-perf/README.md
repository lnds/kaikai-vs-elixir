# Case 6 — runtime performance: native serial vs BEAM parallel

**Split verdict, measured.** Collatz longest-chain scan, N read from argv,
result printed (nothing constant-folds away), same answer verified everywhere
(`n=3732423 steps=596` at N=5M). kaikai compiles to native code and wins the
serial race by ~3.5× and memory by ~58×. Elixir's 14 schedulers win the
wall-clock outright — even paying BEAM boot inside the measurement — because
kaikai's fibers add zero cores. Both facts are the point.

## Measured (N = 5M, min of 3 warm runs, `/usr/bin/time -l`, 14-core M-series)

| Variant | Wall | Peak RSS |
|---|---|---|
| kaikai serial, `--release` native | **0.58 s** | **1.7 MB** |
| kaikai 8 fibers, `--release` | 0.58 s | 2.3 MB |
| Elixir serial (`elixir collatz.exs`) | 2.05 s | 96.9 MB |
| Elixir `Task.async_stream`, 14 shards | **0.44 s** | 97.3 MB |

Boot note: ~0.22 s of every Elixir row is BEAM startup (`elixir -e ""` costs
that much; the kaikai binary starts in ~0 ms). Subtract it and Elixir's
compute is ~1.83 s serial / ~0.22 s parallel — the parallel *compute* beats
kaikai serial by ~2.6×, near-linear scaling across 14 cores.

## What each side proves

**kaikai serial wins on codegen:** the tail-recursive scan compiles to a
native loop; 0.58 s and 1.7 MB resident is the whole story. The BEAM's JIT
(OTP 28) is respectable at 2.05 s — ~3.5× off native for pure integer
recursion, with a ~97 MB VM floor under it.

**Elixir wins the ceiling:** [`elixir/collatz_parallel.exs`](elixir/collatz_parallel.exs)
shards the range with `Task.async_stream` — idiomatic, ~10 lines — and the
CPU time (2.3 s) spreads across 14 schedulers for 0.44 s of wall. kaikai's
[`collatz_fibers.kai`](kaikai/collatz_fibers.kai) runs the same 8-shard shape
in 0.58 s: byte-identical to its serial time. Fibers are a concurrency
construct, not a parallelism one — there is no multi-core story in kaikai
today, and no number of fibers changes the wall-clock of CPU-bound work.

## Reproduce

```sh
kai build --release kaikai/collatz_recursive.kai -o /tmp/ckai
kai build --release kaikai/collatz_fibers.kai   -o /tmp/ckaif
/usr/bin/time -l /tmp/ckai 5000000
/usr/bin/time -l /tmp/ckaif 5000000
/usr/bin/time -l elixir elixir/collatz.exs 5000000
/usr/bin/time -l elixir elixir/collatz_parallel.exs 5000000
# startup floor:
time elixir -e ""        # ~0.22 s
```

All variants must print `n=3732423 steps=596` before their time counts.

## Where each side wins / the trade-off

- **Elixir:** on a 14-core box the parallel wall-clock is the number that
  ships. `Task.async_stream` is one import away from any Enum pipeline, and
  the same primitives run a million I/O-bound processes. Until kaikai
  schedules fibers across cores, Elixir owns "use the whole machine".
- **kaikai:** per-core efficiency (3.5×) and memory (58×) are structural,
  not tuning — native codegen and Perceus RC versus a JIT'd VM with a
  ~97 MB floor. For CLI tools, embedded targets, or anything billed per MB,
  that floor is disqualifying for the BEAM and free for kaikai. The ~0 ms
  binary startup versus ~0.22 s BEAM boot points the same direction (and is
  why the Elixir world grows escript/Burrito workarounds for CLI shapes).
- The honest sentence: **Elixir converts cores into wall-clock; kaikai
  converts cycles into less of everything** — and each is one release away
  from attacking the other's edge (kaikai: multi-core fibers; Elixir: the
  type checker closing case 1–3 gaps, though a native-code gap this size is
  not a roadmap item).
