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
  **kaikai 0.99.11** (native backend); first built on 0.99.6, re-verified
  after 0.99.11 shipped M:N threading and **moved cases 5 and 6** (history
  in those READMEs). 14-core machine (matters for cases 5–6).

### Case status (who wins)

| # | Case | Verdict |
|---|------|---------|
| 1 | typing-holes | kaikai (safety) — struct/dot typos: 1.19 **warns** (exit 0, .beam ships); `cfg[:typo]` Access: silent nil; kaikai: compile error w/ did-you-mean. Bonus finding: a crashing .exs dies before its buffered warning prints |
| 2 | exhaustive-match | kaikai (safety) — tagged tuples + @type/@spec: elixirc silent, runtime CaseClauseError (loud+named, credited); dialyzer flags the call site (opt-in, needs PLT + elixir ebin on code path); kaikai names the missing variant at build |
| 3 | error-handling | kaikai (safety; ergonomics a wash) — `with` is genuinely good; forgetting `{:error,_}` compiles + MatchError; kaikai unhandled effect row = compile error |
| 4 | fault-tolerance | **Elixir** (narrowed) — one-line Supervisor restarts a crashed GenServer, app never stops. kaikai nursery default = fail-fast exit 1; Link+trap_exit hand-rolled supervisor WORKS; AND the **ahu** framework column runs the same real fault under `restartable_cell(Permanent, Limit(3))`: 3 restarts w/ state reset + escalation, exit 0. Elixir keeps registry/defaults/maturity. Running ahu found a real bug (below) |
| 5 | preemptive-scheduling | **Elixir** (survived 0.99.11 threads) — default: first heartbeat only after the full 338 ms crunch. `KAI_THREADS=2`: ready fiber stolen at 10 ms, BUT the beat waking from `sleep(millis(50))` parks BEHIND the hog until ~340 ms — reproduced at `=4` with idle workers (wake-path re-enqueue not stolen). BEAM: all beats on 50 ms cadence even `+S 1`. Parallelism ≠ preemption |
| 6 | runtime-perf | **split, moved twice by 0.99.11** — Collatz N=5M: kaikai serial 0.52 s; 8 fibers default 0.53 s; 8 fibers `KAI_THREADS=8` **0.10 s** (beats Elixir 14-shard 0.44 s ~4.4×); Elixir serial 2.05 s. BUT 0.99.11 RSS: **169.5 MB fixed** at any N/thread-count-1 (vs 1.7 MB on 0.99.6), 757.7 MB at 8 threads → BEAM (97 MB) now wins memory. Same answer everywhere: n=3732423 steps=596 |

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
- **ahu (kaikailang-org/ahu, v0.2.0) is kaikai's fault-tolerance framework**
  — cells (typed GenServer shape) + restart helpers (`Permanent | Transient
  | Temporary`, `Limit(n)`, `with_restart_backoff`, escalation via Cancel;
  nesting composes). Case 4's `kaikai-ahu/` package runs it, git-pinned:
  `ahu = { source = "https://github.com/kaikailang-org/ahu", ref =
  "v0.2.0" }` (`kai install` then `kai run .`). TRAP: `kai info packages`
  documents `{ git = ..., tag = ... }`, which kai 0.99.6 **silently
  ignores** (resolves "1 dependency", locks 0 entries, no error) —
  `source`/`ref` is the real syntax (what `kai add <url>@<ref>` writes).
  Filed on request as kaikai#1215 (repros on 0.99.6 and 0.99.11).
- **BUG FOUND, filed on request as ahu#34
  (github.com/kaikailang-org/ahu/issues/34): ahu `Transient` does not
  restart on real faults.** `restart_loop` matches the trap-exit
  reason against `"Crashed"`, but genuine faults arrive as `"Trapped:
  <msg>"` (e.g. `"Trapped: divide by zero"`), so Transient treats them as
  normal exits and gives up; only `Cancel.raise()` (→ `"Crashed"`) triggers
  Transient restarts. Verified both directions in scratch; `Permanent`
  unaffected (restarts on any reason). Root ambiguity: docs/actors.md's
  trap-exit table documents only `"Normal"`/`"Crashed"` payloads, so either
  the kaikai runtime drifted or ahu never learned the `"Trapped:"` prefix.
  Also documented in ahu itself: a cell crash mid-driver is UNOBSERVED
  (String vs Msg mailbox typing) — driver stalls; and there is no process
  registry, so callers restart with the unit (unlike OTP `name:`).
- **M:N scheduler since 0.99.11** (`KAI_THREADS=N`, opt-in, default 1;
  commit 9a525a2f, part of #1207): per-thread work-stealing deques,
  copy-on-cross-thread mailbox send (non-atomic Perceus RC survives via
  physical copy; same-thread send keeps pointer transfer). NOT yet in
  `kai info fibers`. 8-fiber Collatz: 0.53 s → **0.10 s** at
  `KAI_THREADS=8`.
- **No preemption at any thread count** (docs still explicit): case 5
  measured — default starves the heartbeat for the full crunch;
  with threads, work-stealing rescues *ready* fibers (10 ms) but a fiber
  waking from `Clock.sleep` re-enqueues on the wake path and parks behind
  a CPU hog even with idle workers (stable at `=2` and `=4`). CANDIDATE
  UPSTREAM ISSUE (unfiled): wake-path re-enqueue is not work-stolen.
- **0.99.11 RSS regression (unfiled candidate issue): the M:N runtime
  pre-reserves ~169.5 MB resident** regardless of workload (N=1000, ANY
  KAI_THREADS incl. 1) and ~+84 MB/extra thread (758 MB at 8). Not a leak
  (`KAI_TRACE_RC` clean, leaked=7). 0.99.6 same program: 1.7 MB. The
  commit's "default byte-identical to pre-M:N" holds for semantics, not
  footprint. This flipped case 6's memory verdict to the BEAM.
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
