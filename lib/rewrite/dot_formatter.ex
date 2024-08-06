defmodule Rewrite.DotFormatterError do
  defexception [:reason, :path, :not_formatted, :exits]

  def message(%{reason: {:read, :enoent}, path: path}) do
    "Could not read file #{inspect(path)}: no such file or directory"
  end

  def message(%{reason: :dot_formatter_not_found, path: path}) do
    "#{path} not found"
  end

  def message(%{reason: {:subdirectories, subdirectories}, path: path}) do
    "Expected :subdirectories to return a list of directories, got: #{inspect(subdirectories)}, in: #{inspect(path)}"
  end

  def message(%{reason: {:import_deps, import_deps}, path: path}) do
    "Expected :import_deps to return a list of dependencies, got: #{inspect(import_deps)}, in: #{inspect(path)}"
  end

  def message(%{reason: :no_inputs_or_subdirectories, path: path}) do
    "Expected :inputs or :subdirectories key in #{inspect(path)}"
  end

  def message(%{reason: {:dep_not_found, dep}}) do
    """
    Unknown dependency #{inspect(dep)} given to :import_deps in the formatter \
    configuration. Make sure the dependency is listed in your mix.exs for \
    environment :dev and you have run "mix deps.get"\
    """
  end

  def message(%{reason: :format, not_formatted: not_formatted, exits: exits}) do
    not_formatted = Enum.map(not_formatted, fn {file, _input, _formatted} -> file end)

    """
    Format errors - Not formatted: #{inspect(not_formatted)}, Exits: #{inspect(exits)}\
    """
  end
