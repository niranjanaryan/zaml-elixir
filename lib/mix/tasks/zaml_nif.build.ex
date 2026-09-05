defmodule Mix.Tasks.ZamlNif.Build do
  @moduledoc false
  use Mix.Task

  @shortdoc "Builds the zaml Zig NIF shared library"
  @recursive true

  @impl Mix.Task
  def run(_args) do
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
end
