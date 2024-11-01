defmodule AltExWrapperPlugin do
  @moduledoc """
  A wrapper for `AltExPlugin`.
  """

  import ExUnit.Assertions

  alias AltExPlugin
  @behaviour Rewrite.DotFormatter

  @impl true
  defdelegate features(opts), to: AltExPlugin

  @impl true
  defdelegate format(input, opts), to: AltExPlugin

  @impl true
  def quoted_to_algebra(input, opts) do
    assert opts[:wrapper] == :yes
    AltExPlugin.to_algebra(input, opts)
  end
end
