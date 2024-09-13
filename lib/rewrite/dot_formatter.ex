defmodule Rewrite.DotFormatter do
  # TODO: @moduledoc

  alias Rewrite.DotFormatter
  alias Rewrite.DotFormatterError
  alias Rewrite.Source

  @type formatter :: (term() -> term())

  # TODO: exapnd type and typedoc
  @type t :: map()

  @root "."
  @defaul_dot_formatter ".formatter.exs"

  @formatter_opts [
    :force_do_end_blocks,
    :import_deps,
    :inputs,
    :locals_without_parens,
    :normalize_bitstring_modifiers,
    :normalize_charlists_as_sigils,
    :plugins,
    :sigils,
    :subdirectories
  ]

  @dot_formatter_fields [
    subs: [],
    source: nil,
    plugin_opts: [],
    timestamp: nil,
    path: nil
  ]

  defstruct @formatter_opts ++ @dot_formatter_fields

  def eval(project \\ nil, opts \\ [])

  def eval(opts, []) when is_list(opts), do: eval(nil, opts)

  def eval(project, opts), do: do_eval(project, opts, @root)

  def do_eval(project, opts, path) do
    dot_formatter_path = dot_formatter_path(path, opts)
    opts = Keyword.put(opts, :reload_plugins, false)

    with {:ok, term, timestamp} <- eval_dot_formatter(project, dot_formatter_path),
         {:ok, term} <- validate(term, dot_formatter_path, path),
         {:ok, dot_formatter} <- new(term, dot_formatter_path, timestamp),
         {:ok, dot_formatter} <- eval_deps(dot_formatter),
         {:ok, dot_formatter} <- eval_subs(dot_formatter, project, opts),
         {:ok, dot_formatter} <- update_plugins(dot_formatter, opts) do
      load_plugins(dot_formatter)
    end
  end

  def update(dot_formatter, project \\ nil, opts \\ [])

  def update(%DotFormatter{} = dot_formatter, opts, []) when is_list(opts),
    do: update(dot_formatter, nil, opts)

  def update(%DotFormatter{} = dot_formatter, project, opts) do
    if up_to_date?(dot_formatter, project) do
      {:ok, dot_formatter}
    else
      eval(project, opts)
    end
  end

  defp update_plugins(dot_formatter, opts) do
    updated =
      dot_formatter
      |> remove_plugins(opts[:remove_plugins])
      |> replace_plugins(opts[:replace_plugins])

    if Keyword.get(opts, :reload_plugins, true) do
      reload_plugins(updated, dot_formatter)
    else
      {:ok, updated}
    end
  end

  defp remove_plugins(dot_formatter, nil), do: dot_formatter

  defp remove_plugins(dot_formatter, remove_plugins) when is_list(remove_plugins) do
    map(dot_formatter, fn dot_formatter ->
      Map.update!(dot_formatter, :plugins, fn plugins ->
        Enum.reject(plugins, fn plugin -> plugin in remove_plugins end)
      end)
    end)
  end

  defp replace_plugins(dot_formatter, nil), do: dot_formatter

  defp replace_plugins(dot_formatter, replace_plugins) do
    map(dot_formatter, fn dot_formatter ->
      Map.update!(dot_formatter, :plugins, fn plugins ->
        Enum.map(plugins, fn plugin ->
          Enum.find_value(replace_plugins, plugin, fn {old, new} ->
            if plugin == old, do: new
          end)
        end)
      end)
    end)
  end

  defp reload_plugins(dot_formatter, dot_formatter), do: {:ok, dot_formatter}
  defp reload_plugins(dot_formatter, _old_dot_formatter), do: load_plugins(dot_formatter)

  defp dot_formatter_path(@root, opts) do
    Keyword.get(opts, :dot_formatter, @defaul_dot_formatter)
  end

  defp dot_formatter_path(path, _opts) do
    Path.join(path, @defaul_dot_formatter)
  end

  def new, do: %DotFormatter{inputs: [GlobEx.compile!("**/*")]}

  defp new(term, dot_formatter_path, timestamp) do
    source = Path.basename(dot_formatter_path)

    path =
      dot_formatter_path
      |> Path.dirname()
      |> Path.relative_to("./")

    path = if path == @root, do: "", else: path

    {formatter_opts, plugin_opts} =
      term
      |> Keyword.update(:inputs, nil, fn inputs ->
        inputs
        |> List.wrap()
        |> Enum.map(fn input ->
          path
          |> Path.join(input)
          |> GlobEx.compile!(match_dot: true)
        end)
      end)
      |> Keyword.split(@formatter_opts)

    data =
      formatter_opts
      |> Keyword.put_new(:plugins, [])
      |> Keyword.merge(
        source: source,
        path: path,
        plugin_opts: plugin_opts,
        timestamp: timestamp
      )

    {:ok, struct!(__MODULE__, data)}
  rescue
    error in KeyError ->
      {:error, %DotFormatterError{reason: {:unexpected_format, {error.key, error.term}}}}
  end

  defp validate(term, dot_formatter_path, path) do
    subdirectories = Keyword.get(term, :subdirectories, [])
    inputs = Keyword.get(term, :inputs, [])
    import_deps = Keyword.get(term, :import_deps, [])

    cond do
      not is_list(subdirectories) ->
        {:error,
         %DotFormatterError{
           reason: {:subdirectories, subdirectories},
           path: dot_formatter_path
         }}

      not is_list(import_deps) ->
        {:error,
         %DotFormatterError{
           reason: {:import_deps, import_deps},
           path: dot_formatter_path
         }}

      subdirectories == [] && inputs == [] && path != @root ->
        {:error,
         %DotFormatterError{
           reason: :no_inputs_or_subdirectories,
           path: dot_formatter_path
         }}

      true ->
        {:ok, term}
    end
  end

  @doc """
  Returns the `%DotFormatter{}` struct for the given `path` or `nil` when not 
  found.
  """
  @spec get(t(), path :: Path.t()) :: t()
  def get(%DotFormatter{} = dot_formatter, path) do
    if dot_formatter.path == path do
      dot_formatter
    else
      Enum.find(dot_formatter.subs, fn sub -> get(sub, path) end)
    end
  end

  @doc """
  Returns `true` if the given `dot_formatter` is up to date.

  The function only checks the timestamps in the `dot_formatter` struct with the
  timestamp of the underlying file or source in the `project`.
  """
  @spec up_to_date?(t(), project :: Rewrite.t()) :: boolean()
  def up_to_date?(dot_formatter, project \\ nil) do
    dot_formatter
    |> reduce(fn dot_formatter, acc ->
      up_to_date? = dot_formatter.timestamp == timestamp(dot_formatter, project)
      [up_to_date? | acc]
    end)
    |> Enum.all?()
  end

  defp timestamp(dot_formatter, nil) do
    file = file(dot_formatter)

    case File.stat(file, time: :posix) do
      {:ok, %{mtime: timestamp}} -> timestamp
      {:error, _reason} -> 0
    end
  end

  defp timestamp(dot_formatter, project) do
    file = file(dot_formatter)

    case Rewrite.source(project, file) do
      {:ok, %{timestamp: timestamp}} -> timestamp
      {:error, _reason} -> timestamp(dot_formatter, nil)
    end
  end

  defp file(dot_formatter), do: Path.join(dot_formatter.path, dot_formatter.source)

  # TODO: 
  # * make dot_formatter arg mandatory
  # * write own function for rewrite: format_rewrite/3
  #   * this function get @doc false and will be called by Rewrite.format/3
  @spec format(t() | nil, keyword()) :: :ok | {:error, DotFormatterError.t()}
  # def format(dot_formatter \\ nil, project \\ nil, opts \\ [])
  #
  # def format(opts, nil, []) when is_list(opts) do
  #   format(nil, nil, opts)
  # end
  #
  # def format(%Rewrite{} = project, opts, []) when is_list(opts) do
  #   with {:ok, dot_formatter} <- eval(project, opts) do
  #     format(dot_formatter, project, opts)
  #   end
  # end
  #
  # def format(%DotFormatter{} = dot_formatter, opts, []) when is_list(opts) do
  #   format(dot_formatter, nil, opts)
  # end
  #
  # def format(%Rewrite{} = project, nil, opts) do
  #   with {:ok, dot_formatter} <- eval(project, opts) do
  #     format(dot_formatter, project, opts)
  #   end
  # end
  #
  # def format(nil, nil, opts) do
  #   with {:ok, dot_formatter} <- eval(nil, opts) do
  #     format(dot_formatter, nil, opts)
  #   end
  # end

  def format(%DotFormatter{} = dot_formatter, opts \\ []) when is_list(opts) do
    with {:ok, dot_formatter} <- update_plugins(dot_formatter, opts) do
      dot_formatter
      |> expand(opts)
      |> Task.async_stream(
        async_stream_formatter(opts),
        ordered: false,
        timeout: :infinity
      )
      |> Enum.reduce({[], []}, &collect_status/2)
      |> check()
    end
  end

  # def format(%DotFormatter{} = dot_formatter, %Rewrite{} = project, opts) do
  #   with {:ok, dot_formatter} <- update_plugins(dot_formatter, opts) do
  #     dot_formatter
  #     |> expand(project, opts)
  #     |> Task.async_stream(
  #       async_stream_formatter(project, opts),
  #       ordered: false,
  #       timeout: :infinity
  #     )
  #     |> Enum.reduce({[], []}, &collect_status/2)
  #     |> update_source(project, opts)
  #   end
  # end

  @doc false
  @spec format_rewrite(t(), Rewrite.t(), keyword()) ::
          {:ok, Rewrite.t()} | {:error, DotFormatterError.t()}
  def format_rewrite(%DotFormatter{} = dot_formatter, %Rewrite{} = project, opts \\ []) do
    with {:ok, dot_formatter} <- update_plugins(dot_formatter, opts) do
      dot_formatter
      |> expand(project, opts)
      |> Task.async_stream(
        async_stream_formatter(project, opts),
        ordered: false,
        timeout: :infinity
      )
      |> Enum.reduce({[], []}, &collect_status/2)
      |> update_source(project, opts)
    end
  end

  defp async_stream_formatter(opts) do
    check_formatted? = Keyword.get(opts, :check_formatted, false)

    case check_formatted? do
      false ->
        fn {file, formatter} ->
          try do
            input = File.read!(file)
            output = formatter.(input)
            File.write!(file, output)
          rescue
            exception ->
              {:exit, file, exception, __STACKTRACE__}
          end
        end

      true ->
        fn {file, formatter} ->
          try do
            input = File.read!(file)
            output = formatter.(input)
            if input == output, do: :ok, else: {:not_formatted, {file, input, output}}
          rescue
            exception ->
              {:exit, file, exception, __STACKTRACE__}
          end
        end
    end
  end

  defp async_stream_formatter(project, opts) do
    check_formatted? = Keyword.get(opts, :check_formatted, false)

    case check_formatted? do
      false ->
        fn {file, formatter} ->
          try do
            input = project |> Rewrite.source!(file) |> Source.get(:content)
            output = formatter.(input)
            if input == output, do: :ok, else: {:ok, file, output}
          rescue
            exception ->
              {:exit, file, exception, __STACKTRACE__}
          end
        end

      true ->
        fn {file, formatter} ->
          try do
            input = project |> Rewrite.source!(file) |> Source.get(:content)
            output = formatter.(input)
            if input == output, do: :ok, else: {:not_formatted, {file, input, output}}
          rescue
            exception ->
              {:exit, file, exception, __STACKTRACE__}
          end
        end
    end
  end

  defp collect_status({:ok, :ok}, acc), do: acc

  defp collect_status({:ok, {:ok, file, content}}, {exits, formatted}) do
    {exits, [{file, content} | formatted]}
  end

  defp collect_status({:ok, {:exit, file, error, _meta}}, {exits, not_formatted}) do
    {[{file, error} | exits], not_formatted}
  end

  defp collect_status({:ok, {:not_formatted, file}}, {exits, not_formatted}) do
    {exits, [file | not_formatted]}
  end

  defp check({[], []}), do: :ok

  defp check({exits, not_formatted}) do
    # TODO: error handling refactoring
    {:error, %DotFormatterError{reason: :format, not_formatted: not_formatted, exits: exits}}
  end

  # TODO: check exits

  defp update_source({[], formatted} = result, project, opts) do
    if Keyword.get(opts, :check_formatted, false) do
      check(result)
    else
      by = Keyword.get(opts, :by, Rewrite)

      project =
        Enum.reduce(formatted, project, fn {path, content}, project ->
          Rewrite.update!(project, path, fn source ->
            Source.update(source, by, :content, content)
          end)
        end)

      {:ok, project}
    end
  end

  def format_file(%DotFormatter{} = dot_formatter, file, opts \\ []) do
    with {:ok, content} <- read(file),
         {:ok, formatted} <- format_string(dot_formatter, file, content, opts) do
      write(file, formatted)
    end
  end

  defp read(path) do
    with {:error, reason} <- File.read(path) do
      {:error, %DotFormatterError{reason: {:read, reason}, path: path}}
    end
  end

  defp write(path, content) do
    with {:error, reason} <- File.write(path, content) do
      {:error, %DotFormatterError{reason: {:write, reason}, path: path}}
    end
  end

  # TODO:
  # * add @doc false
  # * call this function by Rewrite.format_source/3
  def format_source(%DotFormatter{} = dot_formatter, %Rewrite{} = project, file, opts \\ []) do
    Rewrite.update(project, file, fn source ->
      content = Source.get(source, :content)

      with {:ok, formatted} <- format_string(dot_formatter, file, content, opts) do
        Source.update(source, :content, formatted)
      end
    end)
  end

  def format_string(dot_formatter, file, string, opts \\ []) do
    opts = Keyword.put_new(opts, :file, file)

    with {:ok, formatter} <- formatter_for_file(dot_formatter, file, opts) do
      {:ok, formatter.(string)}
    end
  rescue
    error in SyntaxError -> {:error, error}
  end

  # TODO: def format_quoted/4

  def formatter_opts(dot_formatter) do
    dot_formatter
    |> Map.take(@formatter_opts)
    |> Enum.filter(fn {_key, vlaue} -> not is_nil(vlaue) end)
    |> Enum.concat(dot_formatter.plugin_opts)
  end

  @spec expand(t(), Rewrite.t() | nil, keyword()) :: [{Path.t(), formatter()}]
  def expand(dot_formatter, project \\ nil, opts \\ [])

  def expand(dot_formatter, opts, []) when is_list(opts) do
    dot_formatter |> do_expand(nil, opts)
  end

  def expand(dot_formatter, project, opts) do
    dot_formatter |> do_expand(project, opts)
  end

  defp do_expand(%DotFormatter{} = dot_formatter, nil, opts) do
    formatter_opts = formatter_opts(dot_formatter)
    identity_formatters = Keyword.get(opts, :identity_formatters, false)
    source_path = Keyword.get(opts, :source_path, false)

    list =
      dot_formatter
      |> files()
      |> filter_by_modified_after(opts)
      |> Enum.reduce([], fn file, acc ->
        formatter = formatter(dot_formatter, formatter_opts, file)

        if !identity_formatters && formatter == (&Function.identity/1) do
          acc
        else
          if source_path do
            [{file, source_path(dot_formatter)} | acc]
          else
            [{file, formatter} | acc]
          end
        end
      end)

    Enum.reduce(dot_formatter.subs, list, fn sub, acc ->
      do_expand(sub, nil, opts) ++ acc
    end)
  end

  defp do_expand(%DotFormatter{} = dot_formatter, project, opts) do
    identity_formatters = Keyword.get(opts, :identity_formatters, false)
    source_path = Keyword.get(opts, :source_path, false)

    project
    |> filter_by_modified_after(opts)
    |> Enum.reduce([], fn source, acc ->
      case dot_formatters_for_file(dot_formatter, source.path) do
        [] ->
          acc

        dot_formatters ->
          dot_formatters
          |> Enum.map(fn dot_formatter ->
            formatter_opts = formatter_opts(dot_formatter)
            formatter = formatter(dot_formatter, formatter_opts, source.path)

            if !identity_formatters && formatter == (&Function.identity/1) do
              acc
            else
              if source_path do
                {source.path, source_path(dot_formatter)}
              else
                {source.path, formatter}
              end
            end
          end)
          |> Enum.concat(acc)
      end
    end)
  end

  defp filter_by_modified_after(input, nil), do: input

  defp filter_by_modified_after(input, opts) when is_list(opts) do
    filter_by_modified_after(input, Keyword.get(opts, :modified_after))
  end

  defp filter_by_modified_after(files, timestamp) when is_list(files) do
    Enum.filter(files, fn file -> File.stat!(file, time: :posix).mtime > timestamp end)
  end

  defp filter_by_modified_after(%Rewrite{} = project, timestamp) do
    Enum.filter(project, fn source -> source.timestamp > timestamp end)
  end

  def conflicts(dot_formatter \\ nil, project \\ nil)

  def conflicts(nil, nil) do
    with {:ok, dot_formatter} <- eval() do
      conflicts(dot_formatter, nil)
    end
  end

  def conflicts(%Rewrite{} = project, nil) do
    with {:ok, dot_formatter} <- eval(project) do
      conflicts(dot_formatter, project)
    end
  end

  def conflicts(%DotFormatter{} = dot_formatter, nil) do
    dot_formatter
    |> expand(source_path: true)
    |> do_conflicts()
  end

  def conflicts(%DotFormatter{} = dot_formatter, %Rewrite{} = project) do
    dot_formatter
    |> expand(project, source_path: true)
    |> do_conflicts()
  end

  defp do_conflicts(expanded) do
    expanded
    |> Enum.group_by(
      fn {path, _dot_formatter_path} -> path end,
      fn {_path, dot_formatter_path} -> dot_formatter_path end
    )
    |> Enum.filter(fn {_path, dot_formatter_paths} ->
      length(dot_formatter_paths) > 1
    end)
  end

  defp source_path(%DotFormatter{path: path, source: source}), do: Path.join(path, source)

  # TODO: 
  # * make dot_formatter arg mandatory
  # * add option input. possible values: :string, :quoted. default: :string
  def formatter_for_file(dot_formatter \\ nil, file, opts \\ [])

  def formatter_for_file(file, opts, []) when is_binary(file) and is_list(opts) do
    formatter_for_file(nil, file, opts)
  end

  def formatter_for_file(nil, file, opts) do
    with {:ok, dot_formatter} <- eval() do
      formatter_for_file(dot_formatter, file, opts)
    end
  end

  def formatter_for_file(dot_formatter, file, opts) do
    case dot_formatters_for_file(dot_formatter, file) do
      [dot_formatter] ->
        formatter_opts = Keyword.merge(formatter_opts(dot_formatter), opts)
        {:ok, formatter(dot_formatter, formatter_opts, file)}

      _dot_formatters ->
        # TODO: error handling
        {:error, :todo}
    end
  end

  @doc """
  Returns a `%DotFormatter{}` struct with the result of invoking `fun` on the 
  given `dot_formatter` and any sub-formatters.
  """
  @spec map(DotFormatter.t(), (DotFormatter.t() -> DotFormatter.t())) :: DotFormatter.t()
  def map(%DotFormatter{} = dot_formatter, fun) do
    dot_formatter = fun.(dot_formatter)

    Map.update!(dot_formatter, :subs, fn subs ->
      Enum.map(subs, fn sub -> map(sub, fun) end)
    end)
  end

  def reduce(%DotFormatter{} = dot_formatter, acc \\ [], fun) do
    acc = fun.(dot_formatter, acc)

    Enum.reduce(dot_formatter.subs, acc, fn sub, acc ->
      reduce(sub, acc, fun)
    end)
  end

  defp dot_formatters_for_file(dot_formatter, file, acc \\ []) do
    match? =
      dot_formatter.inputs
      |> List.wrap()
      |> Enum.any?(fn glob ->
        GlobEx.match?(glob, file)
      end)

    acc = if match?, do: [dot_formatter | acc], else: acc

    Enum.reduce(dot_formatter.subs, acc, fn sub, acc ->
      dot_formatters_for_file(sub, file, acc)
    end)

    # if match? do
    #   dot_formatter
    # else
    #   Enum.find(dot_formatter.subs, fn sub -> dot_formatters_for_file(sub, file) end)
    # end
  end

  defp formatter(dot_formatter, formatter_opts, file) do
    ext = Path.extname(file)
    plugins = plugins_for_extension(dot_formatter.plugins, formatter_opts, ext)

    cond do
      plugins != [] ->
        plugin_formatter(plugins, [extension: ext, file: file] ++ formatter_opts)

      ext in [".ex", ".exs"] ->
        elixir_formatter([file: file] ++ formatter_opts)

      true ->
        &Function.identity/1
    end
  end

  defp plugins_for_extension(nil, _formatter_opts, _ext), do: []

  defp plugins_for_extension(plugins, formatter_opts, ext) do
    Enum.filter(plugins, fn plugin ->
      Code.ensure_loaded?(plugin) and function_exported?(plugin, :features, 1) and
        ext in List.wrap(plugin.features(formatter_opts)[:extensions])
    end)
  end

  defp plugin_formatter(plugins, formatter_opts) do
    fn input ->
      Enum.reduce(plugins, input, fn plugin, input ->
        plugin.format(input, formatter_opts)
      end)
    end
  end

  defp elixir_formatter(formatter_opts) do
    fn input ->
      case Code.format_string!(input, formatter_opts) do
        [] -> ""
        formatted -> IO.iodata_to_binary([formatted, ?\n])
      end
    end
  end

  defp files(dot_formatter) do
    dot_formatter.inputs
    |> List.wrap()
    |> Enum.flat_map(&GlobEx.ls/1)
    |> Enum.filter(&File.regular?/1)
  end

  defp eval_dot_formatter(project \\ nil, path)

  defp eval_dot_formatter(nil, path) do
    if File.regular?(path) do
      {term, _binding} = Code.eval_file(path)
      timestamp = File.stat!(path, time: :posix).mtime
      {:ok, term, timestamp}
    else
      {:error, %DotFormatterError{reason: :dot_formatter_not_found, path: path}}
    end
  end

  defp eval_dot_formatter(project, path) do
    case Rewrite.source(project, path) do
      {:ok, source} ->
        {term, _binding} = source |> Source.get(:content) |> Code.eval_string()
        {:ok, term, source.timestamp}

      {:error, %Rewrite.Error{reason: :nosource}} ->
        eval_dot_formatter(nil, path)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp eval_deps(%{import_deps: nil} = dot_formatter), do: {:ok, dot_formatter}

  defp eval_deps(%{import_deps: deps} = dot_formatter) do
    with {:ok, deps_paths} <- deps_paths(deps),
         {:ok, locals_without_parens} <- locals_without_parens(deps_paths) do
      dot_formatter =
        Map.update!(dot_formatter, :locals_without_parens, fn list ->
          list |> List.wrap() |> Enum.concat(locals_without_parens) |> Enum.uniq()
        end)

      {:ok, dot_formatter}
    end
  end

  defp locals_without_parens(deps_paths) do
    result =
      Enum.reduce_while(deps_paths, [], fn {dep, path}, acc ->
        case eval_dot_formatter(path) do
          {:ok, term, _timestamp} ->
            locals_without_parens = term[:export][:locals_without_parens] || []
            {:cont, acc ++ locals_without_parens}

          {:error, %DotFormatterError{reason: :dot_formatter_not_found}} ->
            {:halt,
             {:error,
              %DotFormatterError{
                reason: {:dep_not_found, dep},
                path: Path.relative_to(path, File.cwd!())
              }}}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end)

    case result do
      {:error, _reason} = error -> error
      locals_without_parens -> {:ok, locals_without_parens}
    end
  end

  defp eval_subs(dot_formatter, project, opts) do
    subdirectories = dot_formatter.subdirectories || []

    result =
      Enum.reduce_while(subdirectories, [], fn subdirectory, acc ->
        with {:ok, dirs} <- dirs(dot_formatter.path, subdirectory),
             {:ok, subs} <- do_eval_subs(project, opts, dirs) do
          {:cont, subs ++ acc}
        else
          error -> {:halt, error}
        end
      end)

    case result do
      {:error, _reason} = error -> error
      result -> {:ok, %DotFormatter{dot_formatter | subs: result}}
    end
  end

  defp do_eval_subs(project, opts, dirs) do
    result =
      Enum.reduce_while(dirs, [], fn dir, acc ->
        if dir |> Path.join(@defaul_dot_formatter) |> File.regular?() do
          case do_eval(project, opts, dir) do
            {:ok, dot_formatter} -> {:cont, [dot_formatter | acc]}
            error -> {:halt, error}
          end
        else
          {:cont, acc}
        end
      end)

    case result do
      {:error, _reason} = error -> error
      [] -> {:error, :empty}
      subs when is_list(subs) -> {:ok, subs}
    end
  end

  defp load_plugins(%{plugins: nil} = dot_formatter), do: {:ok, dot_formatter}

  defp load_plugins(%{plugins: plugins} = dot_formatter) do
    if plugins != [] do
      Mix.Task.run("loadpaths", [])
    end

    if not Enum.all?(plugins, &Code.ensure_loaded?/1) do
      Mix.Task.run("compile", [])
    end

    formatter_opts = formatter_opts(dot_formatter)

    result =
      Enum.reduce_while(plugins, [], fn plugin, acc ->
        cond do
          not Code.ensure_loaded?(plugin) ->
            {:halt, %DotFormatterError{reason: {:plugin_not_found, plugin}}}

          not function_exported?(plugin, :features, 1) ->
            {:halt, %DotFormatterError{reason: {:undefined_features, plugin}}}

          true ->
            {:cont, get_sigils(plugin, formatter_opts) ++ acc}
        end
      end)

    case result do
      sigils when is_list(sigils) ->
        with {:ok, subs} <- load_plugins(dot_formatter.subs, []) do
          sigils = sigils(sigils, formatter_opts)
          {:ok, %{dot_formatter | sigils: sigils, subs: subs}}
        end

      error ->
        {:error, error}
    end
  end

  defp load_plugins([], subs), do: {:ok, Enum.reverse(subs)}

  defp load_plugins([sub | tail], subs) do
    with {:ok, dot_formatter} <- load_plugins(sub) do
      load_plugins(tail, [dot_formatter | subs])
    end
  end

  defp get_sigils(plugin, formatter_opts) do
    if Code.ensure_loaded?(plugin) and function_exported?(plugin, :features, 1) do
      formatter_opts
      |> plugin.features()
      |> Keyword.get(:sigils, [])
      |> List.wrap()
      |> Enum.map(fn sigil -> {sigil, plugin} end)
    else
      []
    end
  end

  defp sigils([], _formatter_opts), do: nil

  defp sigils(sigils, formatter_opts) do
    sigils
    |> Enum.reverse()
    |> Enum.group_by(
      fn {sigil, _plugin} -> sigil end,
      fn {_sigil, plugin} -> plugin end
    )
    |> Enum.map(fn {sigil, plugins} ->
      fun = fn input, opts ->
        Enum.reduce(plugins, input, fn plugin, input ->
          plugin.format(input, opts ++ formatter_opts)
        end)
      end

      {sigil, fun}
    end)
  end

  defp dirs(path, glob) do
    glob = Path.join(path, glob)

    case GlobEx.compile(glob, match_dot: true) do
      {:ok, glob} ->
        {:ok, glob |> GlobEx.ls() |> Enum.filter(&File.dir?/1)}

      {:error, reason} ->
        # TODO: add error handling
        IO.inspect(reason, label: :todo)
    end
  end

  defp deps_paths(deps) do
    paths = Mix.Project.deps_paths()

    result =
      Enum.reduce_while(deps, [], fn dep, acc ->
        case Map.fetch(paths, dep) do
          :error -> {:halt, %DotFormatterError{reason: {:dep_not_found, dep}}}
          {:ok, path} -> {:cont, [{dep, Path.join(path, @defaul_dot_formatter)} | acc]}
        end
      end)

    if is_list(result), do: {:ok, result}, else: {:error, result}
  end
end
