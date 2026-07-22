# CLAUDE.md — kaikai-vs-elixir

Adversarial, honest comparison repo between **kaikai** and **Elixir**. Every
claim is proven by compiling/running code, never asserted. Sibling of
`../kaikai-vs-rust` and `../kaikai-vs-golang`, same methodology, different
target: Elixir's space is the BEAM — preemptive processes, multi-core
schedulers, supervision/fault-tolerance, dynamic language acquiring a
gradual type checker. Remote: github.com/lnds/kaikai-vs-elixir, **private**
— push only when the owner asks; the owner decides when it goes public.

## What this repo is

- `cases/NN-*/` — one folder per case: `README.md`, `elixir/` (the idiomatic
  code a competent Elixir dev would write, `.ex` when compile-time behavior
  matters, `.exs` for runtime demos), `kaikai/` (the `.kai` that runs, plus a
  `*_missing_*`/`*_bad` variant showing the compile error where relevant).
  READMEs paste real outputs.
- `beyond-elixir/` — kaikai-only features Elixir has no form for (high bar:
  macros + the 1.19 checker give Elixir a form for a lot; property testing
  and test injection were excluded on that ground).
- `discarded/` — candidate claims refuted by running them, documented not
  deleted. Two entries: the struct-typo claim the 1.19 checker killed, and
  **wake-path-parking — this repo's own kaikai claim, refuted by upstream
  and conceded** (see case 5 facts below).
