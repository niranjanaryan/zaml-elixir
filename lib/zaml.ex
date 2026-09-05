defmodule Zaml do
  @moduledoc """
  Fast YAML 1.2 parser for Elixir, backed by a Zig NIF using libyaml.
  """

  @on_load :init_nif

  @doc """
  Parses a YAML string and returns the corresponding Elixir term.

  Returns `:parse_error` for malformed input.
  """
  def load(yaml) when is_binary(yaml) do
    Zaml.NIF.load(yaml)
  end

  def init_nif do
    path = :filename.join(:code.priv_dir(:zaml), ~c"zaml")
    :erlang.load_nif(path, 0)
  end

  defmodule NIF do
    @moduledoc false
    def load(_yaml), do: :erlang.nif_error(:nif_not_loaded)
  end
end
