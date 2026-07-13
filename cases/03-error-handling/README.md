# Case 3 — `{:ok, _} | {:error, _}` convention vs a checked effect row

**Category B — the ergonomics are close to a wash; the checkable part is
not.** Elixir's `with` is one of the best error-chaining constructs in any
dynamic language, and this case says so. The claim is only about what happens
when a caller *forgets* the error path: in Elixir that compiles; in kaikai it
does not.

## The claim

> Three fallible parses chain equally cleanly in both languages (`with` /
> an effect row). But the Elixir caller that assumes success — `{:ok, n} =
> sum3(...)` — **compiles without a diagnostic** (the 1.19 checker infers
> both variants and allows the match) and raises `MatchError` at runtime.
> The kaikai caller that omits the handler **fails to compile**: "this can
> fail" is part of the function's type, not a convention in a tuple tag.

## Elixir — `with` is good; forgetting is legal

[`elixir/sum3.ex`](elixir/sum3.ex). The happy path:

```elixir
def sum3(a, b, c) do
  with {:ok, x} <- to_int("a", a),
       {:ok, y} <- to_int("b", b),
       {:ok, z} <- to_int("c", c) do
    {:ok, x + y + z}
  end
end
```

`Sum3.demo()` handles both outcomes and prints `sum=42` / `error: bad b:
oops`. Nothing verbose about it — this is the pattern working as designed.

The forgetful caller:

```elixir
def demo_forgot do
  {:ok, n} = sum3("10", "oops", "12")
  IO.puts("sum=#{n}")
end
```

`elixirc sum3.ex`: **silent, exit 0** — the checker sees `sum3` returns
`{:ok, integer()} | {:error, binary()}` and a partial match against it is
still a legal (crash-on-miss) pattern match. At runtime:

```text
** (MatchError) no match of right hand side value:

    {:error, "bad b: oops"}

    sum3.ex:36: Sum3.demo_forgot/0
```

To be fair: many Elixir developers write exactly that line *on purpose* —
"crash here if it failed" is idiomatic let-it-crash, and under a supervisor
it is a controlled event. The gap is that the compiler cannot tell the
deliberate assertion from the forgotten case; both are the same program.

## kaikai — the error channel is in the type

[`kaikai/parse.kai`](kaikai/parse.kai) — a `Parse` effect whose `bad` op
returns `Nothing` (it cannot resume, so performing it abandons the
computation, like an early `{:error, _}`). `sum3`'s body is the happy path,
three calls, zero per-call ceremony; its type says `Int / Parse`. One
handler discharges the whole row. Output: `sum=42` / `error: bad b: oops` —
same behavior as the Elixir version.

The forgetful caller —
[`kaikai/parse_missing_handler.kai`](kaikai/parse_missing_handler.kai), `kai
build`:

```text
error: effect not handled: Parse
  = note: `main`'s declared row does not include `Parse`
  = help: either declare `main : ... / Parse`, or wrap this call site in
          `handle { ... } with Parse { ... }`
```

There is no way to write "assume success" by accident. (You *can* write it
on purpose — declare the effect in your own row and let a caller handle it,
or install a handler that panics — but each is a visible, typed decision.)

## Reproduce

```sh
cd elixir
elixirc sum3.ex                        # silent, exit 0
elixir -pa . -e "Sum3.demo()"          # sum=42 / error: bad b: oops
elixir -pa . -e "Sum3.demo_forgot()"   # MatchError at runtime
cd ../kaikai
kai run parse.kai                      # sum=42 / error: bad b: oops
kai build parse_missing_handler.kai    # error: effect not handled: Parse
```

## Where Elixir wins / the trade-off

- **`with` needs no new concepts.** It is pattern matching, the thing every
  Elixir developer already breathes. kaikai's version requires effects,
  rows, handlers, and a `Nothing`-typed op — more machine, and you must
  learn it before this reads as "the simple version".
- **`{:ok, _}` tuples cross every boundary.** Processes, ETS, JSON, logs —
  the convention serializes and pattern-matches everywhere. Effect rows are
  a compile-time construct; the moment an error must cross a process or wire
  boundary, kaikai too is back to encoding it in a value.
- **Deliberate crash-on-error is one honest character in Elixir** (`=`), and
  supervision makes it safe in production. In kaikai the same intent takes
  an explicit handler or row declaration — safer, wordier.
- The narrow, real difference: in Elixir the compiler cannot distinguish
  "I decided to crash" from "I forgot"; in kaikai the second is unwritable.
