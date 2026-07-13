defmodule Geometry do
  @type shape :: {:circle, float()} | {:square, float()} | {:triangle, float(), float()}

  # The shape "sum type" is a convention: tagged tuples plus a @type that
  # documents them. `:triangle` was added after area/1 was written; the
  # case below no longer covers the type, and the compiler — 1.19 checker
  # included — says nothing. The crash is at runtime, at the call site.
  @spec area(shape()) :: float()
  def area(shape) do
    case shape do
      {:circle, r} -> 3.14159 * r * r
      {:square, s} -> s * s
    end
  end

  def demo do
    IO.puts("circle:   #{area({:circle, 3.0})}")
    IO.puts("square:   #{area({:square, 3.0})}")
    IO.puts("triangle: #{area({:triangle, 3.0, 4.0})}")
  end
end
