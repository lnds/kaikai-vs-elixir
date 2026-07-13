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

shards = System.schedulers_online()
chunk = div(limit, shards) + 1

{best, best_n} =
  1..limit//chunk
  |> Task.async_stream(fn lo -> Collatz.scan(lo, min(lo + chunk, limit), 0, 0) end,
       ordered: false, timeout: :infinity)
  |> Enum.reduce({0, 0}, fn {:ok, {b, n}}, {bb, bn} ->
    if b > bb, do: {b, n}, else: {bb, bn}
  end)

IO.puts("longest under #{limit}: n=#{best_n} steps=#{best} (shards=#{shards})")
