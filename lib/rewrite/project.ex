defmodule Rewrite.Project do
  @moduledoc """
  The `%Project{}` contains all `%Rewrite.Sources{}` of a project.
  """

  alias Rewrite.Project
  alias Rewrite.ProjectError
  alias Rewrite.Source

  defstruct sources: %{}

  @type id :: reference()

  @type t :: %Project{sources: %{id() => Source.t()}}

  @type wildcard :: IO.chardata()

  @doc """
  Creates a `%Project{}` from the given `inputs`.
  """
  @spec read!(input | [input]) :: t() when input: Path.t() | wildcard() | GlobEx.t()
  def read!(inputs) do
    inputs =
      inputs
      |> List.wrap()
      |> Enum.map(&compile_globs!/1)
      |> Enum.flat_map(&GlobEx.ls/1)

    sources =
      Enum.reduce(inputs, %{}, fn path, sources ->
        source = Source.read!(path)
        Map.put(sources, source.id, source)
      end)

    struct!(Project, sources: sources)
  end

  @doc ~S"""
  Creates a `%Project{}` from the given sources.
  """
  @spec from_sources([Source.t()]) :: Project.t()
  def from_sources(sources) do
    sources =
      Enum.reduce(sources, %{}, fn source, sources ->
        Map.put(sources, source.id, source)
      end)

    struct!(Project, sources: sources)
  end

  @doc """
  Returns all sources sorted by path.
  """
  @spec sources(t()) :: [Source.t()]
  def sources(%Project{sources: sources}) do
    sources
    |> Map.values()
    |> Enum.sort_by(fn source -> source.path end)
  end

  @doc ~S'''
  Returns a list of `%Source{}` for the given `path`.

  It is possible that the project contains multiple sources with the same path.
  The function `conflicts/1` returns all conflicts in a project and the function
  `save/2` returns an error tuple when trying to save a project with conflicts.
  It is up to the user of `rewrite` to handle conflicts.

  ## Examples

      iex> source = Source.from_string(
      ...>    """
      ...>    defmodule MyApp.Mode do
      ...>    end
      ...>    """,
      ...>    "my_app/mode.ex"
      ...> )
      iex> project = Project.from_sources([source])
      iex> Project.sources(project, "my_app/mode.ex")
      [source]
      iex> Project.sources(project, "foo")
      []

      iex> a = Source.from_string(":a", "a.ex")
      iex> b = Source.from_string(":b", "b.ex")
      iex> project = Project.from_sources([a, b])
      iex> update = Source.update(a, :test, path: "b.ex")
      iex> project = Project.update(project, update)
      iex> Project.sources(project, "a.ex")
      []
      iex> Project.sources(project, "b.ex")
      [b, update]
  '''
  @spec sources(t(), Path.t()) :: [Source.t()]
  def sources(%Project{sources: sources}, path) do
    Enum.reduce(sources, [], fn {_id, source}, acc ->
      case source.path == path do
        true -> [source | acc]
        false -> acc
      end
    end)
  end

  @doc """
  Returns the `%Rewrite.Source{}` for the given `path`.

  Returns an `:ok` tuple with the found source, if no or multiple sources are
  available an `:error` is returned.
  """
  @spec source(t(), Path.t()) :: {:ok, Source.t()} | :error
  def source(%Project{} = project, path) do
    case sources(project, path) do
      [source] -> {:ok, source}
      _else -> :error
    end
  end

  @doc """
  Same as `source/2` but raises a `ProjectError`.
  """
  @spec source!(t(), Path.t()) :: Source.t()
  def source!(%Project{} = project, path) do
    case source(project, path) do
      {:ok, source} -> source
      :error -> raise ProjectError, "No source for #{inspect(path)} found."
    end
  end

  @doc """
  Returns a list of `%Rewrite.Source{}` with an implementation for the given
  `module`.
  """
  @spec sources_by_module(t(), module()) :: [Source.t()]
  def sources_by_module(%Project{sources: sources}, module) do
    Enum.reduce(sources, [], fn {_id, source}, acc ->
      case module in source.modules do
        true -> [source | acc]
        false -> acc
      end
    end)
  end

  @doc """
  Returns the `%Rewrite.source{}` for the given `module`.

  Returns an `:ok` tuple with the found source, if no or multiple sources are
  available an `:error` is returned.
  """
  @spec source_by_module(t(), module()) :: {:ok, Source.t()} | :error
  def source_by_module(%Project{} = project, module) do
    case sources_by_module(project, module) do
      [source] -> {:ok, source}
      _else -> :error
    end
  end

  @doc """
  Same as `source_by_module/2` but raises a `ProjectError`.
  """
  @spec source_by_module!(t(), module()) :: Source.t()
  def source_by_module!(%Project{} = project, module) do
    case source_by_module(project, module) do
      {:ok, source} -> source
      :error -> raise ProjectError, "No source for #{inspect(module)} found."
    end
  end

  @doc """
  Updates the `project` with the given `source`.

  If the `source` is part of the project the `source` will be replaced,
  otherwise the `source` will be added.
  """
  @spec update(t(), Source.t() | [Source.t()]) :: t()
  def update(%Project{sources: sources} = project, %Source{} = source) do
    case update?(project, source) do
      false ->
        project

      true ->
        sources = Map.put(sources, source.id, source)
        %Project{project | sources: sources}
    end
  end

  def update(%Project{} = project, sources) when is_list(sources) do
    Enum.reduce(sources, project, fn source, project -> update(project, source) end)
  end

  defp update?(%Project{sources: sources}, %Source{id: id} = source) do
    case Map.fetch(sources, id) do
      {:ok, legacy} -> legacy != source
      :error -> true
    end
  end

  @doc """
  Returns the unreferenced sources.

  Unreferenced source are sources whose original path is no longer part of the
  project.
  """
  @spec unreferenced(t()) :: [Source.t()]
  def unreferenced(%Project{sources: sources}) do
    {actual, orig} =
      sources
      |> Map.values()
      |> Enum.reduce({MapSet.new(), MapSet.new()}, fn source, {actual, orig} ->
        case {Source.path(source), Source.path(source, 1)} do
          {path, path} ->
            {actual, orig}

          {actual_path, orig_path} ->
            {MapSet.put(actual, actual_path), MapSet.put(orig, orig_path)}
        end
      end)

    orig
    |> MapSet.difference(actual)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @doc """
  Returns conflicts between sources.

  Sources with the same path have a conflict.
  """
  @spec conflicts(t()) :: %{Path.t() => [Source.t()]}
  def conflicts(%Project{sources: sources}) do
    sources
    |> Map.values()
    |> conflicts(%{}, %{})
  end

  defp conflicts([], _seen, conflicts), do: conflicts

  defp conflicts([source | sources], seen, conflicts) do
    path = Source.path(source)

    case Map.fetch(conflicts, path) do
      {:ok, list} ->
        conflicts = Map.put(conflicts, path, [source | list])
        conflicts(sources, seen, conflicts)

      :error ->
        case Map.fetch(seen, path) do
          {:ok, item} ->
            seen = Map.delete(seen, path)
            conflicts = Map.put(conflicts, path, [source, item])
            conflicts(sources, seen, conflicts)

          :error ->
            seen = Map.put(seen, path, source)
            conflicts(sources, seen, conflicts)
        end
    end
  end

  @doc """
  Returns `true` if any source has one or more issues.
  """
  @spec issues?(t) :: boolean
  def issues?(%Project{sources: sources}) do
    sources
    |> Map.values()
    |> Enum.any?(fn %Source{issues: issues} -> not Enum.empty?(issues) end)
  end

  @doc """
  Counts the items of the given `type` in the `project`.

  The `type` `:sources` returns the count for all sources in the project,
  including scripts.

  The `type` `:scripts` returns the count of all sources with a path that ends
  with `".exs"`.
  """
  @spec count(t, type :: :sources | :scripts) :: non_neg_integer
  def count(%Project{sources: sources}, :sources), do: map_size(sources)

  def count(%Project{sources: sources}, :scripts) do
    sources
    |> Map.values()
    |> Enum.filter(fn
      %{path: nil} -> false
      %{path: path} -> String.ends_with?(path, ".exs")
    end)
    |> Enum.count()
  end

  @doc """
  Return a `%Project{}` where each `source` is the result of invoking `fun` on
  each `source` of the given `project`.
  """
  @spec map(t(), (Source.t() -> Source.t())) :: t()
  def map(%Project{} = project, fun) do
    Enum.reduce(project, project, fn source, project ->
      Project.update(project, fun.(source))
    end)
  end

  @doc """
  Saves all sources in the `project` to disk.

  This function call `Rewrite.Source.save/1` on all sources in the `project`.

  The optional second argument accepts a list of paths for files to be excluded.
  """
  @spec save(t(), [Path.t()]) ::
          :ok | {:error, :conflicts | {Path.t(), File.posix()}}
  def save(%Project{sources: sources} = project, exclude \\ []) do
    with :ok <- conflict_free(project, exclude) do
      result =
        sources
        |> Map.values()
        |> Enum.reduce([], fn source, errors ->
          save(source, exclude, errors)
        end)

      case result do
        [] -> :ok
        errors -> {:error, errors}
      end
    end
  end

  defp save(source, exclude, errors) do
    case write?(source, exclude) do
      false ->
        errors

      true ->
        case Source.save(source) do
          :ok -> errors
          {:error, :nofile} -> errors
          {:error, reason} -> [{source.path, reason} | errors]
        end
    end
  end

  defp conflict_free(project, exclude) do
    conflicts =
      project
      |> conflicts()
      |> Map.keys()
      |> Enum.reject(fn conflict -> conflict in exclude end)

    case conflicts do
      [] -> :ok
      _list -> {:error, :conflicts}
    end
  end

  defp write?(%Source{path: path}, exclude), do: path not in exclude

  defp compile_globs!(str) when is_binary(str), do: GlobEx.compile!(str)

  defp compile_globs!(glob) when is_struct(glob, GlobEx), do: glob

  defimpl Enumerable do
    def count(project) do
      {:ok, map_size(project.sources)}
    end

    def member?(project, %Source{} = source) do
      {:ok, project.sources |> Map.values() |> Enum.member?(source)}
    end

    def member?(_project, _other) do
      {:ok, false}
    end

    def slice(project) do
      sources = project.sources |> Map.values() |> Enum.sort_by(fn source -> source.path end)
      length = length(sources)

      {:ok, length,
       fn
         _start, 0 -> []
         start, count when start + count == length -> Enum.drop(sources, start)
         start, count -> sources |> Enum.drop(start) |> Enum.take(count)
       end}
    end

    def reduce(project, acc, fun) do
      sources = Map.values(project.sources)
      Enumerable.List.reduce(sources, acc, fun)
    end
  end
end
