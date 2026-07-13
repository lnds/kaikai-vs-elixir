# Case 4 — supervision: a framework vs primitives

**Category C — Elixir wins.** This is OTP's home turf, and the honest result
is not the strawman "kaikai dies on any crash". kaikai has the actual
primitives (links, trap-exit, monitors) and a hand-rolled restart works —
proven below. What it does not have is the *framework*: declarative restart
strategies, intensity limits, supervision trees, and crash isolation as the
default posture of the whole runtime.

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
`process_flag(trap_exit, true)` pattern, working. Everything above that
layer is on you: this demo's "policy" is one hard-coded respawn. Restart
intensity, back-off, ordering (`rest_for_one`), dynamic children, tree
composition — each would be user code, and each is code OTP users have not
written since 1998. (`Monitor` exists too, for observation without linking;
`unlink` does not exist yet, and mailbox-based supervision of *typed* actors
couples the supervisor's message type to a `MonitorDown` variant.)

## Reproduce

```sh
elixir elixir/supervised.exs          # crash logged, restart, exit 0
kai build kaikai/crash_nursery.kai -o /tmp/cn && /tmp/cn; echo $?   # no survivors, 1
kai build kaikai/supervise.kai -o /tmp/sv && /tmp/sv; echo $?       # trapped + restart, 0
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
  default is untouchable. Elixir wins this case on the framework, the
  default, and twenty-five years of production burn-in — not on the
  primitive, which kaikai has.
