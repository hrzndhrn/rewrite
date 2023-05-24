defmodule Rewrite.ProjectUpdateError do
  @moduledoc """
  An exception for when a function can not handle a source.
  """

  alias Rewrite.ProjectUpdateError

  @type reason :: :nopath | :overwrites

  @type t :: %ProjectUpdateError{
          reason: reason,
          source: Path.t(),
          path: Path.t() | nil
        }

  @enforce_keys [:reason]
  defexception [:reason, :source, :path]

  @impl true
  def exception(value) do
    struct!(ProjectUpdateError, value)
  end

  @impl true
  def message(%ProjectUpdateError{reason: :nopath, source: source}) do
    "#{format(source)}: no path in updated source"
  end

  def message(%ProjectUpdateError{reason: :overwrites, source: source, path: path}) do
    "#{format(source)}: updated source overwrites #{inspect(path)}"
  end

  defp format(source), do: "can't update source #{inspect(source)}"
end
