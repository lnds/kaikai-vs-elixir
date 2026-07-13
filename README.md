# kaikai vs Elixir — an adversarial, honest comparison

This repo confronts Elixir. It is written for a skeptical Elixir expert who
will try to refute every claim, so every claim is **proven by compiling and
running code**, not asserted. For each "Elixir lets this bug through" claim
there is a real Elixir program with its real compiler output and its real
runtime crash pasted in; for each "kaikai catches it / is faster" claim there
is a `.kai` program that compiles and runs (or fails to compile, on purpose),
with its real output pasted in.

Elixir is a different target than Rust or Go, so this is a different
comparison than the siblings [`../kaikai-vs-rust`](../kaikai-vs-rust) and
[`../kaikai-vs-golang`](../kaikai-vs-golang). Elixir's bets are the **BEAM**:
preemptive lightweight processes, multi-core scheduling, supervision trees,
fault tolerance as the default posture — plus a beloved dynamic language
that is *acquiring a type checker in real time* (1.19's set-theoretic
inference is load-bearing in three cases here). Those are exactly the axes
measured — including the ones Elixir wins, which are the axes Elixir was
built for.

## Disclaimer / methodology

- **Verified with `Elixir 1.19.5 (compiled with Erlang/OTP 28)` (JIT, 14
  schedulers) and `kaikai 0.99.6` (hanga-roa, stage 2).** kaikai examples run
  on the default native backend; nothing here is backend-sensitive.
- Every Elixir "this compiles but misbehaves" claim is backed by the actual
  `elixirc` output (including its 1.19 type-checker warnings, when any) and
  the actual runtime error. **No strawmen**: the Elixir shown is the version
  a competent Elixir programmer would write, and where the new type checker
  or Dialyzer catches something, that is stated with the same prominence as
  the catch it misses. One imported claim was refuted by the 1.19 checker
  and moved to [`discarded/`](discarded/) — conceding a refuted claim is
  worth more than a fragile one.
- Every kaikai example compiles and runs (`kai run <file>.kai`); "this is a
  compile error" claims paste the actual `kai build` diagnostic.
- Case 6 carries **measured** wall-clock and peak RSS (min of 3 warm runs,
  `/usr/bin/time -l`, N from argv, results printed so nothing constant-folds,
  identical answers verified before timing).
- This is **not propaganda**. Every case has a *"Where Elixir wins / the
  trade-off"* section; two of six cases go to Elixir outright, on the things
  the BEAM actually guarantees. And unlike the Go sibling, Elixir gets a
  dedicated honesty section below for the things **kaikai has no form for**.

## Index

| # | Case | Who wins | Claim (one line) |
|---|------|----------|------------------|
| 1 | [typing-holes](cases/01-typing-holes/) | kaikai (safety) | A typo'd field is a compile **warning** at best (exit 0, the `.beam` ships), a silent `nil` via `Access`, and a **compile error** in kaikai. Full credit to the impressive 1.19 checker, which killed this repo's strong version of the claim ([`discarded/`](discarded/struct-typo-unchecked/)). |
| 2 | [exhaustive-match](cases/02-exhaustive-match/) | kaikai (safety) | Tagged tuples + `@type` are a convention: add `:triangle` and the old `case` compiles clean, crashing at runtime (`CaseClauseError` — loud and named, credit given; Dialyzer can flag the call site, opt-in). kaikai's `match` fails the build naming the missing variant. |
| 3 | [error-handling](cases/03-error-handling/) | kaikai (safety; ergonomics a wash) | `with` chains beautifully — stated plainly. But `{:ok, _} = ...` that forgets the error path compiles and `MatchError`s at runtime; kaikai's unhandled effect row does not compile. |
| 4 | [fault-tolerance](cases/04-fault-tolerance/) | **Elixir** | A crashed worker under a one-line `Supervisor` restarts and the app never stops. kaikai's nursery default is fail-fast (program exits); a `Link`+`trap_exit` supervisor **can** be hand-rolled (shown working!) — the framework, defaults, and 25 years of burn-in are what kaikai lacks. |
| 5 | [preemptive-scheduling](cases/05-preemptive-scheduling/) | **Elixir** | A pure-CPU fiber starves its siblings in kaikai (cooperative, no preemption — ~0.5 s of silence here). The BEAM preempts on reductions: heartbeats interleave even on a single scheduler (`+S 1`). Latency under load is a BEAM *guarantee*. |
| 6 | [runtime-perf](cases/06-runtime-perf/) | **split** | Collatz N=5M: kaikai native serial **0.58 s / 1.7 MB** vs Elixir serial 2.05 s / 97 MB (~3.5× / ~58×). But Elixir's 14 schedulers deliver **0.44 s wall** — beating kaikai serial even paying BEAM boot — while kaikai's 8 fibers add exactly nothing (0.58 s). Cores vs cycles, measured. |

