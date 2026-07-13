# Contracts — `requires` / `ensures`

**Design-by-Contract in the signature: preconditions the caller must meet,
postconditions the function guarantees, checked at runtime with a structured
panic — and at compile time for literal arguments.** Elixir's nearest form is
real and deserves the credit up front: **guards** are preconditions, in the
signature, and idiomatic. The gap is threefold: guards are restricted to a
decidable expression subset; a guard miss is a generic `FunctionClauseError`
(nothing names the violated condition); and there is **no postcondition
form at all** — nothing in Elixir states `ensures result >= 0` (`@spec`
documents types, not values; libraries like `ex_contract` bolt it on with
macros, unmaintained and outside the language).

## The claim

> `requires amount > 0` / `ensures result == balance - amount` sit between
> the signature and the body, with `result` binding the return value. A
> violated clause panics naming the function, the predicate, and its
> declaration site. Predicates are arbitrary effect-pure expressions, not a
> guard-safe subset.

## It runs — contract satisfied

[`kaikai/withdraw.kai`](kaikai/withdraw.kai):

```kaikai
fn withdraw(balance: Int, amount: Int) : Int
  requires amount > 0
  requires amount <= balance
  ensures result >= 0
  ensures result == balance - amount
{
  balance - amount
}
```

`kai run kaikai/withdraw.kai` → `balance after withdraw: 70`.

## It panics — precondition violated

[`kaikai/withdraw_violated.kai`](kaikai/withdraw_violated.kai) withdraws 500
from a balance of 100 (through a binding, so the check is the runtime one):

```text
panic: requires violated in `withdraw`
required: amount <= balance
declared at line 8, col 19
```

Exit 1, and the diagnostic names the clause — compare
`FunctionClauseError: no function clause matching in withdraw/2`, which
reports only that *some* clause didn't match. With a bare literal violation
the kaikai compiler rejects the call at build time; guards get no
compile-time tier.

## The honest caveats

- Contract checks run in every build profile; they are runtime cost where a
  guard is too (BEAM guards are heavily optimized).
- Guards compose with pattern matching into multi-clause dispatch — a
  *dispatch* mechanism, not just a check. Contracts only accept/reject.
  These overlap less than they first appear; the fair sentence is "guards
  dispatch, contracts specify".

## Reproduce

```sh
kai run kaikai/withdraw.kai              # balance after withdraw: 70
kai build kaikai/withdraw_violated.kai -o /tmp/wv && /tmp/wv; echo $?   # panic, 1
```
