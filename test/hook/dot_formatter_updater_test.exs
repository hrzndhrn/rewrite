defmodule Rewrite.Hook.DotFormatterUpdaterTest do
  use RewriteCase

  alias Rewrite.Hook.DotFormatterUpdater
  alias Rewrite.Source

  # doctest Rewrite.Hook.DotFormatterUpdater

  @moduletag :tmp_dir

  describe "DotFormatterUpdater hook" do
    test "updates dot_formatter", context do
      in_tmp context do
        project =
          "**/*"
          |> Rewrite.new!(hooks: [DotFormatterUpdater])
          |> Rewrite.new_source!("foo.ex", "foo bar baz")
          |> Rewrite.format!()

        assert read!(project, "foo.ex") == "foo(bar(baz))\n"

        project =
          project
          |> Rewrite.new_source!(
            ".formatter.exs",
            ~s|[inputs: "**/*", locals_without_parens: [foo: 1]]|
          )
          |> Rewrite.update!("foo.ex", fn source ->
            Source.update(source, :content, "foo bar baz")
          end)
          |> Rewrite.format!()

        assert read!(project, "foo.ex") == "foo bar(baz)\n"

        project =
          project
          |> Rewrite.update!(".formatter.exs", fn source ->
            Source.update(source, :content, ~s|[inputs: "**/*", locals_without_parens: [bar: 1]]|)
          end)
          |> Rewrite.update!("foo.ex", fn source ->
            Source.update(source, :content, "foo bar baz")
          end)
          |> Rewrite.format!(by: TheFormatter)

        assert read!(project, "foo.ex") == "foo(bar baz)\n"

        project =
          project
          |> Rewrite.new_source!("bar.ex", "")
          |> Rewrite.update!("bar.ex", fn source ->
            quoted = Sourceror.parse_string!("bar baz foo")
            Source.update(source, :quoted, quoted, dot_formatter: project.dot_formatter)
          end)

        assert read!(project, "bar.ex") == "bar baz(foo)\n"

        assert Rewrite.source!(project, "foo.ex") |> Map.fetch!(:history) ==
                 [
                   {:content, TheFormatter, "foo bar baz"},
                   {:content, Rewrite, "foo bar(baz)\n"},
                   {:content, Rewrite, "foo bar baz"},
                   {:content, Rewrite, "foo(bar(baz))\n"},
                   {:content, Rewrite, "foo bar baz"}
                 ]

        assert Rewrite.source!(project, "bar.ex") |> Map.fetch!(:history) ==
                 [{:content, Rewrite, ""}]
      end
    end

    test "reads formatter", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "**/*", locals_without_parens: [foo: 1]]
          """
        )

        dot_formatter =
          "**/*"
          |> Rewrite.new!(hooks: [DotFormatterUpdater])
          |> Rewrite.dot_formatter()

        assert dot_formatter.locals_without_parens == [foo: 1]
      end
    end

    test "uses formatter", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [inputs: "**/*", locals_without_parens: [foo: 1]]
          """,
          "lib/foo.ex": """
          foo bar baz
          """
        )

        project = Rewrite.new!("**/*", hooks: [DotFormatterUpdater])

        assert read!(project, "lib/foo.ex") == "foo bar baz\n"

        assert project = Rewrite.format!(project)

        assert read!(project, "lib/foo.ex") == "foo bar(baz)\n"
      end
    end
  end
end
