# Case 6 — runtime performance: native serial vs BEAM parallel

**Split verdict, measured — and re-measured after kaikai 0.99.11 shipped an
M:N scheduler, which moved it in *both* directions.** Collatz longest-chain
scan, N read from argv, result printed (nothing constant-folds away), same
answer verified everywhere (`n=3732423 steps=596` at N=5M).

The one-release history, because it is the whole point of running claims:

- **kaikai 0.99.6:** fibers added zero cores (8 fibers = serial wall,
  byte-identical). kaikai won the core (~3.5× serial, 1.7 MB vs 97 MB);
  Elixir won the machine (14 schedulers, 0.44 s wall).
- **kaikai 0.99.11** (`KAI_THREADS=N`, opt-in, default 1): the same 8-fiber
  binary at `KAI_THREADS=8` runs in **0.10 s** — kaikai now wins the
  wall-clock outright. And the same release **broke the memory story**: the
  new runtime pre-reserves ~169 MB resident at any workload (measured at
  N=1000, `KAI_THREADS=1`), ~758 MB at 8 threads — so at defaults the BEAM
  (97 MB) is now the *smaller* runtime. One release, two verdict moves,
  opposite directions.

## Measured (N = 5M, min of 3 warm runs, `/usr/bin/time -l`, 14-core M-series)

| Variant | Wall | Peak RSS |
|---|---|---|
| kaikai serial `--release` — **0.99.6** | 0.58 s | **1.7 MB** |
| kaikai serial `--release` — **0.99.11** | 0.52 s | 169.5 MB |
| kaikai 8 fibers — 0.99.6 (no threads) | 0.58 s | 2.3 MB |
| kaikai 8 fibers — 0.99.11, default | 0.53 s | 169.5 MB |
| kaikai 8 fibers — 0.99.11, `KAI_THREADS=8` | **0.10 s** | 757.7 MB |
| Elixir serial (`elixir collatz.exs`) | 2.05 s | 96.9 MB |
| Elixir `Task.async_stream`, 14 shards | 0.44 s | 97.3 MB |

Boot note: ~0.22 s of every Elixir row is BEAM startup (`elixir -e ""`
costs that much; the kaikai binary starts in ~0 ms). Subtract it and
Elixir's parallel *compute* is ~0.22 s — still 2× the kaikai 8-thread wall.

## What each side proves

**kaikai wins the core and (now) the machine:** native codegen makes the
serial loop ~3.5× faster than the BEAM JIT, and 0.99.11's work-stealing
scheduler makes the *same unmodified fiber code* scale — `KAI_THREADS=8`
turns 0.53 s into 0.10 s (~5.3× on 8 threads), beating Elixir's 14-shard
0.44 s by ~4.4×. The multicore gap this case dinged kaikai for at 0.99.6
closed in one release, opt-in.

**Elixir wins the floor — currently by forfeit:** ~97 MB of BEAM gets you
the schedulers, preemption (case 5), and OTP. kaikai 0.99.11's fixed
~169 MB reservation (~+84 MB per extra thread) is not a leak
(`KAI_TRACE_RC` is clean: `leaked=7`) but pre-mapped, workload-independent
runtime state — the 0.99.6 binary ran the same N=5M in 1.7 MB. Until that
reservation becomes lazy or sizeable, "kaikai converts cycles into less of
everything" is false at defaults: it is faster *and fatter* than the BEAM.
For CLI/embedded shapes, 0.99.6's 1.7 MB was a headline; 0.99.11 traded it
for cores.

## Reproduce

```sh
kai build --release kaikai/collatz_recursive.kai -o /tmp/ckai
kai build --release kaikai/collatz_fibers.kai   -o /tmp/ckaif
/usr/bin/time -l /tmp/ckai 5000000
/usr/bin/time -l /tmp/ckaif 5000000                  # default: 1 thread
KAI_THREADS=8 /usr/bin/time -l /tmp/ckaif 5000000    # M:N work stealing
/usr/bin/time -l /tmp/ckai 1000                      # RSS floor: ~169 MB at any N
/usr/bin/time -l elixir elixir/collatz.exs 5000000
/usr/bin/time -l elixir elixir/collatz_parallel.exs 5000000
time elixir -e ""        # BEAM boot floor: ~0.22 s
```

All variants must print `n=3732423 steps=596` (fibers: `best steps=596`)
before their time counts.

## Where each side wins / the trade-off

- **Elixir:** `Task.async_stream` is stdlib-idiomatic and its scheduler is
  always on — kaikai's parallelism is an env var you must know exists
  (`KAI_THREADS`, default 1, currently undocumented in `kai info fibers`).
  The BEAM's 97 MB buys preemption and OTP, not just parallel loops; and
  its memory is stable per-process granularity, not a per-thread step
  function.
- **kaikai:** per-core efficiency is structural (native codegen, ~3.5×)
  and now composes with cores: the 0.10 s wall is the fastest number in
  the table by a wide margin. Messages copy across threads
  (copy-on-cross-thread-send), so the non-atomic Perceus RC survives —
  the design keeps single-thread sends at pointer-transfer cost.
- The honest sentence, updated: **kaikai now converts both cycles and
  cores into wall-clock; the BEAM still converts its 97 MB into
  guarantees** — and kaikai's new 169 MB floor is the first number in
  this repo where Elixir is the lighter runtime. Re-run on the next
  release of either; this table has already moved once.
