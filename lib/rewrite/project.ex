defmodule Rewrite.Project do
  @moduledoc """
  The `%Project{}` contains all `%Rewrite.Sources{}` of a project.
  """

  alias Rewrite.Project
  alias Rewrite.ProjectError
  alias Rewrite.ProjectUpdateError
  alias Rewrite.Source
  alias Rewrite.SourceError

  defstruct sources: %{}

  @type t :: %Project{sources: %{Path.t() => Source.t()}}
  @type input :: Path.t() | wildcard() | GlobEx.t()
  @type wildcard :: IO.chardata()
  @type opts :: keyword()

  @doc """
  Creates an empty project.

  ## Examples

      iex> Project.new()
      %Project{sources: %{}}
  """
  @spec new :: t()
  def new, do: %Project{}

  @doc """
  Creates a `%Project{}` from the given `inputs`.
  """
  @spec read!(input() | [input()]) :: t()
  def read!(inputs) do
    sources =
      inputs
      |> expand()
      |> Enum.reduce(%{}, fn path, sources ->
        source = Source.read!(path)
        Map.put(sources, source.path, source)
      end)

    struct!(Project, sources: sources)
  end

  @doc """
  Reads the given `input`/`inputs` and adds the source/sources to the `project`
  when not already readed.

  ## Options

  + `:force`, default: `false` - forces the reading of sources. With
    `force: true` updates and issues for an already existing source are deleted.
  """
  @spec read!(t(), input() | [input()], opts()) :: t()
  def read!(%Project{sources: sources} = project, inputs, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    sources =
      inputs
      |> expand()
      |> Enum.reduce(sources, fn path, sources ->
        if !force && Map.has_key?(sources, path) do
          sources
        else
          source = Source.read!(path)
          Map.put(sources, source.path, source)
        end
      end)

    %{project | sources: sources}
  end

  @doc """
  Puts the given `source` to the `project`.

  Returns `{:ok, project}` if successful, `{:error, reason}` otherwise.

  ## Examples

      iex> project = Project.new()
      iex> {:ok, project} = Project.put(project, Source.from_string(":a", "a.exs"))
      iex> map_size(project.sources)
      1
      iex> Project.put(project, Source.from_string(":b"))
      {:error, %ProjectError{reason: :nopath}}
      iex> Project.put(project, Source.from_string(":a", "a.exs"))
      {:error, %ProjectError{reason: :overwrites, path: "a.exs"}}
  """
  @spec put(t(), Source.t()) :: {:ok, t()} | {:error, ProjectError.t()}
  def put(%Project{}, %Source{path: nil}), do: {:error, ProjectError.exception(reason: :nopath)}

  def put(%Project{sources: sources} = project, %Source{path: path} = source) do
    case Map.has_key?(sources, path) do
      true -> {:error, ProjectError.exception(reason: :overwrites, path: path)}
      false -> {:ok, %{project | sources: Map.put(sources, path, source)}}
    end
  end

  @doc """
  Same as `put/2`, but raises a `Rewrite.ProjectError` exception in case of
  failure.
  """
  @spec put!(t(), Source.t()) :: t()
  def put!(%Project{} = project, %Source{} = source) do
    case put(project, source) do
      {:ok, project} -> project
      {:error, error} -> raise error
    end
  end

  @doc """
  Deletes the source for the given `path` from the `project`. The file on disk
  is not removed.

  If the source is not part of the `project` the unchanged `project` is
  returned.

  ## Examples

      iex> {:ok, project} = Project.from_sources([
      ...>   Source.from_string(":a", "a.exs"),
      ...>   Source.from_string(":b", "b.exs"),
      ...>   Source.from_string(":a", "c.exs")
      ...> ])
      iex> Project.paths(project)
      ["a.exs", "b.exs", "c.exs"]
      iex> project = Project.delete(project, "a.exs")
      iex> Project.paths(project)
      ["b.exs", "c.exs"]
      iex> project = Project.delete(project, "b.exs")
      iex> Project.paths(project)
      ["c.exs"]
      iex> project = Project.delete(project, "b.exs")
      iex> Project.paths(project)
      ["c.exs"]
  """
  @spec delete(t(), Path.t()) :: t()
  def delete(%Project{sources: sources} = project, path) when is_binary(path) do
    %{project | sources: Map.delete(sources, path)}
  end

  @doc """
  Drops the sources with the given `paths` from the `project`.

  The files for the dropped sources are not removed from disk.

  If `paths` contains paths that are not in `project`, they're simply ignored.

  ## Examples

      iex> {:ok, project} = Project.from_sources([
      ...>   Source.from_string(":a", "a.exs"),
      ...>   Source.from_string(":b", "b.exs"),
      ...>   Source.from_string(":a", "c.exs")
      ...> ])
      iex> project = Project.drop(project, ["a.exs", "b.exs", "z.exs"])
      iex> Project.paths(project)
      ["c.exs"]
  """
  @spec drop(t(), [Path.t()]) :: t()
  def drop(%Project{} = project, paths) when is_list(paths) do
    Enum.reduce(paths, project, fn source, project -> delete(project, source) end)
  end

  @doc """
  Tries to delete the `source` file and removes the `source` from the `project`.

  Returns `{:ok, project}` if successful, or `{:error, error}` if an error
  occurs.

  Note the file is deleted even if in read-only mode.
  """
  @spec rm(t(), Path.t()) ::
          {:ok, t()} | {:error, ProjectError.t() | SourceError.t()}
  def rm(%Project{} = project, path) when is_binary(path) do
    with {:ok, source} <- source(project, path),
         :ok <- Source.rm(source) do
      {:ok, delete(project, source.path)}
    end
  end

  @doc """
  Same as `source/2`, but raises a `Rewrite.ProjectError` exception in case of
  failure.
  """
  @spec rm!(t(), Source.t() | Path.t()) :: t()
  def rm!(%Project{} = project, source) when is_binary(source) or is_struct(source, Source) do
    case rm(project, source) do
      {:ok, project} -> project
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns a sorted list of all paths in the `project`.
  """
  @spec paths(t()) :: [Path.t()]
  def paths(%Project{sources: sources}) do
    sources |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns `true` if any source in the `project` returns `true` for
  `Source.updated?/1`.

  ## Examples

      iex> {:ok, project} = Project.from_sources([
      ...>   Source.from_string(":a", "a.exs"),
      ...>   Source.from_string(":b", "b.exs")
      ...> ])
      iex> Project.updated?(project)
      false
      iex> project = Project.update!(project, "a.exs", fn source ->
      ...>   Source.update(source, code: ":z")
      ...> end)
      iex> Project.updated?(project)
      true
  """
  @spec updated?(t()) :: boolean()
  def updated?(%Project{} = project) do
    project.sources |> Map.values() |> Enum.any?(fn source -> Source.updated?(source) end)
  end

  @doc ~S"""
  Creates a `%Project{}` from the given sources.

  Returns `{:ok, project}` for a list of regular sources.

  Returns `{:error, error}` for sources with a missing path and/or duplicated
  paths.
  """
  @spec from_sources([Source.t()]) :: {:ok, Project.t()} | {:error, ProjectError.t()}
  def from_sources(sources) when is_list(sources) do
    {sources, missing, duplicated} =
      Enum.reduce(sources, {%{}, [], []}, fn %Source{} = source, {sources, missing, duplicated} ->
        cond do
          is_nil(source.path) ->
            {sources, [source | missing], duplicated}

          Map.has_key?(sources, source.path) ->
            {sources, missing, [source | duplicated]}

          true ->
            {Map.put(sources, source.path, source), missing, duplicated}
        end
      end)

    if Enum.empty?(missing) && Enum.empty?(duplicated) do
      {:ok, struct!(Project, sources: sources)}
    else
      {:error,
       ProjectError.exception(
         reason: :invalid_sources,
         missing_paths: missing,
         duplicated_paths: duplicated
       )}
    end
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

  @doc """
  Returns the `%Rewrite.Source{}` for the given `path`.

  Returns an `:ok` tuple with the found source, if not exactly one source is
  available an `:error` is returned.

  See also `sources/2` to get a list of sources for a given `path`.
  """
  @spec source(t(), Path.t()) :: {:ok, Source.t()} | {:error, ProjectError.t()}
  def source(%Project{sources: sources}, path) when is_binary(path) do
    with :error <- Map.fetch(sources, path) do
      {:error, ProjectError.exception(reason: :nosource, path: path)}
    end
  end

  @doc """
  Same as `source/2`, but raises a `Rewrite.ProjectError` exception in case of
  failure.
  """
  @spec source!(t(), Path.t()) :: Source.t()
  def source!(%Project{} = project, path) do
    case source(project, path) do
      {:ok, source} -> source
      {:error, error} -> raise error
    end
  end

  @doc """
  Updates the given `source` in the `project`.

  This function will be usually used if the `path` for the `source` has not
  changed.

  Returns `{:ok, project}` if successful, `{:error, error}` otherwise.
  """
  @spec update(t(), Source.t()) ::
          {:ok, t()} | {:error, ProjectError.t()}
  def update(%Project{}, %Source{path: nil}),
    do: {:error, ProjectError.exception(reason: :nopath)}

  def update(%Project{} = project, %Source{} = source) do
    update(project, source.path, source)
  end

  @doc """
  The same as `update/2` but raises a `Rewrite.ProjectError` exception in case
  of an error.
  """
  @spec update!(t(), Source.t()) :: t()
  def update!(%Project{} = project, %Source{} = source) do
    case update(project, source) do
      {:ok, project} -> project
      {:error, error} -> raise error
    end
  end

  @doc """
  Updates a source for the given `path` in the `project`.

  If `source` a `Rewrite.Source` struct the struct is used to update the
  `project`.

  If `source` a function the source for the given `path` is passed to the
  function and the result is used to update the `project`.

  Returns `{:ok, project}` if the update was successful, `{:error, error}`
  otherwise.

  ## Examples

      iex> a = Source.from_string(":a", "a.exs")
      iex> b = Source.from_string(":b", "b.exs")
      iex> {:ok, project} = Project.from_sources([a, b])
      iex> {:ok, project} = Project.update(project, "a.exs", Source.from_string(":foo", "a.exs"))
      iex> project |> Project.source!("a.exs") |> Source.code()
      ":foo"
      iex> {:ok, project} = Project.update(project, "a.exs", fn s -> Source.update(s, code: ":baz") end)
      iex> project |> Project.source!("a.exs") |> Source.code()
      ":baz"
      iex> {:ok, project} = Project.update(project, "a.exs", fn s -> Source.update(s, path: "c.exs") end)
      iex> Project.paths(project)
      ["b.exs", "c.exs"]
      iex> Project.update(project, "no.exs", Source.from_string(":foo", "x.exs"))
      {:error, %ProjectError{reason: :nosource, path: "no.exs"}}
      iex> Project.update(project, "c.exs", Source.from_string(":foo"))
      {:error, %ProjectUpdateError{reason: :nopath, source: "c.exs"}}
      iex> Project.update(project, "c.exs", fn _ -> b end)
      {:error, %ProjectUpdateError{reason: :overwrites, path: "b.exs", source: "c.exs"}}
  """
  @spec update(t(), Path.t(), Source.t() | function()) ::
          {:ok, t()} | {:error, ProjectError.t() | ProjectUpdateError.t()}
  def update(%Project{}, path, %Source{path: nil}) when is_binary(path) do
    {:error, ProjectUpdateError.exception(reason: :nopath, source: path)}
  end

  def update(%Project{} = project, path, %Source{} = source)
      when is_binary(path) do
    with {:ok, _stored} <- source(project, path) do
      do_update(project, path, source)
    end
  end

  def update(%Project{} = project, path, fun) when is_binary(path) and is_function(fun, 1) do
    with {:ok, stored} <- source(project, path),
         {:ok, source} <- apply_update!(stored, fun) do
      do_update(project, path, source)
    end
  end

  defp do_update(project, path, source) do
    case path == source.path do
      true ->
        {:ok, %{project | sources: Map.put(project.sources, path, source)}}

      false ->
        case Map.has_key?(project.sources, source.path) do
          true ->
            {:error,
             ProjectUpdateError.exception(reason: :overwrites, path: source.path, source: path)}

          false ->
            sources = project.sources |> Map.delete(path) |> Map.put(source.path, source)
            {:ok, %{project | sources: sources}}
        end
    end
  end

  defp apply_update!(source, fun) do
    case fun.(source) do
      %Source{path: nil} ->
        {:error, ProjectUpdateError.exception(reason: :nopath, source: source.path)}

      %Source{} = source ->
        {:ok, source}

      got ->
        raise RuntimeError, """
        expected %Source{} from anonymous function given to Project.update/3, got: #{inspect(got)}\
        """
    end
  end

  @doc """
  The same as `update/3` but raises a `Rewrite.ProjectError` exception in case
  of an error.
  """
  @spec update!(t(), Path.t(), Source.t() | function()) :: t()
  def update!(%Project{} = project, path, new) when is_binary(path) do
    case update(project, path, new) do
      {:ok, project} -> project
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns `true` when the `%Project{}` contains a `%Source{}` with the given
  `path`.

  ## Examples

      iex> {:ok, project} = Project.from_sources([
      ...>   Source.from_string(":a", "a.exs")
      ...> ])
      iex> Project.has_source?(project, "a.exs")
      true
      iex> Project.has_source?(project, "b.exs")
      false
  """
  @spec has_source?(t(), Path.t()) :: boolean()
  def has_source?(%Project{sources: sources}, path) when is_binary(path) do
    Map.has_key?(sources, path)
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
  Counts the sources with the given `extname` in the `project`.
  """
  @spec count(t, String.t()) :: non_neg_integer
  def count(%Project{sources: sources}, extname) do
    sources
    |> Map.keys()
    |> Enum.count(fn path -> Path.extname(path) == extname end)
  end

  @doc """
  Invokes `fun` for each `source` in the `project` and updates the `project`
  with the result of `fun`.

  Returns a `{:ok, project}` if any update is successful.

  Returns `{:error, errors, project}` where `project` is updated for all sources
  that are updated successful. The `errors` are the `errors` of `update/3`.
  """
  @spec map(t(), (Source.t() -> Source.t())) ::
          {:ok, t()} | {:error, [{:nosource | :overwrites | :nopath, Source.t()}]}
  def map(%Project{} = project, fun) when is_function(fun, 1) do
    {project, errors} =
      Enum.reduce(project, {project, []}, fn source, {project, errors} ->
        with {:ok, updated} <- apply_update!(source, fun),
             {:ok, project} <- do_update(project, source.path, updated) do
          {project, errors}
        else
          {:error, error} -> {project, [error | errors]}
        end
      end)

    if Enum.empty?(errors) do
      {:ok, project}
    else
      {:error, errors, project}
    end
  end

  @doc """
  Return a `project` where each `source` is the result of invoking `fun` on
  each `source` of the given `project`.
  """
  @spec map!(t(), (Source.t() -> Source.t())) :: t()
  def map!(%Project{} = project, fun) when is_function(fun, 1) do
    Enum.reduce(project, project, fn source, project ->
      with {:ok, updated} <- apply_update!(source, fun),
           {:ok, project} <- do_update(project, source.path, updated) do
        project
      else
        {:error, error} -> raise error
      end
    end)
  end

  @doc """
  Writes a source to disk.

  The function expects a path or a `%Source{}` as first argument.

  Returns `{:ok, project}` if the file was written successful. See also
  `Source.write/2`.

  If the given `source` is not part of the `project` then it is added.
  """
  @spec write(t(), Path.t() | Source.t(), nil | :force) ::
          {:ok, t()} | {:error, ProjectError.t() | SourceError.t()}
  def write(project, path, force \\ nil)

  def write(%Project{} = project, path, force) when is_binary(path) and force in [nil, :force] do
    with {:ok, source} <- source(project, path) do
      write(project, source, force)
    end
  end

  def write(%Project{} = project, %Source{} = source, force) when force in [nil, :force] do
    with {:ok, source} <- Source.write(source) do
      {:ok, Project.update!(project, source)}
    end
  end

  @doc """
  Writes all sources in the `project` to disk.

  This function calls `Rewrite.Source.write/1` on all sources in the `project`.

  Returns `{:ok, project}` if all sources are written successful.

  Returns `{:error, reasons, project}` where project is updated for all sources
  that are written successful. The reasons is a keyword list with the keys
  `File.posix()` or `:changed` and the affected path as value. The key
  `:changed` indicates a file that was changed sind reading.

  ## Options

  + `exclude` - a list paths to exclude form writting.
  + `foece`, default: `false` - forces the writting of changed files.
  """
  @spec write_all(t(), opts()) ::
          {:ok, t()} | {:error, [SourceError.t()], t()}
  def write_all(%Project{} = project, opts \\ []) do
    exclude = Keyword.get(opts, :exclude, [])
    force = if Keyword.get(opts, :force, false), do: :force, else: nil

    write_all(project, exclude, force)
  end

  defp write_all(%Project{sources: sources} = project, exclude, force)
       when force in [nil, :force] do
    {project, errors} =
      sources
      |> Map.values()
      |> Enum.reduce({project, []}, fn source, acc ->
        do_write_all(source, exclude, force, acc)
      end)

    if Enum.empty?(errors), do: {:ok, project}, else: {:error, errors, project}
  end

  defp do_write_all(source, exclude, force, {project, errors}) do
    if source.path in exclude do
      {project, errors}
    else
      case Source.write(source, force: force) do
        {:ok, source} -> {Project.update!(project, source), errors}
        {:error, error} -> {project, [error | errors]}
      end
    end
  end

  defp expand(inputs) do
    inputs
    |> List.wrap()
    |> Enum.map(&compile_globs!/1)
    |> Enum.flat_map(&GlobEx.ls/1)
  end

  defp compile_globs!(str) when is_binary(str), do: GlobEx.compile!(str)

  defp compile_globs!(glob) when is_struct(glob, GlobEx), do: glob

  defimpl Enumerable do
    def count(project) do
      {:ok, map_size(project.sources)}
    end

    def member?(project, %Source{} = source) do
      member? = Map.get(project.sources, source.path) == source
      {:ok, member?}
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
