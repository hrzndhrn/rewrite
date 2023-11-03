defmodule Rewrite.Source.ExTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Rewrite.Source
  alias Rewrite.Source.Ex

  doctest Rewrite.Source.Ex

  describe "read/1" do
    test "creates new source" do
      assert %Source{filetype: ex} = Source.Ex.read!("test/fixtures/source/simple.ex")
      assert %Ex{quoted: {:defmodule, _meta, _args}} = ex
    end
  end

  describe "handle_update/2" do
    test "updates quoted" do
      source = Source.Ex.from_string(":a", "a.exs")
      quoted = Sourceror.parse_string!(":x")
      source = Source.update(source, :quoted, quoted)

      assert source.content == ":x\n"
    end

    test "updates quoted with sync_quoted: true" do
      source = Source.Ex.from_string(":a", "a.exs")

      {:ok, quoted} =
        Code.string_to_quoted("""
          defmodule Test do
            def test, do: :test
          end
        """)

      source = Source.update(source, :quoted, quoted)

      assert Source.get(source, :quoted) != quoted
    end

    test "updates quoted with sync_quoted: false" do
      source = Source.Ex.read!("test/fixtures/source/simple.ex", sync_quoted: false)

      {:ok, quoted} =
        Code.string_to_quoted("""
          defmodule Test do
            def test, do: :test
          end
        """)

      source = Source.update(source, :quoted, quoted)

      assert source.filetype.quoted == quoted
      assert Source.get(source, :quoted) == quoted
    end

    test "updateds content" do
      source = Source.Ex.from_string(":a", "a.exs")
      assert Source.get(source, :quoted) == Sourceror.parse_string!(":a")

      source = Source.update(source, :content, ":x")
      assert Source.get(source, :quoted) == Sourceror.parse_string!(":x")
    end

    test "updates fromatter" do
      source = Source.Ex.from_string(":a", "a.exs")
      formatter = source.filetype.formatter

      source = Source.update(source, :content, ":x")
      assert source.filetype.formatter == formatter

      source = Source.update(source, :path, "x.exs")
      refute source.filetype.formatter == formatter
    end

    test "raises an error" do
      source = Source.Ex.from_string(":a")
      message = ~r/nofile:1:5: unexpected reserved word: end/

      assert_raise SyntaxError, message, fn ->
        Source.update(source, :content, ":ok end")
      end
    end
  end

  describe "handle_update/3" do
    test "updates source with quoted expression" do
      source = Source.Ex.from_string(":a")
      quoted = Sourceror.parse_string!(":x")
      assert %Source{content: content} = Source.update(source, :quoted, quoted)
      assert content == ":x\n"
    end

    test "formats content" do
      source = Source.Ex.from_string(":a")

      quoted =
        Sourceror.parse_string!("""
        defmodule       Foo    do
            end
        """)

      assert %Source{content: content} = Source.update(source, :quoted, quoted)

      assert content == """
             defmodule Foo do
             end
             """
    end

    test "does not updates" do
      code = ":a"
      source = Source.Ex.from_string(code)
      quoted = Sourceror.parse_string!(code)
      assert source = Source.update(source, :quoted, quoted)
      assert Source.updated?(source) == false
    end
  end

  describe "module/2" do
    test "retruns a list with one module" do
      source = Source.Ex.read!("test/fixtures/source/simple.ex")

      assert Source.Ex.modules(source) == [MyApp.Simple]
    end

    test "retruns a list of modules" do
      source = Source.Ex.read!("test/fixtures/source/double.ex")

      assert Source.Ex.modules(source) == [Double.Bar, Double.Foo]
    end

    test "retruns an empty list" do
      source = Source.Ex.from_string(":a")

      assert Source.Ex.modules(source) == []
    end

    test "returns a list of modules for an older version" do
      source = Source.Ex.read!("test/fixtures/source/simple.ex")
      source = Source.update(source, :content, ":a")

      assert Source.Ex.modules(source) == []
      assert Source.Ex.modules(source, 2) == []
      assert Source.Ex.modules(source, 1) == [MyApp.Simple]
    end
  end

  describe "format/1" do
    test "formats with plugin FakeFormatter" do
      plugins = [FakeFormatter]

      source = ":a" |> Source.Ex.from_string() |> Source.Ex.put_formatter_opts(plugins: plugins)

      {_source, io} =
        with_io(fn ->
          Source.Ex.format(source)
        end)

      assert io == "FakeFormatter.format/2\n"
    end

    test "formats with plugin FreedomFormatter" do
      # The FreedomFormatter is also a fake and returns always the same code.
      plugins = [FreedomFormatter]

      source =
        """
        [
             1,
        ]
        """
        |> Source.Ex.from_string()
        |> Source.Ex.put_formatter_opts(plugins: plugins)

      {code, io} =
        with_io(fn ->
          Source.Ex.format(source)
        end)

      assert io == "FreedomFormatter.Formatter.to_algebra/2\n"

      assert code == """
             [
               1,
             ]
             """
    end

    test "formats with plugin FakeFormatter and excludes FreedomFormatter" do
      plugins = [FreedomFormatter, FakeFormatter]
      exclude = [FreedomFormatter]

      source =
        ":a"
        |> Source.Ex.from_string(":a")
        |> Source.Ex.put_formatter_opts(plugins: plugins)
        |> Source.Ex.merge_formatter_opts(exclude_plugins: exclude)

      {_code, io} =
        with_io(fn ->
          Source.Ex.format(source)
        end)

      assert io == "FakeFormatter.format/2\n"
    end

    test "formats with plugins FreedomFormatter and FakeFormatter" do
      {_source, io} =
        with_io(fn ->
          ":a"
          |> Source.Ex.from_string()
          |> Source.Ex.put_formatter_opts(plugins: [FreedomFormatter, FakeFormatter])
          |> Source.Ex.format()
        end)

      assert io == "FreedomFormatter.Formatter.to_algebra/2\nFakeFormatter.format/2\n"
    end

    test "formats with plugin FakeFormatter and FreedomFormatter" do
      {_source, io} =
        with_io(fn ->
          ":a"
          |> Source.Ex.from_string()
          |> Source.Ex.put_formatter_opts(plugins: [FakeFormatter, FreedomFormatter])
          |> Source.Ex.format()
        end)

      assert io == "FakeFormatter.format/2\nFreedomFormatter.format/2\n"
    end
  end

  describe "format/2" do
    test "formats with plugin FakeFormatter" do
      plugins = [FakeFormatter]

      source = Source.Ex.from_string(":a")

      {_source, io} =
        with_io(fn ->
          Source.Ex.format(source, plugins: plugins)
        end)

      assert io == "FakeFormatter.format/2\n"
    end

    test "formats with plugin FreedomFormatter" do
      # The FreedomFormatter is also a fake and returns always the same code.
      plugins = [FreedomFormatter]

      source =
        Source.Ex.from_string("""
        [
             1,
        ]
        """)

      {code, io} =
        with_io(fn ->
          Source.Ex.format(source, plugins: plugins)
        end)

      assert io == "FreedomFormatter.Formatter.to_algebra/2\n"

      assert code == """
             [
               1,
             ]
             """
    end

    test "formats with plugin FakeFormatter and excludes FreedomFormatter" do
      plugins = [FreedomFormatter, FakeFormatter]
      exclude = [FreedomFormatter]

      source = Source.Ex.from_string(":a")

      {_code, io} =
        with_io(fn ->
          Source.Ex.format(source, plugins: plugins, exclude_plugins: exclude)
        end)

      assert io == "FakeFormatter.format/2\n"
    end

    test "formats with plugins FreedomFormatter and FakeFormatter" do
      {_source, io} =
        with_io(fn ->
          ":a"
          |> Source.Ex.from_string()
          |> Source.Ex.format(plugins: [FreedomFormatter, FakeFormatter])
        end)

      assert io == "FreedomFormatter.Formatter.to_algebra/2\nFakeFormatter.format/2\n"
    end

    test "formats with plugin FakeFormatter and FreedomFormatter" do
      {_source, io} =
        with_io(fn ->
          ":a"
          |> Source.Ex.from_string()
          |> Source.Ex.format(plugins: [FakeFormatter, FreedomFormatter])
        end)

      assert io == "FakeFormatter.format/2\nFreedomFormatter.format/2\n"
    end
  end
end
