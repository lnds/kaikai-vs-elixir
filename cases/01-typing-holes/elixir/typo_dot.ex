defmodule AppConfigDot do
  def load do
    %{timeout: 30, retries: 3}
  end

  # Same typo through dot access. Here the 1.19 checker shines: it infers
  # load()'s return type and warns `unknown key .retires`. Still a warning
  # — the .beam ships and the run raises KeyError.
  def demo do
    cfg = load()
    IO.puts("timeout: #{cfg.timeout}")
    IO.puts("retries: #{cfg.retires}")
  end
end
