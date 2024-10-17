defmodule Rewrite.Hook.DotFormatterUpdater do
  @moduledoc """
  A hook that updates the dot-formatter for a `%Rewrite{}` project on changes.
  """

  alias Rewrite.DotFormatter

  @behaviour Rewrite.Hook

  @formatter ".formatter.exs"

  @impl true
  def handle(:new, project) do
    dot_formatter =
      case DotFormatter.read() do
        {:ok, dot_formatter} -> dot_formatter
        {:error, _error} -> DotFormatter.new()
      end

    _project = Rewrite.dot_formatter(project, dot_formatter)

    :ok
  end

  def handle({action, files}, project) when action in [:added, :updated] do
    files |> dot_formatter?() |> update(project)
  end

  defp update(false, _project), do: :ok

  defp update(true, project) do
    dot_formatter = DotFormatter.read!(project)
    _project = Rewrite.dot_formatter(project, dot_formatter)

    :ok
  end

  defp dot_formatter?(@formatter), do: true
  defp dot_formatter?(files) when is_list(files), do: Enum.member?(files, @formatter)
  defp dot_formatter?(_files), do: false
end