### Beyond Elixir — kaikai-only features

[`beyond-elixir/`](beyond-elixir/) collects things kaikai can express that
Elixir has **no form for** — the bar is high because macros plus the growing
type checker mean Elixir has a form for a lot (two candidates were excluded
on exactly that ground: property testing / StreamData, test injection / Mox):

| # | Feature | One line |
|---|---------|----------|
| 1 | [units-of-measure](beyond-elixir/01-units-of-measure/) | `Real<m> + Real<ft>` is a compile error, zero runtime cost — runtime unit libs check late and per-operation. |
| 2 | [user-kinds](beyond-elixir/02-user-kinds/) | Declare your own abelian kinds; cross-kind arithmetic rejected at compile time. No static types → nothing to build this on. |
| 3 | [contracts](beyond-elixir/03-contracts/) | `requires`/`ensures` in the signature. Guards are real preconditions (credit), but subset-restricted, anonymous on violation, and there is no postcondition form at all. |

### What Elixir has that kaikai has no form for

Symmetry demands this list, and it is not short. None of these is a library
gap; each is architecture kaikai does not have today:

- **Multi-core scheduling.** 14 schedulers ran case 6's shards in parallel;
  kaikai fibers are a single-core concurrency construct (measured: 8 fibers,
  0% speedup).
- **Preemption.** Reduction-based descheduling is why case 5's heartbeat
  never starves. kaikai's cancellation is cooperative and its scheduler
  never preempts.
- **Supervision as a framework.** Restart strategies, intensity limits,
  supervision trees, `DynamicSupervisor` — kaikai has the primitives
  (monitor/link/trap-exit) and none of the framework.
- **Hot code upgrades.** Deploy new code into a running node without
  dropping state or connections. kaikai is an ahead-of-time binary; the
  concept does not map.
- **Distribution.** `Node.connect/1` and message passing across machines
  with the same semantics as across processes. kaikai actors are
  single-node by design (per its own docs).
- **Runtime introspection.** `:observer`, per-process mailbox/memory/reduction
  stats, tracing (`:dbg`, `:recon`) on live production systems.
- **Binary pattern matching** (`<<len::32, rest::binary-size(len)>>`) — no
  kaikai equivalent for protocol parsing.
- **Macros / metaprogramming.** Phoenix, Ecto, and ExUnit are built out of
  it; kaikai deliberately has no macro system.

## Bottom line up front

Elixir's bet is the **runtime**: put every fault behind a process boundary,
preempt everything, restart what dies, use all the cores, and let a small
dynamic language ride on top — now with a type checker growing underneath it.
This repo measures that bet paying off exactly where it was placed: cases 4
and 5 are not close, and case 6's wall-clock goes to the BEAM on any
multi-core box.

kaikai's bet is the **compiler**: make the bug classes that OTP so gracefully
*survives* — typos, missing cases, forgotten error paths — unrepresentable
before the program exists, compile to native code with megabytes-not-
hundred-megabytes of footprint, and pay for it by (today) owning one core
per program and no supervision framework.

The sharpest sentence in the repo: **Elixir is engineered to survive at
runtime what kaikai is engineered to prevent at compile time** — and each
side's showcase case (4 vs 1–3) is the other side's admitted gap. Where they
compete head-on (case 6), native codegen wins the core and the scheduler
wins the machine.

## How to re-verify everything

Each case's `## Reproduce` section has the canonical commands. Quick loop:

```sh
# Elixir side — compile a module (this is where 1.19 warnings appear)
elixirc <case>/elixir/<file>.ex && elixir -pa <case>/elixir -e "<Module>.demo()"
elixir <case>/elixir/<file>.exs        # script-shaped cases
# kaikai side
kai run <case>/kaikai/<file>.kai              # runs
kai build <case>/kaikai/<file>_bad.kai        # shows the compile error
```

Perf (case 6): build `--release`, read N from argv, min of warm runs with
`/usr/bin/time -l`. Verdicts and numbers are a snapshot of these two
toolchains and can move as either improves — the 1.19 type checker already
moved one claim to `discarded/`, and it will keep coming.
