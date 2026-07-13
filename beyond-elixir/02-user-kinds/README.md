# User-declared kinds

**The units machinery is not a privileged built-in — `kind` lets you declare
your own.** Elixir has no analogue at any tier: kinds classify *types*, and
without static types there is nothing for a kind system to classify. A macro
could tag values and check tags at runtime; it cannot make the compiler
reject a program.

## The claim

> `kind Metric : AbelianGroup with metric` declares a new kind with its own
> generator syntax. Types inhabiting different kinds never unify, so mixing
> them is a compile error — the same machinery that gives physics
> dimensional safety, user-extensible to any domain with group structure
> (currencies, coordinate frames, tenant IDs).

## It fails to compile — cross-kind addition

[`kaikai/kinds.kai`](kaikai/kinds.kai):

```kaikai
kind Metric   : AbelianGroup with metric
kind Imperial : AbelianGroup with imperial

metric m
imperial ft

fn total(a: Real<m>, b: Real<ft>) : Real<m> = a + b
```

`kai build kaikai/kinds.kai`:

```text
error: type mismatch in arithmetic operator '+'
  --> kinds.kai:10:49
     |
  10 | fn total(a: Real<m>, b: Real<ft>) : Real<m> = a + b
     |                                                 ^
  = note: expected: Real<m>
  = note: found:    Real<ft>
```

`m` inhabits `Metric`, `ft` inhabits `Imperial`; distinct kinds never unify.
The file failing to build **is** the demonstration.

## Reproduce

```sh
kai build kaikai/kinds.kai   # error: type mismatch (expected)
```
