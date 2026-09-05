# fast_yaml's rebar3 build doesn't auto-discover libyaml. Inject
# CFLAGS/CPPFLAGS/LDFLAGS at the top of mix.exs so rebar3 subprocesses
# can find it. Honored: YAML_INCLUDE_DIR / YAML_LIB_DIR env vars
# override the auto-detection.
yaml_inc =
  System.get_env("YAML_INCLUDE_DIR") ||
    Enum.find_value(["/opt/homebrew/include", "/usr/local/include", "/usr/include"], fn prefix ->
      if File.exists?(Path.join(prefix, "yaml.h")), do: prefix
    end)

yaml_lib =
  System.get_env("YAML_LIB_DIR") ||
    Enum.find_value(["/opt/homebrew/lib", "/usr/local/lib", "/usr/lib"], fn prefix ->
      if File.exists?(Path.join(prefix, "libyaml.dylib")) or
           File.exists?(Path.join(prefix, "libyaml.so")) or
           File.exists?(Path.join(prefix, "libyaml.a")),
         do: prefix
    end)

if yaml_inc do
  System.put_env("CFLAGS", "-I#{yaml_inc}")
  System.put_env("CPPFLAGS", "-I#{yaml_inc}")
end

if yaml_lib do
  System.put_env("LDFLAGS", "-L#{yaml_lib}")
end

defmodule Zaml.MixProject do
  use Mix.Project

  def project do
    [
      app: :zaml,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "Fast YAML 1.2 parser for Elixir via a Zig NIF backed by libyaml",
      license: "MIT",
      source_url: "https://github.com/niranjanaryan/zaml-elixir",
      homepage_url: "https://hex.pm/packages/zaml",
      docs: docs(),
      package: package(),
      aliases: aliases(),
      deps: deps(),
      build_per_environment: true
    ]
  end

  def application, do: []

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [{:fast_yaml, "~> 1.0", only: [:dev, :test], runtime: false}]
  end

  defp aliases do
    [
      compile: ["zaml_nif.build", "compile"],
      test: ["zaml_nif.build", "test"]
    ]
  end

  defp docs do
    [
      main: "Zaml",
      extras: ["README.md", "LICENSE", "benchmark/RESULTS.md"]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "native",
        "priv",
        "test",
        "Makefile",
        "mix.exs",
        "mix.lock",
        "README.md",
        "README*",
        "LICENSE*",
        ".formatter.exs",
        ".gitignore",
        "benchmark/benchmark.exs",
        "benchmark/gen_big_yaml.py",
        "benchmark/run_benchmark.py",
        "benchmark/RESULTS.md"
      ],
      exclude_patterns: [
        ~r"^benchmark/big.*\.yml$",
        ~r"^benchmark/libs/"
      ],
      maintainers: ["Niranjan Aryan"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/niranjanaryan/zaml-elixir",
        "Benchmarks" => "https://github.com/niranjanaryan/zaml-elixir/blob/main/benchmark/RESULTS.md"
      }
    ]
  end
end
