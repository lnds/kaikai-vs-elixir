# Case 4 — supervision: a framework vs primitives

**Category C — Elixir wins, by less than the first draft of this case
claimed.** This is OTP's home turf, and the honest result is not the strawman
"kaikai dies on any crash". kaikai has the primitives (links, trap-exit,
monitors) and a hand-rolled restart works — proven below. And kaikai has a
young framework layer too: [**ahu**](https://github.com/kaikailang-org/ahu)
ships declarative restart policies, intensity budgets, backoff, and
escalation — run against the same real fault below, where it both works and
yields this case's upstream-bug find. What Elixir keeps: OTP's registry
(callers outside the restart unit), its defaults, the preemptive runtime
underneath, and twenty-five years of burn-in.

## The claim

> A worker hits a real fault (division by zero). In Elixir, one line of
> supervisor policy restarts it; the crash is a logged event and the next
> call succeeds — restart logic, back-off, and max-intensity all come from
> OTP, none is written by the user. In kaikai the *default* (nursery) is
> fail-fast: the sibling fibers are cancelled and the program exits 1. A
> supervisor **can** be hand-rolled with `Link` + `trap_exit` — it works —
> but the restart policy is code you write and get right yourself.

## Elixir — the crash is an event, not an ending

[`elixir/supervised.exs`](elixir/supervised.exs):

```elixir
{:ok, _sup} = Supervisor.start_link([{Worker, nil}], strategy: :one_for_one)
```

Output (crash report trimmed):

```text
100 / 5 = 20
22:27:40.855 [error] GenServer Worker terminating
** (ArithmeticError) bad argument in arithmetic expression
    :erlang.div(100, 0)
...
worker crashed — supervisor restarts it, the app never stopped
100 / 4 = 25
```

Exit 0. The `ArithmeticError` killed the worker process only; the supervisor
restarted it under the same name; the caller's next request is served by the
fresh worker. Notice what the file does *not* contain: no restart loop, no
back-off, no "what if it crashes twice" — `strategy: :one_for_one` plus
defaults (max 3 restarts / 5 s, then escalate) is the entire policy. This
scales to trees: supervisors supervising supervisors is how every Phoenix
app boots.

## kaikai — fail-fast by default, restart by hand

The default, [`kaikai/crash_nursery.kai`](kaikai/crash_nursery.kai): one
child of three divides by zero.

```text
worker 1 ok
worker 3 ok
kai: nursery child cancelled; no survivors
```

Exit 1. Structured concurrency treats a child fault as scope failure —
siblings are cancelled, the failure propagates, the program dies. That is a
defensible design (no half-alive state), and it is the opposite default from
OTP's "isolate and restart".

The hand-rolled supervisor, [`kaikai/supervise.kai`](kaikai/supervise.kai) —
`spawn.set_trap_exit(true)` turns a linked child's death into a mailbox
message, and the real fault is trapped, not fatal:

```text
worker up, dividing 100 / 0
supervisor saw: Trapped: divide by zero -> restarting
worker up, dividing 100 / 5
result: 20
supervisor saw: Normal -> done
```

Exit 0. So the primitive layer is genuinely there — this is Erlang's
`process_flag(trap_exit, true)` pattern, working. (`Monitor` exists too, for
observation without linking; `unlink` does not exist yet, and mailbox-based
supervision of *typed* actors couples the supervisor's message type to a
`MonitorDown` variant.)

## kaikai + ahu — the framework column

Elixir never arrives without OTP, so fairness demands kaikai's framework
layer be run too. [ahu](https://github.com/kaikailang-org/ahu) (v0.2.0) is
kaikai's concurrency/fault-tolerance package — *cells* (typed stateful
message loops, the GenServer shape) plus *restart helpers* (`Permanent |
Transient | Temporary`, `Limit(n)` intensity, fixed backoff, escalation via
`Cancel` so nested supervisors compose). It is explicit that it is "not an
OTP clone".

[`kaikai-ahu/main.kai`](kaikai-ahu/main.kai) — the same real fault (a
division by zero, in the driver) under `restartable_cell(Permanent,
Limit(3), ...)`:

```text
supervisor: Permanent, Limit(3), fault = real division by zero
driver: cell at 3 — dividing 100 by 0
driver: cell at 3 — dividing 100 by 0
driver: cell at 3 — dividing 100 by 0
supervisor: intensity exhausted, escalating
```

Exit 0. Declarative policy, restarts with state reset (the cell reads 3
every cycle, never 6), an intensity budget, and clean escalation — the OTP
pattern, in a typed language, working against a genuine fault. The Elixir
demo above is no longer "framework vs no framework".

The honest edges, found by running it:

- **Bug (upstream, found here, filed as
  [ahu#34](https://github.com/kaikailang-org/ahu/issues/34)): `Transient`
  does not restart on a real fault.** ahu's restart loop matches the
  trap-exit reason against the string `"Crashed"`, but a genuine fault
  arrives as `"Trapped: divide by zero"` — so `Transient`, whose entire
  purpose is "restart only on crash", treats a real crash as a normal exit
  and returns. Verified both ways: the same body with `Cancel.raise()`
  restarts 3× and escalates; with `10 / 0` it is silently final.
  `Permanent` is unaffected (restarts on any reason).
- **A cell crash mid-driver is unobserved** — documented in ahu itself: the
  trap-exit channel is typed `String` and the body's mailbox is typed `Msg`,
  so only the *driver* fiber's death reaches the supervisor; a cell that
  dies leaves the driver stalled on a receive. The restart unit is the
  cell+driver scope, not each fiber.
- **No registry.** OTP's `name: __MODULE__` is what let the Elixir demo's
  *caller* live outside the supervision tree and keep calling across
  restarts. ahu pids are lexically scoped; callers live inside the restart
  unit and restart with it.

## Reproduce

```sh
elixir elixir/supervised.exs          # crash logged, restart, exit 0
kai build kaikai/crash_nursery.kai -o /tmp/cn && /tmp/cn; echo $?   # no survivors, 1
kai build kaikai/supervise.kai -o /tmp/sv && /tmp/sv; echo $?       # trapped + restart, 0
cd kaikai-ahu && kai install && kai run .   # ahu: 3 restarts + escalation, 0
# (the dep is git-pinned: ahu = { source = "https://github.com/kaikailang-org/ahu",
#  ref = "v0.2.0" }. Note the manifest syntax: `kai info packages` documents a
#  `{ git = ..., tag = ... }` form that kai 0.99.6 silently ignores — resolves
#  "1 dependency", locks 0 entries, no error. `source`/`ref` is what works.)
```

## Where kaikai wins / the trade-off

- **Fail-fast is the right default for batch/CLI shapes.** A compiler pass or
  data pipeline *should* die loudly when a shard corrupts, not limp on with
  one worker silently restarted. kaikai's nursery gives that for free;
  in Elixir you choose it (`restart: :temporary`, or no supervisor).
- **kaikai's crashes are rarer by construction.** Cases 1–3 of this repo are
  bug classes that cannot reach the supervisor because they never compile.
  OTP is partly compensation for a language where they do — brilliant
  compensation, honed for decades, but the fair account says kaikai needs
  case 4's machinery less often.
- **The trade-off stated plainly:** when the fault is environmental (network
  peer dies, disk fills, NIF misbehaves) no type system prevents it, and
  that is where "isolate, log, restart, escalate" as a zero-user-code
  default is untouchable. Elixir wins this case on the registry, the
  defaults, the preemptive runtime under the supervisor, and twenty-five
  years of burn-in — not on the primitive (which kaikai has) and no longer
  on the mere existence of a framework (ahu ships one; it is young, and
  this case found one of its bugs by running it — which is itself the
  maturity gap, measured).
