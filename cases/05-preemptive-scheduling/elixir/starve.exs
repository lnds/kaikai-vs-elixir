defmodule Starve do
  # The same pure CPU loop. The BEAM preempts it on reduction count:
  # no yield point is needed for the heartbeat to run.
  def hog(i, limit) when i >= limit, do: i
  def hog(i, limit), do: hog(i + 1, limit)

  def heartbeat(0), do: :ok

  def heartbeat(k) do
    IO.puts("heartbeat #{k}")
    Process.sleep(50)
    heartbeat(k - 1)
  end

  def main do
    t1 =
      Task.async(fn ->
        r = hog(0, 300_000_000)
        IO.puts("hog done: #{r}")
      end)

    t2 = Task.async(fn -> heartbeat(3) end)
    Task.await(t1, 60_000)
    Task.await(t2, 60_000)
  end
end

Starve.main()
