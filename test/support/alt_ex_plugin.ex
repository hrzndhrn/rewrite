defmodule AltExPlugin do
  @moduledoc """
  An alternative Elixir formatter plugin.

  The formatter sets `:force_do_end_blocks` to true by default.
  """

  import ExUnit.Assertions

  @behaviour Mix.Tasks.Format

  @impl true
  def features(opts) do
    assert opts[:from_formatter_exs] || opts[:plugin_option] == :yes
    [extensions: ~w(.ex .exs), sigils: []]
  end

  @impl true
  def format(input, opts) do
    formatted =
      input
      |> Code.string_to_quoted!()
      |> to_algebra(opts)
      |> Inspect.Algebra.format(:infinity)
      |> IO.iodata_to_binary()

    formatted <> "\n"
  end

  def to_algebra(quoted, opts) do
    assert opts[:from_formatter_exs] || opts[:plugin_option] == :yes
    assert is_binary(opts[:file])

    opts = Keyword.put(opts, :force_do_end_blocks, true)
    Code.quoted_to_algebra(quoted, opts)
  end
end
