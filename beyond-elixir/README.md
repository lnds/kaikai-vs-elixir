# Beyond Elixir — things kaikai expresses that Elixir has no form for

The six numbered [`cases/`](../cases/) are pairwise, adversarial comparisons —
the same program in both languages, measured. This section is **kaikai-only**:
each item is a language feature Elixir does not have, shown by a `.kai`
program that compiles and runs (or fails to compile, on purpose). There is no
Elixir column because there is no Elixir equivalent short of a runtime
library or "just be careful".

The bar for inclusion is deliberately high, because Elixir is *not* a small
language the way Go is: macros mean Elixir can grow almost any surface
syntax, and the 1.19 type checker is closing gaps every release. So each
entry states Elixir's nearest real approach and why it is not the same
thing. Two candidates were **excluded** for exactly that honesty: property
testing (StreamData is semi-official and good — Elixir has a form) and
effect/dependency injection for tests (Mox + behaviours is the established
form). The symmetric list — things Elixir has that kaikai has no form for —
is in the [top-level README](../README.md#what-elixir-has-that-kaikai-has-no-form-for).

## Index

| # | Feature | What it buys | Elixir's closest thing |
|---|---------|-------------|------------------------|
| 1 | [units-of-measure](01-units-of-measure/) | Dimensional safety in the type, zero runtime cost. `Real<m> + Real<ft>` is a compile error — the Mars Climate Orbiter bug, caught by the compiler. | `ex_cldr_units` et al. — runtime checking on wrapped structs, cost per operation, mistakes surface when executed. Nothing at compile time. |
| 2 | [user-kinds](02-user-kinds/) | The `Measure` kind is not special — you declare your own abelian kinds. Two kinds never unify, so `Metric.m + Imperial.ft` is rejected. | Nothing. No static types, so no kind system; a macro could build runtime tags, not compile-time rejection. |
| 3 | [contracts](03-contracts/) | `requires` / `ensures` — pre *and post*conditions in the signature, checked at runtime (and statically for literal args) with a structured violation panic. | Guards — real but preconditions only, restricted to a decidable subset, and a violation is a `FunctionClauseError`, not a named contract breach. No `ensures` anywhere. |

All three verified on kaikai 0.99.6; the outputs in each README are real.
