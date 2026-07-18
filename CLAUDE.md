# CLAUDE.md — kaikai-vs-elixir

Adversarial, honest comparison repo between **kaikai** and **Elixir**. Every
claim is proven by compiling/running code, never asserted. Sibling of
`../kaikai-vs-rust` and `../kaikai-vs-golang`, same methodology, different
target: Elixir's space is the BEAM — preemptive processes, multi-core
schedulers, supervision/fault-tolerance, dynamic language acquiring a
gradual type checker. Local-only git (no remote, no push — the owner
publishes).

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
  deleted. Contains the struct-typo claim the 1.19 checker killed.
- Verified against **Elixir 1.19.5 / OTP 28** (JIT, 14 schedulers, asdf) and
  **kaikai 0.100.0** (native backend, self-hosted stage 2); first built on
  0.99.6, re-verified on 0.99.11 (M:N threading **moved cases 5 and 6**) and
  again on 0.100.0 (RSS regression fixed → case 6 memory back to kaikai;
  case 5's `=4` parking gone; ahu#34 fixed in v0.2.1 — history in those
  READMEs). 14-core machine (matters for cases 5–6).

### Case status (who wins)

| # | Case | Verdict |
|---|------|---------|
| 1 | typing-holes | kaikai (safety) — struct/dot typos: 1.19 **warns** (exit 0, .beam ships); `cfg[:typo]` Access: silent nil; kaikai: compile error w/ did-you-mean. Bonus finding: a crashing .exs dies before its buffered warning prints |
| 2 | exhaustive-match | kaikai (safety) — tagged tuples + @type/@spec: elixirc silent, runtime CaseClauseError (loud+named, credited); dialyzer flags the call site (opt-in, needs PLT + elixir ebin on code path); kaikai names the missing variant at build |
| 3 | error-handling | kaikai (safety; ergonomics a wash) — `with` is genuinely good; forgetting `{:error,_}` compiles + MatchError; kaikai unhandled effect row = compile error |
| 4 | fault-tolerance | **Elixir** (narrowed) — one-line Supervisor restarts a crashed GenServer, app never stops. kaikai nursery default = fail-fast exit 1; Link+trap_exit hand-rolled supervisor WORKS; AND the **ahu** framework column runs the same real fault under `restartable_cell(Permanent, Limit(3))`: 3 restarts w/ state reset + escalation, exit 0. Elixir keeps registry/defaults/maturity. Running ahu found a real bug — filed as ahu#34, **fixed upstream in v0.2.1**, fix re-verified both directions (below) |
| 5 | preemptive-scheduling | **Elixir** (survived threads; re-verified 0.100.0) — default: first heartbeat only after the full ~330 ms crunch. `KAI_THREADS=2`: ready fiber stolen at ~0 ms, BUT the beat waking from `sleep(millis(50))` parks BEHIND the hog until ~337 ms with a worker idle. `=4` NOW lands on cadence (0/49/99 — changed between 0.99.11 and 0.100.0; on 0.99.11 it parked like `=2`). BEAM: all beats on 50 ms cadence even `+S 1`. Parallelism ≠ preemption |
| 6 | runtime-perf | **kaikai, moved three times** — 0.100.0 Collatz N=5M: serial 0.57 s (drifted from 0.52 on 0.99.11); 8 fibers default 0.58 s; `KAI_THREADS=8` **0.08 s** (beats Elixir 14-shard 0.43 s ~5×); Elixir serial 2.03 s. RSS: **2.6 MB at 8 threads** — the 0.99.11 ~169.5 MB/757.7 MB reservation was fixed upstream in 0.99.12 (lazy RC free-list pools), so memory is kaikai's again (BEAM 97 MB). Same answer everywhere: n=3732423 steps=596 |

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
- **M:N scheduler since 0.99.11** (`KAI_THREADS=N`, opt-in, default 1;
  commit 9a525a2f, part of #1207): per-thread work-stealing deques,
  copy-on-cross-thread mailbox send (non-atomic Perceus RC survives via
  physical copy; same-thread send keeps pointer transfer). STILL not in
  `kai info fibers` at 0.100.0. 8-fiber Collatz: 0.58 s → **0.08 s** at
  `KAI_THREADS=8`.
- **No preemption at any thread count** (docs still explicit): case 5
  measured — default starves the heartbeat for the full crunch; with
  threads, work-stealing rescues *ready* fibers (~0 ms) but a fiber waking
  from `Clock.sleep` re-enqueues on the wake path and parks behind a CPU
  hog. NOT thread-count-specific: parks at `=2` (1 worker idle) AND at
  4 hogs + `=8` (4 workers idle); 1 hog + `=4` lands on cadence at
  0.100.0 (parked on 0.99.11) — placement luck, not a fix. Saturation:
  4 hogs + `=4` → first beat 858 ms. Also measured: `Spawn.cancel` on a
  pure-CPU fiber never lands (requested at 9 ms, fiber runs its full
  ~310 ms, nursery exit blocks). FILED: kai#1267 (wake-path fairness),
  kai#1268 (cancel unbounded), kai#1269 (proposal: BEAM-style reduction
  budget via compiler safepoints — asu-reviewed design). NB the real
  tracker is **lnds/kaikai**; kaikailang-org/kaikai is a publish mirror.
- **The 0.99.11 RSS regression (~169.5 MB fixed, ~758 MB at 8 threads) was
  FIXED upstream in 0.99.12** ("lazy-materialise the RC free-list pools",
  closes #1212/#1213 — shipped the same day as the regression; our
  candidate issue was never needed). Verified on 0.100.0: N=1000 serial
  1.77 MB, `KAI_THREADS=8` 2.6 MB.
  Case 6's memory verdict is back to kaikai. Perf drift noted honestly:
  serial N=5M 0.52 s (0.99.11) → 0.57 s (0.100.0).
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
  `shards = System.schedulers_online()` (14). ~2.3 s CPU / 0.44 s wall.
- BEAM RSS is ~97 MB regardless of serial/parallel — it's the VM floor, not
  the workload.

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
- **Local only** — never `git push` or `gh repo create`. The owner publishes.
- READMEs in English (the comparison is for a skeptical Elixir audience).
- Honesty rule: if the idiomatic Elixir does the right thing — or the 1.19
  checker catches it — the claim is false → `discarded/` (one entry already:
  struct typos). Every case keeps a "Where Elixir wins / trade-off" section,
  and the README carries a "what Elixir has that kaikai has no form for"
  list (multi-core, preemption, OTP, hot upgrades, distribution,
  introspection, binary matching, macros). Keep it that way.
- On any Elixir or kaikai upgrade: re-run the suite; re-test especially the
  1.19-checker boundaries in cases 1–3 (they will move) and case 4's
  trap_exit behavior.
