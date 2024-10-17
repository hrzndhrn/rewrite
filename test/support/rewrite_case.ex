defmodule TestHelpers do
  @moduledoc false

  @time 1_723_308_800
  alias Rewrite.Source

  defmacro in_tmp(context, do: block) do
    quote do
      File.cd!(unquote(context).tmp_dir, fn ->
        Mix.Project.pop()

        if unquote(context)[:project] do
          Mix.Project.push(format_with_deps_app())
        end

        unquote(block)
      end)
    end
  end

  def test_time, do: @time

  def format_with_deps_app do
    nr = :erlang.unique_integer([:positive])

    {{:module, module, _bin, _meta}, _binding} =
      Code.eval_string("""
      defmodule FormatWithDepsApp#{nr} do
        def project do
          [
            app: :format_with_deps_#{nr},
            version: "0.1.0",
            deps: [{:my_dep, "0.1.0", path: "deps/my_dep"}]
          ]
        end
      end
      """)

    module
  end

  def write!(time \\ @time, files) when is_list(files) do
    Enum.map(files, fn {file, content} -> file |> to_string() |> write!(content, time) end)
  end

  defp write!(path, content, time) do
    dir = Path.dirname(path)
    unless dir == ".", do: path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
    if is_integer(time), do: File.touch!(path, @time)
    path
  end

  def read!(path), do: File.read!(path)

  def read!(rewrite, path) do
    rewrite |> Rewrite.source!(path) |> Source.get(:content)
  end

  def touched?(path, time), do: File.stat!(path, time: :posix).mtime > time

  def touched?(rewrite, path, time) do
    source = Rewrite.source!(rewrite, path)
    source.timestamp > time
  end

  def now, do: DateTime.utc_now() |> DateTime.to_unix()
end

defmodule RewriteCase do
  @moduledoc false

  use ExUnit.CaseTemplate, async: false

  using do
    quote do
      import TestHelpers
      require TestHelpers
    end
  end
end
