defmodule SigilWPlugin do
  @moduledoc false

  import ExUnit.Assertions

  @behaviour Mix.Tasks.Format

  @impl true
  def features(opts) do
    assert opts[:from_formatter_exs] == :yes
    [sigils: [:W]]
  end

  @impl true
  def format(contents, opts) do
    assert opts[:from_formatter_exs] == :yes
    assert opts[:sigil] == :W
    assert opts[:modifiers] == ~c"abc"
    assert opts[:line] == 2
    assert opts[:file] =~ ~r/a\.ex$/
    contents |> String.split(~r/\s/) |> Enum.join("\n")
  end
end
