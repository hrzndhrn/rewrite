defmodule Rewrite.DotFormatterError do
  defexception [:reason, :path, :not_formatted, :exits]

  @type t :: %{reason: reason(), path: Path.t(), not_formatted: [Path.t()], exits: exits()}

  @type reason :: atom() | {atom(), term()}
  @type exits :: any()

  def message(%{reason: {:read, :enoent}, path: path}) do
    "Could not read file #{inspect(path)}: no such file or directory"
  end

  def message(%{reason: :dot_formatter_not_found, path: path}) do
    "#{path} not found"
  end

  def message(%{reason: {:subdirectories, subdirectories}, path: path}) do
    """
    Expected :subdirectories to return a list of directories, \
    got: #{inspect(subdirectories)}, in: #{inspect(path)}\
    """
  end

  def message(%{reason: {:import_deps, import_deps}, path: path}) do
    """
    Expected :import_deps to return a list of dependencies, \
    got: #{inspect(import_deps)}, in: #{inspect(path)}\
    """
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

  def message(%{reason: {:invalid_dot_formatter, [_ | _] = dot_formatters}, path: path}) do
    dot_formatters =
      Enum.map(dot_formatters, fn dot_formatter ->
        Path.join(dot_formatter.path, dot_formatter.source)
      end)

    """
    Multiple dot-formatters specifying the file #{inspect(path)} in their :inputs \
    options, dot-formatters: #{inspect(dot_formatters)}\
    """
  end

  def message(%{reason: {:invalid_dot_formatter, []}, path: path}) do
    "No formatter specifies the file #{inspect(path)} in its :inputs option"
  end

  def message(%{reason: {:undefined_quoted_to_algebra, plugin}}) do
    """
    The plugin #{inspect(plugin)} replaces the Elixir formatter. Therefore, the \
    plugin needs to be replaced with a wrapped plugin that implements the \
    Rewrite.DotFormatter behaviour. 
    A plugin can be replaced by:

      DotFormatter.eval(replace_plugins: [{#{inspect(plugin)}, WrapPlugin}])

    """
  end

  def message(%{reason: %GlobEx.CompileError{} = error}) do
    "Invalid glob #{inspect(error.input)}, #{Exception.message(error)}"
  end

  def message(%{reason: {:invalid_input, input}}) do
    "Invalid input, got: #{inspect(input)}"
  end

  def message(%{reason: {:no_subs, dirs}}) do
    "No sub formatter found in #{inspect(dirs)}"
  end
end
