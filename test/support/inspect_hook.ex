defmodule InspectHook do
  @moduledoc false

  @behaviour Rewrite.Hook

  @file_name "inspect.txt"

  def handle(:new, project) do
    write(":new - #{inspect(project)}")

    :ok
  end

  def handle(action, project) do
    append("#{inspect(action)} - #{inspect(project)}")

    :ok
  end

  defp write(message) do
    File.write!(@file_name, message <> "\n")
  end

  defp append(message) do
    file = File.open!(@file_name, [:append])
    IO.write(file, message <> "\n")
    File.close(file)
  end
end
