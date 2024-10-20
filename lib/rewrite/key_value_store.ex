defmodule Rewrite.KeyValueStore do
  @moduledoc false

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def put(%Rewrite{} = rewrite, key, value) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, {rewrite.id, key}, value)
    end)

    rewrite
  end

  def get(rewrite, key, default \\ nil)

  def get(%Rewrite{} = rewrite, key, default) do
    get(rewrite.id, key, default)
  end

  def get(id, key, default) when is_integer(id) do
    Agent.get(__MODULE__, fn state ->
      # TODO: Map.get(state, {id, key}, default)
      get_value(state, {id, key}, default)
    end)
  end

  def get_and_update(rewrite, key, value, default \\ nil)

  def get_and_update(%Rewrite{} = rewrite, key, value, default) do
    get_and_update(rewrite.id, key, value, default)
  end

  def get_and_update(id, key, value, default) when is_integer(id) do
    Agent.get_and_update(__MODULE__, fn state ->
      # TODO: result = Map.get(state, {id, key}, default)
      result = get_value(state, {id, key}, default)
      state = Map.put(state, {id, key}, value)

      {result, state}
    end)
  end

  # TODO: remove
  defp get_value(map, key, default) do
    case Map.fetch(map, key) do
      :error -> default
      {:ok, nil} -> default
      {:ok, value} -> value
    end
  end
end
