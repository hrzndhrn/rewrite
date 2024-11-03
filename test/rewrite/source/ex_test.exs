defmodule Rewrite.Source.ExTest do
  use RewriteCase

  alias Rewrite.DotFormatter
  alias Rewrite.Source
  alias Rewrite.Source.Ex

  doctest Rewrite.Source.Ex

  describe "read/1" do
    test "creates new source" do
      assert %Source{filetype: ex} = Source.Ex.read!("test/fixtures/source/simple.ex")
      assert %Ex{quoted: {:defmodule, _meta, _args}} = ex
    end
  end

  describe "from_string/3" do
    test "creates an ex source from string" do
      assert %Source{} = source = Source.Ex.from_string(":a")
      assert is_struct(source.filetype, Ex)
      assert source.path == nil
      assert source.owner == Rewrite
    end

    test "creates an ex source from string with path" do
      assert %Source{} = source = Source.Ex.from_string(":a", path: "test.ex")
      assert source.path == "test.ex"
    end

    test "creates an ex source from string with path and opts" do
      assert %Source{} = source = Source.Ex.from_string(":a", path: "test.ex", owner: Meins)
      assert source.owner == Meins
    end
  end

  describe "handle_update/2" do
    test "updates quoted" do
      source = Source.Ex.from_string(":a", path: "a.exs")
      quoted = Sourceror.parse_string!(":x")
      source = Source.update(source, :quoted, quoted)

      assert source.content == ":x\n"
    end

    test "updates quoted with function" do
      source = Source.Ex.from_string(":a", path: "a.exs")

      source =
        Source.update(source, :quoted, fn quoted ->
          {:__block__, meta, [atom]} = quoted
          {:__block__, meta, [{:ok, atom}]}
        end)

      assert source.content == "{:ok, :a}\n"
    end

    test "updates quoted with resync_quoted: true" do
      source = Source.Ex.from_string(":a", path: "a.exs")

      {:ok, quoted} =
        Code.string_to_quoted("""
          defmodule Test do
            def test, do: :test
          end
        """)

      source = Source.update(source, :quoted, quoted)

      assert Source.get(source, :quoted) != quoted
    end

    test "updates quoted with resync_quoted: false" do
      source = Source.Ex.read!("test/fixtures/source/simple.ex", resync_quoted: false)

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

    test "updates quoted with :dot_formatter" do
      dot_formatter = DotFormatter.from_formatter_opts(locals_without_parens: [bar: 1])
      source = Source.Ex.from_string("", path: "a.ex")
      quoted = Sourceror.parse_string!("foo bar baz")

      source = Source.update(source, :quoted, quoted, dot_formatter: dot_formatter)

      assert source.content == "foo(bar baz)\n"
    end

    test "updateds content" do
      source = Source.Ex.from_string(":a", path: "a.exs")
      assert Source.get(source, :quoted) == Sourceror.parse_string!(":a")

      source = Source.update(source, :content, ":x")
      assert Source.get(source, :quoted) == Sourceror.parse_string!(":x")
    end

    test "updates content without changing" do
      source = Source.Ex.from_string(":a", path: "a.exs")
      source = Source.update(source, :content, ":a")
      assert Source.get(source, :content) == ":a"
    end

    test "raises an error" do
      source = Source.Ex.from_string(":a")
      message = ~r/unexpected.reserved.word:.end/m

      assert_raise SyntaxError, message, fn ->
        Source.update(source, :content, ":ok end")
      end
    end

    @tag :tmp_dir
    test "updates content with the rewrite dot formatter", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": """
          foo bar baz
          """
        )

        rewrite = Rewrite.new!("**/*", dot_formatter: DotFormatter.read!())
        dot_formatter = Rewrite.dot_formatter(rewrite)

        assert read!(rewrite, "a.ex") == "foo bar baz\n"

        source = Rewrite.source!(rewrite, "a.ex")
        source = Source.update(source, :content, "foo bar baz", dot_formatter: dot_formatter)
        assert Source.get(source, :content) == "foo bar baz"

        quoted = Sourceror.parse_string!("foo baz bar")
        source = Source.update(source, :quoted, quoted, dot_formatter: dot_formatter)
        assert Source.get(source, :content) == "foo baz(bar)\n"
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

  describe "modules/2" do
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

  test "inspect" do
    source = Source.Ex.from_string(":a")
    assert inspect(source.filetype) == "#Rewrite.Source.Ex<.ex,.exs>"
  end
end
