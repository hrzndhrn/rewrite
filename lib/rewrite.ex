defmodule Rewrite do
  @moduledoc """
  `Rewrite` provides a struct that contains all resources that could be handeld
  by `Rewrite`.
  """

  alias Rewrite.Source

  alias Rewrite.DotFormatter
  alias Rewrite.Error
  alias Rewrite.KeyValueStore
  alias Rewrite.SourceError
  alias Rewrite.UpdateError

  defstruct [:id, sources: %{}, extensions: %{}]

  @type t :: %Rewrite{sources: %{Path.t() => Source.t()}}
  @type input :: Path.t() | wildcard() | GlobEx.t()
  @type wildcard :: IO.chardata()
  @type opts :: keyword()

  @doc """
  Creates an empty project.

  ## Options

    * `:filetypes` - a list of modules implementing the behavior 
      `Rewrite.Filetye`. This list is used to add the `filetype` to the 
      `sources` of the corresponding files. The list can contain modules 
      representing a file type or a tuple of `{module(), keyword()}`. Rewrite 
      uses the keyword list from the tuple as the options argument when a file
      is read.

      Defaults to `[Rewrite.Source, Rewrite.Source.Ex]`.

    * `:dot_formatter` - a `%DotFormatter{}` that is used to format sources.
      To get and update a dot formatter see `dot_formatter/2` and to create one
      see `Rewrite.DotFormatter`.

  ## Examples

      iex> project = Rewrite.new()
      iex> path = "test/fixtures/source/hello.txt"
      iex> project = Rewrite.read!(project, path)
      iex> project |> Rewrite.source!(path) |> Source.get(:content)
      "hello\\n"
      iex> project |> Rewrite.source!(path) |> Source.owner()
      Rewrite

      iex> project = Rewrite.new(filetypes: [{Rewrite.Source, owner: MyApp}])
      iex> path = "test/fixtures/source/hello.txt"
      iex> project = Rewrite.read!(project, path)
      iex> project |> Rewrite.source!(path) |> Source.owner()
      MyApp
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    extensions = Keyword.get(opts, :filetypes, [Source, Source.Ex])
    rewrite = %Rewrite{id: System.unique_integer([:positive]), extensions: extensions(extensions)}
    dot_formatter(rewrite, Keyword.get(opts, :dot_formatter))
  end

  @doc """
  Creates a `%Rewrite{}` from the given `inputs`.

  Accepts the same options as `new/1`.
  """
  @spec new!(input() | [input()], opts) :: t()
  def new!(inputs, opts \\ []) do
    opts |> new() |> read!(inputs)
  end

  @doc """
  Reads the given `input`/`inputs` and adds the source/sources to the `project`
  when not already readed.

  ## Options

    * `:force`, default: `false` - forces the reading of sources. With
      `force: true` updates and issues for an already existing source are 
      deleted.
  """
  @spec read!(t(), input() | [input()], opts()) :: t()
  def read!(%Rewrite{} = rewrite, inputs, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    reader = rewrite.sources |> Map.keys() |> reader(rewrite.extensions, force)

    inputs = expand(inputs)

    sources =
      Rewrite.TaskSupervisor
      |> Task.Supervisor.async_stream_nolink(inputs, reader)
      |> Enum.reduce(rewrite.sources, fn
        {:ok, nil}, sources ->
          sources

        {:ok, {path, source}}, sources ->
          Map.put(sources, path, %{source | rewrite_id: rewrite.id})

        {:exit, {error, _stacktrace}}, _sources when is_exception(error) ->
          raise error
      end)

    %{rewrite | sources: sources}
  end

  defp reader(paths, extensions, force) do
    fn path ->
      Logger.disable(self())

      if File.dir?(path) || (!force && path in paths) do
        nil
      else
        source = read_source!(path, extensions)
        {path, source}
      end
    end
  end

  defp read_source!(path, extensions) when not is_nil(path) do
    {source, opts} = extension_for_file(extensions, path)

    source.read!(path, opts)
  end

  @doc """
  Returns the extension of the given `file`.
  """
  @spec extension_for_file(t() | map(), Path.t()) :: {module(), opts()}
  def extension_for_file(%Rewrite{extensions: extensions}, path) do
    extension_for_file(extensions, path)
  end

  def extension_for_file(extensions, path) do
    ext = Path.extname(path)
    default = Map.fetch!(extensions, "default")

    case Map.get(extensions, ext, default) do
      {module, opts} -> {module, opts}
      module -> {module, []}
    end
  end

  @doc """
  Puts the given `source` to the given `rewrite` project.

  Returns `{:ok, rewrite}` if successful, `{:error, reason}` otherwise.

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

  def put(%Rewrite{sources: sources} = rewrite, %Source{path: path} = source) do
    case Map.has_key?(sources, path) do
      true ->
        {:error, Error.exception(reason: :overwrites, path: path)}

      false ->
        source = %{source | rewrite_id: rewrite.id}
        {:ok, %{rewrite | sources: Map.put(sources, path, source)}}
    end
  end

  @doc """
  Same as `put/2`, but raises a `Rewrite.Error` exception in case of failure.
  """
  @spec put!(t(), Source.t()) :: t()
  def put!(%Rewrite{} = rewrite, %Source{} = source) do
    case put(rewrite, source) do
      {:ok, rewrite} -> rewrite
      {:error, error} -> raise error
    end
  end

  @doc """
  Deletes the source for the given `path` from the `rewrite`. The file on disk
  is not removed.

  If the source is not part of the `rewrite` project the unchanged `rewrite` is
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
  def delete(%Rewrite{sources: sources} = rewrite, path) when is_binary(path) do
    %{rewrite | sources: Map.delete(sources, path)}
  end

  @doc """
  Drops the sources with the given `paths` from the `rewrite` project.

  The files for the dropped sources are not removed from disk.

  If `paths` contains paths that are not in `rewrite`, they're simply ignored.

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
  def drop(%Rewrite{} = rewrite, paths) when is_list(paths) do
    Enum.reduce(paths, rewrite, fn source, rewrite -> delete(rewrite, source) end)
  end

  @doc """
  Tries to delete the `source` file and removes the `source` from the `rewrite`
  project.

  Returns `{:ok, rewrite}` if successful, or `{:error, error}` if an error
  occurs.

  Note the file is deleted even if in read-only mode.
  """
  @spec rm(t(), Path.t()) ::
          {:ok, t()} | {:error, Error.t() | SourceError.t()}
  def rm(%Rewrite{} = rewrite, path) when is_binary(path) do
    with {:ok, source} <- source(rewrite, path),
         :ok <- Source.rm(source) do
      {:ok, delete(rewrite, source.path)}
    end
  end

  @doc """
  Same as `source/2`, but raises a `Rewrite.Error` exception in case of failure.
  """
  @spec rm!(t(), Source.t() | Path.t()) :: t()
  def rm!(%Rewrite{} = rewrite, source) when is_binary(source) or is_struct(source, Source) do
    case rm(rewrite, source) do
      {:ok, rewrite} -> rewrite
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns a sorted list of all paths in the `rewrite` project.
  """
  @spec paths(t()) :: [Path.t()]
  def paths(%Rewrite{sources: sources}) do
    sources |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns `true` if any source in the `rewrite` project returns `true` for
  `Source.updated?/1`.

  ## Examples

      iex> {:ok, project} = Rewrite.from_sources([
      ...>   Source.Ex.from_string(":a", "a.exs"),
      ...>   Source.Ex.from_string(":b", "b.exs"),
      ...>   Source.Ex.from_string("c", "c.txt")
      ...> ])
      iex> Rewrite.updated?(project)
      false
      iex> project = Rewrite.update!(project, "a.exs", fn source ->
      ...>   Source.update(source, :quoted, ":z")
      ...> end)
      iex> Rewrite.updated?(project)
      true
  """
  @spec updated?(t()) :: boolean()
  def updated?(%Rewrite{} = rewrite) do
    rewrite.sources |> Map.values() |> Enum.any?(fn source -> Source.updated?(source) end)
  end

  @doc ~S"""
  Creates a `%Rewrite{}` from the given sources.

  Returns `{:ok, rewrite}` for a list of regular sources.

  Returns `{:error, error}` for sources with a missing path and/or duplicated
  paths.
  """
  @spec from_sources([Source.t()], [module()]) :: {:ok, t()} | {:error, Error.t()}
  def from_sources(sources, filetypes \\ [Source.Ex]) when is_list(sources) do
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
      {:ok, struct!(Rewrite, sources: sources, extensions: extensions(filetypes))}
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
  Same as `from_sources/2`, but raises a `Rewrite.Error` exception in case of
  failure.
  """
  @spec from_sources!([Source.t()], [module()]) :: t()
  def from_sources!(sources, filetypes \\ [Source.Ex]) when is_list(sources) do
    case from_sources(sources, filetypes) do
      {:ok, rewrite} -> rewrite
      {:error, error} -> raise error
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
  def source!(%Rewrite{} = rewrite, path) do
    case source(rewrite, path) do
      {:ok, source} -> source
      {:error, error} -> raise error
    end
  end

  @doc """
  Updates the given `source` in the `rewrite` project.

  This function will be usually used if the `path` for the `source` has not
  changed.

  Returns `{:ok, rewrite}` if successful, `{:error, error}` otherwise.
  """
  @spec update(t(), Source.t()) ::
          {:ok, t()} | {:error, Error.t()}
  def update(%Rewrite{}, %Source{path: nil}),
    do: {:error, Error.exception(reason: :nopath)}

  def update(%Rewrite{} = rewrite, %Source{} = source) do
    update(rewrite, source.path, source)
  end

  @doc """
  The same as `update/2` but raises a `Rewrite.Error` exception in case
  of an error.
  """
  @spec update!(t(), Source.t()) :: t()
  def update!(%Rewrite{} = rewrite, %Source{} = source) do
    case update(rewrite, source) do
      {:ok, rewrite} -> rewrite
      {:error, error} -> raise error
    end
  end

  @doc """
  Updates a source for the given `path` in the `rewrite` project.

  If `source` a `Rewrite.Source` struct the struct is used to update the
  `rewrite` project.

  If `source` a function the source for the given `path` is passed to the
  function and the result is used to update the `rewrite` project.

  Returns `{:ok, rewrite}` if the update was successful, `{:error, error}`
  otherwise.

  ## Examples

      iex> a = Source.Ex.from_string(":a", "a.exs")
      iex> b = Source.Ex.from_string(":b", "b.exs")
      iex> {:ok, project} = Rewrite.from_sources([a, b])
      iex> {:ok, project} = Rewrite.update(project, "a.exs", Source.Ex.from_string(":foo", "a.exs"))
      iex> project |> Rewrite.source!("a.exs") |> Source.get(:content)
      ":foo"
      iex> {:ok, project} = Rewrite.update(project, "a.exs", fn s -> Source.update(s, :content, ":baz") end)
      iex> project |> Rewrite.source!("a.exs") |> Source.get(:content)
      ":baz"
      iex> {:ok, project} = Rewrite.update(project, "a.exs", fn s -> Source.update(s, :path, "c.exs") end)
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

  def update(%Rewrite{} = rewrite, path, %Source{} = source)
      when is_binary(path) do
    with {:ok, _stored} <- source(rewrite, path) do
      do_update(rewrite, path, source)
    end
  end

  def update(%Rewrite{} = rewrite, path, fun) when is_binary(path) and is_function(fun, 1) do
    with {:ok, stored} <- source(rewrite, path),
         {:ok, source} <- apply_update!(stored, fun) do
      do_update(rewrite, path, source)
    end
  end

  defp do_update(rewrite, path, source) do
    case path == source.path do
      true ->
        {:ok, %{rewrite | sources: Map.put(rewrite.sources, path, source)}}

      false ->
        case Map.has_key?(rewrite.sources, source.path) do
          true ->
            {:error, UpdateError.exception(reason: :overwrites, path: source.path, source: path)}

          false ->
            sources = rewrite.sources |> Map.delete(path) |> Map.put(source.path, source)
            {:ok, %{rewrite | sources: sources}}
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
  def update!(%Rewrite{} = rewrite, path, new) when is_binary(path) do
    case update(rewrite, path, new) do
      {:ok, rewrite} -> rewrite
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
  Counts the sources with the given `extname` in the `rewrite` project.
  """
  @spec count(t, String.t()) :: non_neg_integer
  def count(%Rewrite{sources: sources}, extname) when is_binary(extname) do
    sources
    |> Map.keys()
    |> Enum.count(fn path -> Path.extname(path) == extname end)
  end

  @doc """
  Invokes `fun` for each `source` in the `rewrite` project and updates the
  `rewirte` project with the result of `fun`.

  Returns a `{:ok, rewrite}` if any update is successful.

  Returns `{:error, errors, rewrite}` where `rewrite` is updated for all sources
  that are updated successful. The `errors` are the `errors` of `update/3`.
  """
  @spec map(t(), (Source.t() -> Source.t())) ::
          {:ok, t()} | {:error, [{:nosource | :overwrites | :nopath, Source.t()}]}
  def map(%Rewrite{} = rewrite, fun) when is_function(fun, 1) do
    {rewrite, errors} =
      Enum.reduce(rewrite, {rewrite, []}, fn source, {rewrite, errors} ->
        with {:ok, updated} <- apply_update!(source, fun),
             {:ok, rewrite} <- do_update(rewrite, source.path, updated) do
          {rewrite, errors}
        else
          {:error, error} -> {rewrite, [error | errors]}
        end
      end)

    if Enum.empty?(errors) do
      {:ok, rewrite}
    else
      {:error, errors, rewrite}
    end
  end

  @doc """
  Return a `rewrite` project where each `source` is the result of invoking
  `fun` on each `source` of the given `rewrite` project.
  """
  @spec map!(t(), (Source.t() -> Source.t())) :: t()
  def map!(%Rewrite{} = rewrite, fun) when is_function(fun, 1) do
    Enum.reduce(rewrite, rewrite, fn source, rewrite ->
      with {:ok, updated} <- apply_update!(source, fun),
           {:ok, rewrite} <- do_update(rewrite, source.path, updated) do
        rewrite
      else
        {:error, error} -> raise error
      end
    end)
  end

  @doc """
  Writes a source to disk.

  The function expects a path or a `%Source{}` as first argument.

  Returns `{:ok, rewrite}` if the file was written successful. See also
  `Source.write/2`.

  If the given `source` is not part of the `rewrite` project then it is added.
  """
  @spec write(t(), Path.t() | Source.t(), nil | :force) ::
          {:ok, t()} | {:error, Error.t() | SourceError.t()}
  def write(rewrite, path, force \\ nil)

  def write(%Rewrite{} = rewrite, path, force) when is_binary(path) and force in [nil, :force] do
    with {:ok, source} <- source(rewrite, path) do
      write(rewrite, source, force)
    end
  end

  def write(%Rewrite{} = rewrite, %Source{} = source, force) when force in [nil, :force] do
    with {:ok, source} <- Source.write(source) do
      {:ok, Rewrite.update!(rewrite, source)}
    end
  end

  @doc """
  Writes all sources in the `rewrite` project to disk.

  This function calls `Rewrite.Source.write/1` on all sources in the `rewrite`
  project.

  Returns `{:ok, rewrite}` if all sources are written successfully.

  Returns `{:error, reasons, rewrite}` where `rewrite` is updated for all 
  sources that are written successfully.

  ## Options

  + `exclude` - a list paths to exclude form writting.
  + `force`, default: `false` - forces the writting of unchanged files.
  """
  @spec write_all(t(), opts()) ::
          {:ok, t()} | {:error, [SourceError.t()], t()}
  def write_all(%Rewrite{} = rewrite, opts \\ []) do
    exclude = Keyword.get(opts, :exclude, [])
    force = if Keyword.get(opts, :force, false), do: :force, else: nil

    write_all(rewrite, exclude, force)
  end

  defp write_all(%Rewrite{sources: sources} = rewrite, exclude, force)
       when force in [nil, :force] do
    sources = for {path, source} <- sources, path not in exclude, do: source
    writer = fn source -> Source.write(source, force: force) end

    {rewrite, errors} =
      Rewrite.TaskSupervisor
      |> Task.Supervisor.async_stream_nolink(sources, writer)
      |> Enum.reduce({rewrite, []}, fn {:ok, result}, {rewrite, errors} ->
        case result do
          {:ok, source} -> {Rewrite.update!(rewrite, source), errors}
          {:error, error} -> {rewrite, [error | errors]}
        end
      end)

    if Enum.empty?(errors), do: {:ok, rewrite}, else: {:error, errors, rewrite}
  end

  @doc """
  Formats the given `rewrite` project with the given `dot_formatter`.

  If no `dot_formatter` is given, the `%DotFormatter{}` from 
  `dot_formatter(rewrite)` is used.

  The options are the same as for `DotFormatter.read/2`.
  """
  @spec format(t(), DotFormatter.t() | keyword() | nil, keyword()) :: {:ok, t()}
  def format(rewrite, dot_formatter \\ nil, opts \\ [])

  def format(%Rewrite{} = rewrite, nil, [] = opts) do
    dot_formatter = dot_formatter(rewrite)
    format(rewrite, dot_formatter, opts)
  end

  def format(%Rewrite{} = rewrite, [_ | _] = opts, _opts) do
    dot_formatter = dot_formatter(rewrite)
    format(rewrite, dot_formatter, opts)
  end

  def format(%Rewrite{} = rewrite, dot_formatter, opts) do
    DotFormatter.format_rewrite(dot_formatter, rewrite, opts)
  end

  @doc """
  Formats a source in a `rewrite` project with the given `dot_formatter`.

  The options are the same as for `Code.format_string!/2`.
  """
  @spec format_source(t(), DotFormatter.t(), String.t(), keyword()) :: {:ok, t()}
  def format_source(%Rewrite{} = rewrite, %DotFormatter{} = dot_formatter, file, opts \\ []) do
    DotFormatter.format_source(dot_formatter, rewrite, file, opts)
  end

  @doc """
  Returns the `DotFormatter` for the given `rewrite` project.

  When no formatter is set, the default formatter from 
  `Rewrite.DotFormatter.new/0` is returned. A dot formatter can be set with
  `dot_formatter/2`.
  """
  @spec dot_formatter(t() | id) :: DotFormatter.t() when id: integer()
  def dot_formatter(rewrite) when is_struct(rewrite, Rewrite) or is_integer(rewrite) do
    KeyValueStore.get(rewrite, :dot_formatter, DotFormatter.new())
  end

  @doc """
  Sets a `dot_formatter` for the given `rewrite` project.
  """
  @spec dot_formatter(t(), DotFormatter.t()) :: t()
  def dot_formatter(%Rewrite{} = rewrite, dot_formatter)
      when is_struct(dot_formatter, DotFormatter) or is_nil(dot_formatter) do
    KeyValueStore.put(rewrite, :dot_formatter, dot_formatter)
  end

  @doc """
  Creates a new `%Source{}` and puts the source to the `%Rewrite{}` project.
  """
  @spec new_source(t(), Path.t(), String.t(), opts()) :: {:ok, t()} | {:error, Error.t()}
  def new_source(%Rewrite{sources: sources} = rewrite, path, content, opts \\ []) do
    case Map.has_key?(sources, path) do
      true ->
        {:error, Error.exception(reason: :overwrites, path: path)}

      false ->
        {source, source_opts} = extension_for_file(rewrite, path)
        opts = Keyword.merge(source_opts, opts)
        source = source.from_string(content, path, opts)
        put(rewrite, source)
    end
  end

  @doc """
  Same as `new_source/4`, but raises a `Rewrite.Error` exception in case of failure.
  """
  @spec new_source!(t(), Path.t(), String.t(), opts()) :: t()
  def new_source!(%Rewrite{} = rewrite, path, content, opts \\ []) do
    case new_source(rewrite, path, content, opts) do
      {:ok, rewrite} -> rewrite
      {:error, error} -> raise error
    end
  end

  defp extensions(modules) do
    modules
    |> Enum.flat_map(fn
      Source ->
        [{"default", Source}]

      {Source, opts} ->
        [{"default", {Source, opts}}]

      {module, opts} ->
        Enum.map(module.extensions(), fn extension -> {extension, {module, opts}} end)

      module ->
        Enum.map(module.extensions(), fn extension -> {extension, module} end)
    end)
    |> Map.new()
    |> Map.put_new("default", Source)
  end

  defp expand(inputs) do
    inputs
    |> List.wrap()
    |> Enum.map(&compile_globs!/1)
    |> Enum.flat_map(&GlobEx.ls/1)
    |> Enum.uniq()
  end

  defp compile_globs!(str) when is_binary(str), do: GlobEx.compile!(str, match_dot: true)

  defp compile_globs!(glob) when is_struct(glob, GlobEx), do: glob

  defimpl Enumerable do
    def count(rewrite) do
      {:ok, map_size(rewrite.sources)}
    end

    def member?(rewrite, %Source{} = source) do
      member? = Map.get(rewrite.sources, source.path) == source
      {:ok, member?}
    end

    def member?(_rewrite, _other) do
      {:ok, false}
    end

    def slice(rewrite) do
      sources = rewrite.sources |> Map.values() |> Enum.sort_by(fn source -> source.path end)
      length = length(sources)

      {:ok, length,
       fn
         start, count when start + count == length -> Enum.drop(sources, start)
         start, count -> sources |> Enum.drop(start) |> Enum.take(count)
       end}
    end

    def reduce(rewrite, acc, fun) do
      sources = Map.values(rewrite.sources)
      Enumerable.List.reduce(sources, acc, fun)
    end
  end
end
