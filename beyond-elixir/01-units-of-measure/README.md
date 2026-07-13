# Units of measure

**kaikai carries physical units in the type, checked at compile time, erased
at runtime.** Elixir has no form for this: a `float` holding metres and a
`float` holding feet are indistinguishable, to the compiler and to the 1.19
type checker — `float()` is `float()`. The runtime-library route exists
(`ex_cldr_units` wraps quantities in structs and raises on mismatched
arithmetic) but it checks when the code *runs*, costs a struct + dispatch per
operation, and only covers the operations the library wraps.

## The claim

> In kaikai a dimensioned quantity is `Real<m>`, `Real<m/s>`. The compiler
> checks dimensions: adding metres to feet is a type error, dividing composes
> the unit, and the apparatus is **phantom** — zero runtime cost, erased
> after type-checking. The Mars Climate Orbiter unit-mismatch bug is
> uncatchable-until-runtime in Elixir and a compile error in kaikai.

## It runs — units compose correctly

[`kaikai/speed.kai`](kaikai/speed.kai):

```kaikai
unit m
unit s

fn speed(dist: Real<m>, time: Real<s>) : Real<m/s> = dist / time

fn main() : Unit / Stdout = {
  let v = speed(100.0<m>, 9.58<s>)
  let raw = v * 1.0<s/m>              # cancel to a dimensionless Real to print
  Stdout.print("speed = #{real_to_string(raw)} m/s")
}
```

`kai run kaikai/speed.kai`:

```text
speed = 10.4384 m/s
```

## It fails to compile — the Mars Orbiter bug

[`kaikai/mars_orbiter.kai`](kaikai/mars_orbiter.kai) adds metres to feet.
`kai build`:

```text
error: type mismatch in arithmetic operator '+'
  --> mars_orbiter.kai:8:49
    |
  8 | fn total(a: Real<m>, b: Real<ft>) : Real<m> = a + b
    |                                                 ^
  = note: expected: Real<m>
  = note: found:    Real<ft>
```

## The honest caveats

- Printing requires cancelling to a bare `Real` (`v * 1.0<s/m>`) — the
  discipline is airtight enough that even *you* cannot casually extract the
  number. Ergonomic cost, stated.
- Elixir's runtime libraries do more than this in one dimension: unit
  *conversion* (m → ft) with locale-aware formatting. kaikai's units reject
  the mix; they do not convert for you.

## Reproduce

```sh
kai run kaikai/speed.kai            # speed = 10.4384 m/s
kai build kaikai/mars_orbiter.kai   # error: type mismatch
```