end

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
    path: nil
  ]

  defstruct @formatter_opts ++ @dot_formatter_fields

  def eval(project \\ nil, opts \\ [])

  def eval(opts, []) when is_list(opts), do: eval(nil, opts)

  def eval(project, opts), do: do_eval(project, opts, @root)

  def do_eval(project, opts, path) do
    dot_formatter_path = dot_formatter_path(path, opts)

    with {:ok, term} <- eval_dot_formatter(project, dot_formatter_path),
         {:ok, term} <- validate(term, dot_formatter_path, path),
         {:ok, dot_formatter} <- new(term, dot_formatter_path),
         {:ok, dot_formatter} <- eval_deps(dot_formatter),
         {:ok, dot_formatter} <- eval_subs(dot_formatter, project, opts) do
      load_plugins(dot_formatter)
    end
  end

  defp dot_formatter_path(@root, opts) do
    Keyword.get(opts, :dot_formatter, @defaul_dot_formatter)
  end

  defp dot_formatter_path(path, _opts) do
    Path.join(path, @defaul_dot_formatter)
  end

  defp new(term, dot_formatter_path) do
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

    data = Keyword.merge(formatter_opts, source: source, path: path, plugin_opts: plugin_opts)

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

  @spec format(t() | nil, Rewrite.t() | nil, keyword()) :: :ok | {:error, DotFormatterError.t()}
  def format(dot_formatter \\ nil, project \\ nil, opts \\ [])

  def format(opts, nil, []) when is_list(opts) do
    format(nil, nil, opts)
  end

  def format(%Rewrite{} = project, opts, []) when is_list(opts) do
    with {:ok, dot_formatter} <- eval(project, opts) do
      format(dot_formatter, project, opts)
    end
  end

  def format(%Rewrite{} = project, nil, opts) do
    with {:ok, dot_formatter} <- eval(project, opts) do
      format(dot_formatter, project, opts)
    end
  end

  def format(nil, nil, opts) do
    with {:ok, dot_formatter} <- eval(nil, opts) do
      format(dot_formatter, nil, opts)
    end
  end

  def format(%DotFormatter{} = dot_formatter, nil, opts) do
    dot_formatter
    |> expand()
    |> Task.async_stream(doer(opts), ordered: false, timeout: :infinity)
    |> Enum.reduce({[], []}, &collect_status/2)
    |> check()
  end

  def format(%DotFormatter{} = dot_formatter, %Rewrite{} = project, opts) do
    dot_formatter
    |> expand(project)
    |> Task.async_stream(doer(project, opts), ordered: false, timeout: :infinity)
    |> Enum.reduce({[], []}, &collect_status/2)
    |> update(project, opts)
  end

  defp doer(opts) do
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

  defp doer(project, opts) do
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

  defp update({[], formatted} = result, project, opts) do
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

  def format_file(dot_formatter \\ nil, project \\ nil, file, opts \\ [])

  def format_file(nil, nil, file, opts) do
    with {:ok, content} <- read(file),
         {:ok, formatted} <- format_string!(content, opts) do
      write(file, formatted)
    end
  end

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
      |> Enum.reduce([], fn file, acc ->
        formatter = formatter(dot_formatter, formatter_opts, file)

        if !identity_formatters && formatter == (&Function.identity/1) do
          acc
        else
          if source_path do
            [{file, formatter, source_path(dot_formatter)} | acc]
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
    formatter_opts = formatter_opts(dot_formatter)
    identity_formatters = Keyword.get(opts, :identity_formatters, false)
    source_path = Keyword.get(opts, :source_path, false)

    list =
      Enum.reduce(project, [], fn source, acc ->
        case dot_formatter_for_file(dot_formatter, source.path) do
          nil ->
            acc

          dot_formatter ->
            formatter = formatter(dot_formatter, formatter_opts, source.path)

            if !identity_formatters && formatter == (&Function.identity/1) do
              acc
            else
              if source_path do
                [{source.path, formatter, source_path(dot_formatter)} | acc]
              else
                [{source.path, formatter} | acc]
              end
            end
        end
      end)

    Enum.reduce(dot_formatter.subs, list, fn sub, acc ->
      do_expand(sub, project, opts) ++ acc
    end)
  end

  # TODO: implement check for conflicts
  def check_conflict, do: :todo
  #   result =
  #     Enum.reduce_while(expanded, %{}, fn {path, formatter, dot_formatter_path}, acc ->
  #       if Map.has_key?(acc, path) do
  #         {:halt,
  #          {:error,
  #           %DotFormatterError{
  #             reason: {:conflict, dot_formatter_path, Map.get(acc, path)},
  #             path: path
  #           }}}
  #       else
  #         {:cont, Map.put(acc, path, dot_formatter_path)}
  #       end
  #     end)
  #
  #   case result do
  #     {:error, _error} = error -> error
  #     _else -> {:ok, expanded}
  #   end
  # end

  defp source_path(%DotFormatter{path: path, source: source}), do: Path.join(path, source)

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
    case dot_formatter_for_file(dot_formatter, file) do
      nil ->
        :error

      dot_formatter ->
        formatter_opts = Keyword.merge(formatter_opts(dot_formatter), opts)
        {:ok, formatter(dot_formatter, formatter_opts, file)}
    end
  end

  defp dot_formatter_for_file(dot_formatter, file) do
    match? =
      dot_formatter.inputs
      |> List.wrap()
      |> Enum.any?(fn glob ->
        GlobEx.match?(glob, file)
      end)

    if match? do
      dot_formatter
    else
      Enum.find(dot_formatter.subs, fn sub -> dot_formatter_for_file(sub, file) end)
    end
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

  defp format_string!(string, opts) do
    formatted =
      case Code.format_string!(string, opts) do
        [] -> ""
        formatted -> IO.iodata_to_binary([formatted, ?\n])
      end

    if string == formatted, do: :ok, else: {:ok, formatted}
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

  defp eval_dot_formatter(project \\ nil, path)

  defp eval_dot_formatter(nil, path) do
    if File.regular?(path) do
      {term, _binding} = Code.eval_file(path)
      {:ok, term}
    else
      {:error, %DotFormatterError{reason: :dot_formatter_not_found, path: path}}
    end
  end

  defp eval_dot_formatter(project, path) do
    case Rewrite.source(project, path) do
      {:ok, source} ->
        {term, _binding} = source |> Source.get(:content) |> Code.eval_string()
        {:ok, term}

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
          {:ok, term} ->
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
      [] ->
        {:ok, dot_formatter}

      sigils when is_list(sigils) ->
        sigils =
          sigils
          |> Enum.reverse()
          |> sigils(formatter_opts)

        subs = Enum.map(dot_formatter.subs, &load_plugins/1)
        {:ok, %{dot_formatter | sigils: sigils, subs: subs}}

      error ->
        {:error, error}
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

  defp sigils(sigils, formatter_opts) do
    sigils
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
