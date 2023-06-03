defmodule Rewrite.Source do
  @moduledoc """
  A representation of some source in a project.

  The `%Source{}` contains the `code` of the file given by `path`. The module
  contains `Source.update/3` to update the `path` and/or the `code`. The changes
  are recorded in the `updates` list.

  The struct also holds `issues` for the source.
  """

  # alias Mix.Tasks.Format
  alias Rewrite.Source
  alias Rewrite.SourceError
  alias Rewrite.UpdateError
  alias Rewrite.TextDiff
  # alias Sourceror.Zipper

  defstruct [
    :from,
    :path,
    :content,
    :hash,
    :owner,
    :filetype,
    updates: [],
    issues: [],
    private: %{}
  ]

  @type opts :: keyword()

  @typedoc """
  The `version` of a `%Source{}`. The version `1` indicates that the source has
  no changes.
  """
  @type version :: pos_integer()

  # TODO: ???
  @type kind :: :code | :path

  # TODO by and owner or just one of this
  @type by :: module()
  @type owner :: module()

  @type key :: atom()
  @type value :: any()

  @type content :: String.t()
  @type extension :: String.t()

  @type from :: :file | :ast | :string

  @type issue :: any()

  @type filetype :: %{}

  @type t :: %Source{
          path: Path.t() | nil,
          content: String.t(),
          hash: String.t(),
          updates: [{kind(), by(), String.t()}],
          issues: [issue()],
          filetype: filetype(),
          from: from(),
          owner: owner(),
          private: map()
        }

  @doc ~S'''
  Creates a new `%Source{}` from the given `path`.

  ## Examples

      iex> source = Source.read!("test/fixtures/source/simple.ex")
      iex> source.modules
      [MyApp.Simple]
      iex> source.code
      """
      defmodule MyApp.Simple do
        def foo(x) do
          x * 2
        end
      end
      """
  '''
  @spec read!(Path.t(), opts) :: t()
  def read!(path, opts \\ []) do
    content = File.read!(path)
    owner = Keyword.get(opts, :owner, Rewrite)
    new(content: content, path: path, owner: owner, from: :file)
  end

  defp new(fields) do
    content = Keyword.fetch!(fields, :content)
    path = Keyword.get(fields, :path, nil)

    struct!(
      Source,
      content: content,
      from: Keyword.fetch!(fields, :from),
      hash: hash(path, content),
      owner: Keyword.get(fields, :owner, Rewrite),
      path: Keyword.get(fields, :path, nil)
    )
  end

  @doc """
  Creates a new `%Source{}` from the given `string`.

  ## Examples

      iex> source = Source.from_string("a + b")
      iex> source.modules
      []
      iex> source.code
      "a + b"
  """
  @spec from_string(String.t(), Path.t() | nil, opts()) :: t()
  def from_string(content, path \\ nil, opts \\ []) do
    owner = Keyword.get(opts, :owner, Rewrite)

    new(content: content, path: path, owner: owner, from: :string)
  end

  @doc ~S"""
  Writes the source to disk.

  Returns `{:ok, source}` when the file was written successfully. The returned
  `source` does not include any previous changes or issues.

  If there's an error, this function returns `{:error, error}` where `error`
  is a `Rewrite.SourceError`. You can raise it manually with `raise/1`.

  Returns `{:error, error}` with `reason: :nopath` if the current `path` is nil.

  Returns `{:error, error}` with `reason: :changed` if the file was changed
  since reading. See also `file_changed?/1`. The option `force: true` forces
  overwriting a changed file.

  If the source `:path` was updated then the old file will be deleted.

  Missing directories are created.

  ## Options

  + `:force`, default: `false` - forces the saving to overwrite changed files.
  + `:rm`, default: `true` - prevents file deletion when set to `false`.

  ## Examples

      iex> ":test" |> Source.from_string() |> Source.write()
      {:error, %SourceError{reason: :nopath, path: nil, action: :write}}

      iex> path = "tmp/foo.ex"
      iex> File.write(path, ":foo")
      iex> source = path |> Source.read!() |> Source.update(:test, code: ":bar")
      iex> Source.updated?(source)
      true
      iex> {:ok, source} = Source.write(source)
      iex> File.read(path)
      {:ok, ":bar\n"}
      iex> Source.updated?(source)
      false

      iex> source = Source.from_string(":bar")
      iex> Source.write(source)
      {:error, %SourceError{reason: :nopath, path: nil, action: :write}}
      iex> source |> Source.update(:test, path: "tmp/bar.ex") |> Source.write()
      iex> File.read("tmp/bar.ex")
      {:ok, ":bar\n"}

      iex> path = "tmp/ping.ex"
      iex> File.write(path, ":ping")
      iex> source = Source.read!(path)
      iex> new_path = "tmp/pong.ex"
      iex> source = Source.update(source, :test, path: new_path)
      iex> Source.write(source)
      iex> File.exists?(path)
      false
      iex> File.read(new_path)
      {:ok, ":ping\n"}

      iex> path = "tmp/ping.ex"
      iex> File.write(path, ":ping")
      iex> source = Source.read!(path)
      iex> new_path = "tmp/pong.ex"
      iex> source = Source.update(source, :test, path: new_path)
      iex> Source.write(source, rm: false)
      iex> File.exists?(path)
      true
      iex> File.read(new_path)
      {:ok, ":ping\n"}

      iex> path = "tmp/ping.ex"
      iex> File.write(path, ":ping")
      iex> source = path |> Source.read!() |> Source.update(:test, code: "peng")
      iex> File.write(path, ":pong")
      iex> Source.write(source)
      {:error, %SourceError{reason: :changed, path: "tmp/ping.ex", action: :write}}
      iex> {:ok, _source} = Source.write(source, force: true)
  """
  @spec write(t(), opts()) :: {:ok, t()} | {:error, SourceError.t()}
  def write(%Source{} = source, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    rm = Keyword.get(opts, :rm, true)
    write(source, force, rm)
  end

  defp write(%Source{path: nil}, _force, _rm) do
    {:error, SourceError.exception(reason: :nopath, action: :write)}
  end

  defp write(%Source{updates: []} = source, _force, _rm), do: {:ok, source}

  defp write(%Source{path: path, content: content} = source, force, rm) do
    if file_changed?(source) && !force do
      {:error, SourceError.exception(reason: :changed, path: source.path, action: :write)}
    else
      with :ok <- maybe_rm(source, rm),
           :ok <- mkdir_p(path),
           :ok <- file_write(path, eof_newline(content)) do
        {:ok, %{source | hash: hash(path, content), updates: [], issues: []}}
      end
    end
  end

  defp file_write(path, content) do
    with {:error, reason} <- File.write(path, content) do
      {:error, SourceError.exception(reason: reason, path: path, action: :write)}
    end
  end

  defp mkdir_p(path) do
    path |> Path.dirname() |> File.mkdir_p()
  end

  defp maybe_rm(_source, false), do: :ok

  defp maybe_rm(source, true) do
    case {Source.updated?(source, :path), Source.path(source, 1)} do
      {false, _path} ->
        :ok

      {true, nil} ->
        :ok

      {true, path} ->
        with {:error, reason} <- File.rm(path) do
          {:error, SourceError.exception(reason: reason, path: path, action: :write)}
        end
    end
  end

  @doc """
  Same as `write/1`, but raises a `Rewrite.SourceError` exception in case of
  failure.
  """
  @spec write!(t()) :: t()
  def write!(%Source{} = source) do
    case write(source) do
      {:ok, source} -> source
      {:error, error} -> raise error
    end
  end

  @doc """
  Tries to delete the file `source`.

  Returns `:ok` if successful, or `{:error, reason}` if an error occurs.

  Note the file is deleted even if in read-only mode.
  """
  @spec rm(t()) :: :ok | {:error, SourceError.t()}
  def rm(%Source{path: nil}), do: {:error, %SourceError{reason: :nopath, action: :rm}}

  def rm(%Source{path: path}) do
    with {:error, reason} <- File.rm(path) do
      {:error, %SourceError{reason: reason, action: :rm, path: path}}
    end
  end

  @doc """
  Same as `rm/1`, but raises a `Rewrite.SourceError` exception in case of
  failure. Otherwise `:ok`.
  """
  @spec rm!(t()) :: :ok
  def rm!(%Source{} = source) do
    with {:error, reason} <- rm(source), do: raise(reason)
  end

  @doc """
  Returns the `version` of the given `source`. The value `1` indicates that the
  source has no changes.
  """
  @spec version(t()) :: version()
  def version(%Source{updates: updates}), do: length(updates) + 1

  @doc """
  Adds the given `issues` to the `source`.
  """
  @spec add_issues(t(), [issue()]) :: t()
  def add_issues(%Source{issues: list} = source, issues) do
    version = version(source)
    issues = issues |> Enum.map(fn issue -> {version, issue} end) |> Enum.concat(list)

    %Source{source | issues: issues}
  end

  @doc """
  Adds the given `issue` to the `source`.
  """
  @spec add_issue(t(), issue()) :: t()
  def add_issue(%Source{} = source, issue), do: add_issues(source, [issue])

  @doc """
  Assigns a private `key` and `value` to the `source`.

  This is not used or accessed by Rewrite, but is intended as private storage
  for users or libraries that wish to store additional data about a source.

  ## Examples

      iex> source =
      ...>   "a + b"
      ...>   |> Source.from_string()
      ...>   |> Source.put_private(:origin, :example)
      iex> source.private[:origin]
      :example
  """
  @spec put_private(t(), key :: any(), value()) :: t()
  def put_private(%Source{} = source, key, value) do
    Map.update!(source, :private, &Map.put(&1, key, value))
  end

  @doc ~S"""
  Updates the `content` or the `path` of a `source`.

  ## Examples

      iex> source =
      ...>   "a + b"
      ...>   |> Source.from_string()
      ...>   |> Source.update(:example, path: "test/fixtures/new.exs")
      ...>   |> Source.update(:example, content: "a - b")
      iex> source.updates
      [{:content, :example, "a + b"}, {:path, :example, nil}]
      iex> source.content
      "a - b"

  If the new value equal to the current value, no updates will be added.

      iex> source =
      ...>   "a = 42"
      ...>   |> Source.from_string()
      ...>   |> Source.update(:example, content: "b = 21")
      ...>   |> Source.update(:example, content: "b = 21")
      ...>   |> Source.update(:example, content: "b = 21")
      iex> source.updates
      [{:content, :example, "a = 42"}]
  """
  @spec update(Source.t(), by(), key(), value()) :: Source.t()
  def update(source, by \\ Rewrite, key, value)

  def update(%Source{} = source, by, key, value)
      when is_atom(by) and key in [:content, :path] do
    legacy = Map.fetch!(source, key)

    case legacy == value do
      true ->
        source

      false ->
        IO.inspect("update")

        source
        |> do_update(key, value)
        |> update_updates(key, by, legacy)
        |> update_filetype(key)
    end
  end

  def update(%Source{filetype: %module{}} = source, by, key, value) do
    case module.update(source, key, value) |> IO.inspect() do
      :ok ->
        source

      {:ok, updates} ->
        source
        |> update_filetype(updates[:filetype])
        |> update_content(updates[:content], by)

      :error ->
        {:error,
         UpdateError.exception(
           reason: :filetype,
           source: source.path,
           filetype: module,
           key: key,
           value: value
         )}
    end
  end

  defp do_update(source, :path, path) do
    %Source{source | path: path}
  end

  defp do_update(source, :content, content) do
    %Source{source | content: content}
  end

  defp update_filetype(source, nil), do: source

  defp update_filetype(%{filtetype: nil} = source, _filtetype), do: source

  defp update_filetype(%{filetype: %module{}} = source, key) when is_atom(key) do
    case module.update(source, key) do
      :ok ->
        source

      {:ok, filetype} ->
        update_filetype(source, filetype)

      :error ->
        {:error,
         UpdateError.exception(
           reason: :filetype,
           source: source.path,
           filetype: module,
           key: key,
           value: Map.fetch(source, key)
         )}
    end
  end

  defp update_filetype(source, filetype) do
    %Source{source | filetype: filetype}
  end

  defp update_content(source, nil, _b), do: source

  defp update_content(source, content, by) do
    update(source, by, :content, content)
  end

  # defp update_modules(source, key) when key in [:ast, :code],
  #   do: %{source | modules: get_modules(source.code)}

  # defp update_modules(source, _key), do: source

  @doc """
  Returns `true` if the source was updated.

  The optional argument `kind` specifies whether only `:code` changes or `:path`
  changes are considered. Defaults to `:any`.

  ## Examples

      iex> source = Source.from_string("a = 42")
      iex> Source.updated?(source)
      false
      iex> source = Source.update(source, :example, code: "b = 21")
      iex> Source.updated?(source)
      true
      iex> Source.updated?(source, :path)
      false
      iex> Source.updated?(source, :code)
      true
  """
  @spec updated?(t(), kind :: :code | :path | :any) :: boolean()
  def updated?(source, kind \\ :any)

  def updated?(%Source{updates: []}, _kind), do: false

  def updated?(%Source{updates: _updates}, :any), do: true

  def updated?(%Source{updates: updates}, kind) when kind in [:code, :path] do
    Enum.any?(updates, fn
      {^kind, _by, _value} -> true
      _update -> false
    end)
  end

  @doc """
  Returns `true` if the file has been modified since it was read.

  If the key `:from` does not contain `:file` the function returns `false`.

  ## Examples

      iex> File.write("tmp/code.ex", "a = 24")
      iex> source = Source.read!("tmp/code.ex")
      iex> Source.file_changed?(source)
      false
      iex> File.write("tmp/code.ex", "a = 42")
      iex> Source.file_changed?(source)
      true
      iex> source = Source.update(source, :test, path: nil)
      iex> Source.file_changed?(source)
      true
      iex> File.write("tmp/code.ex", "a = 24")
      iex> Source.file_changed?(source)
      false
      iex> File.rm!("tmp/code.ex")
      iex> Source.file_changed?(source)
      true

      iex> source = Source.from_string("a = 77")
      iex> Source.file_changed?(source)
      false
  """
  @spec file_changed?(Source.t()) :: boolean
  def file_changed?(%Source{from: from}) when from != :file, do: false

  def file_changed?(%Source{} = source) do
    path = path(source, 1)

    case File.read(path) do
      {:ok, content} -> hash(path, content) != source.hash
      _error -> true
    end
  end

  @doc """
  Returns `true` if the `source` has issues for the given `version`.

  The `version` argument also accepts `:actual` and `:all` to check whether the
  `source` has problems for the actual version or if there are problems at all.

  ## Examples

      iex> source =
      ...>   "a + b"
      ...>   |> Source.from_string("some/where/plus.exs")
      ...>   |> Source.add_issue(%{issue: :foo})
      ...>   |> Source.update(:example, path: "some/where/else/plus.exs")
      ...>   |> Source.add_issue(%{issue: :bar})
      iex> Source.has_issues?(source)
      true
      iex> Source.has_issues?(source, 1)
      true
      iex> Source.has_issues?(source, :all)
      true
      iex> source = Source.update(source, :example, code: "a - b")
      iex> Source.has_issues?(source)
      false
      iex> Source.has_issues?(source, 2)
      true
      iex> Source.has_issues?(source, :all)
      true
  """
  @spec has_issues?(t(), version() | :actual | :all) :: boolean
  def has_issues?(source, version \\ :actual)

  def has_issues?(%Source{issues: issues}, :all), do: not_empty?(issues)

  def has_issues?(%Source{} = source, :actual) do
    has_issues?(source, version(source))
  end

  def has_issues?(%Source{issues: issues, updates: updates}, version)
      when version >= 1 and version <= length(updates) + 1 do
    issues
    |> Enum.filter(fn {for_version, _issue} -> for_version == version end)
    |> not_empty?()
  end

  @doc """
  Returns the current path for the given `source`.
  """
  @spec path(t()) :: Path.t() | nil
  def path(%Source{path: path}), do: path

  @doc """
  Returns the path of a `source` for the given `version`.

  ## Examples

      iex> source =
      ...>   "a + b"
      ...>   |> Source.from_string("some/where/plus.exs")
      ...>   |> Source.update(:example, path: "some/where/else/plus.exs")
      ...> Source.path(source, 1)
      "some/where/plus.exs"
      iex> Source.path(source, 2)
      "some/where/else/plus.exs"
  """
  @spec path(t(), version()) :: Path.t() | nil
  def path(%Source{path: path, updates: updates}, version)
      when version >= 1 and version <= length(updates) + 1 do
    updates
    |> Enum.take(length(updates) - version + 1)
    |> Enum.reduce(path, fn
      {:path, _by, path}, _path -> path
      _version, path -> path
    end)
  end

  # @doc """
  # Returns the current modules for the given `source`.
  # """
  # @spec modules(t()) :: [module()]
  # def modules(%Source{modules: modules}), do: modules

  # @doc ~S'''
  # Returns the modules of a `source` for the given `version`.

  # ## Examples

  #     iex> bar =
  #     ...>   """
  #     ...>   defmodule Bar do
  #     ...>      def bar, do: :bar
  #     ...>   end
  #     ...>   """
  #     iex> foo =
  #     ...>   """
  #     ...>   defmodule Foo do
  #     ...>      def foo, do: :foo
  #     ...>   end
  #     ...>   """
  #     iex> source = Source.from_string(bar)
  #     iex> source = Source.update(source, :example, code: bar <> foo)
  #     iex> Source.modules(source)
  #     [Foo, Bar]
  #     iex> Source.modules(source, 2)
  #     [Foo, Bar]
  #     iex> Source.modules(source, 1)
  #     [Bar]
  # '''
  # @spec modules(t(), version()) :: [module()]
  # def modules(%Source{updates: updates} = source, version)
  #     when version >= 1 and version <= length(updates) + 1 do
  #   source |> code(version) |> get_modules()
  # end

  @doc """
  Returns the current content for the given `source`.
  """
  @spec content(t()) :: String.t()
  def content(%Source{content: content}), do: content

  @doc ~S'''
  Returns the content of a `source` for the given `version`.

  ## Examples

      iex> bar =
      ...>   """
      ...>   defmodule Bar do
      ...>      def bar, do: :bar
      ...>   end
      ...>   """
      iex> foo =
      ...>   """
      ...>   defmodule Foo do
      ...>      def foo, do: :foo
      ...>   end
      ...>   """
      iex> source = Source.from_string(bar)
      iex> source = Source.update(source, :example, content: foo)
      iex> Source.content(source) == foo
      true
      iex> Source.content(source, 2) == foo
      true
      iex> Source.content(source, 1) == bar
      true
  '''
  @spec content(t(), version()) :: String.t()
  def content(%Source{content: content, updates: updates}, version)
      when version >= 1 and version <= length(updates) + 1 do
    updates
    |> Enum.take(length(updates) - version + 1)
    |> Enum.reduce(content, fn
      {:content, _by, content}, _content -> content
      _version, content -> content
    end)
  end

  # @doc """
  # Returns the AST for the given `%Source`.

  # The returned extended AST is generated with `Sourceror.parse_string/1`.

  # Uses the current `code` of the `source`.

  # ## Examples

  #     iex> "def foo, do: :foo" |> Source.from_string() |> Source.ast()
  #     {:def, [trailing_comments: [], leading_comments: [], line: 1, column: 1],
  #       [
  #         {:foo, [trailing_comments: [], leading_comments: [], line: 1, column: 5], nil},
  #         [
  #           {{:__block__,
  #             [trailing_comments: [], leading_comments: [], format: :keyword, line: 1, column: 10],
  #             [:do]},
  #            {:__block__, [trailing_comments: [], leading_comments: [], line: 1, column: 14], [:foo]}}
  #         ]
  #       ]
  #     }
  # """
  # @spec ast(t()) :: Macro.t()
  # def ast(%Source{ast: ast}), do: ast

  # @doc """
  # Returns the owner of the given `source`.
  # """
  # @spec owner(t()) :: module()
  # def owner(%Source{owner: owner}), do: owner

  # @doc """
  # Compares the `path` values of the given sources.

  # ## Examples

  #     iex> a = Source.from_string(":foo", "a.exs")
  #     iex> Source.compare(a, a)
  #     :eq
  #     iex> b = Source.from_string(":foo", "b.exs")
  #     iex> Source.compare(a, b)
  #     :lt
  #     iex> Source.compare(b, a)
  #     :gt
  # """
  # @spec compare(t(), t()) :: :lt | :eq | :gt
  # def compare(%Source{path: path1}, %Source{path: path2}) do
  #   cond do
  #     path1 < path2 -> :lt
  #     path1 > path2 -> :gt
  #     true -> :eq
  #   end
  # end

  @doc ~S'''
  Returns iodata showing all diffs of the given `source`.

  See `Rewrite.TextDiff.format/3` for options.

  ## Examples

      iex> code = """
      ...> def foo( x ) do
      ...>   {:x,
      ...>     x}
      ...> end
      ...> """
      iex> formatted = code |> Code.format_string!() |> IO.iodata_to_binary()
      iex> source = Source.from_string(code)
      iex> source |> Source.diff() |> IO.iodata_to_binary()
      ""
      iex> source
      ...> |> Source.update(Test, code: formatted)
      ...> |> Source.diff(color: false)
      ...> |> IO.iodata_to_binary()
      """
      1   - |def foo( x ) do
      2   - |  {:x,
      3   - |    x}
        1 + |def foo(x) do
        2 + |  {:x, x}
      4 3   |end
      5 4   |
      """
  '''
  @spec diff(t(), opts()) :: iodata()
  def diff(%Source{} = source, opts \\ []) do
    TextDiff.format(
      source |> content(1) |> eof_newline(),
      source |> content() |> eof_newline(),
      opts
    )
  end

  @doc ~S'''
  Calculates the current hash from the given `source`.

  ## Examples

      iex> source = Source.from_string("""
      ...> defmodule Foo do
      ...>   def bar, do: :bar
      ...> end
      ...> """)
      iex> Source.hash(source)
      <<76, 24, 5, 252, 117, 230, 0, 217, 129, 150, 68, 248, 6, 48, 72, 46>>
  '''
  @spec hash(t()) :: binary()
  def hash(%Source{path: path, content: content}), do: hash(path, content)

  @doc """
  Sets the `filetype` for the `source`.
  """
  @spec filetype(t(), filetype()) :: t()
  def filetype(%Source{} = source, filetype), do: %Source{source | filetype: filetype}

  @doc """
  Gets the value for a specific `key` in `source` or `source.filetype`.

  If the key is `:content` or `:path` the value comes directly form `source`
  other keys are applied with `source.filetype`.
  """
  @spec get(t(), key()) :: value()
  def get(%Source{} = source, key) when key in [:content, :path] do
    Map.get(source, key)
  end

  def get(%Source{filetype: filetype}, key) when not is_nil(filetype) do
    Map.get(filetype, key)
  end

  @doc """
  Fetches the value for a specific `key` in `source` or `source.filetype`.

  If the key is `:content` or `:path` the value comes directly form `source`
  other keys are applied with `source.filetype`.
  """
  @spec fetch(t(), key()) :: {:ok, value()} | :error
  def fetch(%Source{} = source, key) when key in [:content, :path] do
    Map.fetch(source, key)
  end

  def fetch(%Source{filetype: filetype}, key) when not is_nil(filetype) do
    Map.fetch(filetype, key)
  end

  @doc """
  Fetches the value for a specific `key` in `source` or `source.filetype`,
  erroring out if `source` or `source.filetype` doesn't contain key.

  If the key is `:content` or `:path` the value comes directly form `source`
  other keys are applied with `source.filetype`.
  """
  @spec fetch!(t(), key()) :: {:ok, value()} | :error
  def fetch!(%Source{} = source, key) when key in [:content, :path] do
    Map.fetch(source, key)
  end

  def fetch!(%Source{filetype: filetype}, key) when not is_nil(filetype) do
    Map.fetch(filetype, key)
  end

  # defp get_modules(code) when is_binary(code) do
  #   code
  #   |> Sourceror.parse_string!()
  #   |> get_modules()
  # end

  # defp get_modules(code) do
  #   code
  #   |> Zipper.zip()
  #   |> Zipper.traverse([], fn
  #     {{:defmodule, _meta, [module | _args]}, _zipper_meta} = zipper, acc ->
  #       {zipper, [concat(module) | acc]}

  #     zipper, acc ->
  #       {zipper, acc}
  #   end)
  #   |> elem(1)
  #   |> Enum.uniq()
  #   |> Enum.filter(&is_atom/1)
  # end

  # defp format(ast, file \\ nil, formatter_opts \\ nil) do
  #   file = file || "source.ex"

  #   formatter_opts =
  #     if is_nil(formatter_opts) do
  #       {_formatter, formatter_opts} = Format.formatter_for_file(file)
  #       formatter_opts
  #     else
  #       formatter_opts
  #     end

  #   ext = Path.extname(file)
  #   plugins = plugins_for_ext(formatter_opts, ext)

  #   {quoted_to_algebra, plugins} =
  #     case plugins do
  #       [FreedomFormatter | plugins] ->
  #         # For now just a workaround to support the FreedomFormatter.
  #         {&FreedomFormatter.Formatter.to_algebra/2, plugins}

  #       plugins ->
  #         {&Code.quoted_to_algebra/2, plugins}
  #     end

  #   formatter_opts =
  #     formatter_opts ++
  #       [
  #         quoted_to_algebra: quoted_to_algebra,
  #         extension: ext,
  #         file: file
  #       ]

  #   code = Sourceror.to_string(ast, formatter_opts)

  #   Enum.reduce(plugins, code, fn plugin, code ->
  #     plugin.format(code, formatter_opts)
  #   end)
  # end

  # defp plugins_for_ext(formatter_opts, ext) do
  #   formatter_opts
  #   |> Keyword.get(:plugins, [])
  #   |> Enum.filter(fn plugin ->
  #     Code.ensure_loaded?(plugin) and function_exported?(plugin, :features, 1) and
  #       ext in List.wrap(plugin.features(formatter_opts)[:extensions])
  #   end)
  # end

  # defp concat({:__aliases__, _meta, module}), do: Module.concat(module)

  # defp concat(ast), do: ast

  defp hash(nil, code), do: :crypto.hash(:md5, code)

  defp hash(path, code), do: :crypto.hash(:md5, path <> code)

  defp update_updates(%Source{updates: updates} = source, key, by, legacy) do
    %{source | updates: [{key, by, legacy} | updates]}
  end

  defp not_empty?(enum), do: not Enum.empty?(enum)

  defp eof_newline(string), do: String.trim_trailing(string) <> "\n"
end
