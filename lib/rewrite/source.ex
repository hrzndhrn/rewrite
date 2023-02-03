defmodule Rewrite.Source do
  @moduledoc """
  A representation of some source in a project.

  The `%Source{}` contains the `code` of the file given by `path`. The module
  contains `Source.update/3` to update the `path` and/or the `code`. The changes
  are recorded in the `updates` list.

  The struct also holds `issues` for the source.
  """

  alias Mix.Tasks.Format
  alias Rewrite.Source
  alias Rewrite.TextDiff
  alias Sourceror.Zipper

  defstruct [
    :id,
    :from,
    :path,
    :code,
    :ast,
    :hash,
    :modules,
    :owner,
    updates: [],
    issues: []
  ]

  @typedoc """
  The `version` of a `%Source{}`. The version `1` indicates that the source has
  no changes.
  """
  @type version :: pos_integer()

  @type kind :: :code | :path

  @type by :: module()

  @type id :: String.t()

  @type from :: :file | :ast | :string

  @type issue :: term()

  @type t :: %Source{
          id: id(),
          path: Path.t() | nil,
          code: String.t(),
          ast: Macro.t(),
          hash: String.t(),
          modules: [module()],
          updates: [{kind(), by(), String.t()}],
          issues: [issue()],
          from: from(),
          owner: module()
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
  @spec read!(Path.t()) :: t()
  def read!(path) do
    code = File.read!(path)
    new(code: code, path: path, from: :file)
  end

  defp new(fields) do
    {code, ast} =
      case Keyword.get(fields, :ast) do
        nil ->
          code = Keyword.fetch!(fields, :code)
          {code, Sourceror.parse_string!(code)}

        ast ->
          {format(ast), ast}
      end

    path = Keyword.get(fields, :path, nil)

    struct!(
      Source,
      id: make_ref(),
      from: Keyword.fetch!(fields, :from),
      path: Keyword.get(fields, :path, nil),
      code: code,
      ast: ast,
      hash: hash(path, code),
      modules: get_modules(ast),
      owner: Keyword.get(fields, :owner, Rewrite)
    )
  end

  @doc """
  Creates a new `%Source{}` from the given `string`.

  ## Examples

      iex> source = Source.from_string("a + b")
      iex> source.modules
      []
      iex> source.code
      "a + b\\n"
  """
  @spec from_string(String.t(), nil | Path.t(), module()) :: t()
  def from_string(string, path \\ nil, owner \\ Rewrite) do
    new(code: newline(string), path: path, owner: owner, from: :string)
  end

  @doc """
  Creates a new `%Source{}` from the given `ast`.

  ## Examples

      iex> ast = Sourceror.parse_string!("a + b")
      iex> source = Source.from_ast(ast)
      iex> source.modules
      []
      iex> source.code
      "a + b\\n"
  """
  @spec from_ast(Macro.t(), nil | Path.t(), module()) :: t()
  def from_ast(ast, path \\ nil, owner \\ Rewrite) do
    new(ast: ast, path: path, owner: owner, from: :string)
  end

  @doc """
  Marks the given `source` as deleted.

  This function set the `path` of the `given` source to `nil`.
  """
  @spec del(t(), nil | module()) :: t()
  def del(source, by \\ nil)

  def del(%Source{path: nil} = source, _by), do: source

  def del(%Source{path: legacy} = source, by) do
    source
    |> Map.put(:path, nil)
    |> update_updates({:path, by, legacy})
    |> update_hash()
  end

  @doc ~S"""
  Saves the source to disk.

  If the source `:path` was updated then the old file will be deleted. The
  original file will also deleted when the `source` was marked as deleted with
  `del/1`.

  Missing directories are created.

  ## Examples

      iex> ":test" |> Source.from_string() |> Source.save()
      {:error, :nofile}

      iex> path = "tmp/foo.ex"
      iex> File.write(path, ":foo")
      iex> source = path |> Source.read!() |> Source.update(:test, code: ":bar")
      iex> Source.save(source)
      :ok
      iex> File.read(path)
      {:ok, ":bar\n"}
      iex> source |> Source.del() |> Source.save()
      iex> File.exists?(path)
      false

      iex> source = Source.from_string(":bar")
      iex> Source.save(source)
      {:error, :nofile}
      iex> source |> Source.update(:test, path: "tmp/bar.ex") |> Source.save()
      :ok

      iex> path = "tmp/ping.ex"
      iex> File.write(path, ":ping")
      iex> source = path |> Source.read!()
      iex> new_path = "tmp/pong.ex"
      iex> source |> Source.update(:test, path: new_path) |> Source.save()
      :ok
      iex> File.exists?(path)
      false
      iex> File.read(new_path)
      {:ok, ":ping"}
  """
  @spec save(t()) :: :ok | {:error, :nofile | File.posix()}
  def save(%Source{path: nil, updates: []}), do: {:error, :nofile}

  def save(%Source{updates: []}), do: :ok

  def save(%Source{path: nil} = source), do: rm(source)

  def save(%Source{path: path, code: code} = source) do
    with :ok <- mkdir_p(path),
         :ok <- File.write(path, code) do
      rm(source)
    end
  end

  defp mkdir_p(path) do
    path |> Path.dirname() |> File.mkdir_p()
  end

  defp rm(source) do
    case {Source.updated?(source, :path), Source.path(source, 1)} do
      {false, _path} -> :ok
      {true, nil} -> :ok
      {true, path} -> File.rm(path)
    end
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

  @doc ~S"""
  Updates the `code` or the `path` of a `source`.

  ## Examples

      iex> source =
      ...>   "a + b"
      ...>   |> Source.from_string()
      ...>   |> Source.update(:example, path: "test/fixtures/new.exs")
      ...>   |> Source.update(:example, code: "a - b")
      iex> source.updates
      [{:code, :example, "a + b\n"}, {:path, :example, nil}]
      iex> source.code
      "a - b\n"

  If the new value equal to the current value, no updates will be added.

      iex> source =
      ...>   "a = 42"
      ...>   |> Source.from_string()
      ...>   |> Source.update(:example, code: "b = 21")
      ...>   |> Source.update(:example, code: "b = 21")
      ...>   |> Source.update(:example, code: "b = 21")
      iex> source.updates
      [{:code, :example, "a = 42\n"}]
  """
  @spec update(t(), by(), [code: String.t()] | [ast: Macro.t()] | [path: Path.t()]) :: t()
  def update(%Source{} = source, by, [{key, value}])
      when is_atom(by) and key in [:ast, :code, :path] do
    legacy = Map.fetch!(source, key)

    value = if key == :code, do: newline(value), else: value

    case legacy == value do
      true ->
        source

      false ->
        update =
          case key do
            :ast -> {:code, by, source.code}
            _else -> {key, by, legacy}
          end

        source
        |> do_update(key, value)
        |> update_updates(update)
        |> update_modules(key)
        |> update_hash()
    end
  end

  defp do_update(source, :code, code) do
    ast = Sourceror.parse_string!(code)
    %Source{source | ast: ast, code: code}
  end

  defp do_update(%Source{path: path} = source, :ast, ast) do
    %Source{source | ast: ast, code: format(ast, path)}
  end

  defp do_update(source, :path, path) do
    %Source{source | path: path}
  end

  defp update_modules(source, key) when key in [:ast, :code],
    do: %{source | modules: get_modules(source.code)}

  defp update_modules(source, _key), do: source

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
  Returns `true` if the `%Source{}` was created.

  Created means here that a new file is written when saving.

  ## Examples

      iex> source = Source.read!("test/fixtures/source/simple.ex")
      ...> Source.created?(source)
      false

      iex> source = Source.from_string(":foo")
      ...> Source.created?(source)
      true

      iex> source = Source.from_string(":foo", "test/fixtures/new.ex", Test)
      ...> Source.created?(source)
      true
  """
  @spec created?(t()) :: boolean
  def created?(%Source{from: from}), do: from != :file

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

  @doc """
  Returns the current modules for the given `source`.
  """
  @spec modules(t()) :: [module()]
  def modules(%Source{modules: modules}), do: modules

  @doc ~S'''
  Returns the modules of a `source` for the given `version`.

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
      iex> source = Source.update(source, :example, code: bar <> foo)
      iex> Source.modules(source)
      [Foo, Bar]
      iex> Source.modules(source, 2)
      [Foo, Bar]
      iex> Source.modules(source, 1)
      [Bar]
  '''
  @spec modules(t(), version()) :: [module()]
  def modules(%Source{updates: updates} = source, version)
      when version >= 1 and version <= length(updates) + 1 do
    source |> code(version) |> get_modules()
  end

  @doc """
  Returns the current code for the given `source`.
  """
  @spec code(t()) :: String.t()
  def code(%Source{code: code}), do: code

  @doc ~S'''
  Returns the code of a `source` for the given `version`.

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
      iex> source = Source.update(source, :example, code: foo)
      iex> Source.code(source) == foo
      true
      iex> Source.code(source, 2) == foo
      true
      iex> Source.code(source, 1) == bar
      true
  '''
  @spec code(t(), version()) :: String.t()
  def code(%Source{code: code, updates: updates}, version)
      when version >= 1 and version <= length(updates) + 1 do
    updates
    |> Enum.take(length(updates) - version + 1)
    |> Enum.reduce(code, fn
      {:code, _by, code}, _code -> code
      _version, code -> code
    end)
  end

  @doc """
  Returns the AST for the given `%Source`.

  The returned extended AST is generated with `Sourceror.parse_string/1`.

  Uses the current `code` of the `source`.

  ## Examples

      iex> "def foo, do: :foo" |> Source.from_string() |> Source.ast()
      {:def, [trailing_comments: [], leading_comments: [], line: 1, column: 1],
        [
          {:foo, [trailing_comments: [], leading_comments: [], line: 1, column: 5], nil},
          [
            {{:__block__,
              [trailing_comments: [], leading_comments: [], format: :keyword, line: 1, column: 10],
              [:do]},
             {:__block__, [trailing_comments: [], leading_comments: [], line: 1, column: 14], [:foo]}}
          ]
        ]
      }
  """
  @spec ast(t()) :: {:ok, Macro.t()} | {:error, term()}
  def ast(%Source{ast: ast}), do: ast

  @doc """
  Returns the owner of the given `source`.
  """
  @spec owner(t()) :: module()
  def owner(%Source{owner: owner}), do: owner

  @doc """
  Compares the `path` values of the given sources.

  ## Examples

      iex> a = Source.from_string(":foo", "a.exs")
      iex> Source.compare(a, a)
      :eq
      iex> b = Source.from_string(":foo", "b.exs")
      iex> Source.compare(a, b)
      :lt
      iex> Source.compare(b, a)
      :gt
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%Source{path: path1}, %Source{path: path2}) do
    cond do
      path1 < path2 -> :lt
      path1 > path2 -> :gt
      true -> :eq
    end
  end

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
  @spec diff(t(), keyword()) :: iodata()
  def diff(%Source{} = source, opts \\ []) do
    TextDiff.format(code(source, 1), code(source), opts)
  end

  defp get_modules(code) when is_binary(code) do
    code
    |> Sourceror.parse_string!()
    |> get_modules()
  end

  defp get_modules(code) do
    code
    |> Zipper.zip()
    |> Zipper.traverse([], fn
      {{:defmodule, _meta, [module | _args]}, _zipper_meta} = zipper, acc ->
        {zipper, [concat(module) | acc]}

      zipper, acc ->
        {zipper, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
  end

  defp format(ast, file \\ nil) do
    {_formatter, opts} = Format.formatter_for_file(file || "source.ex")

    algebra =
      case Keyword.get(opts, :plugins) do
        [FreedomFormatter] ->
          FreedomFormatter.Formatter.to_algebra(ast, opts)

        _else ->
          Code.quoted_to_algebra(ast, opts)
      end

    algebra
    |> Inspect.Algebra.format(Keyword.get(opts, :line_length, 98))
    |> IO.iodata_to_binary()
    |> newline()
  end

  defp concat({:__aliases__, _meta, module}), do: Module.concat(module)

  defp hash(nil, code), do: :crypto.hash(:md5, code)

  defp hash(path, code), do: :crypto.hash(:md5, path <> code)

  defp update_hash(%Source{path: path, code: code} = source) do
    %{source | hash: hash(path, code)}
  end

  defp update_updates(%Source{updates: updates} = source, update) do
    %{source | updates: [update | updates]}
  end

  defp not_empty?(enum), do: not Enum.empty?(enum)

  defp newline(string), do: String.trim_trailing(string) <> "\n"
end
