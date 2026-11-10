# Case 1 — typos: warnings that ship vs errors that don't

**Category A — Elixir's new type checker catches some of this, as warnings;
kaikai makes all of it a compile error.** This case is deliberately narrow and
gives Elixir 1.19 full credit first: its set-theoretic checker is real, it
infers types across functions with no annotations, and it catches the classic
"typo'd a field name" bug in more places every release. The honest claim is
about what remains.

## The claim

> A typo'd field/key access in Elixir lands in one of three tiers: (a) dot
> access on a struct or inferred map — caught by the 1.19 checker, **as a
> warning**: `elixirc` exits 0 and the `.beam` ships; (b) bracket (`Access`)
> syntax — **silent `nil`** at runtime, no diagnostic at any tier; (c) a
> script that crashes can die **before the buffered warning is ever printed**.
> In kaikai the same typo is a **compile error** with a did-you-mean; there is
> no warning tier to ignore and no unchecked access syntax.

## Elixir — tier (a): the checker catches it, the artifact still ships

[`elixir/typo_struct.ex`](elixir/typo_struct.ex) — `u.nmae` for `u.name` on a
`%User{}`. `elixirc typo_struct.ex`:

```text
    warning: unknown key .nmae in expression:

        u.nmae

    the given type does not have the given key:

        dynamic(%User{name: term(), age: term()})
    ...
    └─ typo_struct.ex:10:24: Greeter.show/1
```

This is genuinely good — 1.19 infers the struct type from the pattern and
names the bad key. But it is a *warning*: **exit code 0, the `.beam` is
produced**, CI that doesn't set `--warnings-as-errors` deploys it, and the
run raises at runtime:

```text
** (KeyError) key :nmae not found in: %User{name: "ana", age: 30}
Did you mean: * :name
```

[`elixir/typo_dot.ex`](elixir/typo_dot.ex) shows the same tier for a plain
map: the checker infers `load()`'s return type `%{retries: integer(),
timeout: integer()}` across the function boundary and warns on `cfg.retires`.
Impressive — and still exit 0.

## Elixir — tier (b): Access syntax is silent

[`elixir/typo_access.ex`](elixir/typo_access.ex) — the same typo written
`cfg[:retires]`, which is exactly how optional config keys are convention-
ally read. `elixirc` prints **nothing**. Running it:

```text
timeout: 30
retries:
```

`cfg[:retires]` returned `nil`, `nil` interpolated as the empty string, and
the output is silently wrong. No crash, no warning, the `nil` flows onward —
if it later hits arithmetic the `ArithmeticError` points far from the typo.

## Elixir — tier (c): the warning you never saw

A curiosity, verified: put the tier-(a) code in a script and run
`elixir typo_struct.exs` — the output is the `KeyError` **with no warning
before it**. Warnings are buffered and grouped per compilation; the crash
kills the script before they flush. The diagnostic that predicted the crash
is never printed. (Run the same file without executing anything and the
warning appears.)

## kaikai — one tier: it does not compile

[`kaikai/config_typo.kai`](kaikai/config_typo.kai), `kai build`:

```text
error: no field 'retires' on AppConfig (did you mean `.retries`?)
  --> config_typo.kai:11:45
     |
  11 |   Stdout.print("retries: #{int_to_string(cfg.retires)}")
     |                                             ^
```

And there is no unchecked access path to fall back to: a `Map` read returns
`Option[v]`, so "the key might be absent" is a case the type system forces
you to handle. [`kaikai/lookup.kai`](kaikai/lookup.kai) runs (`found 3` /
`absent`); [`kaikai/lookup_missing_none.kai`](kaikai/lookup_missing_none.kai)
— the version that forgets absence — does not compile:

```text
error: non-exhaustive match on Option: missing None
  = note: missing variant: `None`
```

## Reproduce

```sh
cd elixir
elixirc typo_struct.ex          # warning, exit 0
elixir -pa . -e "Greeter.main()"    # KeyError at runtime
elixirc typo_access.ex          # silent
elixir -pa . -e "AppConfig.demo()"  # "retries: " — silently wrong
cd ../kaikai
kai build config_typo.kai       # error: no field 'retires' (did you mean .retries?)
kai run lookup.kai              # found 3 / absent
kai build lookup_missing_none.kai   # error: non-exhaustive match: missing None
```

## Where Elixir wins / the trade-off

- **The 1.19 checker is a genuine, fast-moving achievement.** Gradual typing
  over a 12-year-old dynamic language, no annotations required, already
  covering structs, inferred map returns, and more each release. The gap
  this case shows (Access syntax, warning-not-error) is the kind the Elixir
  team is actively closing — re-run this case on 1.20.
- **`--warnings-as-errors` exists.** A team that turns it on gets much of the
  kaikai behavior. The gap is that it is opt-in and repo-wide (turning it on
  late in a legacy codebase is a project), whereas in kaikai it is not a
  choice anyone can un-make.
- **Dynamic access is a feature.** `cfg[:maybe_key]` returning `nil` is
  exactly what you want for genuinely optional keys — Elixir makes the
  optional read frictionless, kaikai makes you match an `Option` every time.
  The cost is only visible when the key was supposed to exist.
- kaikai's advantage here is categorical, not incremental: field access
  cannot be wrong at runtime because it never compiles wrong.
