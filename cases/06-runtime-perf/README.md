# Case 6 — runtime performance: native serial vs BEAM parallel

**kaikai wins both axes as of 0.100.0 — after the verdict moved three times
in three releases.** Collatz longest-chain scan, N read from argv, result
printed (nothing constant-folds away), same answer verified everywhere
(`n=3732423 steps=596` at N=5M).

The release-by-release history, because it is the whole point of running
claims:

- **kaikai 0.99.6:** fibers added zero cores (8 fibers = serial wall,
  byte-identical). kaikai won the core (~3.5× serial, 1.7 MB vs 97 MB);
  Elixir won the machine (14 schedulers, 0.44 s wall).
- **kaikai 0.99.11** (`KAI_THREADS=N`, opt-in, default 1): the same 8-fiber
  binary at `KAI_THREADS=8` ran in **0.10 s** — kaikai took the wall-clock
  outright. And the same release **broke the memory story**: the new runtime
  pre-reserved ~169 MB resident at any workload, ~758 MB at 8 threads — the
  BEAM (97 MB) was briefly the *smaller* runtime.
- **kaikai 0.100.0:** the reservation was a bug, and it was fixed one point
  release after it shipped (0.99.12: "lazy-materialise the RC free-list
  pools — restore ~2 MiB idle RSS"). Re-measured below: **2.6 MB at 8
  threads**, 0.08 s wall. Both axes are kaikai's again.

## Measured (N = 5M, min of 3 warm runs, `/usr/bin/time -l`, 14-core M-series)

kaikai 0.100.0 / Elixir 1.19.5 (OTP 28), re-run same day, same machine:

| Variant | Wall | Peak RSS |
|---|---|---|
| kaikai serial `--release` | 0.57 s | **1.8 MB** |
| kaikai 8 fibers, default (1 thread) | 0.58 s | 2.3 MB |
| kaikai 8 fibers, `KAI_THREADS=8` | **0.08 s** | **2.6 MB** |
| Elixir serial (`elixir collatz.exs`) | 2.03 s | 97.0 MB |
| Elixir `Task.async_stream`, 14 shards | 0.43 s | 97.4 MB |

Historical rows (kept because the moves are the story): 0.99.6 serial
0.58 s / 1.7 MB; 0.99.11 serial 0.52 s / 169.5 MB; 0.99.11 `KAI_THREADS=8`
0.10 s / 757.7 MB. Note the serial wall also drifted 0.52 → 0.57 s between
0.99.11 and 0.100.0 (~10% — stated, not hidden; still ~3.6× the BEAM JIT).

Boot note: ~0.22 s of every Elixir row is BEAM startup (`elixir -e ""`
costs that much; the kaikai binary starts in ~0 ms). Subtract it and
Elixir's parallel *compute* is ~0.21 s — still ~2.6× the kaikai 8-thread
wall.

## What each side proves

**kaikai wins the core and the machine:** native codegen makes the serial
loop ~3.6× faster than the BEAM JIT, and the work-stealing scheduler makes
the *same unmodified fiber code* scale — `KAI_THREADS=8` turns 0.58 s into
0.08 s (~7× on 8 threads), beating Elixir's 14-shard 0.43 s by ~5×.

**And the memory story is back:** 2.6 MB at 8 threads vs the BEAM's 97 MB
floor. The 0.99.11 reservation was real when this repo measured it, and it
was gone one point release later — pre-mapped RC free-list pools, made
lazy. "kaikai converts cycles into less of everything" is true again at
every thread count measured here.

**What ~97 MB of BEAM still buys:** the schedulers are always on,
preemption (case 5) is a guarantee, and OTP is resident. kaikai's
parallelism remains an env var you must know exists.

## Reproduce

```sh
kai build --release kaikai/collatz_recursive.kai -o /tmp/ckai
kai build --release kaikai/collatz_fibers.kai   -o /tmp/ckaif
/usr/bin/time -l /tmp/ckai 5000000
/usr/bin/time -l /tmp/ckaif 5000000                  # default: 1 thread
KAI_THREADS=8 /usr/bin/time -l /tmp/ckaif 5000000    # M:N work stealing
KAI_THREADS=8 /usr/bin/time -l /tmp/ckaif 1000       # RSS floor: ~2.6 MB again
/usr/bin/time -l elixir elixir/collatz.exs 5000000
/usr/bin/time -l elixir elixir/collatz_parallel.exs 5000000
time elixir -e ""        # BEAM boot floor: ~0.22 s
```

All variants must print `n=3732423 steps=596` (fibers: `best steps=596`)
before their time counts.

## Where each side wins / the trade-off

- **Elixir:** `Task.async_stream` is stdlib-idiomatic and its scheduler is
  always on — kaikai's parallelism is an env var you must know exists
  (`KAI_THREADS`, default 1, still undocumented in `kai info fibers` at
  0.100.0). The BEAM's 97 MB buys preemption and OTP, not just parallel
  loops.
- **kaikai:** per-core efficiency is structural (native codegen, ~3.6×)
  and composes with cores: the 0.08 s wall is the fastest number in the
  table by a wide margin, at 1/37th of the BEAM's memory. Messages copy
  across threads (copy-on-cross-thread-send), so the non-atomic Perceus RC
  survives — the design keeps single-thread sends at pointer-transfer cost.
- The honest sentence, updated again: **kaikai converts cycles and cores
  into wall-clock at megabyte scale; the BEAM converts its 97 MB into
  guarantees.** This table moved three times in three releases — one of
  them because a regression this repo measured was fixed upstream within a
  day of shipping. Re-run on the next release of either.
