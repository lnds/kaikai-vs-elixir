defmodule Collatz do
  def steps(1, s), do: s
  def steps(n, s) when rem(n, 2) == 0, do: steps(div(n, 2), s + 1)
  def steps(n, s), do: steps(3 * n + 1, s + 1)

  def scan(i, limit, best, best_n) when i >= limit, do: {best, best_n}
  def scan(i, limit, best, best_n) do
    s = steps(i, 0)
    if s > best, do: scan(i + 1, limit, s, i), else: scan(i + 1, limit, best, best_n)
  end
end

limit = case System.argv() do
  [n | _] -> String.to_integer(n)
  [] -> 1_000_000
end

{best, best_n} = Collatz.scan(1, limit, 0, 0)
IO.puts("longest under #{limit}: n=#{best_n} steps=#{best}")
