defmodule NewlineToDotPlugin do
  @moduledoc false

  import ExUnit.Assertions
  import GlobEx.Sigils

  @behaviour Mix.Tasks.Format

  @impl true
  def features(opts) do
    assert opts[:from_formatter_exs] == :yes
    [extensions: ~w(.w), sigils: [:W]]
  end

  @impl true
  def format(contents, opts) do
    assert opts[:from_formatter_exs] == :yes

    cond do
      opts[:extension] ->
        assert opts[:extension] == ".w"
        assert opts[:file] =~ ~r/a\.w$/
        assert [W: sigil_fun] = opts[:sigils]
        assert is_function(sigil_fun, 2)

      opts[:sigil] ->
        assert opts[:sigil] == :W
        assert opts[:inputs] == [~g|a.ex|d]
        assert opts[:modifiers] == ~c"abc"

      true ->
        flunk("Plugin not loading in correctly.")
    end

    contents |> String.replace("\n", ".")
  end
end
