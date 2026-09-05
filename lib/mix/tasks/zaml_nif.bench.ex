defmodule Mix.Tasks.ZamlNif.Bench do
  @moduledoc false
  use Mix.Task

  @shortdoc "Benchmark Zaml against fast_yaml on a YAML file (default: benchmark/big.yml)"
  @recursive true

  @impl Mix.Task
  def run(args) do
    ensure_yaml_compiled()
    Application.ensure_all_started(:fast_yaml)
    Application.ensure_all_started(:zaml)

    path =
      case args do
        [p | _] -> p
        _ -> "benchmark/big.yml"
      end

    {:ok, contents} = File.read(path)
    n_runs = 3

    n_lines =
      case System.cmd("wc", ["-l", path], stderr_to_stdout: true) do
        {out, 0} ->
          out |> String.split() |> List.first() |> Integer.parse() |> elem(0)

        _ ->
          0
      end

    IO.puts("""
    Benchmarking on #{delimit(byte_size(contents))} byte, #{n_lines} line YAML file (#{path})
    """)

    # --- Zaml ---
    {zaml_times, _} = bench(fn -> Zaml.load(contents) end, n_runs)
    {zaml_avg, zaml_min, zaml_max} = summarize(zaml_times)

    IO.puts(
      "  Zaml (NIF, libyaml + Zig)    avg #{fmt_sec(zaml_avg)}  (min #{fmt_sec(zaml_min)}, max #{fmt_sec(zaml_max)})"
    )

    # --- fast_yaml ---
    {fy_times, _} =
      bench(
        fn ->
          case :fast_yaml.decode(contents, [:sane_scalars, :maps]) do
            {:ok, docs} -> docs
            other -> other
          end
        end,
        n_runs
      )

    {fy_avg, fy_min, fy_max} = summarize(fy_times)
    IO.puts("  fast_yaml 1.0 (rebar3 NIF)   avg #{fmt_sec(fy_avg)}  (min #{fmt_sec(fy_min)}, max #{fmt_sec(fy_max)})")

    IO.puts("")
    IO.puts("Summary (avg seconds over #{n_runs} runs):")
    IO.puts("  Zaml (NIF, libyaml + Zig)    #{fmt_sec(zaml_avg)}")
    IO.puts("  fast_yaml 1.0                #{fmt_sec(fy_avg)}")
    IO.puts("")
    IO.puts("  Zaml vs fast_yaml: #{:io_lib.format("~.2fx", [fy_avg / zaml_avg])}")
  end

  defp bench(fun, n_runs) do
    Enum.map(1..n_runs, fn _ ->
      {us, result} = :timer.tc(fun)
      {us / 1_000_000.0, result}
    end)
    |> Enum.unzip()
    |> then(fn {times, results} -> {times, hd(results)} end)
  end

  defp summarize(times) do
    avg = Enum.sum(times) / length(times)
    {avg, Enum.min(times), Enum.max(times)}
  end

  defp fmt_sec(s) when s >= 1.0, do: :io_lib.format("~.3f s", [s]) |> List.to_string()
  defp fmt_sec(s), do: :io_lib.format("~.1f ms", [s * 1000.0]) |> List.to_string()

  defp delimit(n) when is_integer(n) and n < 1000, do: Integer.to_string(n)

  defp delimit(n) when is_integer(n) do
    s = Integer.to_string(n)
    {head, tail} = String.split_at(s, rem(String.length(s), 3))
    if head == "", do: tail, else: head <> "," <> delimit_str(tail)
  end

  defp delimit_str(s) when byte_size(s) <= 3, do: s

  defp delimit_str(s) do
    {h, t} = String.split_at(s, 3)
    h <> "," <> delimit_str(t)
  end

  # fast_yaml's rebar3 build script doesn't auto-discover Homebrew's
  # libyaml. If we know the path, set CFLAGS/CPPFLAGS/LDFLAGS so rebar
  # picks it up; otherwise hope pkg-config is set up.
  defp ensure_yaml_compiled do
    yaml_inc = System.get_env("YAML_INCLUDE_DIR") || guess_yaml_dir("include")
    yaml_lib = System.get_env("YAML_LIB_DIR") || guess_yaml_dir("lib")

    if yaml_inc do
      System.put_env("CFLAGS", "-I#{yaml_inc}")
      System.put_env("CPPFLAGS", "-I#{yaml_inc}")
      if yaml_lib, do: System.put_env("LDFLAGS", "-L#{yaml_lib}")
    end

    :ok
  end

  defp guess_yaml_dir(sub) do
    marker = if sub == "include", do: "yaml.h", else: "libyaml.dylib"

    for prefix <- ["/opt/homebrew", "/usr/local", "/usr"],
        File.exists?(Path.join(prefix, Path.join(sub, marker))) do
      Path.join(prefix, sub)
    end
    |> List.first()
  end
end
