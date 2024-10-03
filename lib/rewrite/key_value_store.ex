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

  def get(%Rewrite{} = rewrite, key, default) do
    get(rewrite.id, key, default)
  end

  def get(id, key, default) when is_integer(id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state, {id, key}) do
        :error -> default
        {:ok, nil} -> default
        {:ok, value} -> value
      end
    end)
  end
end