- Verified against **Elixir 1.19.5 / OTP 28** (JIT, 14 schedulers, asdf) and
  **kaikai 0.104.0** (native backend, self-hosted stage 2); first built on
  0.99.6, re-verified on 0.99.11 (M:N threading **moved cases 5 and 6**),
  0.100.0 (RSS regression fixed; ahu#34 fixed in v0.2.1), and 0.104.0
  (**KAI_THREADS defaults to ncpu** → case 6 wins by default, case 5
  narrowed + parking claim retracted — history in those READMEs). 14-core
  machine (matters for cases 5–6).

### Case status (who wins)

| # | Case | Verdict |
|---|------|---------|
| 1 | typing-holes | kaikai (safety) — struct/dot typos: 1.19 **warns** (exit 0, .beam ships); `cfg[:typo]` Access: silent nil; kaikai: compile error w/ did-you-mean. Bonus finding: a crashing .exs dies before its buffered warning prints |
| 2 | exhaustive-match | kaikai (safety) — tagged tuples + @type/@spec: elixirc silent, runtime CaseClauseError (loud+named, credited); dialyzer flags the call site (opt-in, needs PLT + elixir ebin on code path); kaikai names the missing variant at build |
| 3 | error-handling | kaikai (safety; ergonomics a wash) — `with` is genuinely good; forgetting `{:error,_}` compiles + MatchError; kaikai unhandled effect row = compile error |
| 4 | fault-tolerance | **Elixir** (narrowed) — one-line Supervisor restarts a crashed GenServer, app never stops. kaikai nursery default = fail-fast exit 1; Link+trap_exit hand-rolled supervisor WORKS; AND the **ahu** framework column runs the same real fault under `restartable_cell(Permanent, Limit(3))`: 3 restarts w/ state reset + escalation, exit 0. Elixir keeps registry/defaults/maturity. Running ahu found a real bug — filed as ahu#34, **fixed upstream in v0.2.1**, fix re-verified both directions (below) |
| 5 | preemptive-scheduling | **Elixir** (narrowed hard at 0.104, WITH A RETRACTION) — threads default-on: any spare worker → beats on 50 ms cadence (0/49/99 at `=2`, `=4`, default 14). The old "wake parks behind hog" claim (kai#1267) was OUR measurement artifact — conceded in `discarded/wake-path-parking/`. What survives for Elixir: `=1` starves (~340 ms), SATURATION (16 hogs ≥ 14 workers → first beat ~420 ms; hogs=workers → ~350 ms), and `Spawn.cancel` on pure-CPU never lands (req ~6 ms, fiber runs full ~340 ms). BEAM: cadence under any load even `+S 1` |
| 6 | runtime-perf | **kaikai, now BY DEFAULT** — 0.104.0 Collatz N=5M: fibers default (14 threads) **0.08 s** (beats Elixir 14-shard 0.49 s ~6×); serial 0.63 s (drift 0.52→0.57→0.63 across releases, stated); Elixir serial 2.14 s. RSS: default worker pool costs ~11–12 MB (vs BEAM 92 MB); `KAI_THREADS=1` keeps the ~2 MB floor. Same answer everywhere: n=3732423 steps=596 |

## Elixir facts that bit / matter here

- **1.19's type checker is load-bearing for honesty.** It warns on unknown
  struct fields AND on unknown keys of maps returned across function
  boundaries (inference, no annotations). It does NOT check `Access`
  (`m[:k]`) reads, does NOT do case exhaustiveness (even with @type+@spec,
  even with the bad call in the same module), does NOT flag partial matches
  like `{:ok, n} = fallible()`. All warnings are exit-0. Re-test all of this
  on every Elixir upgrade — claims here have a short shelf life.
- **Warnings are buffered per compilation**: an .exs whose execution crashes
  can die before the warning that predicted the crash is printed (case 1
  tier c). Compile-only (`elixir file.ex` with no top-level call) shows it.
- **Struct literals can't be used in the defining script's top level**
  (`cannot access struct User ... same context that defines it`) — put the
  demo call inside another module's function.
- **Dialyzer on OTP 28 + Elixir 1.19**: `--build_plt --apps ... <elixir
  ebin>` **crashed**; what works: minimal PLT (`--apps erts kernel stdlib`,
  ~7 s) then `dialyzer -pa <elixir ebin> Elixir.Mod.beam`. It flags the bad
  call site via success typing; it says nothing about the non-exhaustive
  case with no analyzed caller.
- `elixirc` in a dir with stale `Elixir.*.beam` redefines modules (warning
  noise) — `rm -f Elixir.*.beam` between runs; NB `rm -f *.beam` errors in
  zsh when no match (`setopt`-dependent), ignore or glob-guard.
- BEAM boot floor here: **~0.22 s** (`time elixir -e ""`); kaikai binary
  ~0 ms. Included inside case 6's Elixir rows, stated in the README.
- Collatz sanity outputs: N=1M `n=837799 steps=524`; N=5M `n=3732423
  steps=596` — verify before timing anything.

## kaikai facts that bit / matter here

`kai info <topic>` is the source of truth (`fibers`, `actors`, `effects`,
`syntax`). Specifics this repo leans on:

- **Records**: `type AppConfig = { timeout: Int, retries: Int }` (there is NO
  `record` keyword). Field typo → `error: no field 'retires' (did you mean
  .retries?)`.
- **Supervision primitives exist and work on 0.99.6**: `Link.link(pid)` +
  `spawn.set_trap_exit(true)` turns a linked child's death into a mailbox
  String — a real fault (10/0) arrives as `"Trapped: divide by zero"`, and
  the supervisor survives and can respawn (case 4's supervise.kai, exit 0).
  `Monitor.monitor(pid)` exists (v1: pushes bare pid). NO `unlink`, NO
  supervision framework/strategies — that's Elixir's win, stated as such.
- **Nursery default is fail-fast**: a child fault cancels siblings, program
  prints `kai: nursery child cancelled; no survivors`, exit 1.
- **ahu (kaikailang-org/ahu, v0.2.1) is kaikai's fault-tolerance framework**
  — cells (typed GenServer shape) + restart helpers (`Permanent | Transient
  | Temporary`, `Limit(n)`, `with_restart_backoff`, escalation via Cancel;
  nesting composes). Case 4's `kaikai-ahu/` package runs it, git-pinned:
  `ahu = { source = "https://github.com/kaikailang-org/ahu", ref =
  "v0.2.1" }` (`kai install` then `kai run .`). The old TRAP — kai 0.99.6
  silently ignored the documented `{ git = ..., tag = ... }` form (filed as
  kaikai#1215) — was FIXED in 0.99.13: both spellings resolve, unknown
  forms error loudly (verified on 0.100.0).
- **ahu#34 (Transient never restarted on real faults) is FIXED in v0.2.1**
  (commit 1bff4435): `restart_loop` matched the trap-exit reason against
  `"Crashed"` only, but genuine faults arrive as `"Trapped: <msg>"`; the
  fix adds a shared `is_crash` predicate covering both. Re-verified on the
  pin both directions: real 10/0 under Transient+Limit(3) → 3 restarts +
  escalation, exit 0; clean exit → single run, no restart. `Permanent`
  unchanged. Still true in ahu: a cell crash mid-driver is UNOBSERVED
  (String vs Msg mailbox typing) — driver stalls; and there is no process
  registry, so callers restart with the unit (unlike OTP `name:`).
- **M:N scheduler since 0.99.11, DEFAULT-ON since 0.104** (workers = host
  cores, capped 32; #1332 closed #1207; commit 9a525a2f introduced it):
  per-thread work-stealing deques, copy-on-cross-thread mailbox send
  (non-atomic Perceus RC survives via physical copy; same-thread send
  keeps pointer transfer). Now documented in `kai info fibers`.
  `KAI_THREADS=1` is the byte-identical cooperative escape hatch — set it
  to demo single-thread starvation. 8-fiber Collatz: **0.08 s** at
  default(14) or `=8`.
- **The wake-path-parking claim was OUR measurement artifact — RETRACTED**
  (kai#1267 closed not-reproducible; upstream was right). The `[0/337/389]`
  shape came from anchoring t0 at pipeline start: a cold kaikai binary
  takes ~250–350 ms to first print on macOS (page faults + signature
  validation). Proven against ourselves: the exact 0.100-built binary,
  warm, holds cadence 6/6 at `=2` (and the 858 ms / 4-hog+`=8` figures
  fell the same way). PROTOCOL NOW: the program prints `start`, timestamps
  anchor there, discard cold runs — baked into case 5's harness. Full
  forensics in `discarded/wake-path-parking/`. Bonus find: 0.100's runtime
  hung once in ~12 saturated runs (real intermittent deadlock; 0.104 ships
  global-quiescence detection #1403, no hang seen there).
- **No preemption at any thread count** (docs still explicit) — what
  actually survives on 0.104: `=1` starves for the full crunch; saturation
  (runnable CPU fibers ≥ workers) makes the beat wait out a hog (16 hogs
  on 14 default workers → first beat ~420 ms; case 5's
  starve_saturate.kai); `Spawn.cancel` on a pure-CPU fiber never lands
  (req ~6 ms, fiber runs full ~340 ms). kai#1268 was folded into
  **kai#1269 (safepoint/reduction-budget proposal — still OPEN)**. NB the
  real tracker is **lnds/kaikai**; kaikailang-org/kaikai is a publish
  mirror.
- **RSS: the default worker pool costs ~11–12 MB** (0.104, any workload
  size); `KAI_THREADS=1` keeps the ~2 MB floor (N=1000: 2.4 MB). The
  0.99.11 regression (~169.5 MB/~758 MB) stays fixed. Perf drift noted
  honestly: serial N=5M 0.52 (0.99.11) → 0.57 (0.100) → 0.63 s (0.104).
- **LLVM folds pure counter loops** (`fn hog(i,limit) = if i>=limit ...`
  → closed form) in `--release`: a starvation demo with a counter hog
  measures nothing. Case 5's hog is a Collatz scan (data-dependent) for
  exactly this reason. Verify hogs actually burn CPU before timing them.
- Hot loops: tail recursion with accumulator (the `while`+`var` 65× trap is
  documented in ../kaikai-vs-golang, not re-run here).
- `kai build` errors exit 0 through a grep pipe — check `pipestatus[1]`/run
  unpiped when demonstrating exit codes.

## Benchmarking notes

- Method: `kai build --release` vs `elixir file.exs`, wall = min of 3 warm
  runs via `/usr/bin/time -l`, peak RSS from the same. N from argv, result
  printed. 14-core arm64 mac.
- Elixir parallel = `Task.async_stream` over `1..limit//chunk` range starts,
  `shards = System.schedulers_online()` (14). ~0.49 s wall at last re-run.
- BEAM RSS is ~92 MB regardless of serial/parallel — it's the VM floor, not
  the workload.
- **Latency measurements (case 5): anchor t0 on a line the program itself
  prints, and use warm binaries only** — pipeline-start t0 + cold binary
  already produced one retracted claim. The parking signature, if hunting
  one, is a >50 ms gap BETWEEN consecutive beats (immune to start offset).

## Environment gotchas

- The user's shell prints a noisy `zoxide` doctor warning on every
  `kai`/`git` invocation. Harmless; filter with
  `2>&1 | grep -vE "zoxide|ajeetdsouza"` or `export _ZO_DOCTOR=0`.
- Elixir via asdf: ebin at
  `~/.asdf/installs/elixir/1.19.5-otp-28/lib/elixir/ebin` (dialyzer -pa
  needs it). Portable form:
  `elixir -e 'IO.puts(:code.lib_dir(:elixir) |> Path.join("ebin"))'`.
- zsh: `echo === X ===` fails (`== not found`) — don't use bare `=` runs in
  echoed separators.

## Conventions

- Commits: Conventional, English, no Claude attribution.
- **Private remote** (github.com/lnds/kaikai-vs-elixir) — push only on the
  owner's explicit ask; never change visibility. The owner publishes.
- READMEs in English (the comparison is for a skeptical Elixir audience).
- Honesty rule: if the idiomatic Elixir does the right thing — or the 1.19
  checker catches it — the claim is false → `discarded/` (two entries:
  struct typos, and our own wake-path-parking claim — the rule cuts both
  ways). Every case keeps a "Where Elixir wins / trade-off" section,
  and the README carries a "what Elixir has that kaikai has no form for"
  list (multi-core, preemption, OTP, hot upgrades, distribution,
  introspection, binary matching, macros). Keep it that way.
- On any Elixir or kaikai upgrade: re-run the suite; re-test especially the
  1.19-checker boundaries in cases 1–3 (they will move) and case 4's
  trap_exit behavior.
