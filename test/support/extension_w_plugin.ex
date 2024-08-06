defmodule ExtensionWPlugin do
  @moduledoc false

  import ExUnit.Assertions

  @behaviour Mix.Tasks.Format

  @impl true
  def features(opts) do
    assert opts[:from_formatter_exs] == :yes
    [extensions: ~w(.w), sigils: [:W]]
  end

  @impl true
  def format(contents, opts) do
    assert opts[:from_formatter_exs] == :yes
    assert opts[:extension] == ".w"
    assert opts[:file] =~ ~r/a\.w$/
    assert [W: sigil_fun] = opts[:sigils]
    assert is_function(sigil_fun, 2)
    contents |> String.split(~r/\s/) |> Enum.join("\n")
  end
end
