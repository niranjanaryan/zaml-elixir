defmodule Mix.Tasks.ZamlNif.Build do
  @moduledoc false
  use Mix.Task

  @shortdoc "Builds the zaml Zig NIF shared library"
  @recursive true

  @impl Mix.Task
  def run(_args) do
    ensure_yaml_env()
    ensure_fast_yaml_compiled()
    app_path = Mix.Project.app_path()
    priv_dir = Path.join(app_path, "priv")
    File.mkdir_p!(priv_dir)
    so_path = Path.join(priv_dir, "zaml.so")
    stamp_path = Path.join(priv_dir, ".zaml_nif.stamp")

    sources = ["native/zaml_nif.zig", "Makefile"]

    need_build =
      not File.exists?(so_path) or
        Enum.any?(sources, fn s ->
          File.exists?(s) and newer?(s, so_path)
        end)

    if need_build do
      Mix.shell().info("Compiling zaml NIF (zig build-lib)...")

      erts_dir = erlang_includes()

      {out, exit} =
        System.cmd(
          "make",
          ["all", "MIX_APP_PATH=#{app_path}", "ERTS_INCLUDE_DIR=#{erts_dir}"],
          stderr_to_stdout: true,
          cd: File.cwd!()
        )

      IO.write(out)
      if exit != 0, do: raise("Failed to compile zaml NIF")
      File.touch(stamp_path)
    end
  end

  defp erlang_includes do
    if dir = System.get_env("ERTS_INCLUDE_DIR"), do: dir, else: find_erts_include()
  end

  # Find the ERTS include directory by walking up from the erl binary.
  # This is more reliable than code:lib_dir(erts, include) which can point
  # to a non-existent path under non-standard Erlang layouts (e.g. mise).
  defp find_erts_include do
    case locate_erl() do
      nil ->
        raise "Could not determine ERTS include dir; set ERTS_INCLUDE_DIR explicitly"

      bin ->
        bin
        |> Path.dirname()
        |> walk_up_for_erts(5)
        |> case do
          nil -> raise "Could not determine ERTS include dir; set ERTS_INCLUDE_DIR explicitly"
          erts_root -> Path.join(erts_root, "include")
        end
    end
  end

  defp locate_erl do
    System.find_executable("erl")
  end

  defp walk_up_for_erts(_dir, 0), do: nil

  defp walk_up_for_erts(dir, n) do
    parent = Path.dirname(dir)

    case Path.wildcard(Path.join(parent, "erts-*")) do
      [] -> walk_up_for_erts(parent, n - 1)
      [erts | _] -> erts
    end
  end

  defp newer?(a, b) do
    case {File.stat(a, time: :posix), File.stat(b, time: :posix)} do
      {{:ok, %File.Stat{mtime: t1}}, {:ok, %File.Stat{mtime: t2}}} -> t1 > t2
      _ -> true
    end
  end

  # Make sure rebar3-compiled deps (fast_yaml) can find libyaml.
  # pkg-config is checked first; fall back to common well-known prefixes.
  defp ensure_yaml_env do
    yaml_inc = System.get_env("YAML_INCLUDE_DIR") || guess_yaml_dir("include", "yaml.h")
    yaml_lib = System.get_env("YAML_LIB_DIR") || guess_yaml_dir("lib", "libyaml.dylib")

    if yaml_inc do
      System.put_env("CFLAGS", "-I#{yaml_inc}")
      System.put_env("CPPFLAGS", "-I#{yaml_inc}")
      if yaml_lib, do: System.put_env("LDFLAGS", "-L#{yaml_lib}")
    end
  end

  defp guess_yaml_dir(sub, marker) do
    for prefix <- ["/opt/homebrew", "/usr/local", "/usr"],
        File.exists?(Path.join(prefix, Path.join(sub, marker))) do
      Path.join(prefix, sub)
    end
    |> List.first()
  end

  # If the user has `fast_yaml` in their deps and it failed to compile because
  # of a missing libyaml header, retry now that we've exported the env vars.
  defp ensure_fast_yaml_compiled do
    fast_yaml_priv = Path.join([Mix.Project.deps_path(), "fast_yaml", "priv"])

    if File.dir?(fast_yaml_priv) do
      so_path = Path.wildcard(Path.join([fast_yaml_priv, "**/*.so"])) |> List.first()

      if is_nil(so_path) do
        Mix.shell().info("Re-attempting fast_yaml compile with libyaml env...")

        {out, exit} =
          System.cmd(
            "mix",
            ["deps.compile", "fast_yaml", "--force"],
            stderr_to_stdout: true,
            cd: File.cwd!()
          )

        IO.write(out)
        if exit != 0, do: raise("fast_yaml compile failed even with libyaml env set")
      end
    end
  end
end
