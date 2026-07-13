# Discarded — "Elixir doesn't catch struct-field typos"

The candidate claim, imported from the era of Elixir ≤ 1.16 (and from what
"dynamic language" used to imply):

> A typo'd struct field (`user.nmae`) sails through the Elixir compiler and
> only fails at runtime with a `KeyError`.

**False on Elixir 1.19, proven by compiling.** The set-theoretic type checker
infers the struct type from the pattern and flags the access:

```text
    warning: unknown key .nmae in expression:

        u.nmae

    the given type does not have the given key:

        dynamic(%User{name: term(), age: term()})
```

It does the same for plain maps returned from another function — inference
across function boundaries, no annotations. The strong claim is dead, and
publishing it would be exactly the strawman this repo exists to avoid.

What survives is the *narrowed* claim in
[`cases/01-typing-holes/`](../../cases/01-typing-holes/): the diagnostic is a
**warning** (exit 0, the `.beam` ships), bracket/`Access` reads (`cfg[:key]`)
remain silent-`nil`, and a crashing script can die before the buffered
warning prints. Narrower, still real — and likely to narrow further as the
checker grows, which is why the case says "re-run this on 1.20".
