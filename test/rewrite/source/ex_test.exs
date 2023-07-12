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

      assert source.content == ":x"
    end

    test "updateds content" do
      source = Source.Ex.from_string(":a", "a.exs")
      assert Source.Ex.quoted(source) == Sourceror.parse_string!(":a")

      source = Source.update(source, :content, ":x")
      assert Source.Ex.quoted(source) == Sourceror.parse_string!(":x")
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
      assert content == ":x"
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
             end\
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

  describe "fomrat/2" do
    test "formats with plugin FakeFormatter" do
      plugins = [FakeFormatter]

      source = Source.Ex.from_string(":a")

      {_source, io} = with_io(fn -> Source.Ex.format(source, plugins: plugins) end)

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

      {source, io} = with_io(fn -> Source.Ex.format(source, plugins: plugins) end)

      assert io == "FreedomFormatter.Formatter.to_algebra/2\n"

      assert Source.content(source) == """
             [
               1,
             ]\
             """
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
