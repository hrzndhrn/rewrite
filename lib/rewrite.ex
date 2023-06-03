defmodule Rewrite do
  @moduledoc """
  `Rewrite` provides a struct that contains all resouces that could be handeld
  by `Rewrite`.
  """

  alias Rewrite.Source

  alias Rewrite.Error
  alias Rewrite.SourceError
  alias Rewrite.UpdateError

  defstruct sources: %{}, extensions: %{}

  @type t :: %Rewrite{sources: %{Path.t() => Source.t()}}
  @type input :: Path.t() | wildcard() | GlobEx.t()
  @type wildcard :: IO.chardata()
  @type opts :: keyword()

  @doc """
  Creates an empty project.

  ## Examples

      iex> Rewrite.new()
      %Rewrite{sources: %{}}
  """
  @spec new([module()]) :: t()
  def new(filetypes \\ [Source.Ex]) do
    %Rewrite{extensions: extensions(filetypes)}
  end

  defp extensions(modules) do
    modules
    |> Enum.flat_map(fn module ->
      IO.inspect(module)

      module.extensions()
      |> List.wrap()
      |> Enum.map(fn extension -> {extension, module} end)
    end)
    |> Map.new()
  end

  defp read_source!(path, extensions) when not is_nil(path) do
    ext = Path.extname(path)
    source = Map.get(extensions, ext, Source)

    source.read!(path)
  end

  @doc """
  Creates a `%Rewrite{}` from the given `inputs`.
  """
  @spec new!(input() | [input()], [module]) :: t()
  def new!(inputs, filetypes \\ [Source.Ex]) do
    extensions = extensions(filetypes)

    sources =
      inputs
      |> expand()
      |> Enum.reduce(%{}, fn path, sources ->
        source = read_source!(path, extensions)
        Map.put(sources, source.path, source)
      end)

    struct!(Rewrite, sources: sources, extensions: extensions)
  end

  @doc """
  Reads the given `input`/`inputs` and adds the source/sources to the `project`
  when not already readed.

  ## Options

  + `:force`, default: `false` - forces the reading of sources. With
    `force: true` updates and issues for an already existing source are deleted.
  """
  @spec read!(t(), input() | [input()], opts()) :: t()
  def read!(%Rewrite{} = rewrite, inputs, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    sources =
      inputs
      |> expand()
      |> Enum.reduce(rewrite.sources, fn path, sources ->
        if !force && Map.has_key?(sources, path) do
          sources
        else
          source = read_source!(path, rewrite.extensions)
          Map.put(sources, source.path, source)
        end
      end)

    %{rewrite | sources: sources}
  end

  @doc """
  Puts the given `source` to the `project`.

  Returns `{:ok, project}` if successful, `{:error, reason}` otherwise.

  ## Examples

      iex> project = Rewrite.new()
      iex> {:ok, project} = Rewrite.put(project, Source.from_string(":a", "a.exs"))
      iex> map_size(project.sources)
      1
      iex> Rewrite.put(project, Source.from_string(":b"))
      {:error, %Rewrite.Error{reason: :nopath}}
      iex> Rewrite.put(project, Source.from_string(":a", "a.exs"))
      {:error, %Rewrite.Error{reason: :overwrites, path: "a.exs"}}
  """
  @spec put(t(), Source.t()) :: {:ok, t()} | {:error, Error.t()}
  def put(%Rewrite{}, %Source{path: nil}), do: {:error, Error.exception(reason: :nopath)}

  def put(%Rewrite{sources: sources} = project, %Source{path: path} = source) do
    case Map.has_key?(sources, path) do
      true -> {:error, Error.exception(reason: :overwrites, path: path)}
      false -> {:ok, %{project | sources: Map.put(sources, path, source)}}
    end
  end

  @doc """
  Same as `put/2`, but raises a `Rewrite.Error` exception in case of
  failure.
  """
  @spec put!(t(), Source.t()) :: t()
  def put!(%Rewrite{} = project, %Source{} = source) do
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

      iex> {:ok, project} = Rewrite.from_sources([
      ...>   Source.from_string(":a", "a.exs"),
      ...>   Source.from_string(":b", "b.exs"),
      ...>   Source.from_string(":a", "c.exs")
      ...> ])
      iex> Rewrite.paths(project)
      ["a.exs", "b.exs", "c.exs"]
      iex> project = Rewrite.delete(project, "a.exs")
      iex> Rewrite.paths(project)
      ["b.exs", "c.exs"]
      iex> project = Rewrite.delete(project, "b.exs")
      iex> Rewrite.paths(project)
      ["c.exs"]
      iex> project = Rewrite.delete(project, "b.exs")
      iex> Rewrite.paths(project)
      ["c.exs"]
  """
  @spec delete(t(), Path.t()) :: t()
  def delete(%Rewrite{sources: sources} = project, path) when is_binary(path) do
    %{project | sources: Map.delete(sources, path)}
  end

  @doc """
  Drops the sources with the given `paths` from the `project`.

  The files for the dropped sources are not removed from disk.

  If `paths` contains paths that are not in `project`, they're simply ignored.

  ## Examples

      iex> {:ok, project} = Rewrite.from_sources([
      ...>   Source.from_string(":a", "a.exs"),
      ...>   Source.from_string(":b", "b.exs"),
      ...>   Source.from_string(":a", "c.exs")
      ...> ])
      iex> project = Rewrite.drop(project, ["a.exs", "b.exs", "z.exs"])
      iex> Rewrite.paths(project)
      ["c.exs"]
  """
  @spec drop(t(), [Path.t()]) :: t()
  def drop(%Rewrite{} = project, paths) when is_list(paths) do
    Enum.reduce(paths, project, fn source, project -> delete(project, source) end)
  end

  @doc """
  Tries to delete the `source` file and removes the `source` from the `project`.

  Returns `{:ok, project}` if successful, or `{:error, error}` if an error
  occurs.

  Note the file is deleted even if in read-only mode.
  """
  @spec rm(t(), Path.t()) ::
          {:ok, t()} | {:error, Error.t() | SourceError.t()}
  def rm(%Rewrite{} = project, path) when is_binary(path) do
    with {:ok, source} <- source(project, path),
         :ok <- Source.rm(source) do
      {:ok, delete(project, source.path)}
    end
  end

  @doc """
  Same as `source/2`, but raises a `Rewrite.Error` exception in case of
  failure.
  """
  @spec rm!(t(), Source.t() | Path.t()) :: t()
  def rm!(%Rewrite{} = project, source) when is_binary(source) or is_struct(source, Source) do
    case rm(project, source) do
      {:ok, project} -> project
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns a sorted list of all paths in the `project`.
  """
  @spec paths(t()) :: [Path.t()]
  def paths(%Rewrite{sources: sources}) do
    sources |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns `true` if any source in the `project` returns `true` for
  `Source.updated?/1`.

  ## Examples

      iex> {:ok, project} = Rewrite.from_sources([
      ...>   Source.from_string(":a", "a.exs"),
      ...>   Source.from_string(":b", "b.exs")
      ...> ])
      iex> Rewrite.updated?(project)
      false
      iex> project = Rewrite.update!(project, "a.exs", fn source ->
      ...>   Source.update(source, code: ":z")
      ...> end)
      iex> Rewrite.updated?(project)
      true
  """
  @spec updated?(t()) :: boolean()
  def updated?(%Rewrite{} = project) do
    project.sources |> Map.values() |> Enum.any?(fn source -> Source.updated?(source) end)
  end

  @doc ~S"""
  Creates a `%Rewrite{}` from the given sources.

  Returns `{:ok, project}` for a list of regular sources.

  Returns `{:error, error}` for sources with a missing path and/or duplicated
  paths.
  """
  @spec from_sources([Source.t()]) :: {:ok, Rewrite.t()} | {:error, Error.t()}
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
      {:ok, struct!(Rewrite, sources: sources)}
    else
      {:error,
       Error.exception(
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
  def sources(%Rewrite{sources: sources}) do
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
  @spec source(t(), Path.t()) :: {:ok, Source.t()} | {:error, Error.t()}
  def source(%Rewrite{sources: sources}, path) when is_binary(path) do
    with :error <- Map.fetch(sources, path) do
      {:error, Error.exception(reason: :nosource, path: path)}
    end
  end

  @doc """
  Same as `source/2`, but raises a `Rewrite.Error` exception in case of
  failure.
  """
  @spec source!(t(), Path.t()) :: Source.t()
  def source!(%Rewrite{} = project, path) do
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
          {:ok, t()} | {:error, Error.t()}
  def update(%Rewrite{}, %Source{path: nil}),
    do: {:error, Error.exception(reason: :nopath)}

  def update(%Rewrite{} = project, %Source{} = source) do
    update(project, source.path, source)
  end

  @doc """
  The same as `update/2` but raises a `Rewrite.Error` exception in case
  of an error.
  """
  @spec update!(t(), Source.t()) :: t()
  def update!(%Rewrite{} = project, %Source{} = source) do
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
      iex> {:ok, project} = Rewrite.from_sources([a, b])
      iex> {:ok, project} = Rewrite.update(project, "a.exs", Source.from_string(":foo", "a.exs"))
      iex> project |> Rewrite.source!("a.exs") |> Source.code()
      ":foo"
      iex> {:ok, project} = Rewrite.update(project, "a.exs", fn s -> Source.update(s, code: ":baz") end)
      iex> project |> Rewrite.source!("a.exs") |> Source.code()
      ":baz"
      iex> {:ok, project} = Rewrite.update(project, "a.exs", fn s -> Source.update(s, path: "c.exs") end)
      iex> Rewrite.paths(project)
      ["b.exs", "c.exs"]
      iex> Rewrite.update(project, "no.exs", Source.from_string(":foo", "x.exs"))
      {:error, %Rewrite.Error{reason: :nosource, path: "no.exs"}}
      iex> Rewrite.update(project, "c.exs", Source.from_string(":foo"))
      {:error, %Rewrite.UpdateError{reason: :nopath, source: "c.exs"}}
      iex> Rewrite.update(project, "c.exs", fn _ -> b end)
      {:error, %Rewrite.UpdateError{reason: :overwrites, path: "b.exs", source: "c.exs"}}
  """
  @spec update(t(), Path.t(), Source.t() | function()) ::
          {:ok, t()} | {:error, Error.t() | UpdateError.t()}
  def update(%Rewrite{}, path, %Source{path: nil}) when is_binary(path) do
    {:error, UpdateError.exception(reason: :nopath, source: path)}
  end

  def update(%Rewrite{} = project, path, %Source{} = source)
      when is_binary(path) do
    with {:ok, _stored} <- source(project, path) do
      do_update(project, path, source)
    end
  end

  def update(%Rewrite{} = project, path, fun) when is_binary(path) and is_function(fun, 1) do
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
            {:error, UpdateError.exception(reason: :overwrites, path: source.path, source: path)}

          false ->
            sources = project.sources |> Map.delete(path) |> Map.put(source.path, source)
            {:ok, %{project | sources: sources}}
        end
    end
  end

  defp apply_update!(source, fun) do
    case fun.(source) do
      %Source{path: nil} ->
        {:error, UpdateError.exception(reason: :nopath, source: source.path)}

      %Source{} = source ->
        {:ok, source}

      got ->
        raise RuntimeError, """
        expected %Source{} from anonymous function given to Rewrite.update/3, got: #{inspect(got)}\
        """
    end
  end

  @doc """
  The same as `update/3` but raises a `Rewrite.Error` exception in case
  of an error.
  """
  @spec update!(t(), Path.t(), Source.t() | function()) :: t()
  def update!(%Rewrite{} = project, path, new) when is_binary(path) do
    case update(project, path, new) do
      {:ok, project} -> project
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns `true` when the `%Rewrite{}` contains a `%Source{}` with the given
  `path`.

  ## Examples

      iex> {:ok, project} = Rewrite.from_sources([
      ...>   Source.from_string(":a", "a.exs")
      ...> ])
      iex> Rewrite.has_source?(project, "a.exs")
      true
      iex> Rewrite.has_source?(project, "b.exs")
      false
  """
  @spec has_source?(t(), Path.t()) :: boolean()
  def has_source?(%Rewrite{sources: sources}, path) when is_binary(path) do
    Map.has_key?(sources, path)
  end

  @doc """
  Returns `true` if any source has one or more issues.
  """
  @spec issues?(t) :: boolean
  def issues?(%Rewrite{sources: sources}) do
    sources
    |> Map.values()
    |> Enum.any?(fn %Source{issues: issues} -> not Enum.empty?(issues) end)
  end

  @doc """
  Counts the sources with the given `extname` in the `project`.
  """
  @spec count(t, String.t()) :: non_neg_integer
  def count(%Rewrite{sources: sources}, extname) do
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
  def map(%Rewrite{} = project, fun) when is_function(fun, 1) do
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
  def map!(%Rewrite{} = project, fun) when is_function(fun, 1) do
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
          {:ok, t()} | {:error, Error.t() | SourceError.t()}
  def write(project, path, force \\ nil)

  def write(%Rewrite{} = project, path, force) when is_binary(path) and force in [nil, :force] do
    with {:ok, source} <- source(project, path) do
      write(project, source, force)
    end
  end

  def write(%Rewrite{} = project, %Source{} = source, force) when force in [nil, :force] do
    with {:ok, source} <- Source.write(source) do
      {:ok, Rewrite.update!(project, source)}
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
  def write_all(%Rewrite{} = project, opts \\ []) do
    exclude = Keyword.get(opts, :exclude, [])
    force = if Keyword.get(opts, :force, false), do: :force, else: nil

    write_all(project, exclude, force)
  end

  defp write_all(%Rewrite{sources: sources} = project, exclude, force)
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
        {:ok, source} -> {Rewrite.update!(project, source), errors}
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
