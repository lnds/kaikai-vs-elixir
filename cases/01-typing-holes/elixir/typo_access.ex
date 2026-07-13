defmodule AppConfig do
  def load do
    %{timeout: 30, retries: 3}
  end

  # `cfg[:retires]` is a typo for `cfg[:retries]`. Access syntax returns
  # nil for a missing key, the checker says nothing (even in 1.19), and
  # nil interpolates as the empty string: the output is silently wrong.
  def demo do
    cfg = load()
    IO.puts("timeout: #{cfg[:timeout]}")
    IO.puts("retries: #{cfg[:retires]}")
  end
end
