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
  **kaikai 0.192.6** (native backend, self-hosted stage 2); first built on
  0.99.6, re-verified on 0.99.11 (M:N threading **moved cases 5 and 6**),
  0.100.0 (RSS regression fixed; ahu#34 fixed in v0.2.1), 0.104.0
  (**KAI_THREADS defaults to ncpu** → case 6 wins by default, case 5
  narrowed + parking claim retracted), and 0.114.0 (**quiet release**: ten
  releases of front-end work, no scheduler change; everything re-verified
  identical bar case 6's serial wall drifting back 0.63 → 0.57 s — see
  the 0.114 notes below), and 0.192.6 (no verdict moved; case 6 default
  RSS back to ~2 MB, case 5's entry-fiber pin now rare, case 4's ahu pin
  moved to `main`, case 5 harness needs a pty — see the 0.192 notes
  below). 14-core machine (matters for cases 5–6).

### Case status (who wins)

| # | Case | Verdict |
|---|------|---------|
| 1 | typing-holes | kaikai (safety) — struct/dot typos: 1.19 **warns** (exit 0, .beam ships); `cfg[:typo]` Access: silent nil; kaikai: compile error w/ did-you-mean. Bonus finding: a crashing .exs dies before its buffered warning prints |
| 2 | exhaustive-match | kaikai (safety) — tagged tuples + @type/@spec: elixirc silent, runtime CaseClauseError (loud+named, credited); dialyzer flags the call site (opt-in, needs PLT + elixir ebin on code path); kaikai names the missing variant at build |
| 3 | error-handling | kaikai (safety; ergonomics a wash) — `with` is genuinely good; forgetting `{:error,_}` compiles + MatchError; kaikai unhandled effect row = compile error |
| 4 | fault-tolerance | **Elixir** (narrowed) — one-line Supervisor restarts a crashed GenServer, app never stops. kaikai nursery default = fail-fast exit 1; Link+trap_exit hand-rolled supervisor WORKS; AND the **ahu** framework column runs the same real fault under `restartable_cell(Permanent, Limit(3))`: 3 restarts w/ state reset + escalation, exit 0. Elixir keeps registry/defaults/maturity. Running ahu found a real bug — filed as ahu#34, **fixed upstream in v0.2.1**, fix re-verified both directions (below). At 0.192.6 the ahu pin is `main` (f3cce7e): no ahu tag builds on 0.192 |
| 5 | preemptive-scheduling | **Elixir** (narrowed hard at 0.104, WITH A RETRACTION) — threads default-on: any *spawned* fiber's beat on 50 ms cadence (0/49/99 at `=2`, `=4`, default 14). The old "wake parks behind hog" claim (kai#1267) was OUR measurement artifact — conceded in `discarded/wake-path-parking/`. What survives for Elixir: `=1` starves (~320 ms), SATURATION (16 hogs ≥ 14 workers → first beat ~430 ms at 0.114, 352–421 ms at 0.192.6), `Spawn.cancel` on pure-CPU never lands (fiber runs full ~325 ms), and a sleep on the NURSERY BODY wakes ~330 ms late (entry fiber pinned to main thread, kai#1556) — ~4/5 runs at 0.114, 3/40 at 0.192.6 — while a spawned sleeper is on time every run. kai#1269 (safepoint proposal) CLOSED not-planned → design position, not pending fix. BEAM: cadence under any load even `+S 1` |
| 6 | runtime-perf | **kaikai, now BY DEFAULT** — 0.192.6 Collatz N=5M: fibers default (14 threads) **0.08 s** (beats Elixir 14-shard 0.42 s ~5×); serial 0.56 s (drift 0.52→0.57→0.63→0.57→0.56, stated); Elixir serial 1.97 s. RSS: serial default 1.8 MB, fibers default 3.5 MB (0.104–0.114 worker-pool cost of ~11–12 MB is gone) vs BEAM ~92 MB. BEAM boot floor ~0.15 s. Same answer everywhere: n=3732423 steps=596 |

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
- BEAM boot floor here: **~0.15 s** (`time elixir -e ""`); kaikai binary
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
- **ahu (kaikailang-org/ahu) is kaikai's fault-tolerance framework**
  — cells (typed GenServer shape) + restart helpers (`Permanent | Transient
  | Temporary`, `Limit(n)`, `with_restart_backoff`, escalation via Cancel;
  nesting composes). Case 4's `kaikai-ahu/` package runs it, git-pinned:
  `ahu = { source = "https://github.com/kaikailang-org/ahu", ref =
  "main" }`, lock at f3cce7e (`kai fetch` then `kai run .`; bare
  `kai install` still works with a deprecation warning). It was `ref =
  "v0.2.1"` until 0.192: the compiler now rejects uppercase type
  parameters (`error: type parameters must start with a lowercase
  letter` on `StepResult[State]`), v0.2.1..v0.2.3 all fail, and the port
  (ahu bccf9b7) is on `main`, untagged. When ahu tags it, pin the tag.
  `ref` must be a branch or tag: a commit sha fails the clone. Two
  kai-pkg traps seen at 0.192.6: the v0.2.1 lock's sha (b1d243f) no
  longer exists in ahu's history and `kai fetch` silently rewrote it to
  the tag's commit (c0de5d9), and a failed clone (`ref` = a full sha)
  prints `git clone failed` but **exits 0** with a lock of 0 entries —
  check the lock, not the exit code. The old TRAP — kai 0.99.6
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
  keeps pointer transfer). NB `kai info fibers` on 0.114 no longer
  mentions M:N/work-stealing at all — it documents fibers, nursery and
  cooperative cancellation only. Don't cite the doc for the threading
  model; cite the release/changelog.
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
  (fiber runs its full ~330 ms). **kai#1269 (the safepoint/reduction-budget
  proposal) is now CLOSED as not planned** — with kai#1268 (cancellation)
  closed first as "a corollary that closes when #1269 ships", and #1269
  then closed citing #1268 as "addressed directly". Neither shipped; the
  probe still measures the original behaviour. The defensible part of the
  close is upstream's last line: the cooperative-scheduler design position
  is preserved deliberately. So frame this case as a DESIGN POSITION, not
  a pending fix. NB the real tracker is **lnds/kaikai**;
  kaikailang-org/kaikai is a publish mirror.
