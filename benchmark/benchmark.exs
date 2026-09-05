defmodule Zaml.Benchmark do
  @moduledoc false

  def run(path) do
    {:ok, contents} = File.read(path)
    n_runs = 3

    {timings, last_result} =
      Enum.reduce(1..n_runs, {[], nil}, fn _, {acc, _} ->
        {us, result} = :timer.tc(fn -> Zaml.load(contents) end)
        {[us / 1000.0 | acc], result}
      end)

    timings = Enum.reverse(timings)
    avg_ms = Enum.sum(timings) / n_runs
    min_ms = Enum.min(timings)
    max_ms = Enum.max(timings)

    IO.puts(
      "Zaml (Elixir NIF, libyaml + Zig): avg #{Float.round(avg_ms, 2)} ms  (min #{Float.round(min_ms, 2)}, max #{Float.round(max_ms, 2)})"
    )

    case last_result do
      %{} = m ->
        first_key = m |> Map.keys() |> Enum.min()
        first_val = Map.fetch!(m, first_key)
        IO.puts("RESULT_TYPE=map")
        IO.puts("RESULT_SIZE=#{map_size(m)}")
        IO.puts("RESULT_FIRST_KEY=#{first_key}")
        IO.puts("RESULT_FIRST_VALUE=#{inspect(first_val)}")

      other ->
        IO.puts("RESULT_TYPE=#{inspect(other)}")
    end

    {avg_ms, min_ms, max_ms}
  end
end

[path | _] = System.argv()
Zaml.Benchmark.run(path)
