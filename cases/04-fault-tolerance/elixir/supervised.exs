defmodule Worker do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  def divide(a, b), do: GenServer.call(__MODULE__, {:divide, a, b})

  @impl true
  def init(_), do: {:ok, nil}

  @impl true
  def handle_call({:divide, a, b}, _from, state) do
    {:reply, div(a, b), state}
  end
end

# One line of supervision policy. Restart-on-crash, back-off, max
# intensity, tree composition — all come with it; none is written here.
{:ok, _sup} = Supervisor.start_link([{Worker, nil}], strategy: :one_for_one)

IO.puts("100 / 5 = #{Worker.divide(100, 5)}")

try do
  Worker.divide(100, 0)
catch
  :exit, _ -> IO.puts("worker crashed — supervisor restarts it, the app never stopped")
end

Process.sleep(100)
IO.puts("100 / 4 = #{Worker.divide(100, 4)}")