- **The ENTRY FIBER IS PINNED to the process main thread (kai#1556), and it
  costs latency** (found at 0.114, case 5's `wake_entry_fiber.kai`): a
  `sleep` in the NURSERY BODY wakes ~335 ms late in ~4 of 5 warm runs with
  one hog and 13 workers idle, because that fiber cannot migrate off the
  worker the hog landed on; a SPAWNED sleeper is 2/54 ms every run in the
  same program. It is a coin flip on hog placement, hence the variance.
  At 0.192.6 the pin is still in the runtime (`pinned_main`) but the coin
  is weighted: nursery-body sleeper late in 3/40 runs, cancel requested on
  time 30/30.
  This is NOT the retracted parking claim (that one alleged *spawned*
  fibers park, off a cold binary) — it survives the corrected protocol.
  Consequence for measurement: **put anything latency-sensitive in a
  spawned fiber, never in the nursery body**, or you measure the pin. This
  is exactly what made the old `[6ms] cancel requested` figure wrong — it
  was the lucky 4-in-15 run reported as the rule.
- **RSS: the default worker pool cost ~11–12 MB at 0.104–0.114; at
  0.192.6 it is gone** — default serial 1.8 MB, default 14-thread fibers
  3.5 MB, `KAI_THREADS=1` fibers 2.1 MB (N=1000: 2.1 MB at `=1`, 3.6 MB
  default). The 0.99.11 regression (~169.5 MB/~758 MB) stays fixed. Perf
  drift noted honestly: serial N=5M 0.52 (0.99.11) → 0.57 (0.100) → 0.63
  (0.104) → 0.57 (0.114) → 0.56 s (0.192.6).
- **stdout is block-buffered off a TTY since 0.171** (`kai_set_args` only
  sets line buffering when `isatty`); the runtime flushes before it blocks,
  writes stderr, or exits. Piped into a timestamper, a program's `start`
  line is held until the entry fiber first blocks, so at `KAI_THREADS=1`
  the anchor lands after the hog and starvation vanishes from the numbers
  (`[0/52/104] hog done 156 ms` for a ~325 ms hog). Case 5 runs every
  kaikai and Elixir binary under `script -q /dev/null cmd </dev/null` (a
  pty; the `</dev/null` is needed when stdin is not a terminal).
- **0.192.6 visible warnings**: case 4 ahu `main.kai` warns `unused import
  spawn` and that `with_mailbox` in tail position is not a guaranteed tail
  call; `starve_saturate.kai` warns `unused binding rs`. All exit 0.
- **0.105–0.114 was all front end**: symbol table + SymId identity, module
  and namespace resolution (#1800/#1897 lanes), Perceus fixes, fmt. No
  scheduler, effect-row or exhaustiveness change — which is why the whole
  suite re-verified byte-for-byte. New at 0.114 and visible in this repo:
  an **unused-import / unused-binding warning** (#1846) that now fires on
  `starve_saturate.kai` (`rs`) and on ahu's `main.kai` (`import spawn`),
  plus a **nursery brand-tracking warning** (#1550) from inside ahu's
  `app.kai`. All warnings, exit 0; no output changed.
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
  runs via `/usr/bin/time -l`, peak RSS from the same (max resident bytes
  / 2^20, labelled MB). N from argv, result printed. 14-core arm64 mac.
- Elixir parallel = `Task.async_stream` over `1..limit//chunk` range starts,
  `shards = System.schedulers_online()` (14). ~0.42 s wall at last re-run.
- BEAM RSS is ~92 MB regardless of serial/parallel — it's the VM floor, not
  the workload.
- **Latency measurements (case 5): anchor t0 on a line the program itself
  prints, and use warm binaries only** — pipeline-start t0 + cold binary
  already produced one retracted claim. The parking signature, if hunting
  one, is a >50 ms gap BETWEEN consecutive beats (immune to start offset).
- **A latency number needs its VARIANCE, not its best run** — report N runs
  or a range. The `[6ms] cancel requested` figure was a 4-in-15 outcome
  quoted as the rule, and it hid the pinned-entry-fiber effect for a whole
  release. Corollary from the same find: **the timed sleeper must be a
  spawned fiber**; a sleep in the nursery body measures the pin.

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
