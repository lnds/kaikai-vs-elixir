defmodule Starve do
  # The same fold-proof CPU hog: a Collatz scan. The BEAM preempts it
  # on reduction count; no yield point is needed for the heartbeat.
  def collatz(1, s), do: s
  def collatz(n, s) when rem(n, 2) == 0, do: collatz(div(n, 2), s + 1)
  def collatz(n, s), do: collatz(3 * n + 1, s + 1)

  def hog(i, limit, acc) when i >= limit, do: acc
  def hog(i, limit, acc), do: hog(i + 1, limit, acc + collatz(i, 0))

  def heartbeat(0), do: :ok

  def heartbeat(k) do
    IO.puts("heartbeat #{k}")
    Process.sleep(50)
    heartbeat(k - 1)
  end

  def main do
    t1 =
      Task.async(fn ->
        acc = hog(1, 3_000_000, 0)
        IO.puts("hog done: acc=#{acc}")
      end)

    t2 = Task.async(fn -> heartbeat(3) end)
    Task.await(t1, 60_000)
    Task.await(t2, 60_000)
  end
end

Starve.main()
