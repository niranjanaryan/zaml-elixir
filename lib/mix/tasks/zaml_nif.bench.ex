defmodule Mix.Tasks.ZamlNif.Bench do
  @moduledoc false
  use Mix.Task

  @shortdoc "Benchmark Zaml against fast_yaml, glazer, yaml_elixir, and yamerl (default: benchmark/big.yml)"
  @recursive true

  @label_width 30

  @impl Mix.Task
  def run(args) do
    ensure_yaml_compiled()
    start_apps()

    path =
      case args do
        [p | _] -> p
        _ -> "benchmark/big.yml"
      end

    {:ok, contents} = File.read(path)
    n_runs = 5

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

    results =
      parsers()
      |> Enum.filter(fn {_label, app, _fun} -> available?(app) end)
      |> Enum.map(fn {label, _app, fun} -> {label, measure(fun, contents, n_runs)} end)

    rows =
      Enum.map(results, fn {label, {avg, min, max}} ->
        "  #{pad(label)} avg #{fmt_sec(avg)}  (min #{fmt_sec(min)}, max #{fmt_sec(max)})"
      end)

    Enum.each(rows, &IO.puts/1)

    skipped =
      parsers()
      |> Enum.reject(fn {_label, app, _fun} -> available?(app) end)
      |> Enum.map(fn {label, _app, _fun} -> label end)

    if skipped != [] do
      IO.puts("")
      IO.puts("  (skipped, not available: #{Enum.join(skipped, ", ")})")
    end

    print_summary(results, n_runs)
  end

  defp parsers do
    [
      {"Zaml (NIF, libyaml + Zig)", :zaml, fn c -> Zaml.load(c) end},
      {"fast_yaml 1.0 (rebar3 NIF)", :fast_yaml, fn c -> :fast_yaml.decode(c, [:sane_scalars, :maps]) end},
      {"glazer_yaml 1.1 (C++ NIF)", :glazer, fn c -> :glazer_yaml.decode(c, [:use_nil]) end},
      {"yaml_elixir 2.12 (yamerl)", :yaml_elixir, fn c -> YamlElixir.read_from_string(c) end},
      {"yamerl 0.10 (raw)", :yamerl,
       fn c ->
         :yamerl_constr.string(c,
           detailed_constr: true,
           str_node_as_binary: true,
           keep_duplicate_keys: true
         )
       end}
    ]
  end

  defp available?(:zaml), do: Code.ensure_loaded?(Zaml)
  defp available?(:fast_yaml), do: Code.ensure_loaded?(:fast_yaml)
  defp available?(:glazer), do: Code.ensure_loaded?(:glazer_yaml)
  defp available?(:yaml_elixir), do: Code.ensure_loaded?(YamlElixir)
  defp available?(:yamerl), do: Code.ensure_loaded?(:yamerl_constr)

  defp start_apps do
    for app <- [:zaml, :fast_yaml, :glazer, :yamerl] do
      Application.ensure_all_started(app)
    end

    :ok
  end

  defp measure(fun, contents, n_runs) do
    # Warm up once (JIT, caches, page faults) so it isn't charged to run 1.
    fun.(contents)
    :erlang.garbage_collect()

    1..n_runs
    |> Enum.map(fn _ ->
      # Drop the previous result before timing so GC pauses from freed
      # 1M-entry maps aren't charged to the next parser's run.
      :erlang.garbage_collect()
      {us, _result} = :timer.tc(fn -> fun.(contents) end)
      us / 1_000_000.0
    end)
    |> then(fn times ->
      {Enum.sum(times) / length(times), Enum.min(times), Enum.max(times)}
    end)
  end

  defp print_summary(results, n_runs) do
    case results do
      [] ->
        :ok

      [{zaml_label, {zaml_avg, _, _}} | _] ->
        IO.puts("")
        IO.puts("Summary (avg seconds over #{n_runs} runs):")

        Enum.each(results, fn {label, {avg, _, _}} ->
          IO.puts("  #{pad(label)} #{fmt_sec(avg)}")
        end)

        IO.puts("")

        Enum.each(tl(results), fn {label, {avg, _, _}} ->
          ratio = avg / zaml_avg
          IO.puts("  #{zaml_label} vs #{label}: #{:io_lib.format("~.2fx", [ratio])}")
        end)
    end
  end

  defp pad(label), do: String.pad_trailing(label, @label_width)

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
