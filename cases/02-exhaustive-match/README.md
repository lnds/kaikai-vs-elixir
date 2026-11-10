# Case 2 — tagged tuples vs checked sum types

**Category A — Elixir's "sum type" is a convention the compiler cannot check;
kaikai's is a type the compiler proves matches against.** The idiomatic
Elixir encoding of a variant type is tagged tuples plus a `@type` that
documents them. It reads beautifully. But the `@type` is documentation: when
the type grows a variant, every `case` that should handle it keeps compiling.

## The claim

> Add `{:triangle, b, h}` to a tagged-tuple "sum type" and the `case` written
> before it exists compiles clean — `@type` and `@spec` declared, 1.19
> checker silent — and raises `CaseClauseError` at runtime. Dialyzer (opt-in,
> separate tool) can flag the bad call site via success typing. In kaikai the
> match is checked against the declared sum type at compile time: the build
> fails naming the exact missing variant.

## Elixir — the missing clause is a runtime crash

[`elixir/area.ex`](elixir/area.ex) — `:triangle` was added to `@type shape`
after `area/1` was written; `area/1` has a `@spec`, and `demo/0` calls it
with a triangle *in the same module*. `elixirc area.ex`: **silent, exit 0.**
Running it:

```text
circle:   28.274309999999996
square:   9.0
** (CaseClauseError) no case clause matching:

    {:triangle, 3.0, 4.0}

    area.ex:10: Geometry.area/1
```

Credit where due, twice. First: the failure is **loud, immediate, and names
the value** — nothing like Go's silent wrong answer in the sibling repo; a
`CaseClauseError` under a supervisor is a restart, not corruption (see
case 4). Second: **Dialyzer does catch the call site.** With a PLT built and
Elixir's ebin on the code path:

```text
area.ex:15:31: The call 'Elixir.Geometry':area
         ({triangle, 3.0, 4.0}) will never return since it differs in the
         1st argument from the success typing arguments:
         ({'circle', number()} | {'square', number()})
```

The honest print on that: it is a separate opt-in tool (PLT setup, minutes of
first-run analysis, `mix dialyxir` in practice), it flags the *caller* it can
see (an unanalyzed caller in another app gets nothing), and it stays silent
about the non-exhaustive `case` itself when no caller exercises it.

## kaikai — the missing arm is a build error

[`kaikai/area.kai`](kaikai/area.kai) compiles and runs precisely because
every constructor is handled (`circle: 28.274309999999996 / square: 9 /
triangle: 6` — since kaikai prints a `Real` as its shortest round-trip
form; 0.114 printed `28.2743`).
Delete the `Triangle` arm —
[`kaikai/area_missing_triangle.kai`](kaikai/area_missing_triangle.kai),
`kai build`:

```text
error: non-exhaustive match on Shape: missing Triangle
  = note: missing variant: `Triangle`
  = note: covered: Square, Circle
  = help: add an arm `Triangle -> ...` or a wildcard `_ -> ...`
```

Because `Shape = Circle(Real) | Square(Real) | Triangle(Real, Real)` is a
closed sum type — not a naming convention over tuples — the checker knows
the full set of cases, in every match, exercised by a caller or not.

## Reproduce

```sh
cd elixir
elixirc area.ex                     # silent, exit 0
elixir -pa . -e "Geometry.demo()"   # CaseClauseError at runtime
# optional, the honest extra mile:
dialyzer --build_plt --apps erts kernel stdlib   # once, ~7 s here
dialyzer -pa $(elixir -e 'IO.puts(:code.lib_dir(:elixir) |> Path.join("ebin"))') Elixir.Geometry.beam
cd ../kaikai
kai run area.kai                    # triangle: 6
kai build area_missing_triangle.kai # error: missing Triangle
```

## Where Elixir wins / the trade-off

- **The crash-don't-corrupt failure mode is a real design.** `CaseClauseError`
  names the value, arrives at the exact moment of the gap, and under OTP it
  is a restart with a logged report. Elixir's bet is that a great runtime
  failure story makes compile-time exhaustiveness less critical — case 4
  shows that bet paying off.
- **Open-world matching is flexibility.** Tagged tuples interoperate across
  libraries and protocol boundaries with zero shared type declarations —
  `{:reply, x}` from anyone's code matches anyone's clause. kaikai's closed
  sums demand the type be declared and imported; growing a shared type means
  touching every match, which is the point, and also friction.
- **Pattern matching ergonomics are a wash or better in Elixir** — multi-
  clause heads, guards, binaries, pin operator. Exhaustiveness is the one
  thing it does not have; this case is about exactly that and claims nothing
  wider.
