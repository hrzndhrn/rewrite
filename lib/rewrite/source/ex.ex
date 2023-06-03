defmodule Rewrite.Source.Ex do
  @moduledoc """
  Bla ...
  """

  # TODO:update moduledoc

  alias Mix.Tasks.Format
  alias Rewrite.Source
  alias Rewrite.Source.Ex
  alias Sourceror.Zipper

  # TODO: save formatter in struct
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
    if ex.quoted == quoted do
      :ok
    else
      code = format(quoted, source.path, Map.get(source.private, :dot_formatter_opts))

      {:ok, content: code, filetype: %Ex{ex | quoted: quoted}}
    end
  end

  def modules(%Source{filetype: %Ex{} = ex}) do
    get_modules(ex.quoted)
  end

  # TODO: add modules/2

  def quoted(%Source{filetype: %Ex{} = ex}) do
    ex.quoted
  end

  # TODO: add quoted/2

  def format(quoted) do
    format(quoted, nil, nil)
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
    |> Enum.filter(&is_atom/1)
  end

  defp concat({:__aliases__, _meta, module}), do: Module.concat(module)

  defp concat(ast), do: ast
end
