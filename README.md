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
  schedulers) and `kaikai 0.114.0` (hanga-roa, stage 2, self-hosted)**,
  native backend; nothing here is backend-sensitive. First built against
  kaikai 0.99.6; 0.99.11 shipped an M:N work-stealing scheduler
  (`KAI_THREADS`, opt-in) mid-comparison and **moved cases 5 and 6**;
  0.100.0 moved them again (the 0.99.11 memory regression was fixed
  upstream in 0.99.12, flipping case 6's memory verdict back); 0.104.0
  turned multi-threading **on by default** (workers = host cores), moving
  both once more. The ahu `Transient` bug this repo found and filed
  (ahu#34) was fixed upstream in v0.2.1 and the fix is re-verified in
  case 4. The 0.104 re-verify also forced a **retraction**: case 5's
  wake-path-parking claim (filed as kai#1267) was a measurement artifact
  — conceded in [`discarded/`](discarded/wake-path-parking/), protocol
  fixed. 0.114.0 (ten releases of front-end work: symbol table, module
  and namespace resolution, Perceus — **no scheduler change**) moved
  nothing: every case re-verified identical, bar case 6's serial wall
  drifting back 0.63 → 0.57 s. Two things did change around case 5:
  upstream **closed the safepoint proposal (kai#1269) as not planned**,
  making that gap a stated design position rather than pending work, and
  re-measuring the cancellation probe exposed a variance the 0.104 write-up
  had reported as a single lucky number — the fix and the finding behind
  it (the entry fiber is pinned to the main thread) are in case 5. History
  kept in each case; cases 1–4 and beyond-elixir re-verified unchanged.
- Every Elixir "this compiles but misbehaves" claim is backed by the actual
  `elixirc` output (including its 1.19 type-checker warnings, when any) and
  the actual runtime error. **No strawmen**: the Elixir shown is the version
  a competent Elixir programmer would write, and where the new type checker
  or Dialyzer catches something, that is stated with the same prominence as
  the catch it misses. One imported claim was refuted by the 1.19 checker
  and moved to [`discarded/`](discarded/) — conceding a refuted claim is
  worth more than a fragile one. The rule cuts both ways: when upstream
  refuted one of *this repo's* kaikai claims, it went to the same place
  ([`discarded/wake-path-parking/`](discarded/wake-path-parking/)).
- Every kaikai example compiles and runs (`kai run <file>.kai`); "this is a
  compile error" claims paste the actual `kai build` diagnostic.
- Case 6 carries **measured** wall-clock and peak RSS (min of 3 warm runs,
  `/usr/bin/time -l`, N from argv, results printed so nothing constant-folds,
  identical answers verified before timing).
- This is **not propaganda**. Every case has a *"Where Elixir wins / the
  trade-off"* section; two of six cases go to Elixir outright, on the things
  the BEAM actually guarantees. And unlike the Go sibling, Elixir gets a
  dedicated honesty section below for the things **kaikai has no form for**.

## Verdicts at a glance

| # | Case | Winner | Why |
|---|------|--------|-----|
| 1 | typing-holes | **kaikai** (safety) | A field typo is at best a 1.19 **warning** in Elixir (exit 0, the `.beam` ships) and a silent `nil` via `Access`; in kaikai it is a compile error with did-you-mean. |
| 2 | exhaustive-match | **kaikai** (safety) | Adding a variant compiles clean in Elixir and crashes at runtime with `CaseClauseError` (Dialyzer catches it, but opt-in); kaikai fails the build naming the missing variant. |
| 3 | error-handling | **kaikai** (safety; ergonomics a wash) | `with` chains beautifully, but a forgotten `{:error, _}` path compiles and `MatchError`s at runtime; an unhandled effect row in kaikai does not compile. |
| 4 | fault-tolerance | **Elixir** (narrowed) | A one-line `Supervisor` restarts the crashed worker and the app never stops. kaikai's primitives work and ahu runs the same real fault with restarts + escalation — but Elixir keeps the registry, the defaults, and 25 years of burn-in. |
| 5 | preemptive-scheduling | **Elixir** (narrowed hard at 0.104, with a retraction) | What survives is the *guarantee*: under saturation kaikai's heartbeat waits out a hog (~430 ms) and `Spawn.cancel` on pure-CPU never lands; the BEAM holds cadence under any load, even `+S 1`. With spare workers kaikai is already on cadence — the old "parking" claim was this repo's own measurement artifact, [conceded](discarded/wake-path-parking/). Upstream closed the safepoint proposal as not planned: a design position, not a pending fix. |
| 6 | runtime-perf | **kaikai** (now by default) | 0.08 s vs the BEAM's parallel 0.43 s (~5×) with zero configuration since 0.104 (threads = ncpu); serial ~3.4× the JIT; ~12 MB RSS vs 92 MB (~1/8th). Stated drift: serial 0.52 → 0.63 → 0.57 s over four releases. |

The pattern: 4–2 by case count, but each side wins exactly where it placed
its bet — kaikai where the compiler can make bugs **unrepresentable** (1–3)
and cycles into wall-clock (6); Elixir where the runtime **guarantees**
behavior when things fail or saturate (4–5).

## Index

| # | Case | Who wins | Claim (one line) |
|---|------|----------|------------------|
| 1 | [typing-holes](cases/01-typing-holes/) | kaikai (safety) | A typo'd field is a compile **warning** at best (exit 0, the `.beam` ships), a silent `nil` via `Access`, and a **compile error** in kaikai. Full credit to the impressive 1.19 checker, which killed this repo's strong version of the claim ([`discarded/`](discarded/struct-typo-unchecked/)). |
| 2 | [exhaustive-match](cases/02-exhaustive-match/) | kaikai (safety) | Tagged tuples + `@type` are a convention: add `:triangle` and the old `case` compiles clean, crashing at runtime (`CaseClauseError` — loud and named, credit given; Dialyzer can flag the call site, opt-in). kaikai's `match` fails the build naming the missing variant. |
| 3 | [error-handling](cases/03-error-handling/) | kaikai (safety; ergonomics a wash) | `with` chains beautifully — stated plainly. But `{:ok, _} = ...` that forgets the error path compiles and `MatchError`s at runtime; kaikai's unhandled effect row does not compile. |
| 4 | [fault-tolerance](cases/04-fault-tolerance/) | **Elixir** | A crashed worker under a one-line `Supervisor` restarts and the app never stops. kaikai's nursery default is fail-fast; a `Link`+`trap_exit` supervisor hand-rolls fine, and the **ahu** framework runs the same real fault under `Permanent`+`Limit(3)` with escalation (shown working!). Elixir keeps the win on registry, defaults, maturity — running ahu here found a policy-inverting `Transient` bug (filed as ahu#34, fixed upstream in v0.2.1, fix re-verified), which *is* the maturity gap, measured. |
| 5 | [preemptive-scheduling](cases/05-preemptive-scheduling/) | **Elixir** (narrowed at 0.104, with a retraction) | With default-on threads and a spare worker, a *spawned* fiber's heartbeat lands on cadence — the earlier "wakes park behind a hog" claim was a measurement artifact, [conceded](discarded/wake-path-parking/). What survives: under **saturation** (hogs ≥ workers) the beat waits out a hog's full crunch, `Spawn.cancel` on a pure-CPU fiber never lands, and (new at 0.114) a sleep on the **nursery's own body** wakes ~330 ms late in ~4 of 5 runs, because the entry fiber is pinned to the main thread and cannot migrate. The BEAM preempts on reductions: every beat on time under any load, even `+S 1`. Spare capacity ≠ a guarantee. |
| 6 | [runtime-perf](cases/06-runtime-perf/) | **kaikai** (now by default) | Collatz N=5M: kaikai serial 0.57 s (~3.4× the BEAM JIT); the same fiber binary runs in **0.08 s** with zero configuration since 0.104 (workers = ncpu) vs Elixir's 14-shard 0.43 s — at ~12 MB RSS vs the BEAM's 92 MB. Stated drift: kaikai's serial wall 0.52 → 0.63 → 0.57 s over four releases (0.114 clawed part of it back), and default RSS ~2 → ~12 MB when the worker pool became default-on (`KAI_THREADS=1` keeps the ~2 MB floor). |

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

- **Preemption.** Reduction-based descheduling is why case 5's heartbeat
  never starves. kaikai's scheduler never preempts at any thread count
  (docs explicit; multi-core *by default* it now has — 0.104 dropped off
  this list). With spare workers the difference is invisible; under
  saturation the beat waits out a hog's crunch, and cancellation of a
  pure-CPU fiber never lands (case 5, measured; the upstream safepoint
  proposal, kai#1269, was closed as not planned — this is a design
  position, not a pending fix).
- **Supervision as a *mature* framework.** kaikai has the primitives
  (monitor/link/trap-exit) and a young framework
  ([ahu](https://github.com/kaikailang-org/ahu): policies, intensity,
  backoff, escalation — run in case 4). What it has no form for yet: a
  process registry (named workers whose callers outlive restarts),
  `DynamicSupervisor`, per-fiber crash observation inside a cell scope —
  and OTP's decades of burn-in (case 4 found an ahu `Transient` bug by
  running it once).
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
This repo measures that bet paying off exactly where it was placed —
though the margin keeps shrinking: case 5 narrowed from "starves by
default" to "no guarantee under saturation or cancellation" once 0.104
turned threads on by default (and shed a claim this repo had to retract),
case 4 stays Elixir's on maturity and defaults (though ahu narrows it to a
contest between frameworks, not framework-vs-nothing). Case 6's wall-clock
went to the BEAM at 0.99.6 and to kaikai at 0.99.11 — and the memory
floor, briefly ceded to the BEAM by a 0.99.11 regression, came back at
0.100.0 after an upstream fix. The ground moving under the comparison on
every release — including two upstream bugs this repo found, filed, and
saw fixed, and one claim upstream refuted right back — is the methodology
working. So is re-running the suite against 0.114 and finding almost
nothing moved: the same discipline that retracts a claim has to be able to
report a quiet release.

kaikai's bet is the **compiler**: make the bug classes that OTP so gracefully
*survives* — typos, missing cases, forgotten error paths — unrepresentable
before the program exists, compile to native code with megabytes-not-
hundred-megabytes of footprint, and pay for it by (today) offering
preemption not at all and supervision as a young framework rather than a
twenty-five-year default — parallelism, opt-in until 0.104, is now on by
default.

The sharpest sentence in the repo: **Elixir is engineered to survive at
runtime what kaikai is engineered to prevent at compile time** — and each
side's showcase case (4 vs 1–3) is the other side's admitted gap. Where
they compete head-on (case 6), native codegen wins the core, default-on
work-stealing wins the machine, and the memory floor is kaikai's at every
measured configuration.

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
