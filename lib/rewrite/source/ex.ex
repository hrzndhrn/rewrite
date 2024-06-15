defmodule Rewrite.Source.Ex do
  @moduledoc ~s'''
  An implementation of `Rewrite.Filetye` to handle Elixir source files.

  The module uses the [`sourceror`](https://github.com/doorgan/sourceror) package
  to provide an [extended AST](https://hexdocs.pm/sourceror/readme.html#sourceror-s-ast)
  representation of an Elixir file.

  `Ex` extends the `source` by the key `:quoted`.

  ## Updating and syncing `:quoted`

  When `:quoted` becomes updated, content becomes formatted to the Elixir source
  code. To keep the code in `:content` in sync with the AST in `:quoted`, the
  new code is parsed to a new `:quoted`. That means that
  `Source.update(source, :quoted, quoted)` also updates the AST.

  The syncing of `:quoted` can be suppressed with the option `sync_quoted: false`.

  ## Examples

      iex> source = Source.Ex.from_string("Enum.reverse(list)")
      iex> Source.get(source, :quoted)
      {{:., [trailing_comments: [], line: 1, column: 5],
        [
          {:__aliases__,
           [
             trailing_comments: [],
             leading_comments: [],
             last: [line: 1, column: 1],
             line: 1,
             column: 1
           ], [:Enum]},
          :reverse
        ]},
       [
         trailing_comments: [],
         leading_comments: [],
         closing: [line: 1, column: 18],
         line: 1,
         column: 6
       ], [{:list, [trailing_comments: [], leading_comments: [], line: 1, column: 14], nil}]}
      iex> quoted = Code.string_to_quoted!("""
      ...> defmodule MyApp.New do
      ...>   def      foo do
      ...>   :foo
      ...> end
      ...> end
      ...> """)
      iex> source = Source.update(source, :quoted, quoted)
      iex> Source.updated?(source)
      true
      iex> Source.get(source, :content)
      """
      defmodule MyApp.New do
        def foo do
          :foo
        end
      end
      """
      iex> Source.get(source, :quoted) == quoted
      false

  Without syncing `:quoted`:

      iex> project = Rewrite.new([{Source.Ex, sync_quoted: false}])
      iex> path = "test/fixtures/source/simple.ex"
      iex> project = Rewrite.read!(project, path)
      iex> source = Rewrite.source!(project, path)
      iex> quoted = Code.string_to_quoted!("""
      ...> defmodule MyApp.New do
      ...>   def      foo do
      ...>   :foo
      ...> end
      ...> end
      ...> """)
      iex> source = Source.update(source, :quoted, quoted)
      iex> Source.get(source, :quoted) == quoted
      true
  '''

  alias Mix.Tasks.Format
  alias Rewrite.Source
  alias Rewrite.Source.Ex
  alias Sourceror.Zipper

  @enforce_keys [:quoted, :formatter]
  defstruct [:quoted, :formatter, :opts]

  @type t :: %Ex{
          quoted: Macro.t(),
          formatter: (Macro.t() -> String.t()),
          opts: nil | keyword()
        }

  @behaviour Rewrite.Filetype

  @impl Rewrite.Filetype
  def extensions, do: [".ex", ".exs"]

  @doc """
  Returns a `%Rewrite.Source{}` with an added `:filetype`.
  """
  @impl Rewrite.Filetype
  def from_string(string, path \\ nil) do
    string
    |> Source.from_string(path)
    |> add_filetype()
  end

  @impl Rewrite.Filetype
  def from_string(string, path, _opts), do: from_string(string, path)

  @doc """
  Returns a `%Rewrite.Source{}` with an added `:filetype`.

  The `content` reads from the file under the given `path`.

  ## Options

    * `:formatter_opts`, default: `[]` - additional formatter options.

    * `sync_quoted`, default: `true` - forcing the re-parsing when the source
      field `quoted` is updated.
  """
  @impl Rewrite.Filetype
  def read!(path, opts \\ []) do
    path
    |> Source.read!()
    |> add_filetype(opts)
  end

  @impl Rewrite.Filetype
  def handle_update(%Source{filetype: %Ex{} = ex} = source, :path) do
    %Ex{ex | formatter: formatter(source.path, nil)}
  end

  def handle_update(%Source{filetype: %Ex{} = ex} = source, :content) do
    %Ex{ex | quoted: Sourceror.parse_string!(source.content)}
  end

  @impl Rewrite.Filetype
  def handle_update(%Source{filetype: %Ex{} = ex}, :quoted, quoted) do
    if ex.quoted == quoted do
      []
    else
      {quoted, code} = update_quoted(ex, quoted)

      [content: code, filetype: %Ex{ex | quoted: quoted}]
    end
  end

  defp update_quoted(ex, quoted) do
    code = ex.formatter.(quoted, formatter_opts(ex))

    quoted =
      case sync_quoted?(ex) do
        true -> Sourceror.parse_string!(code)
        false -> quoted
      end

    {quoted, code}
  end

  @impl Rewrite.Filetype
  def undo(%Source{filetype: %Ex{} = ex} = source) do
    Source.filetype(source, %Ex{
      ex
      | quoted: Sourceror.parse_string!(source.content),
        formatter: formatter(source.path, nil)
    })
  end

  @impl Rewrite.Filetype
  def fetch(%Source{filetype: %Ex{} = ex}, :quoted) do
    {:ok, ex.quoted}
  end

  def fetch(%Source{}, _key), do: :error

  @impl Rewrite.Filetype
  def fetch(%Source{filetype: %Ex{}, history: history} = source, :quoted, version)
      when version >= 1 and version <= length(history) + 1 do
    value = source |> Source.get(:content, version) |> Sourceror.parse_string!()

    {:ok, value}
  end

  def fetch(%Source{filetype: %Ex{}}, _key, _version), do: :error

  @doc """
  Returns the current modules for the given `source`.
  """
  @spec modules(Source.t()) :: [module()]
  def modules(%Source{filetype: %Ex{} = ex}) do
    get_modules(ex.quoted)
  end

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
      ...>   defmodule Baz.Foo do
      ...>      def foo, do: :foo
      ...>   end
      ...>   """
      iex> source = Source.Ex.from_string(bar)
      iex> source = Source.update(source, :content, bar <> foo)
      iex> Source.Ex.modules(source)
      [Baz.Foo, Bar]
      iex> Source.Ex.modules(source, 2)
      [Baz.Foo, Bar]
      iex> Source.Ex.modules(source, 1)
      [Bar]
  '''
  @spec modules(Source.t(), Source.version()) :: [module()]
  def modules(%Source{filetype: %Ex{}, history: history} = source, version)
      when version >= 1 and version <= length(history) + 1 do
    source |> Source.get(:content, version) |> Sourceror.parse_string!() |> get_modules()
  end

  @doc ~S'''
  Formats the given `source`, `code` or `quoted` into code.

  Returns an updated `source` when input is a `source`.

      iex> code = """
      ...> defmodule    Foo do
      ...>     def   foo,   do:    :foo
      ...>    end
      ...> """
      iex> Source.Ex.format(code)
      """
      defmodule Foo do
        def foo, do: :foo
      end
      """
      iex> Source.Ex.format(code, force_do_end_blocks: true)
      """
      defmodule Foo do
        def foo do
          :foo
        end
      end
      """

      iex> source = Source.Ex.from_string("""
      ...> defmodule    Foo do
      ...>     def   foo,   do:    :foo
      ...>    end
      ...> """)
      iex> Source.Ex.format(source, force_do_end_blocks: true)
      """
      defmodule Foo do
        def foo do
          :foo
        end
      end
      """
  '''
  @spec format(Source.t() | String.t() | Macro.t(), formatter_opts :: keyword() | nil) ::
          String.t()
  def format(input, formatter_opts \\ nil)

  def format(%Source{filetype: %Ex{} = ex}, formatter_opts) do
    ex.formatter.(ex.quoted, formatter_opts || formatter_opts(ex))
  end

  def format(input, formatter_opts) when is_binary(input) do
    input |> Sourceror.parse_string!() |> format(formatter_opts)
  end

  def format(input, formatter_opts) do
    formatter(nil, formatter_opts).(input, nil)
  end

  @doc """
  Puts the `formatter_opts` to the `source`.

  The formatter options are in use during updating and formatting.
  """
  @spec put_formatter_opts(Source.t(), keyword()) :: Source.t()
  def put_formatter_opts(%Source{filetype: %Ex{opts: opts} = ex} = source, formatter_opts) do
    opts = Keyword.put(opts || [], :formatter_opts, formatter_opts)

    Source.filetype(source, %Ex{ex | opts: opts})
  end

  @doc """
  Merges the `formatter_opts` for a `source`.
  """
  @spec merge_formatter_opts(Source.t(), keyword()) :: Source.t()
  def merge_formatter_opts(%Source{filetype: %Ex{opts: opts} = ex} = source, formatter_opts) do
    formatter_opts = Keyword.merge(formatter_opts(ex), formatter_opts)
    opts = Keyword.put(opts || [], :formatter_opts, formatter_opts)

    Source.filetype(source, %Ex{ex | opts: opts})
  end

  defp add_filetype(source, opts \\ nil) do
    ex =
      struct!(Ex,
        quoted: Sourceror.parse_string!(source.content),
        formatter: formatter(source.path, nil),
        opts: opts
      )

    Source.filetype(source, ex)
  end

  defp formatter(file, formatter_opts) do
    file = file || "source.ex"

    formatter_opts =
      if is_nil(formatter_opts) do
        {_formatter, formatter_opts} = Format.formatter_for_file(file)
        formatter_opts
      else
        formatter_opts
      end

    ext = Path.extname(file)
    plugins = plugins_for_ext(formatter_opts, ext)

    {quoted_to_algebra, plugins} = quoted_to_algebra(plugins)

    formatter_opts =
      formatter_opts ++
        [
          quoted_to_algebra: quoted_to_algebra,
          extension: ext,
          file: file
        ]

    formatter_opts = Keyword.put(formatter_opts, :plugins, plugins)

    fn quoted, opts ->
      opts =
        formatter_opts
        |> update_formatter_opts(opts, ext)
        |> eval_deps()

      code = Sourceror.to_string(quoted, opts)

      code =
        opts
        |> Keyword.fetch!(:plugins)
        |> Enum.reduce(code, fn plugin, code ->
          plugin.format(code, opts)
        end)

      String.trim_trailing(code, "\n") <> "\n"
    end
  end

  defp eval_deps(formatter_opts) do
    deps = Keyword.get(formatter_opts, :import_deps, [])

    locals_without_parens = eval_deps_opts(deps)

    formatter_opts =
      Keyword.update(
        formatter_opts,
        :locals_without_parens,
        locals_without_parens,
        &(locals_without_parens ++ &1)
      )

    formatter_opts
  end

  defp eval_deps_opts([]) do
    []
  end

  defp eval_deps_opts(deps) do
    deps_paths = Mix.Project.deps_paths()

    for dep <- deps,
        dep_path = fetch_valid_dep_path(dep, deps_paths),
        !is_nil(dep_path),
        dep_dot_formatter = Path.join(dep_path, ".formatter.exs"),
        File.regular?(dep_dot_formatter),
        dep_opts = eval_file_with_keyword_list(dep_dot_formatter),
        parenless_call <- dep_opts[:export][:locals_without_parens] || [],
        uniq: true,
        do: parenless_call
  end

  defp fetch_valid_dep_path(dep, deps_paths) when is_atom(dep) do
    with %{^dep => path} <- deps_paths,
         true <- File.dir?(path) do
      path
    else
      _ ->
        nil
    end
  end

  defp fetch_valid_dep_path(_dep, _deps_paths) do
    nil
  end

  defp eval_file_with_keyword_list(path) do
    {opts, _} = Code.eval_file(path)

    unless Keyword.keyword?(opts) do
      raise "Expected #{inspect(path)} to return a keyword list, got: #{inspect(opts)}"
    end

    opts
  end

  defp update_formatter_opts(left, nil, _ext), do: left

  defp update_formatter_opts(left, right, ext) do
    left
    |> Keyword.merge(right)
    |> exclude_plugins()
    |> filter_plugins(ext)
    |> update_quoted_to_algebra()
  end

  defp exclude_plugins(opts) do
    case Keyword.has_key?(opts, :plugins) && Keyword.has_key?(opts, :exclude_plugins) do
      true -> do_exclude_plugins(opts)
      false -> opts
    end
  end

  defp filter_plugins(opts, ext) do
    Keyword.put(opts, :plugins, plugins_for_ext(opts, ext))
  end

  defp do_exclude_plugins(opts) do
    Keyword.update!(opts, :plugins, fn plugins ->
      exclude = Keyword.fetch!(opts, :exclude_plugins)
      Enum.reject(plugins, fn plugin -> plugin in exclude end)
    end)
  end

  defp update_quoted_to_algebra(opts) do
    case Keyword.get(opts, :plugins, []) do
      [FreedomFormatter | _] = plugins ->
        {quoted_to_algebra, plugins} = quoted_to_algebra(plugins)
        Keyword.merge(opts, quoted_to_algebra: quoted_to_algebra, plugins: plugins)

      _plugins ->
        opts
    end
  end

  defp quoted_to_algebra(plugins) do
    case plugins do
      [FreedomFormatter | plugins] ->
        # For now just a workaround to support the FreedomFormatter.
        {&FreedomFormatter.Formatter.to_algebra/2, plugins}

      plugins ->
        {&Code.quoted_to_algebra/2, plugins}
    end
  end

  defp plugins_for_ext(formatter_opts, ext) do
    formatter_opts
    |> Keyword.get(:plugins, [])
    |> Enum.filter(fn plugin ->
      Code.ensure_loaded?(plugin) and function_exported?(plugin, :features, 1) and
        ext in List.wrap(plugin.features(formatter_opts)[:extensions])
    end)
  end

  defp get_modules(code) do
    code
    |> Zipper.zip()
    |> Zipper.traverse([], fn
      %Zipper{node: {:defmodule, _meta, [module | _args]}} = zipper, acc ->
        {zipper, [concat(module) | acc]}

      zipper, acc ->
        {zipper, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
    |> Enum.filter(&is_atom/1)
  end

  defp concat({:__aliases__, _meta, module}), do: Module.concat(module)

  defp formatter_opts(%Ex{opts: nil}), do: []
  defp formatter_opts(%Ex{opts: opts}), do: Keyword.get(opts, :formatter_opts, [])

  defp sync_quoted?(%Ex{opts: nil}), do: true

  defp sync_quoted?(%Ex{opts: opts}), do: Keyword.get(opts, :sync_quoted, true)
end
