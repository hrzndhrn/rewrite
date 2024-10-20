defmodule Rewrite.DotFormatterTest do
  use RewriteCase, async: false

  import GlobEx.Sigils

  alias Rewrite.DotFormatter
  alias Rewrite.DotFormatterError
  alias Rewrite.Source

  @time test_time()
  @moduletag :tmp_dir

  describe "format/2" do
    test "formats file", context do
      in_tmp context do
        write!("a.ex": "foo bar")

        assert DotFormatter.format(DotFormatter.new()) == :ok
        assert read!("a.ex") == "foo(bar)\n"
      end
    end

    test "uses inputs and configuration from .formatter.exs", context do
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

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               foo bar(baz)
               """

        # update .formatter.exs

        write!(
          ".formatter.exs": """
          [inputs: ["a.ex"]]
          """
        )

        # with the old dot_formatter
        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               foo bar(baz)
               """

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               foo(bar(baz))
               """
      end
    end

    test "caches inputs from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: Path.wildcard("{a,b}.ex"),
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               foo bar(baz)
               """

        # add b.ex

        write!(
          "b.ex": """
          bar baz bat
          """
        )

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("b.ex") == """
               bar baz bat
               """

        {:ok, dot_formatter} = DotFormatter.read()
        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("b.ex") == """
               bar(baz(bat))
               """
      end
    end

    test "expands patterns in inputs from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["{a,.b}.ex"]
          ]
          """,
          "a.ex": """
          foo bar
          """,
          ".b.ex": """
          foo bar
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               foo(bar)
               """

        assert read!(".b.ex") == """
               foo(bar)
               """
      end
    end

    test "uses sigil plugins from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex": """
          if true do
            ~W'''
            foo bar baz
            '''abc
          end
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               if true do
                 ~W'''
                 foo
                 bar
                 baz
                 '''abc
               end
               """
      end
    end

    test "uses extension plugins from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.w") == """
               foo
               bar
               baz
               """
      end
    end

    test "uses multiple plugins from .formatter.exs targeting the same file extension", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [ExtensionWPlugin, NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.w") == "foo.bar.baz."
      end
    end

    test "uses multiple plugins from .formatter.exs with the same file extension in declared order",
         context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin, ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.w") == "foo\nbar\nbaz."
      end
    end

    test "uses multiple plugins from .formatter.exs targeting the same sigil", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex": """
          def sigil_test(assigns) do
            ~W"foo bar baz\n"abc
          end
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               def sigil_test(assigns) do
                 ~W"foo\nbar\nbaz."abc
               end
               """
      end
    end

    test "uses multiple plugins from .formatter.exs with the same sigil in declared order",
         context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            plugins: [SigilWPlugin, NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex": """
          def sigil_test(assigns) do
            ~W"foo bar baz"abc
          end
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               def sigil_test(assigns) do
                 ~W"foo.bar.baz"abc
               end
               """
      end
    end

    test "uses remaining plugin after removing another", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin, ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter, remove_plugins: [NewlineToDotPlugin]) == :ok

        assert read!("a.w") == "foo\nbar\nbaz\n"
      end
    end

    test "uses remaining plugin after removing another in read", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin, ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read(remove_plugins: [NewlineToDotPlugin])

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.w") == "foo\nbar\nbaz\n"
      end
    end

    test "uses replaced plugin", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter,
                 replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}]
               ) == :ok

        assert read!("a.w") == "foo\nbar\nbaz\n"
      end
    end

    test "uses replaced plugin in read", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} =
          DotFormatter.read(replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}])

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.w") == "foo\nbar\nbaz\n"
      end
    end

    test "uses inputs and configuration from :dot_formatter", context do
      in_tmp context do
        write!(
          "custom_formatter.exs": """
          [
            inputs: ["a.ex"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read(dot_formatter: "custom_formatter.exs")

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               foo bar(baz)
               """
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

        write!(
          ".formatter.exs": """
          [subdirectories: ["li", "lib"]]
          """,
          "li/.formatter.exs": """
          [inputs: "**/*", locals_without_parens: [other_fun: 2]]
          """,
          "lib/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
          """,
          "li/a.ex": code,
          "lib/a.ex": code,
          "lib/b.ex": code,
          "other/a.ex": code
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("li/a.ex") == """
               my_fun(:foo, :bar)
               other_fun :baz, :bang
               """

        assert read!("lib/a.ex") == """
               my_fun :foo, :bar
               other_fun(:baz, :bang)
               """

        assert read!("lib/b.ex") == code

        assert read!("other/a.ex") == code
      end
    end

    @tag :project
    test "uses exported configuration from dependencies", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [import_deps: [:my_dep]]
          """,
          "a.ex": """
          my_fun :foo, :bar
          """,
          "deps/my_dep/.formatter.exs": """
          [export: [locals_without_parens: [my_fun: 2]]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("a.ex") == """
               my_fun :foo, :bar
               """
      end
    end

    @tag :project
    test "uses exported configuration from dependencies and subdirectories", context do
      in_tmp context do
        write!(
          "deps/my_dep/.formatter.exs": """
          [export: [locals_without_parens: [my_fun: 2]]]
          """,
          ".formatter.exs": """
          [subdirectories: ["lib"]]
          """,
          "lib/.formatter.exs": """
          [subdirectories: ["*"]]
          """,
          "lib/sub/.formatter.exs": """
          [inputs: "a.ex", import_deps: [:my_dep]]
          """,
          "lib/sub/a.ex": """
          my_fun :foo, :bar
          other_fun :baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("lib/sub/a.ex") == """
               my_fun :foo, :bar
               other_fun(:baz)
               """

        # Add a new entry to "lib" and it also gets picked.

        write!(
          "lib/extra/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [other_fun: 1]]
          """,
          "lib/extra/a.ex": """
          my_fun :foo, :bar
          other_fun :baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert read!("lib/extra/a.ex") == """
               my_fun(:foo, :bar)
               other_fun :baz
               """
      end
    end

    test "with SyntaxError when parsing invalid source file", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "a.ex"]
          """,
          "a.ex": """
          defmodule <%= module %>.Bar do end
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert {:error,
                %DotFormatterError{
                  reason: :format,
                  not_formatted: [],
                  exits: [{"a.ex", syntax_error}]
                } = error} = DotFormatter.format(dot_formatter)

        assert is_struct(syntax_error, SyntaxError)

        assert Exception.message(error) =~ """
               Format errors - \
               Not formatted: [], \
               Exits: [{"a.ex", %SyntaxError{\
               """

        assert DotFormatter.format(dot_formatter, check_formatted: true) == {:error, error}
      end
    end

    test "uses inputs and configuration from .formatter.exs (check formatted)", context do
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

        {:ok, dot_formatter} = DotFormatter.read()

        error = %DotFormatterError{
          reason: :format,
          not_formatted: [{"a.ex", "foo bar baz\n", "foo bar(baz)\n"}],
          exits: []
        }

        assert DotFormatter.format(dot_formatter, check_formatted: true) == {:error, error}

        assert Exception.message(error) == """
               Format errors - \
               Not formatted: ["a.ex"], \
               Exits: []\
               """

        # update a.ex

        write!(
          "a.ex": """
          foo bar(baz)
          """
        )

        assert DotFormatter.format(dot_formatter, check_formatted: true) == :ok
      end
    end

    test "formats files modified after", context do
      in_tmp context do
        code = """
        foo bar baz
        """

        write!(
          ".formatter.exs": """
          [
            inputs: ["*"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": code,
          "b.ex": code
        )

        now = now()
        File.touch!("a.ex", now - 1234)
        File.touch!("b.ex", now - 12)

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter, modified_after: now - 123) == :ok

        assert read!("a.ex") == code

        assert read!("b.ex") == """
               foo bar(baz)
               """
      end
    end

    test "does not touch files without formatter", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [
            inputs: ["*"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": "foo",
          "b.rb": "foo"
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter) == :ok

        assert touched?("a.ex", @time)
        refute touched?("b.rb", @time)
      end
    end

    test "touches files without formatter when identity_formatters: true", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [
            inputs: ["*"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": "foo",
          "b.rb": "foo"
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert DotFormatter.format(dot_formatter, identity_formatters: true) == :ok

        assert touched?("a.ex", @time)
        assert touched?("b.rb", @time)
      end
    end

    test "returns error when multiple formatters reference the same file", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["**/*.ex"],
            subdirectories: ["foo"]
          ]
          """,
          "foo/.formatter.exs": """
          [
            inputs: ["**/*.{ex,exs}"]
          ]
          """,
          "foo/a.ex": "foo a",
          "foo/b.ex": "foo b",
          "bar/b.ex": "bar b"
        )

        {:ok, dot_formatter} = DotFormatter.read()

        assert {:error, error} = DotFormatter.format(dot_formatter)
        assert is_struct(error, DotFormatterError)

        assert Exception.message(error) == """
               Multiple formatter files specifying the same file in their :inputs options:
               file: "foo/b.ex", formatters: ["foo/.formatter.exs", ".formatter.exs"]
               file: "foo/a.ex", formatters: ["foo/.formatter.exs", ".formatter.exs"]\
               """
      end
    end
  end

  describe "format_rewrite/2" do
    test "formats file", context do
      in_tmp context do
        write!("a.ex": "foo bar")

        rewrite = Rewrite.new!("**/*")
        assert {:ok, rewrite} = DotFormatter.format_rewrite(DotFormatter.new(), rewrite)
        assert read!(rewrite, "a.ex") == "foo(bar)\n"
      end
    end

    test "will be called by Rewrite.format/3", context do
      in_tmp context do
        write!("a.ex": "foo bar")

        rewrite = Rewrite.new!("**/*")
        assert {:ok, rewrite} = Rewrite.format(rewrite)
        assert read!(rewrite, "a.ex") == "foo(bar)\n"
      end
    end

    test "uses inputs and configuration from .formatter.exs", context do
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

        rewrite = Rewrite.new!("**/*")
        {:ok, dot_formatter} = DotFormatter.read(rewrite)

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               foo bar(baz)
               """

        # update .formatter.exs

        write!(
          ".formatter.exs": """
          [inputs: ["a.ex"]]
          """
        )

        rewrite = Rewrite.new!("**/*")

        # with the old dot formatter
        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               foo bar(baz)
               """

        {:ok, dot_formatter} = DotFormatter.read(rewrite)

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               foo(bar(baz))
               """
      end
    end

    test "caches inputs from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: Path.wildcard("{a,b}.ex"),
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": """
          foo bar baz
          """
        )

        rewrite = Rewrite.new!("**/*")

        {:ok, dot_formatter} = DotFormatter.read(rewrite)
        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               foo bar(baz)
               """

        # add b.ex

        write!(
          "b.ex": """
          bar baz bat
          """
        )

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert Rewrite.source(rewrite, "b.ex") ==
                 {:error, %Rewrite.Error{reason: :nosource, path: "b.ex"}}

        rewrite = Rewrite.new!("**/*")
        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "b.ex") == """
               bar baz bat
               """

        {:ok, dot_formatter} = DotFormatter.read(rewrite)

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "b.ex") == """
               bar(baz(bat))
               """
      end
    end

    test "expands patterns in inputs from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["{a,.b}.ex"]
          ]
          """,
          "a.ex": """
          foo bar
          """,
          ".b.ex": """
          foo bar
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               foo(bar)
               """

        assert read!(rewrite, ".b.ex") == """
               foo(bar)
               """
      end
    end

    test "uses sigil plugins from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex": """
          if true do
            ~W'''
            foo bar baz
            '''abc
          end
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               if true do
                 ~W'''
                 foo
                 bar
                 baz
                 '''abc
               end
               """
      end
    end

    test "uses extension plugins from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.w") == """
               foo
               bar
               baz
               """
      end
    end

    test "uses multiple plugins from .formatter.exs targeting the same file extension", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [ExtensionWPlugin, NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.w") == "foo.bar.baz."
      end
    end

    test "uses multiple plugins from .formatter.exs with the same file extension in declared order",
         context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin, ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.w") == "foo\nbar\nbaz."
      end
    end

    test "uses multiple plugins from .formatter.exs targeting the same sigil", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex": """
          def sigil_test(assigns) do
            ~W"foo bar baz\n"abc
          end
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               def sigil_test(assigns) do
                 ~W"foo\nbar\nbaz."abc
               end
               """
      end
    end

    test "uses multiple plugins from .formatter.exs with the same sigil in declared order",
         context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            plugins: [SigilWPlugin, NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex": """
          def sigil_test(assigns) do
            ~W"foo bar baz"abc
          end
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               def sigil_test(assigns) do
                 ~W"foo.bar.baz"abc
               end
               """
      end
    end

    test "uses remaining plugin after removing another", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin, ExtensionWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} =
                 DotFormatter.format_rewrite(dot_formatter, rewrite,
                   remove_plugins: [NewlineToDotPlugin]
                 )

        assert read!(rewrite, "a.w") == "foo\nbar\nbaz\n"
      end
    end

    test "uses replaced plugin", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} =
                 DotFormatter.format_rewrite(dot_formatter, rewrite,
                   replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}]
                 )

        assert read!(rewrite, "a.w") == "foo\nbar\nbaz\n"
      end
    end

    test "uses replaced plugin in read", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.w"],
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.w": """
          foo bar baz
          """
        )

        rewrite = Rewrite.new!("**/*")

        {:ok, dot_formatter} =
          DotFormatter.read(replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}])

        assert {:ok, rewrite} =
                 DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.w") == "foo\nbar\nbaz\n"
      end
    end

    test "uses inputs and configuration from :dot_formatter", context do
      in_tmp context do
        write!(
          "custom_formatter.exs": """
          [
            inputs: ["a.ex"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": """
          foo bar baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read(dot_formatter: "custom_formatter.exs")
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} =
                 DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               foo bar(baz)
               """
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

        write!(
          ".formatter.exs": """
          [subdirectories: ["li", "lib"]]
          """,
          "li/.formatter.exs": """
          [inputs: "**/*", locals_without_parens: [other_fun: 2]]
          """,
          "lib/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
          """,
          "li/a.ex": code,
          "lib/a.ex": code,
          "lib/b.ex": code,
          "other/a.ex": code
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "li/a.ex") == """
               my_fun(:foo, :bar)
               other_fun :baz, :bang
               """

        assert read!(rewrite, "lib/a.ex") == """
               my_fun :foo, :bar
               other_fun(:baz, :bang)
               """

        assert read!(rewrite, "lib/b.ex") == code

        assert read!(rewrite, "other/a.ex") == code
      end
    end

    @tag :project
    test "uses exported configuration from dependencies", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [import_deps: [:my_dep]]
          """,
          "a.ex": """
          my_fun :foo, :bar
          """,
          "deps/my_dep/.formatter.exs": """
          [export: [locals_without_parens: [my_fun: 2]]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "a.ex") == """
               my_fun :foo, :bar
               """
      end
    end

    @tag :project
    test "uses exported configuration from dependencies and subdirectories", context do
      in_tmp context do
        write!(
          "deps/my_dep/.formatter.exs": """
          [export: [locals_without_parens: [my_fun: 2]]]
          """,
          ".formatter.exs": """
          [subdirectories: ["lib"]]
          """,
          "lib/.formatter.exs": """
          [subdirectories: ["*"]]
          """,
          "lib/sub/.formatter.exs": """
          [inputs: "a.ex", import_deps: [:my_dep]]
          """,
          "lib/sub/a.ex": """
          my_fun :foo, :bar
          other_fun :baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "lib/sub/a.ex") == """
               my_fun :foo, :bar
               other_fun(:baz)
               """

        # Add a new entry to "lib".

        write!(
          "lib/extra/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [other_fun: 1]]
          """,
          "lib/extra/a.ex": """
          my_fun :foo, :bar
          other_fun :baz
          """
        )

        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "lib/extra/a.ex") == """
               my_fun :foo, :bar
               other_fun :baz
               """

        # read new dot_formatter.

        {:ok, dot_formatter} = DotFormatter.read()

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert read!(rewrite, "lib/extra/a.ex") == """
               my_fun(:foo, :bar)
               other_fun :baz
               """
      end
    end

    test "uses inputs and configuration from .formatter.exs (check formatted)", context do
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

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        error = %DotFormatterError{
          reason: :format,
          not_formatted: [{"a.ex", "foo bar baz\n", "foo bar(baz)\n"}],
          exits: []
        }

        assert DotFormatter.format_rewrite(dot_formatter, rewrite, check_formatted: true) ==
                 {:error, error}

        assert Exception.message(error) == """
               Format errors - \
               Not formatted: ["a.ex"], \
               Exits: []\
               """

        # update a.ex

        write!(
          "a.ex": """
          foo bar(baz)
          """
        )

        assert {:error, _error} =
                 DotFormatter.format_rewrite(dot_formatter, rewrite, check_formatted: true)

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format_rewrite(dot_formatter, rewrite, check_formatted: true) == :ok
      end
    end

    test "formats sources modified after", context do
      in_tmp context do
        code = """
        foo bar baz
        """

        write!(
          ".formatter.exs": """
          [
            inputs: ["*"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": code,
          "b.ex": code
        )

        {:ok, dot_formatter} = DotFormatter.read()

        now = now()
        File.touch!("a.ex", now - 1234)
        File.touch!("b.ex", now - 12)

        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} =
                 DotFormatter.format_rewrite(dot_formatter, rewrite, modified_after: now - 123)

        assert read!(rewrite, "a.ex") == code

        assert read!(rewrite, "b.ex") == """
               foo bar(baz)
               """
      end
    end

    test "does not touch sources without formatter", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [
            inputs: ["*"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": "foo",
          "b.rb": "foo"
        )

        {:ok, dot_formatter} = DotFormatter.read()

        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} = DotFormatter.format_rewrite(dot_formatter, rewrite)

        assert touched?(rewrite, "a.ex", @time)
        refute touched?(rewrite, "b.rb", @time)
      end
    end

    test "does not touch sources without formatter even when identity_formatters: true",
         context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [
            inputs: ["*"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": "foo",
          "b.rb": "foo"
        )

        {:ok, dot_formatter} = DotFormatter.read()

        rewrite = Rewrite.new!("**/*")

        assert {:ok, rewrite} =
                 DotFormatter.format_rewrite(dot_formatter, rewrite, identity_formatters: true)

        assert touched?(rewrite, "a.ex", @time)
        refute touched?(rewrite, "b.rb", @time)
      end
    end

    test "returns error when multiple formatters reference the same file", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["**/*.ex"],
            subdirectories: ["foo"]
          ]
          """,
          "foo/.formatter.exs": """
          [
            inputs: ["**/*.{ex,exs}"]
          ]
          """,
          "foo/a.ex": "foo a",
          "foo/b.ex": "foo b",
          "bar/b.ex": "bar b"
        )

        {:ok, dot_formatter} = DotFormatter.read()

        rewrite = Rewrite.new!("**/*")

        assert {:error, error} = DotFormatter.format_rewrite(dot_formatter, rewrite)
        assert is_struct(error, DotFormatterError)

        assert Exception.message(error) == """
               Multiple formatter files specifying the same file in their :inputs options:
               file: "foo/b.ex", formatters: ["foo/.formatter.exs", ".formatter.exs"]
               file: "foo/a.ex", formatters: ["foo/.formatter.exs", ".formatter.exs"]\
               """
      end
    end
  end

  describe "format_string/2" do
    test "formats a string", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "lib/**/*.ex,exs}", locals_without_parens: [foo: 1]]
          """
        )

        assert DotFormatter.format_string("foo bar baz") == {:ok, "foo bar(baz)\n"}

        assert DotFormatter.format_string("foo bar baz", file: "foo.ex") ==
                 {:ok, "foo bar(baz)\n"}
      end
    end

    test "returns an error tuple for invalid code", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "lib/**/*.ex,exs}"]
          """
        )

        assert {:error, %SyntaxError{}} =
                 DotFormatter.format_string("defmodule <%= module %>.Foo do end")

        assert {:error, %TokenMissingError{}} = DotFormatter.format_string("foo(")
      end
    end

    test "returns an error tuple for invalid dot-formatter", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "lib/**/*.ex,exs}", locals_without_parens: :invalid]
          """
        )

        assert {:error, %DotFormatterError{}} = DotFormatter.format_string("foo")
      end
    end
  end

  describe "format_string!/2" do
    test "formats a string", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "lib/**/*.ex,exs}", locals_without_parens: [foo: 1]]
          """
        )

        assert DotFormatter.format_string!("foo bar baz") == "foo bar(baz)\n"
      end
    end

    test "raises an error", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "lib/**/*.ex,exs}"]
          """
        )

        assert_raise SyntaxError, fn ->
          DotFormatter.format_string!("defmodule <%= module %>.Foo do end")
        end
      end
    end
  end

  describe "format_string/4" do
    test "formats string" do
      assert DotFormatter.format_string(
               DotFormatter.new(),
               "foo.ex",
               "foo bar"
             ) ==
               {:ok,
                """
                foo(bar)
                """}
    end

    test "formats string with opts" do
      assert DotFormatter.format_string(
               DotFormatter.new(),
               "foo.ex",
               "foo bar",
               locals_without_parens: [foo: 1]
             ) ==
               {:ok,
                """
                foo bar
                """}
    end

    test "uses identity function for none Elixir files without plugin" do
      assert DotFormatter.format_string(DotFormatter.new(), "a.some", "foo") == {:ok, "foo"}
    end
  end

  describe "format_quoted/2" do
    test "formats a string", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "lib/**/*.ex,exs}", locals_without_parens: [foo: 1]]
          """
        )

        quoted = Sourceror.parse_string!("foo bar baz")
        assert DotFormatter.format_quoted(quoted) == {:ok, "foo bar(baz)\n"}
      end
    end

    test "returns an error for invlaid quoted expression" do
      assert {:error, %FunctionClauseError{}} =
               DotFormatter.format_quoted({:x, :x, :x})
    end
  end

  describe "format_quoted!/2" do
    test "formats a string", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "lib/**/*.ex,exs}", locals_without_parens: [foo: 1]]
          """
        )

        quoted = Sourceror.parse_string!("foo bar baz")
        assert DotFormatter.format_quoted!(quoted) == "foo bar(baz)\n"
      end
    end

    test "raises an error", context do
      in_tmp context do
        assert_raise DotFormatterError, fn ->
          DotFormatter.format_quoted!("foo bar baz", locals_without_parens: :invalid)
        end
      end
    end
  end

  describe "format_quoted/4" do
    test "formats AST" do
      dot_formatter = DotFormatter.new()
      file = "foo.ex"
      code = "foo bar"
      formatted = "foo(bar)\n"

      assert DotFormatter.format_quoted(dot_formatter, file, Sourceror.parse_string!(code)) ==
               {:ok, formatted}

      assert DotFormatter.format_quoted(dot_formatter, file, Code.string_to_quoted!(code)) ==
               {:ok, formatted}
    end

    test "formats AST with opts" do
      dot_formatter = DotFormatter.new()
      opts = [locals_without_parens: [foo: 1]]
      file = "foo.ex"
      code = "foo bar"
      formatted = "foo bar\n"

      assert DotFormatter.format_quoted(dot_formatter, file, Sourceror.parse_string!(code), opts) ==
               {:ok, formatted}

      assert DotFormatter.format_quoted(dot_formatter, file, Code.string_to_quoted!(code), opts) ==
               {:ok, formatted}
    end

    test "formats with an rewrite project", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: "**/*.{ex,exs}",
            locals_without_parens: [my_fun: 2]
          ]
          """
        )

        quoted =
          Sourceror.parse_string!("""
          my_fun :foo, :bar
          other_fun :baz, :bang
          """)

        dot_formatter = DotFormatter.read!()
        rewrite = Rewrite.new!("**/*", dot_formatter: dot_formatter)

        assert rewrite
               |> Rewrite.dot_formatter()
               |> DotFormatter.format_quoted!("nofile.ex", quoted) == """
               my_fun :foo, :bar
               other_fun(:baz, :bang)
               """

        assert rewrite
               |> Rewrite.dot_formatter()
               |> DotFormatter.format_quoted!("nofile.ex", quoted,
                 locals_without_parens: [other_fun: 2]
               ) == """
               my_fun(:foo, :bar)
               other_fun :baz, :bang
               """
      end
    end
  end

  describe "format_file/4" do
    test "doesn't format empty files into line breaks", context do
      in_tmp context do
        write!("a.exs": "")

        assert DotFormatter.format_file(DotFormatter.new(), "a.exs") == :ok
        assert read!("a.exs") == ""
      end
    end

    test "removes line breaks in an empty file", context do
      in_tmp context do
        write!("a.exs": "  \n  \n  ")

        assert DotFormatter.format_file(DotFormatter.new(), "a.exs") == :ok
        assert read!("a.exs") == ""
      end
    end

    test "returns a syntax error", context do
      in_tmp context do
        write!(
          "a.ex": """
          defmodule <%= module %>.Bar do end
          """
        )

        assert {:error, reason} = DotFormatter.format_file(DotFormatter.new(), "a.ex")
        assert is_struct(reason, SyntaxError)
      end
    end

    test "returns an error if the file doesn't exist" do
      assert {:error, error} = DotFormatter.format_file(DotFormatter.new(), "nonexistent.exs")

      assert error == %Rewrite.DotFormatterError{
               reason: {:read, :enoent},
               path: "nonexistent.exs"
             }

      assert Exception.message(error) ==
               "Could not read file \"nonexistent.exs\": no such file or directory"
    end
  end

  describe "format_source/4" do
    test "doesn't format empty files into line breaks", context do
      in_tmp context do
        write!("a.exs": "")

        rewrite = Rewrite.new!("**/*")
        assert {:ok, rewrite} = DotFormatter.format_source(DotFormatter.new(), rewrite, "a.exs")
        assert read!(rewrite, "a.exs") == ""
      end
    end

    test "removes line breaks in an empty file", context do
      in_tmp context do
        write!("a.exs": "  \n  \n  ")

        rewrite = Rewrite.new!("**/*")
        assert {:ok, rewrite} = DotFormatter.format_source(DotFormatter.new(), rewrite, "a.exs")
        assert read!(rewrite, "a.exs") == ""
      end
    end

    test "called by Rewrite.format_source/3", context do
      in_tmp context do
        write!("a.exs": "  \n  \n  ")

        rewrite = Rewrite.new!("**/*")
        assert {:ok, rewrite} = Rewrite.format_source(rewrite, "a.exs")
        assert read!(rewrite, "a.exs") == ""
      end
    end

    test "returns an error if the file doesn't exist", context do
      in_tmp context do
        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.format_source(DotFormatter.new(), rewrite, "nonexistent.exs") == {
                 :error,
                 %Rewrite.Error{
                   __exception__: true,
                   path: "nonexistent.exs",
                   reason: :nosource,
                   duplicated_paths: nil,
                   missing_paths: nil
                 }
               }
      end
    end
  end

  describe "create/2" do
    test "creates a dot formatter" do
      assert {:ok, dot_formatter} = DotFormatter.create(inputs: ["*.ex"])

      assert %Rewrite.DotFormatter{
               inputs: [~g|*.ex|d],
               plugins: [],
               subs: [],
               source: ".formatter.exs",
               plugin_opts: [],
               timestamp: _timestamp,
               path: ""
             } = dot_formatter
    end

    test "return an error tuple" do
      assert {:error, error} = DotFormatter.create(inputs: :foo)
      assert Exception.message(error) == "Invalid inputs, got: :foo"
    end

    test "creates a dot formatter with plugin", context do
      in_tmp context do
        assert {:ok, dot_formatter} =
                 DotFormatter.create(
                   inputs: ["*.ex"],
                   plugins: [AltExWrapperPlugin],
                   from_formatter_exs: :yes
                 )

        assert %Rewrite.DotFormatter{
                 inputs: [~g|*.ex|d],
                 path: "",
                 plugin_opts: [{:from_formatter_exs, :yes}],
                 plugins: [AltExWrapperPlugin],
                 source: ".formatter.exs",
                 subs: [],
                 timestamp: _timestamp
               } = dot_formatter
      end
    end

    @tag :project
    test "reads exported configuration from dependencies", context do
      in_tmp context do
        write!(
          "deps/my_dep/.formatter.exs": """
          [export: [locals_without_parens: [my_fun: 2]]]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.create(import_deps: [:my_dep], inputs: "*.ex")

        assert %Rewrite.DotFormatter{
                 import_deps: [:my_dep],
                 locals_without_parens: [my_fun: 2],
                 inputs: [~g|*.ex|d],
                 path: "",
                 plugin_opts: [],
                 plugins: [],
                 source: ".formatter.exs",
                 subs: [],
                 timestamp: _timestamp
               } = dot_formatter
      end
    end
  end

  describe "create!/2" do
    test "creates a dot formatter" do
      assert dot_formatter = DotFormatter.create!(inputs: ["*.ex"])

      assert %DotFormatter{
               inputs: [~g|*.ex|d],
               plugins: [],
               subs: [],
               source: ".formatter.exs",
               plugin_opts: [],
               timestamp: _timestamp,
               path: ""
             } = dot_formatter
    end

    test "raises an error" do
      assert_raise DotFormatterError, fn -> DotFormatter.create!(inputs: :foo) end
    end
  end

  describe "read/3" do
    test "reads the default formatter", context do
      in_tmp context do
        write!(
          @time,
          ".formatter.exs": """
          [inputs: ["*.ex"]]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.read()
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

        assert DotFormatter.read(rewrite) == {:ok, dot_formatter}
      end
    end

    test "returns an error tuple when no .formatter.exs exist", context do
      in_tmp context do
        assert {:error, error} = DotFormatter.read()
        assert Exception.message(error) =~ ".formatter.exs not found"
      end
    end

    test "reads the default formatter from file system", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [inputs: ["*.ex"]]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.read()

        rewrite = Rewrite.new!("lib/**/*")
        assert {:error, _error} = Rewrite.source(rewrite, ".formatter.exs")
        assert DotFormatter.read(rewrite) == {:ok, dot_formatter}
      end
    end

    test "returns an error tuple for invalid input", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [inputs: [:invalid]]
          """
        )

        assert {:error, error} = DotFormatter.read()
        assert Exception.message(error) == "Invalid input, got: :invalid"
      end
    end

    test "returns an error tuple for invalid glob", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [inputs: "["]
          """
        )

        assert {:error, error} = DotFormatter.read()

        assert Exception.message(error) ==
                 "Invalid glob \"[\", missing terminator for delimiter opened at 1"
      end
    end

    test "returns an error tuple for invalid locals_without_parens", context do
      in_tmp context do
        write!(
          @time,
          ".formatter.exs": """
          [inputs: "*", locals_without_parens: :foo]
          """
        )

        assert {:error, error} = DotFormatter.read()
        assert Exception.message(error) == "Invalid locals_without_parens, got: :foo"
      end
    end

    test "reads the updated formatter", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: ["*.ex"]]
          """
        )

        project =
          "*"
          |> Rewrite.new!()
          |> Rewrite.update!(".formatter.exs", fn source ->
            Source.update(source, :content, """
            [inputs: ["*.ex", "*.exs"]]
            """)
          end)

        assert {:ok, dot_formatter} = DotFormatter.read(project)
        assert dot_formatter.inputs == [~g|*.exs|d, ~g|*.ex|d]
        assert dot_formatter.source == ".formatter.exs"
      end
    end

    @tag :project
    test "reads exported configuration from dependencies", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [import_deps: [:my_dep], inputs: "*"]
          """
        )

        write!(
          "deps/my_dep/.formatter.exs": """
          [export: [locals_without_parens: [my_fun: 2]]]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.read()
        assert dot_formatter.locals_without_parens == [my_fun: 2]
      end
    end

    test "returns an error tuple for mising subdirectories", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [subdirectories: ["priv", "lib"]]
          """
        )

        assert {:error, error} = DotFormatter.read()
        assert Exception.message(error) == "No sub formatter found in \"priv\""
      end
    end

    test "reads dot formatters from subdirectories", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [subdirectories: ["priv", "lib"]]
          """,
          "priv/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [other_fun: 2]]
          """,
          "lib/.formatter.exs": """
          [inputs: "**/*", locals_without_parens: [my_fun: 2]]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.read()

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

    test "returns error tuple for invalid glob in sub formatter", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [subdirectories: ["lib"]]
          """,
          "lib/.formatter.exs": """
          [inputs: "["]
          """
        )

        assert {:error, error} = DotFormatter.read()

        assert Exception.message(error) ==
                 "Invalid glob \"lib/[\", missing terminator for delimiter opened at 5"
      end
    end

    test "returns error tuple for invalid glob in subdirectories", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [subdirectories: ["["]]
          """,
          "lib/.formatter.exs": """
          [inputs: "["]
          """
        )

        assert {:error, error} = DotFormatter.read()

        assert Exception.message(error) ==
                 "Invalid glob \"[\", missing terminator for delimiter opened at 1"
      end
    end

    test "reads dot formatters from subdirectories with glob", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [subdirectories: ["*"]]
          """,
          "foo.exs": "# causes no error",
          "foo/bar.exs": "# causes no error",
          "priv/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [other_fun: 2]]
          """,
          "lib/.formatter.exs": """
          [inputs: "**/*", locals_without_parens: [my_fun: 2]]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.read()

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
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "a.ex": """
          def sigil_test(assigns) do
            ~W"foo bar baz\n"abc
          end
          """
        )

        rewrite = Rewrite.new!("**/*")

        assert {:ok, dot_formatter} = DotFormatter.read()
        assert DotFormatter.read(rewrite) == {:ok, dot_formatter}
        assert %{sigils: [W: fun]} = dot_formatter
        assert is_function(fun, 2)
        assert dot_formatter.plugins == [NewlineToDotPlugin, SigilWPlugin]
      end
    end

    test "reads sigil plugins from .formatter.exs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["a.ex"],
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.read()
        assert %{sigils: [W: fun]} = dot_formatter
        assert is_function(fun, 2)
      end
    end

    test "reads exported configuration from subdirectories", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [subdirectories: ["li", "lib"]]
          """,
          "li/.formatter.exs": """
          [inputs: "**/*", locals_without_parens: [other_fun: 2]]
          """,
          "lib/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
          """
        )

        assert DotFormatter.read() ==
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
        write!(
          ".formatter.exs": """
          [
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.read(remove_plugins: [SigilWPlugin])
        assert dot_formatter.plugins == [NewlineToDotPlugin]
        assert [W: fun] = dot_formatter.sigils
        assert is_function(fun, 2)

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.read(rewrite, remove_plugins: [SigilWPlugin]) == {:ok, dot_formatter}
      end
    end

    test "removes plugins", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            plugins: [NewlineToDotPlugin, SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        assert {:ok, dot_formatter} =
                 DotFormatter.read(remove_plugins: [SigilWPlugin, NewlineToDotPlugin])

        assert dot_formatter.plugins == []
        assert dot_formatter.sigils == nil

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.read(rewrite, remove_plugins: [SigilWPlugin, NewlineToDotPlugin]) ==
                 {:ok, dot_formatter}
      end
    end

    test "removes plugin from sub", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            subdirectories: ["lib", "priv"]
          ]
          """,
          "lib/.formatter.exs": """
          [
            inputs: "*",
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "priv/.formatter.exs": """
          [
            inputs: "*",
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        assert {:ok, dot_formatter} = DotFormatter.read(remove_plugins: [SigilWPlugin])

        priv_dot_formatter = DotFormatter.get(dot_formatter, "priv")
        assert priv_dot_formatter.plugins == []
        assert priv_dot_formatter.sigils == nil

        lib_dot_formatter = DotFormatter.get(dot_formatter, "lib")
        assert lib_dot_formatter.plugins == [NewlineToDotPlugin]
        assert lib_dot_formatter.sigils != nil

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.read(rewrite, remove_plugins: [SigilWPlugin]) == {:ok, dot_formatter}
      end
    end

    test "replaces plugin", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        assert {:ok, dot_formatter} =
                 DotFormatter.read(replace_plugins: [{SigilWPlugin, NewlineToDotPlugin}])

        assert dot_formatter.plugins == [NewlineToDotPlugin]
        assert [W: fun] = dot_formatter.sigils
        assert is_function(fun, 2)

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.read(rewrite, replace_plugins: [{SigilWPlugin, NewlineToDotPlugin}]) ==
                 {:ok, dot_formatter}
      end
    end

    test "replaces plugin in sub", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            subdirectories: ["lib", "priv"]
          ]
          """,
          "lib/.formatter.exs": """
          [
            inputs: "*",
            plugins: [NewlineToDotPlugin],
            from_formatter_exs: :yes
          ]
          """,
          "priv/.formatter.exs": """
          [
            inputs: "*",
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        assert {:ok, dot_formatter} =
                 DotFormatter.read(replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}])

        lib_dot_formatter = DotFormatter.get(dot_formatter, "lib")
        assert lib_dot_formatter.plugins == [ExtensionWPlugin]
        assert lib_dot_formatter.sigils != nil

        priv_dot_formatter = DotFormatter.get(dot_formatter, "priv")
        assert priv_dot_formatter.plugins == [SigilWPlugin]
        assert priv_dot_formatter.sigils != nil

        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.read(rewrite,
                 replace_plugins: [{NewlineToDotPlugin, ExtensionWPlugin}]
               ) ==
                 {:ok, dot_formatter}
      end
    end

    test "validates :subdirectories", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [subdirectories: "oops"]
          """
        )

        assert {:error,
                %DotFormatterError{
                  reason: {:invalid_subdirectories, "oops"},
                  path: ".formatter.exs"
                } = error} = DotFormatter.read()

        message = """
        Expected :subdirectories to return a list of directories, \
        got: "oops", \
        in: ".formatter.exs"\
        """

        assert Exception.message(error) == message
      end
    end

    test "validates subdirectories in :subdirectories", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [subdirectories: ["lib"]]
          """,
          "lib/.formatter.exs": """
          []
          """
        )

        assert {:error,
                %Rewrite.DotFormatterError{
                  reason: :no_inputs_or_subdirectories,
                  path: "lib/.formatter.exs"
                } = error} = DotFormatter.read()

        message = """
        Expected :inputs or :subdirectories key in "lib/.formatter.exs"\
        """

        assert Exception.message(error) == message
      end
    end

    test "validates :import_deps", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [import_deps: "oops"]
          """
        )

        assert {:error,
                %DotFormatterError{
                  reason: {:invalid_import_deps, "oops"},
                  path: ".formatter.exs"
                } = error} = DotFormatter.read()

        message = """
        Expected :import_deps to return a list of dependencies, got: "oops", in: ".formatter.exs"\
        """

        assert Exception.message(error) == message
      end
    end

    @tag :project
    test "validates dependencies in :import_deps", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [import_deps: [:my_dep]]
          """
        )

        assert {:error,
                %Rewrite.DotFormatterError{
                  reason: {:dep_not_found, :my_dep},
                  path: "deps/my_dep/.formatter.exs"
                } = error} = DotFormatter.read()

        message = """
        Unknown dependency :my_dep given to :import_deps in the formatter \
        configuration. Make sure the dependency is listed in your mix.exs for \
        environment :dev and you have run "mix deps.get"\
        """

        assert Exception.message(error) == message

        write!(
          ".formatter.exs": """
          [import_deps: [:nonexistent_dep]]
          """
        )

        assert {:error,
                %DotFormatterError{
                  reason: {:dep_not_found, :nonexistent_dep}
                } = error} = DotFormatter.read()

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
                } = error} = DotFormatter.read()

        assert Exception.message(error) == ".formatter.exs not found"
      end
    end
  end

  describe "read!/3" do
    test "raises an error when no .formatter.exs exist", context do
      in_tmp context do
        message = ".formatter.exs not found"

        assert_raise DotFormatterError, message, fn ->
          DotFormatter.read!()
        end
      end
    end
  end

  describe "update/3" do
    test "does not update the file if it's up to date", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: ["*.ex"]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert {:ok, updated} = DotFormatter.update(dot_formatter)
        assert dot_formatter == updated

        assert {:ok, updated} = DotFormatter.update(dot_formatter, rewrite)
        assert dot_formatter == updated
      end
    end

    test "updates the dot_formatter", context do
      in_tmp context do
        write!(
          @time,
          ".formatter.exs": """
          [inputs: ["*.ex"]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
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
        write!(
          @time,
          ".formatter.exs": """
          [
            inputs: ["*.ex"],
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
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
        write!(
          ".formatter.exs": """
          [inputs: ["*.ex"]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.up_to_date?(dot_formatter) == true
        assert DotFormatter.up_to_date?(dot_formatter, rewrite) == true
      end
    end

    test "returns true whith a dot_formatter containing subs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [subdirectories: ["priv", "lib"]]
          """
        )

        write!(
          "priv/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [other_fun: 2]]
          """
        )

        write!(
          "lib/.formatter.exs": """
          [inputs: "**/*", locals_without_parens: [my_fun: 2]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.up_to_date?(dot_formatter) == true
        assert DotFormatter.up_to_date?(dot_formatter, rewrite) == true
      end
    end

    test "returns false", context do
      in_tmp context do
        write!(@time,
          ".formatter.exs": """
          [inputs: ["*.ex"]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
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
        write!(@time,
          ".formatter.exs": """
          [subdirectories: ["priv", "lib"]]
          """,
          "priv/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [other_fun: 2]]
          """,
          "lib/.formatter.exs": """
          [inputs: "**/*", locals_without_parens: [my_fun: 2]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
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
        write!(
          ".formatter.exs": """
          [subdirectories: ["li", "lib"]]
          """,
          "li/.formatter.exs": """
          [inputs: "**/*"]
          """,
          "lib/.formatter.exs": """
          [inputs: "a.ex"]
          """,
          "lib/a.ex": """
          # comment
          """,
          "li/a.ex": """
          # comment
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.conflicts(dot_formatter) == []
        assert DotFormatter.conflicts(dot_formatter, rewrite) == []
      end
    end

    test "returns a list of conflicts", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "lib/**/*.{ex,exs}", subdirectories: ["lib", "foo"]]
          """,
          "lib/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
          """,
          "foo/.formatter.exs": """
          [inputs: "../lib/a.ex", locals_without_parens: [my_fun: 2]]
          """,
          "lib/a.ex": """
          my_fun :foo, :bar
          other_fun :baz
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()
        rewrite = Rewrite.new!("**/*")

        assert DotFormatter.conflicts(dot_formatter) == [
                 {"lib/a.ex", ["lib/.formatter.exs", ".formatter.exs"]}
               ]

        assert DotFormatter.conflicts(dot_formatter, rewrite) == [
                 {"lib/a.ex", ["lib/.formatter.exs", ".formatter.exs"]}
               ]
      end
    end
  end

  describe "formatter_for_file/2" do
    test "uses configuration from subs", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [subdirectories: ["foo", "bar"]]
          """,
          "foo/.formatter.exs": """
          [inputs: "a.ex", locals_without_parens: [my_fun: 2]]
          """,
          "bar/.formatter.exs": """
          [inputs: "**/*", locals_without_parens: [other_fun: 2]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        formatter = DotFormatter.formatter_for_file(dot_formatter, "foo/a.ex")
        assert formatter.("my_fun     1,  2") == "my_fun 1, 2\n"
        assert formatter.("other_fun  1,  2") == "other_fun(1, 2)\n"

        formatter = DotFormatter.formatter_for_file(dot_formatter, "bar/a.ex")
        assert formatter.("my_fun     1,  2") == "my_fun(1, 2)\n"
        assert formatter.("other_fun  1,  2") == "other_fun 1, 2\n"

        formatter =
          DotFormatter.formatter_for_file(dot_formatter, "bar/a.ex",
            locals_without_parens: [my_fun: 2]
          )

        assert formatter.("my_fun     1,  2") == "my_fun 1, 2\n"
        assert formatter.("other_fun  1,  2") == "other_fun(1, 2)\n"
      end
    end

    test "returns a formatter that excepts an AST as input", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "**/*.ex", locals_without_parens: [my_fun: 2]]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        formatter = DotFormatter.formatter_for_file(dot_formatter, "lib/a.ex", from: :quoted)

        code = """
        my_fun :foo, :bar
        other_fun :baz, :bang
        """

        formatted = """
        my_fun :foo, :bar
        other_fun(:baz, :bang)
        """

        assert formatter.(Code.string_to_quoted!(code)) == formatted
        assert formatter.(Sourceror.parse_string!(code)) == formatted
      end
    end

    test "returns an AST formatter using sigils", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["**/*.ex"],
            plugins: [SigilWPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        formatter = DotFormatter.formatter_for_file(dot_formatter, "lib/a.ex", from: :quoted)

        code = """
        if true do
          ~W'''
          foo bar baz
          '''abc
        end
        """

        formatted = """
        if true do
          ~W'''
          foo
          bar
          baz
          '''abc
        end
        """

        assert formatter.(Code.string_to_quoted!(code)) == formatted
        assert formatter.(Sourceror.parse_string!(code)) == formatted
      end
    end

    test "returns an AST formatter using AltExPlugin", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["**/*.ex,exs}"],
            plugins: [AltExPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        formatter =
          DotFormatter.formatter_for_file(dot_formatter, "lib/a.ex",
            from: :quoted,
            wrapper: :yes
          )

        code = """
        if x == 0, do: x + 1
        """

        formatted = """
        if x == 0 do
          x + 1
        end
        """

        assert formatter.(Code.string_to_quoted!(code)) == formatted
        assert formatter.(Sourceror.parse_string!(code)) == formatted
      end
    end

    test "returns an AST formatter using AltExWrapperPlugin", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["**/*.ex,exs}"],
            plugins: [AltExWrapperPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        formatter =
          DotFormatter.formatter_for_file(dot_formatter, "lib/a.ex",
            from: :quoted,
            wrapper: :yes
          )

        code = """
        if x == 0, do: x + 1
        """

        formatted = """
        if x == 0 do
          x + 1
        end
        """

        assert formatter.(Code.string_to_quoted!(code)) == formatted
        assert formatter.(Sourceror.parse_string!(code)) == formatted
      end
    end

    test "returns an AST formatter using AltExWrapperPlugin and AltExPlugin", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["**/*.ex,exs}"],
            plugins: [AltExWrapperPlugin, AltExPlugin],
            from_formatter_exs: :yes
          ]
          """
        )

        {:ok, dot_formatter} = DotFormatter.read()

        formatter =
          DotFormatter.formatter_for_file(dot_formatter, "lib/a.ex",
            from: :quoted,
            wrapper: :yes
          )

        code = """
        if x == 0, do: x + 1
        """

        formatted = """
        if x == 0 do
          x + 1
        end
        """

        assert formatter.(Code.string_to_quoted!(code)) == formatted
        assert formatter.(Sourceror.parse_string!(code)) == formatted
      end
    end
  end

  describe "formatter_opts_for_file/2" do
    test "returns formatter opts", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "*.ex", subdirectories: ["lib", "priv"]]
          """,
          "lib/.formatter.exs": """
          [inputs: "**/*.{ex,exs}", locals_without_parens: [other_fun: 2]]
          """,
          "priv/.formatter.exs": """
          [inputs: "**/*.{ex,exs}", locals_without_parens: [my_fun: 2]]
          """
        )

        dot_formatter = DotFormatter.read!()

        assert formatter_opts = DotFormatter.formatter_opts_for_file(dot_formatter, "a.ex")
        assert(formatter_opts[:subdirectories] == ["lib", "priv"])
        assert(formatter_opts[:inputs] == [~g|*.ex|d])

        assert opts = DotFormatter.formatter_opts_for_file(dot_formatter, "lib/a.ex")
        assert opts[:inputs] == [~g|lib/**/*.{ex,exs}|d]
        assert opts[:locals_without_parens] == [other_fun: 2]

        assert opts = DotFormatter.formatter_opts_for_file(dot_formatter, "priv/a.ex")
        assert opts[:inputs] == [~g|priv/**/*.{ex,exs}|d]
        assert opts[:locals_without_parens] == [my_fun: 2]
      end
    end

    test "returns formatter opts for the nearest dot-formatter", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [formatter: :root, inputs: "lib/**/*.ex,exs}", subdirectories: ["a", "b"]]
          """,
          "a/.formatter.exs": """
          [formatter: :a, inputs: "*.ex", subdirectories: ["z"]]
          """,
          "a/z/.formatter.exs": """
          [formatter: :az, inputs: "**/*.exs"]
          """,
          "b/.formatter.exs": """
          [formatter: :b, inputs: "**/*.ex"]
          """
        )

        dot_formatter = DotFormatter.read!()

        assert DotFormatter.formatter_opts_for_file(dot_formatter, "foo.ex")[:formatter] == :root

        assert DotFormatter.formatter_opts_for_file(dot_formatter, "foo/bar.ex")[:formatter] ==
                 :root

        assert DotFormatter.formatter_opts_for_file(dot_formatter, "a/foo/bar.ex")[:formatter] ==
                 :a

        assert DotFormatter.formatter_opts_for_file(dot_formatter, "a/z/foo/bar.ex")[:formatter] ==
                 :az

        assert DotFormatter.formatter_opts_for_file(dot_formatter, "b/z/foo/bar.ex")[:formatter] ==
                 :b
      end
    end
  end

  describe "from_formatter_opts/2" do
    test "create %DotFormatter{}" do
      formatter_opts = [
        extension: ".ex",
        file: "/Users/foo/Projects/bar/lib/source.ex",
        sigils: [],
        plugins: [FormatterPlugin],
        trailing_comma: true,
        inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
        locals_without_parens: [noop: 1],
        subdirectories: ["priv/*/migrations"]
      ]

      assert dot_formatter = DotFormatter.from_formatter_opts(formatter_opts)
      assert dot_formatter.plugins == [FormatterPlugin]
      assert dot_formatter.subs == []
    end

    test "removes plugins" do
      formatter_opts = [
        extension: ".ex",
        file: "/Users/foo/Projects/bar/lib/source.ex",
        sigils: [],
        plugins: [FormatterA, FormatterB, FormatterC],
        trailing_comma: true,
        inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
        locals_without_parens: [noop: 1],
        subdirectories: ["priv/*/migrations"]
      ]

      assert dot_formatter =
               DotFormatter.from_formatter_opts(formatter_opts,
                 remove_plugins: [FormatterA, FormatterC]
               )

      assert dot_formatter.plugins == [FormatterB]
    end

    test "returns a %DotFormatter{} that works with format_string!/4" do
      formatter_opts = [
        extension: ".ex",
        file: "/Users/foo/Projects/bar/lib/source.ex",
        locals_without_parens: [foo: 1]
      ]

      assert dot_formatter = DotFormatter.from_formatter_opts(formatter_opts)

      assert DotFormatter.format_string!(dot_formatter, "source.ex", "foo bar baz") ==
               "foo bar(baz)\n"
    end
  end
end
