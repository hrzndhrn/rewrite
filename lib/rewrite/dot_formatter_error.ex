defmodule Rewrite.DotFormatterError do
  defexception [:reason, :path, :not_formatted, :exits]

  @type t :: %{reason: reason(), path: Path.t(), not_formatted: [Paths.t()], exits: exits()}

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
end
