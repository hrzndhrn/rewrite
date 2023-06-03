defmodule Rewrite.Source.Ex do
  # TODO:update moduledoc
  @moduledoc """
  Bla ...
  """

  alias Rewrite.Source
  alias Rewrite.Source.Ex
  alias Mix.Tasks.Format

  defstruct [:quoted, :formatter]

  @behaviour Rewrite.Filetype

  defp new(source) do
    ex = struct!(Ex, quoted: Sourceror.parse_string!(source.content))

    Source.filetype(source, ex)
  end

  @impl Rewrite.Filetype
  def extensions, do: [".ex", ".exs"]

  @impl Rewrite.Filetype
  def from_string(string, path \\ nil, _opts \\ []) do
    string
    |> Source.from_string(path)
    |> new()
  end

  @doc """
  imple
  """
  @impl Rewrite.Filetype
  def read!(path, _opts \\ []) do
    path
    |> Source.read!()
    |> new()
  end

  @impl Rewrite.Filetype
  def update(%Source{}, :path), do: :ok

  def update(%Source{filetype: %Ex{} = ex} = source, :content) do
    quoted = Sourceror.parse_string!(source.content)

    {:ok, %Ex{ex | quoted: quoted}}
  end

  @impl Rewrite.Filetype
  def update(%Source{filetype: %Ex{} = ex} = source, :quoted, quoted) do
    if (ex.quoted == quoted) |> IO.inspect() do
      :ok
    else
      code = format(quoted, source.path, Map.get(source.private, :dot_formatter_opts))

      {:ok, content: code, filetype: %Ex{ex | quoted: quoted}}
    end
  end

  defp format(ast, file, formatter_opts) do
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

    {quoted_to_algebra, plugins} =
      case plugins do
        [FreedomFormatter | plugins] ->
          # For now just a workaround to support the FreedomFormatter.
          {&FreedomFormatter.Formatter.to_algebra/2, plugins}

        plugins ->
          {&Code.quoted_to_algebra/2, plugins}
      end

    formatter_opts =
      formatter_opts ++
        [
          quoted_to_algebra: quoted_to_algebra,
          extension: ext,
          file: file
        ]

    code = Sourceror.to_string(ast, formatter_opts)

    Enum.reduce(plugins, code, fn plugin, code ->
      plugin.format(code, formatter_opts)
    end)
  end

  defp plugins_for_ext(formatter_opts, ext) do
    formatter_opts
    |> Keyword.get(:plugins, [])
    |> Enum.filter(fn plugin ->
      Code.ensure_loaded?(plugin) and function_exported?(plugin, :features, 1) and
        ext in List.wrap(plugin.features(formatter_opts)[:extensions])
    end)
  end
end
