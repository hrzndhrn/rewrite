defmodule Rewrite.DotFormatterTest do
  use ExUnit.Case, async: false

  import GlobEx.Sigils

  alias Rewrite.DotFormatter
  alias Rewrite.DotFormatterError
  alias Rewrite.Source

  @time 1_723_308_800

  defmodule Elixir.SigilWPlugin do
    @behaviour Mix.Tasks.Format

    @impl true
    def features(opts) do
      assert opts[:from_formatter_exs] == :yes
      [sigils: [:W]]
    end

    @impl true
    def format(contents, opts) do
      assert opts[:from_formatter_exs] == :yes
      assert opts[:sigil] == :W
      assert opts[:modifiers] == ~c"abc"
      assert opts[:line] == 2
      assert opts[:file] =~ ~r/a\.ex$/
      contents |> String.split(~r/\s/) |> Enum.join("\n")
    end
  end

  defmodule Elixir.ExtensionWPlugin do
    @behaviour Mix.Tasks.Format

    @impl true
    def features(opts) do
      assert opts[:from_formatter_exs] == :yes
      [extensions: ~w(.w), sigils: [:W]]
    end

    @impl true
    def format(contents, opts) do
      assert opts[:from_formatter_exs] == :yes
      assert opts[:extension] == ".w"
      assert opts[:file] =~ ~r/a\.w$/
      assert [W: sigil_fun] = opts[:sigils]
      assert is_function(sigil_fun, 2)
      contents |> String.split(~r/\s/) |> Enum.join("\n")
    end
  end

  defmodule Elixir.NewlineToDotPlugin do
    @behaviour Mix.Tasks.Format

    @impl true
    def features(opts) do
      assert opts[:from_formatter_exs] == :yes
      [extensions: ~w(.w), sigils: [:W]]
    end

    @impl true
    def format(contents, opts) do
      assert opts[:from_formatter_exs] == :yes

      cond do
        opts[:extension] ->
          assert opts[:extension] == ".w"
          assert opts[:file] =~ ~r/a\.w$/
          assert [W: sigil_fun] = opts[:sigils]
          assert is_function(sigil_fun, 2)

        opts[:sigil] ->
          assert opts[:sigil] == :W
          assert opts[:inputs] == [~g|a.ex|d]
          assert opts[:modifiers] == ~c"abc"

        true ->
          flunk("Plugin not loading in correctly.")
      end

      contents |> String.replace("\n", ".")
    end
  end

  defmacrop in_tmp(context, do: block) do
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

  @moduletag :tmp_dir

  describe "format/2" do
    test "uses inputs and configuration from .formatter.exs", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.ex"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        foo bar(baz)
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected

        # update .formatter.exs

        write!(".formatter.exs", """
        [inputs: ["a.ex"]]
        """)

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        foo(bar(baz))
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected
      end
    end

    test "does not cache inputs from .formatter.exs", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: Path.wildcard("{a,b}.ex"),
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        foo bar(baz)
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected

        # add b.ex

        write!("b.ex", """
        bar baz bat
        """)

        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        assert Rewrite.source(rewrite, "b.ex") ==
                 {:error, %Rewrite.Error{reason: :nosource, path: "b.ex"}}

        assert DotFormatter.format() == :ok
        rewrite = Rewrite.new!("**/*")
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        bar(baz(bat))
        """

        assert read!("b.ex") == expected
        assert read!(rewrite, "b.ex") == expected
      end
    end

    test "expands patterns in inputs from .formatter.exs", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["{a,.b}.ex"]
          ]
          """,
          "a.ex" => """
          foo bar
          """,
          ".b.ex" => """
          foo bar
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        foo(bar)
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected

        expected = """
        foo(bar)
        """

        assert read!(".b.ex") == expected
        assert read!(rewrite, ".b.ex") == expected
      end
    end

    test "uses sigil plugins from .formatter.exs", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.ex"],
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex" => """
          if true do
            ~W'''
            foo bar baz
            '''abc
          end
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        if true do
          ~W'''
          foo
          bar
          baz
          '''abc
        end
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected
      end
    end

    test "uses extension plugins from .formatter.exs", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.w"],
            plugins: [ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        foo
        bar
        baz
        """

        assert read!("a.w") == expected
        assert read!(rewrite, "a.w") == expected
      end
    end

    test "uses multiple plugins from .formatter.exs targeting the same file extension", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.w"],
            plugins: [ExtensionWPlugin, NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = "foo.bar.baz."

        assert read!("a.w") == expected
        assert read!(rewrite, "a.w") == expected
      end
    end

    test "uses multiple plugins from .formatter.exs with the same file extension in declared order",
         context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin, ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = "foo\nbar\nbaz."

        assert read!("a.w") == expected
        assert read!(rewrite, "a.w") == expected
      end
    end

    test "uses multiple plugins from .formatter.exs targeting the same sigil", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.ex"],
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex" => """
          def sigil_test(assigns) do
            ~W"foo bar baz\n"abc
          end
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        def sigil_test(assigns) do
          ~W"foo\nbar\nbaz."abc
        end
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected
      end
    end

    test "uses multiple plugins from .formatter.exs with the same sigil in declared order",
         context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.ex"],
            plugins: [SigilWPlugin, NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex" => """
          def sigil_test(assigns) do
            ~W"foo bar baz"abc
          end
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        def sigil_test(assigns) do
          ~W"foo.bar.baz"abc
        end
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected
      end
    end

    test "uses remaining plugin after removing another", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin, ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format(remove_plugins: [NewlineToDotPlugin]) == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite, remove_plugins: [NewlineToDotPlugin])

        expected = "foo\nbar\nbaz\n"

        assert read!("a.w") == expected
        assert read!(rewrite, "a.w") == expected
      end
    end

    test "uses remaining plugin after removing another with pre eval", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin, ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        {:ok, dot_formatter} = DotFormatter.eval()

        assert DotFormatter.format(dot_formatter, remove_plugins: [NewlineToDotPlugin]) == :ok

        assert {:ok, rewrite} =
                 DotFormatter.format(dot_formatter, rewrite, remove_plugins: [NewlineToDotPlugin])

        expected = "foo\nbar\nbaz\n"

        assert read!("a.w") == expected
        assert read!(rewrite, "a.w") == expected
      end
    end

    test "uses replaced plugin", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format(replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}]) ==
                 :ok

        assert {:ok, rewrite} =
                 DotFormatter.format(rewrite,
                   replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}]
                 )

        expected = "foo\nbar\nbaz\n"

        assert read!("a.w") == expected
        assert read!(rewrite, "a.w") == expected
      end
    end

    test "uses replaced plugin with pre eval", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        {:ok, dot_formatter} = DotFormatter.eval()

        assert DotFormatter.format(dot_formatter,
                 replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}]
               ) ==
                 :ok

        assert {:ok, rewrite} =
                 DotFormatter.format(dot_formatter, rewrite,
                   replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}]
                 )

        expected = "foo\nbar\nbaz\n"

        assert read!("a.w") == expected
        assert read!(rewrite, "a.w") == expected
      end
    end

    test "uses inputs and configuration from :dot_formatter", context do
      in_tmp context do
        write!(%{
          "custom_formatter.exs" => """
          [
            inputs: ["a.ex"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format(dot_formatter: "custom_formatter.exs") == :ok

        assert {:ok, rewrite} =
                 DotFormatter.format(rewrite, dot_formatter: "custom_formatter.exs")

        expected = """
        foo bar(baz)
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected
      end
    end

    test "uses exported configuration from subdirectories", context do
      in_tmp context do
        # We also create a directory called li to ensure files
        # from lib won't accidentally match on li.
        code = """
        my_fun :foo, :bar
        other_fun :baz, :bang
        """

        write!(%{
          ".formatter.exs" => """
          [subdirectories: ["li", "lib"]]
          """,
          "li/.formatter.exs" => """
          [inputs: "**/*", locals_without_parens: [other_fun: 2]]
          """,
          "lib/.formatter.exs" => """
          [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
          """,
          "li/a.ex" => code,
          "lib/a.ex" => code,
          "lib/b.ex" => code,
          "other/a.ex" => code
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        my_fun(:foo, :bar)
        other_fun :baz, :bang
        """

        assert read!("li/a.ex") == expected
        assert read!(rewrite, "li/a.ex") == expected

        expected = """
        my_fun :foo, :bar
        other_fun(:baz, :bang)
        """

        assert read!("lib/a.ex") == expected
        assert read!(rewrite, "lib/a.ex") == expected

        assert read!("lib/b.ex") == code
        assert read!(rewrite, "lib/b.ex") == code

        assert read!("other/a.ex") == code
        assert read!(rewrite, "other/a.ex") == code
      end
    end

    @tag :project
    test "uses exported configuration from dependencies", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [import_deps: [:my_dep]]
          """,
          "a.ex" => """
          my_fun :foo, :bar
          """,
          "deps/my_dep/.formatter.exs" => """
          [export: [locals_without_parens: [my_fun: 2]]]
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        my_fun :foo, :bar
        """

        assert read!("a.ex") == expected
        assert read!(rewrite, "a.ex") == expected
      end
    end

    @tag :project
    test "uses exported configuration from dependencies and subdirectories", context do
      in_tmp context do
        write!(%{
          "deps/my_dep/.formatter.exs" => """
          [export: [locals_without_parens: [my_fun: 2]]]
          """,
          ".formatter.exs" => """
          [subdirectories: ["lib"]]
          """,
          "lib/.formatter.exs" => """
          [subdirectories: ["*"]]
          """,
          "lib/sub/.formatter.exs" => """
          [inputs: "a.ex", import_deps: [:my_dep]]
          """,
          "lib/sub/a.ex" => """
          my_fun :foo, :bar
          other_fun :baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        my_fun :foo, :bar
        other_fun(:baz)
        """

        assert read!("lib/sub/a.ex") == expected
        assert read!(rewrite, "lib/sub/a.ex") == expected

        # Add a new entry to "lib" and it also gets picked.

        write!(%{
          "lib/extra/.formatter.exs" => """
          [inputs: "a.ex", locals_without_parens: [other_fun: 1]]
          """,
          "lib/extra/a.ex" => """
          my_fun :foo, :bar
          other_fun :baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format() == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite)

        expected = """
        my_fun(:foo, :bar)
        other_fun :baz
        """

        assert read!("lib/extra/a.ex") == expected
        assert read!(rewrite, "lib/extra/a.ex") == expected
      end
    end

    test "with SyntaxError when parsing invalid source file", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [inputs: "a.ex"]
          """,
          "a.ex" => """
          defmodule <%= module %>.Bar do end
          """
        })

        error = %DotFormatterError{
          reason: :format,
          not_formatted: [],
          exits: [
            {"a.ex",
             %SyntaxError{
               file: "a.ex",
               line: 1,
               column: 13,
               snippet: "defmodule <%= module %>.Bar do end",
               description: "syntax error before: '='"
             }}
          ]
        }

        assert DotFormatter.format() == {:error, error}

        assert Exception.message(error) == """
               Format errors - \
               Not formatted: [], \
               Exits: [{"a.ex", %SyntaxError{\
               file: "a.ex", line: 1, column: 13, \
               snippet: "defmodule <%= module %>.Bar do end", \
               description: "syntax error before: '='"}}]\
               """
      end
    end

    test "uses inputs and configuration from .formatter.exs (check formatted)", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.ex"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex" => """
          foo bar baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        error = %DotFormatterError{
          reason: :format,
          not_formatted: [{"a.ex", "foo bar baz\n", "foo bar(baz)\n"}],
          exits: []
        }

        assert DotFormatter.format(check_formatted: true) == {:error, error}
        assert DotFormatter.format(rewrite, check_formatted: true) == {:error, error}

        assert Exception.message(error) == """
               Format errors - \
               Not formatted: ["a.ex"], \
               Exits: []\
               """

        # update a.ex

        write!("a.ex", """
        foo bar(baz)
        """)

        assert DotFormatter.format(check_formatted: true) == :ok
        assert {:error, _error} = DotFormatter.format(rewrite, check_formatted: true)

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format(rewrite, check_formatted: true) == :ok
      end
    end

    test "formats files modified after", context do
      in_tmp context do
        unformatted = """
        foo bar baz
        """

        formatted = """
        foo bar(baz)
        """

        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["*"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex" => unformatted,
          "b.ex" => unformatted
        })

        now = now()
        File.touch!("a.ex", now - 1234)
        File.touch!("b.ex", now - 12)

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format(modified_after: now - 123) == :ok
        assert {:ok, rewrite} = DotFormatter.format(rewrite, modified_after: now - 123)

        assert read!("a.ex") == unformatted
        assert read!(rewrite, "a.ex") == unformatted
        assert read!("b.ex") == formatted
        assert read!(rewrite, "b.ex") == formatted
      end
    end
  end

  describe "format_file/4" do
    test "doesn't format empty files into line breaks", context do
      in_tmp context do
        write!("a.exs", "")

        assert DotFormatter.format_file("a.exs") == :ok
        assert read!("a.exs") == ""
      end
    end

    test "removes line breaks in an empty file", context do
      in_tmp context do
        write!("a.exs", "  \n  \n  ")
        DotFormatter.format_file("a.exs")

        assert DotFormatter.format_file("a.exs") == :ok
        assert read!("a.exs") == ""
      end
    end

    test "returns an error if the file doesn't exist" do
      assert DotFormatter.format_file("nonexistent.exs") == {
               :error,
               %Rewrite.DotFormatterError{
                 reason: {:read, :enoent},
                 path: "nonexistent.exs"
               }
             }
    end
  end

  describe "eval/3" do
    test "reads the default formatter", context do
      in_tmp context do
        write!(
          ".formatter.exs",
          """
          [inputs: ["*.ex"]]
          """,
          @time
        )

        assert {:ok, dot_formatter} = DotFormatter.eval()
        assert dot_formatter.inputs == [~g|*.ex|d]

        assert dot_formatter == %Rewrite.DotFormatter{
                 inputs: [~g|*.ex|d],
                 plugins: [],
                 subs: [],
                 source: ".formatter.exs",
                 plugin_opts: [],
                 timestamp: @time,
                 path: ""
               }

        rewrite = Rewrite.new!("**/*")
        File.rm!(".formatter.exs")

        assert DotFormatter.eval(rewrite) == {:ok, dot_formatter}
      end
    end

    test "reads the updated formatter", context do
      in_tmp context do
        write!(".formatter.exs", """
        [inputs: ["*.ex"]]
        """)

        project =
          "*"
          |> Rewrite.new!()
          |> Rewrite.update!(".formatter.exs", fn source ->
            Source.update(source, :content, """
            [inputs: ["*.ex", "*.exs"]]
            """)
          end)

        assert {:ok, dot_formatter} = DotFormatter.eval(project)
        assert dot_formatter.inputs == [~g|*.ex|d, ~g|*.exs|d]
        assert dot_formatter.source == ".formatter.exs"
      end
    end

    @tag :project
    test "reads exported configuration from dependencies", context do
      in_tmp context do
        write!(".formatter.exs", """
        [import_deps: [:my_dep], inputs: "*"]
        """)

        write!("deps/my_dep/.formatter.exs", """
        [export: [locals_without_parens: [my_fun: 2]]]
        """)

        assert {:ok, dot_formatter} = DotFormatter.eval()
        assert dot_formatter.locals_without_parens == [my_fun: 2]
      end
    end

    test "reads dot formatters from subdirectories", context do
      in_tmp context do
        write!(
          %{
            ".formatter.exs" => """
            [subdirectories: ["priv", "lib"]]
            """,
            "priv/.formatter.exs" => """
            [inputs: "a.ex", locals_without_parens: [other_fun: 2]]
            """,
            "lib/.formatter.exs" => """
            [inputs: "**/*", locals_without_parens: [my_fun: 2]]
            """
          },
          @time
        )

        assert {:ok, dot_formatter} = DotFormatter.eval()

        assert dot_formatter == %Rewrite.DotFormatter{
                 plugins: [],
                 source: ".formatter.exs",
                 path: "",
                 subdirectories: ["priv", "lib"],
                 timestamp: @time,
                 subs: [
                   %Rewrite.DotFormatter{
                     subs: [],
                     plugins: [],
                     inputs: [~g|lib/**/*|d],
                     locals_without_parens: [my_fun: 2],
                     source: ".formatter.exs",
                     timestamp: @time,
                     path: "lib"
                   },
                   %Rewrite.DotFormatter{
                     subs: [],
                     plugins: [],
                     inputs: [~g|priv/a.ex|d],
                     locals_without_parens: [other_fun: 2],
                     source: ".formatter.exs",
                     timestamp: @time,
                     path: "priv"
                   }
                 ]
               }
      end
    end

    test "reads dot formatters from subdirectories with glob", context do
      in_tmp context do
        write!(
          %{
            ".formatter.exs" => """
            [subdirectories: ["*"]]
            """,
            "foo.exs" => "# causes no error",
            "foo/bar.exs" => "# causes no error",
            "priv/.formatter.exs" => """
            [inputs: "a.ex", locals_without_parens: [other_fun: 2]]
            """,
            "lib/.formatter.exs" => """
            [inputs: "**/*", locals_without_parens: [my_fun: 2]]
            """
          },
          @time
        )

        assert {:ok, dot_formatter} = DotFormatter.eval()

        assert dot_formatter == %Rewrite.DotFormatter{
                 source: ".formatter.exs",
                 path: "",
                 plugins: [],
                 timestamp: @time,
                 subdirectories: ["*"],
                 subs: [
                   %Rewrite.DotFormatter{
                     inputs: [~g|priv/a.ex|d],
                     locals_without_parens: [other_fun: 2],
                     plugins: [],
                     timestamp: @time,
                     source: ".formatter.exs",
                     path: "priv"
                   },
                   %Rewrite.DotFormatter{
                     inputs: [~g|lib/**/*|d],
                     locals_without_parens: [my_fun: 2],
                     plugins: [],
                     timestamp: @time,
                     source: ".formatter.exs",
                     path: "lib"
                   }
                 ]
               }
      end
    end

    test "reads multiple plugins from .formatter.exs targeting the same sigil", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["a.ex"],
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex" => """
          def sigil_test(assigns) do
            ~W"foo bar baz\n"abc
          end
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert {:ok, dot_formatter} = DotFormatter.eval()
        assert DotFormatter.eval(rewrite) == {:ok, dot_formatter}
        assert %{sigils: [W: fun]} = dot_formatter
        assert is_function(fun, 2)
      end
    end

    test "reads sigil plugins from .formatter.exs", context do
      in_tmp context do
        write!(".formatter.exs", """
        [
          inputs: ["a.ex"],
          plugins: [SigilWPlugin],
          from_formatter_exs: :yes
        ]
        """)

        assert {:ok, dot_formatter} = DotFormatter.eval()
        assert %{sigils: [W: fun]} = dot_formatter
        assert is_function(fun, 2)
      end
    end

    test "reads exported configuration from subdirectories", context do
      in_tmp context do
        write!(
          %{
            ".formatter.exs" => """
            [subdirectories: ["li", "lib"]]
            """,
            "li/.formatter.exs" => """
            [inputs: "**/*", locals_without_parens: [other_fun: 2]]
            """,
            "lib/.formatter.exs" => """
            [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
            """
          },
          @time
        )

        assert DotFormatter.eval() ==
                 {:ok,
                  %Rewrite.DotFormatter{
                    subdirectories: ["li", "lib"],
                    source: ".formatter.exs",
                    timestamp: @time,
                    plugins: [],
                    path: "",
                    subs: [
                      %Rewrite.DotFormatter{
                        inputs: [~g|lib/a.ex|d],
                        locals_without_parens: [my_fun: 2],
                        timestamp: @time,
                        plugins: [],
                        source: ".formatter.exs",
                        path: "lib"
                      },
                      %Rewrite.DotFormatter{
                        inputs: [~g|li/**/*|d],
                        locals_without_parens: [other_fun: 2],
                        timestamp: @time,
                        plugins: [],
                        source: ".formatter.exs",
                        path: "li"
                      }
                    ]
                  }}
      end
    end

    test "removes plugin", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        })

        assert {:ok, dot_formatter} = DotFormatter.eval(remove_plugins: [SigilWPlugin])
        assert dot_formatter.plugins == [NewlineToDotPlugin]
        assert [W: fun] = dot_formatter.sigils
        assert is_function(fun, 2)

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.eval(rewrite, remove_plugins: [SigilWPlugin]) == {:ok, dot_formatter}
      end
    end

    test "removes plugins", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        })

        assert {:ok, dot_formatter} =
                 DotFormatter.eval(remove_plugins: [SigilWPlugin, NewlineToDotPlugin])

        assert dot_formatter.plugins == []
        assert dot_formatter.sigils == nil

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.eval(rewrite, remove_plugins: [SigilWPlugin, NewlineToDotPlugin]) ==
                 {:ok, dot_formatter}
      end
    end

    test "removes plugin from sub", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            subdirectories: ["lib", "priv"]
          ]
          """,
          "lib/.formatter.exs" => """
          [
            inputs: "*",
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "priv/.formatter.exs" => """
          [
            inputs: "*",
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        })

        assert {:ok, dot_formatter} = DotFormatter.eval(remove_plugins: [SigilWPlugin])

        priv_dot_formatter = DotFormatter.get(dot_formatter, "priv")
        assert priv_dot_formatter.plugins == []
        assert priv_dot_formatter.sigils == nil

        lib_dot_formatter = DotFormatter.get(dot_formatter, "lib")
        assert lib_dot_formatter.plugins == [NewlineToDotPlugin]
        assert lib_dot_formatter.sigils != nil

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.eval(rewrite, remove_plugins: [SigilWPlugin]) == {:ok, dot_formatter}
      end
    end

    test "replaces plugin", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        })

        assert {:ok, dot_formatter} =
                 DotFormatter.eval(replace_plugins: [{SigilWPlugin, NewlineToDotPlugin}])

        assert dot_formatter.plugins == [NewlineToDotPlugin]
        assert [W: fun] = dot_formatter.sigils
        assert is_function(fun, 2)

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.eval(rewrite, replace_plugins: [{SigilWPlugin, NewlineToDotPlugin}]) ==
                 {:ok, dot_formatter}
      end
    end

    test "replaces plugin in sub", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            subdirectories: ["lib", "priv"]
          ]
          """,
          "lib/.formatter.exs" => """
          [
            inputs: "*",
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "priv/.formatter.exs" => """
          [
            inputs: "*",
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        })

        assert {:ok, dot_formatter} =
                 DotFormatter.eval(replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}])

        lib_dot_formatter = DotFormatter.get(dot_formatter, "lib")
        assert lib_dot_formatter.plugins == [ExtensionWPlugin]
        assert lib_dot_formatter.sigils != nil

        priv_dot_formatter = DotFormatter.get(dot_formatter, "priv")
        assert priv_dot_formatter.plugins == [SigilWPlugin]
        assert priv_dot_formatter.sigils != nil

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.eval(rewrite,
                 replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}]
               ) ==
                 {:ok, dot_formatter}
      end
    end

    test "validates :subdirectories", context do
      in_tmp context do
        write!(".formatter.exs", """
        [subdirectories: "oops"]
        """)

        assert {:error,
                %DotFormatterError{
                  reason: {:subdirectories, "oops"},
                  path: ".formatter.exs"
                } = error} = DotFormatter.eval()

        message = """
        Expected :subdirectories to return a list of directories, got: "oops", in: ".formatter.exs"\
        """

        assert Exception.message(error) == message
      end
    end

    test "validates subdirectories in :subdirectories", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [subdirectories: ["lib"]]
          """,
          "lib/.formatter.exs" => """
          []
          """
        })

        assert {:error,
                %Rewrite.DotFormatterError{
                  reason: :no_inputs_or_subdirectories,
                  path: "lib/.formatter.exs"
                } = error} = DotFormatter.eval()

        message = """
        Expected :inputs or :subdirectories key in "lib/.formatter.exs"\
        """

        assert Exception.message(error) == message
      end
    end

    test "validates :import_deps", context do
      in_tmp context do
        write!(".formatter.exs", """
        [import_deps: "oops"]
        """)

        assert {:error,
                %DotFormatterError{
                  reason: {:import_deps, "oops"},
                  path: ".formatter.exs"
                } = error} = DotFormatter.eval()

        message = """
        Expected :import_deps to return a list of dependencies, got: "oops", in: ".formatter.exs"\
        """

        assert Exception.message(error) == message
      end
    end

    @tag :project
    test "validates dependencies in :import_deps", context do
      in_tmp context do
        write!(".formatter.exs", """
        [import_deps: [:my_dep]]
        """)

        assert {:error,
                %Rewrite.DotFormatterError{
                  reason: {:dep_not_found, :my_dep},
                  path: "deps/my_dep/.formatter.exs"
                } = error} = DotFormatter.eval()

        message = """
        Unknown dependency :my_dep given to :import_deps in the formatter \
        configuration. Make sure the dependency is listed in your mix.exs for \
        environment :dev and you have run "mix deps.get"\
        """

        assert Exception.message(error) == message

        write!(".formatter.exs", """
        [import_deps: [:nonexistent_dep]]
        """)

        assert {:error,
                %DotFormatterError{
                  reason: {:dep_not_found, :nonexistent_dep}
                } = error} = DotFormatter.eval()

        message = """
        Unknown dependency :nonexistent_dep given to :import_deps in the formatter \
        configuration. Make sure the dependency is listed in your mix.exs for \
        environment :dev and you have run "mix deps.get"\
        """

        assert Exception.message(error) == message
      end
    end

    test "in an empty dir", context do
      in_tmp context do
        assert {:error,
                %DotFormatterError{
                  reason: :dot_formatter_not_found,
                  path: ".formatter.exs"
                } = error} = DotFormatter.eval()

        assert Exception.message(error) == ".formatter.exs not found"
      end
    end
  end

  describe "update/3" do
    test "does not update the file if it's up to date", context do
      in_tmp context do
        write!(".formatter.exs", """
        [inputs: ["*.ex"]]
        """)

        {:ok, dot_formatter} = DotFormatter.eval()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, updated} = DotFormatter.update(dot_formatter)
        assert dot_formatter == updated

        assert {:ok, updated} = DotFormatter.update(dot_formatter, rewrite)
        assert dot_formatter == updated
      end
    end

    test "updates the dot_formatter", context do
      in_tmp context do
        write!(".formatter.exs", """
        [inputs: ["*.ex"]]
        """, @time)

        {:ok, dot_formatter} = DotFormatter.eval()
        rewrite = Rewrite.new!("**/*")

        File.touch!(".formatter.exs")

        assert {:ok, updated} = DotFormatter.update(dot_formatter)
        assert dot_formatter != updated

        assert {:ok, updated} = DotFormatter.update(dot_formatter, rewrite)
        assert dot_formatter == updated

        rewrite = Rewrite.update!(rewrite, ".formatter.exs", &Source.touch/1)

        assert {:ok, updated} = DotFormatter.update(dot_formatter, rewrite)
        assert dot_formatter != updated
      end
    end

    test "updates the dot_formatter with opts", context do
      in_tmp context do
        write!(".formatter.exs", """
        [
          inputs: ["*.ex"],
          plugins: [SigilWPlugin],
          from_formatter_exs: :yes
        ]
        """, @time)

        {:ok, dot_formatter} = DotFormatter.eval()
        rewrite = Rewrite.new!("**/*")

        assert dot_formatter.plugins == [SigilWPlugin]

        File.touch!(".formatter.exs")
        rewrite = Rewrite.update!(rewrite, ".formatter.exs", &Source.touch/1)
        opts = [remove_plugins: [SigilWPlugin]]

        assert {:ok, updated} = DotFormatter.update(dot_formatter, opts)
        assert updated.plugins == []

        assert {:ok, updated} = DotFormatter.update(dot_formatter, rewrite, opts)
        assert updated.plugins == []
      end
    end
  end

  describe "up_to_date?/2" do
    test "returns true", context do
      in_tmp context do
        write!(".formatter.exs", """
        [inputs: ["*.ex"]]
        """)

        {:ok, dot_formatter} = DotFormatter.eval()
        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.up_to_date?(dot_formatter) == true
        assert DotFormatter.up_to_date?(dot_formatter, rewrite) == true
      end
    end

    test "returns true whith a dot_formatter containing subs", context do
      in_tmp context do
        write!(".formatter.exs", """
        [subdirectories: ["priv", "lib"]]
        """)

        write!("priv/.formatter.exs", """
        [inputs: "a.ex", locals_without_parens: [other_fun: 2]]
        """)

        write!("lib/.formatter.exs", """
        [inputs: "**/*", locals_without_parens: [my_fun: 2]]
        """)

        {:ok, dot_formatter} = DotFormatter.eval()
        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.up_to_date?(dot_formatter) == true
        assert DotFormatter.up_to_date?(dot_formatter, rewrite) == true
      end
    end

    test "returns false", context do
      in_tmp context do
        write!(
          ".formatter.exs",
          """
          [inputs: ["*.ex"]]
          """,
          @time
        )

        {:ok, dot_formatter} = DotFormatter.eval()
        rewrite = Rewrite.new!("**/*")

        File.touch!(".formatter.exs")
        assert DotFormatter.up_to_date?(dot_formatter) == false
        assert DotFormatter.up_to_date?(dot_formatter, rewrite) == true

        rewrite = Rewrite.update!(rewrite, ".formatter.exs", &Source.touch/1)
        assert DotFormatter.up_to_date?(dot_formatter, rewrite) == false
      end
    end

    test "returns false with dot_formatter containing subs", context do
      in_tmp context do
        write!(
          %{
            ".formatter.exs" => """
            [subdirectories: ["priv", "lib"]]
            """,
            "priv/.formatter.exs" => """
            [inputs: "a.ex", locals_without_parens: [other_fun: 2]]
            """,
            "lib/.formatter.exs" => """
            [inputs: "**/*", locals_without_parens: [my_fun: 2]]
            """
          },
          @time
        )

        {:ok, dot_formatter} = DotFormatter.eval()
        rewrite = Rewrite.new!("**/*")

        File.touch!("priv/.formatter.exs")
        assert DotFormatter.up_to_date?(dot_formatter) == false
        assert DotFormatter.up_to_date?(dot_formatter, rewrite) == true

        rewrite = Rewrite.update!(rewrite, "lib/.formatter.exs", &Source.touch/1)
        assert DotFormatter.up_to_date?(dot_formatter, rewrite) == false
      end
    end
  end

  describe "conflicts/2" do
    test "returns an empty list", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [subdirectories: ["li", "lib"]]
          """,
          "li/.formatter.exs" => """
          [inputs: "**/*"]
          """,
          "lib/.formatter.exs" => """
          [inputs: "a.ex"]
          """,
          "lib/a.ex" => """
          # comment
          """,
          "li/a.ex" => """
          # comment
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.conflicts() == []
        assert DotFormatter.conflicts(rewrite) == []
      end
    end

    test "returns a list of conflicts", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [inputs: "lib/**/*.{ex,exs}", subdirectories: ["lib", "foo"]]
          """,
          "lib/.formatter.exs" => """
          [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
          """,
          "foo/.formatter.exs" => """
          [inputs: "../lib/a.ex", locals_without_parens: [my_fun: 2]]
          """,
          "lib/a.ex" => """
          my_fun :foo, :bar
          other_fun :baz
          """
        })

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.conflicts() == [
                 {"lib/a.ex", ["lib/.formatter.exs", ".formatter.exs"]}
               ]

        assert DotFormatter.conflicts(rewrite) == [
                 {"lib/a.ex", ["lib/.formatter.exs", ".formatter.exs"]}
               ]
      end
    end
  end

  describe "formatter_for_file/2" do
    test "uses exported configuration from subdirectories", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [subdirectories: ["li", "lib"]]
          """,
          "li/.formatter.exs" => """
          [inputs: "**/*", locals_without_parens: [other_fun: 2]]
          """,
          "lib/.formatter.exs" => """
          [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
          """
        })

        assert {:ok, formatter} = DotFormatter.formatter_for_file("li/extra/a.ex")
        assert formatter.("other_fun  1,  2") == "other_fun 1, 2\n"

        assert {:ok, formatter} =
                 DotFormatter.formatter_for_file("li/extra/a.ex",
                   locals_without_parens: [my_fun: 1]
                 )

        assert formatter.("other_fun  1,  2") == "other_fun(1, 2)\n"
        assert formatter.("my_fun   1") == "my_fun 1\n"

        assert DotFormatter.formatter_for_file("lib/extra/a.ex") == {:error, :todo}
      end
    end

    test "uses exported configuration from subs" do
      dot_formatter = %DotFormatter{
        subdirectories: ["li", "lib"],
        source: ".formatter.exs",
        path: ".",
        subs: [
          %DotFormatter{
            inputs: [~g|lib/a.ex|d],
            locals_without_parens: [my_fun: 2],
            source: ".formatter.exs",
            path: "lib"
          },
          %DotFormatter{
            inputs: [~g|li/**/*|d],
            locals_without_parens: [other_fun: 2],
            source: ".formatter.exs",
            path: "li"
          }
        ]
      }

      assert {:ok, formatter} = DotFormatter.formatter_for_file(dot_formatter, "li/extra/a.ex")
      assert formatter.("other_fun  1,  2") == "other_fun 1, 2\n"

      assert DotFormatter.formatter_for_file(dot_formatter, "lib/extra/a.ex") == {:error, :todo}

      assert {:ok, formatter} =
               DotFormatter.formatter_for_file(
                 dot_formatter,
                 "li/extra/a.ex",
                 locals_without_parens: [my_fun: 1]
               )

      assert formatter.("other_fun  1,  2") == "other_fun(1, 2)\n"
      assert formatter.("my_fun  1") == "my_fun 1\n"
    end
  end

  defp format_with_deps_app do
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

  defp write!(files, content \\ nil, time \\ nil)

  defp write!(files, time, nil) when is_integer(time), do: write!(files, nil, time)

  defp write!(files, nil, time) do
    Enum.map(files, fn {file, content} -> write!(file, content, time) end)
  end

  defp write!(path, content, time) do
    dir = Path.dirname(path)
    unless dir == ".", do: path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, content)
    if is_integer(time), do: File.touch!(path, @time)
    path
  end

  defp read!(path), do: File.read!(path)

  defp read!(rewrite, path) do
    rewrite |> Rewrite.source!(path) |> Source.get(:content)
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_unix()
end
