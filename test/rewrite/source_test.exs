defmodule Rewrite.SourceTest do
  use ExUnit.Case

  alias Rewrite.Source
  alias Sourceror.Zipper

  doctest Rewrite.Source

  describe "read/1" do
    test "creates new source" do
      path = "test/fixtures/source/simple.ex"
      code = File.read!(path)

      source = Source.read!(path)

      assert_source(source, %{
        path: path,
        code: code,
        modules: [MyApp.Simple],
        owner: Rewrite,
        from: :file
      })
    end
  end

  describe "from_string/2" do
    test "creates a source from code" do
      code = "def foo, do: :foo\n"
      source = Source.from_string(code)
      assert source.code == code
      assert source.path == nil
      assert source.modules == []
    end
  end

  describe "del/2" do
    test "sets path to nil" do
      source = ":a" |> Source.from_string("foo.ex") |> Source.del()

      assert source.path == nil
    end

    test "returns orig source" do
      source = Source.from_string(":a")

      assert Source.del(source) == source
    end
  end

  describe "update/3" do
    test "does not update source when code not changed" do
      source = Source.read!("test/fixtures/source/simple.ex")
      updated = Source.update(source, :test, code: Source.code(source))

      assert Source.updated?(updated) == false
    end

    test "updates the code" do
      path = "test/fixtures/source/simple.ex"
      code = File.read!(path)
      changes = String.replace(code, "MyApp", "TheApp")

      source =
        path
        |> Source.read!()
        |> Source.update(:test, code: changes)

      assert_source(source, %{
        path: path,
        code: changes,
        modules: [TheApp.Simple],
        updates: [{:code, :test, code}],
        ast: Sourceror.parse_string!(changes)
      })
    end

    test "updates the code with an AST" do
      path = "test/fixtures/source/simple.ex"
      code = File.read!(path)
      changes = code |> String.replace("MyApp", "TheApp") |> String.trim_trailing()
      zipper = changes |> Sourceror.parse_string!() |> Zipper.zip()

      source =
        path
        |> Source.read!()
        |> Source.update(:test, ast: Zipper.root(zipper))

      assert_source(source, %{
        path: path,
        code: changes,
        modules: [TheApp.Simple],
        updates: [{:code, :test, code}],
        ast: Sourceror.parse_string!(changes)
      })
    end

    test "updates the code twice" do
      path = "test/fixtures/source/simple.ex"
      code = File.read!(path)
      changes1 = String.replace(code, "MyApp", "TheApp")
      changes2 = String.replace(changes1, "TheApp", "Application")

      orig = Source.read!(path)

      source =
        orig
        |> Source.update(:foo, code: changes1)
        |> Source.update(:bar, code: changes2)

      assert orig.id == source.id

      assert_source(source, %{
        path: path,
        code: changes2,
        modules: [Application.Simple],
        updates: [
          {:code, :bar, changes1},
          {:code, :foo, code}
        ]
      })
    end

    test "updates the code and path" do
      path = "test/fixtures/source/simple.ex"
      code = File.read!(path)
      changes1 = String.replace(code, "MyApp", "TheApp")
      changes2 = "test/fixtures/source/the_app.ex"

      source =
        path
        |> Source.read!()
        |> Source.update(:foo, code: changes1)
        |> Source.update(:bar, path: changes2)

      assert_source(source, %{
        path: changes2,
        code: changes1,
        modules: [TheApp.Simple],
        updates: [
          {:path, :bar, path},
          {:code, :foo, code}
        ]
      })
    end
  end

  describe "path/1" do
    test "returns path" do
      path = "test/fixtures/source/simple.ex"
      source = Source.read!(path)

      assert Source.path(source) == path
    end

    test "returns current path" do
      source = Source.read!("test/fixtures/source/simple.ex")
      path = "test/fixtures/source/new.ex"

      source = Source.update(source, :test, path: path)

      assert Source.path(source) == path
    end
  end

  describe "path/2" do
    test "returns the path for the given version" do
      path = "test/fixtures/source/simple.ex"

      source =
        path
        |> Source.read!()
        |> Source.update(:test, path: "a.ex")
        |> Source.update(:test, path: "b.ex")
        |> Source.update(:test, path: "c.ex")

      assert Source.path(source, 1) == path
      assert Source.path(source, 2) == "a.ex"
      assert Source.path(source, 3) == "b.ex"
      assert Source.path(source, 4) == "c.ex"
    end

    test "returns the path for given version without path changes" do
      path = "test/fixtures/source/simple.ex"

      source =
        path
        |> Source.read!()
        |> Source.update(:test, code: "a = 1")
        |> Source.update(:test, code: "b = 2")

      assert Source.path(source, 1) == path
      assert Source.path(source, 2) == path
      assert Source.path(source, 3) == path
    end
  end

  describe "code/2" do
    test "returns the code for the given version without code changes" do
      path = "test/fixtures/source/simple.ex"
      code = File.read!(path)

      source =
        path
        |> Source.read!()
        |> Source.update(:test, path: "a.ex")
        |> Source.update(:test, path: "b.ex")

      assert Source.code(source, 1) == code
      assert Source.code(source, 2) == code
      assert Source.code(source, 3) == code
    end

    test "returns the code for given version" do
      code = "a + b\n"

      source =
        code
        |> Source.from_string()
        |> Source.update(:test, code: "a = 1")
        |> Source.update(:test, code: "b = 2")

      assert Source.code(source, 1) == code
      assert Source.code(source, 2) == "a = 1"
      assert Source.code(source, 3) == "b = 2"
    end
  end

  describe "modules/2" do
    test "returns the modules for the given version" do
      path = "test/fixtures/source/simple.ex"
      code = File.read!(path)
      changes1 = String.replace(code, "MyApp", "TheApp")
      changes2 = String.replace(code, "MyApp", "AnApp")

      source =
        path
        |> Source.read!()
        |> Source.update(:test, code: changes1)
        |> Source.update(:test, code: changes2)

      assert Source.modules(source, 1) == [MyApp.Simple]
      assert Source.modules(source, 2) == [TheApp.Simple]
      assert Source.modules(source, 3) == [AnApp.Simple]
    end
  end

  describe "put_private/3" do
    test "updates the private map" do
      source = Source.from_string("a + b\n")

      assert source = Source.put_private(source, :any_key, :any_value)
      assert source.private[:any_key] == :any_value
    end
  end

  defp hash(path, code), do: :crypto.hash(:md5, path <> code)

  defp assert_source(%Source{} = source, expected) do
    assert is_reference(source.id)
    assert source.path == expected.path
    assert source.code == expected.code
    assert source.hash == hash(expected.path, expected.code)
    assert source.modules == expected.modules
    assert source.updates == Map.get(expected, :updates, [])
    assert source.issues == Map.get(expected, :issues, [])
    assert source.private == Map.get(expected, :private, %{})

    if Map.has_key?(expected, :ast) do
      assert source.ast == expected.ast
    end
  end
end
