defmodule UpdateHook do
  @moduledoc false

  @behaviour Rewrite.Hook

  alias Rewrite.Source

  def handle(:new, _project), do: :ok

  def handle({action, paths}, project) do
    project =
      paths
      |> List.wrap()
      |> Enum.reduce(project, fn path, project ->
        Rewrite.update!(project, path, fn source ->
          content = Source.get(source, :content)
          updated = "#{content}\n# #{inspect(action)} - UpdateHook"
          Source.update(source, UpdateHook, :content, updated)
        end)
      end)

    {:ok, project}
  end
end
