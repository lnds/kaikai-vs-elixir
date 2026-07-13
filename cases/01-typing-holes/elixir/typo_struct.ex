defmodule User do
  defstruct name: "", age: 0
end

defmodule Greeter do
  # `u.nmae` is a typo for `u.name`. Elixir 1.19's type checker catches
  # this — as a WARNING. The module still compiles, elixirc exits 0, and
  # the .beam is produced; running it raises KeyError at runtime.
  def show(%User{} = u) do
    IO.puts("name: #{u.nmae}")
  end

  def main do
    show(%User{name: "ana", age: 30})
  end
end
