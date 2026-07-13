defmodule Sum3 do
  def to_int(field, s) do
    case Integer.parse(s) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "bad #{field}: #{s}"}
    end
  end

  # `with` is Elixir's answer to error chaining, and it is a good one:
  # the happy path reads straight, the first {:error, _} short-circuits.
  def sum3(a, b, c) do
    with {:ok, x} <- to_int("a", a),
         {:ok, y} <- to_int("b", b),
         {:ok, z} <- to_int("c", c) do
      {:ok, x + y + z}
    end
  end

  def demo do
    case sum3("10", "20", "12") do
      {:ok, n} -> IO.puts("sum=#{n}")
      {:error, msg} -> IO.puts("error: #{msg}")
    end

    case sum3("10", "oops", "12") do
      {:ok, n} -> IO.puts("sum=#{n}")
      {:error, msg} -> IO.puts("error: #{msg}")
    end
  end

  # The forgetful caller: assumes success. {:ok, _} | {:error, _} is a
  # convention, not a checked type — this compiles without a peep (the
  # 1.19 checker infers both variants and still allows the match) and
  # raises MatchError at runtime.
  def demo_forgot do
    {:ok, n} = sum3("10", "oops", "12")
    IO.puts("sum=#{n}")
  end
end
