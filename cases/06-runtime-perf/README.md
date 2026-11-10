# Case 6 — runtime performance: native serial vs BEAM parallel

**kaikai wins both axes, and since 0.104.0 it does so by default — after
the verdict moved three times in three releases.** Collatz longest-chain
scan, N read from argv, result printed (nothing constant-folds away), same
answer verified everywhere (`n=3732423 steps=596` at N=5M).

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
- **kaikai 0.100.0:** the reservation was a bug, fixed one point release
  after it shipped (0.99.12: "lazy-materialise the RC free-list pools").
  2.6 MB at 8 threads, 0.08 s wall — both axes kaikai's again.
- **kaikai 0.104.0:** multi-threading is **on by default** (workers = host
  cores, no env var). The unmodified fiber binary hits its 0.08 s with zero
  configuration — the standing caveat "kaikai's parallelism is an env var
  you must know exists" is gone. Cost, stated: the default worker pool
  holds ~11–12 MB RSS (vs ~2 MB single-thread) and the serial wall drifted
  0.57 → 0.63 s.
- **kaikai 0.114.0:** ten releases of front-end work (symbol table, module
  and namespace resolution, Perceus fixes) and **no scheduler change** —
  the shape holds and the serial drift partly reversed: 0.63 → 0.57 s. The
  fiber wall, the RSS figures and the answers are unmoved.
- **kaikai 0.192.6:** walls unmoved (serial 0.56 s, fibers 0.08 s), but the
  **default worker-pool RSS is gone**: serial 11.3 → 1.8 MB and the
  default 14-thread fiber run 11.7 → 3.5 MB. The ~2 MB floor is now the
  default, not an env-var escape hatch, so the memory gap to the BEAM is
  ~26× again rather than ~8×. The 0.192 Perceus/native codegen work did
  not move this loop: it is integer-only tail recursion with no
  allocation to reuse.

## Measured (N = 5M, min of 3 warm runs, `/usr/bin/time -l`, 14-core M-series)

kaikai 0.192.6 / Elixir 1.19.5 (OTP 28), re-run same day, same machine,
kaikai and Elixir runs interleaved (RSS = max resident bytes / 2^20):

| Variant | Wall | Peak RSS |
|---|---|---|
| kaikai serial `--release` | 0.56 s | **1.8 MB** |
| kaikai serial, `KAI_THREADS=1` | 0.56 s | 1.8 MB |
| kaikai 8 fibers, default (14 threads) | **0.08 s** | 3.5 MB |
| kaikai 8 fibers, `KAI_THREADS=8` | **0.08 s** | 2.9 MB |
| kaikai 8 fibers, `KAI_THREADS=1` | 0.56 s | 2.1 MB |
| Elixir serial (`elixir collatz.exs`) | 1.97 s | 91.4 MB |
| Elixir `Task.async_stream`, 14 shards | 0.42 s | 92.6 MB |

Run-to-run spread over the 3 reps: kaikai walls within ±0.01 s except one
`KAI_THREADS=8` outlier at 0.14 s; Elixir serial 1.97–2.19 s, parallel
0.42–0.43 s; RSS identical across reps for kaikai, 91.4–95.5 MB for the
BEAM.

0.114.0 rows: serial 0.57 s / 11.3 MB; `KAI_THREADS=1` 0.56 s / 1.9 MB;
fibers default 0.08 s / 11.7 MB; `=8` 0.08 s / 11.2 MB; `=1` 0.56 s /
2.4 MB; Elixir 1.95 s / 92.1 MB and 0.43 s / 92.8 MB.

Historical rows (kept because the moves are the story): 0.99.6 serial
0.58 s / 1.7 MB; 0.99.11 serial 0.52 s / 169.5 MB; 0.99.11 `KAI_THREADS=8`
0.10 s / 757.7 MB; 0.100.0 serial 0.57 s / 1.8 MB; 0.100.0 `=8` 0.08 s /
2.6 MB; 0.104.0 serial 0.63 s / 11.3 MB. The serial wall has drifted
0.52 → 0.57 → 0.63 → 0.57 → 0.56 s across five releases — stated, not
hidden (~3.5× the BEAM JIT at 0.192.6). The default RSS rose from ~2 MB
to ~11 MB when the worker pool became default-on (0.104) and is back at
~2 MB by 0.192.6 (serial) / 3.5 MB (14-thread fibers).

Boot note: ~0.15 s of every Elixir row is BEAM startup (`elixir -e ""`
costs that much; the kaikai binary starts in ~0 ms). Subtract it and
Elixir's parallel *compute* is ~0.27 s — still ~3× the kaikai default
wall.

## What each side proves

**kaikai wins the core and the machine, now without being asked:** native
codegen makes the serial loop ~3.4× faster than the BEAM JIT, and the
default-on work-stealing scheduler makes the *same unmodified fiber code*
scale — 0.08 s on 14 workers, beating Elixir's 14-shard 0.42 s by ~5×,
at ~1/26th of the BEAM's memory.

**The memory story:** from 0.104 to 0.114 the default-on worker pool cost
~11–12 MB, a slice of the megabyte story traded for the BEAM's always-on
posture. At 0.192.6 that cost is gone: the default serial run is 1.8 MB
and the 14-thread fiber run 3.5 MB, against the BEAM's ~92 MB.

**What ~92 MB of BEAM still buys:** preemption (case 5) is a guarantee
rather than spare capacity, and OTP is resident. The schedulers-always-on
point, however, is no longer a differentiator — kaikai's are too.

## Reproduce

```sh
kai build --release kaikai/collatz_recursive.kai -o /tmp/ckai
kai build --release kaikai/collatz_fibers.kai   -o /tmp/ckaif
/usr/bin/time -l /tmp/ckai 5000000
/usr/bin/time -l /tmp/ckaif 5000000                  # default: workers = ncpu
KAI_THREADS=8 /usr/bin/time -l /tmp/ckaif 5000000    # pinned, comparable to 0.100 rows
KAI_THREADS=1 /usr/bin/time -l /tmp/ckaif 5000000    # single-thread escape hatch
KAI_THREADS=1 /usr/bin/time -l /tmp/ckaif 1000       # RSS floor: ~2.1 MB (default: ~3.6 MB)
/usr/bin/time -l elixir elixir/collatz.exs 5000000
/usr/bin/time -l elixir elixir/collatz_parallel.exs 5000000
time elixir -e ""        # BEAM boot floor: ~0.15 s
```

All variants must print `n=3732423 steps=596` (fibers: `best steps=596`)
before their time counts.

## Where each side wins / the trade-off

- **Elixir:** `Task.async_stream` is stdlib-idiomatic, and the BEAM's
  92 MB buys preemption and OTP, not just parallel loops. kaikai's serial
  wall has wandered 0.52–0.63 s across five releases (0.56 s at 0.192.6);
  the BEAM JIT's number has not moved.
- **kaikai:** per-core efficiency is structural (native codegen, ~3.5×)
  and composes with cores by default: 0.08 s is the fastest number in
  the table by a wide margin, at a few MB against the BEAM's ~92. Messages
  copy across threads (copy-on-cross-thread-send), so the non-atomic
  Perceus RC survives — single-thread sends keep pointer-transfer cost.
- The honest sentence, updated again: **kaikai converts cycles and cores
  into wall-clock at megabyte scale; the BEAM converts its 92 MB into
  guarantees.** This table has moved on every release measured — one of
  them because a regression this repo measured was fixed upstream within a
  day of shipping. Re-run on the next release of either.
