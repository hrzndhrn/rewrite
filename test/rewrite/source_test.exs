defmodule Rewrite.SourceTest do
  use ExUnit.Case

  alias Rewrite.Source
  alias Rewrite.SourceError

  doctest Rewrite.Source

  describe "read/1" do
    test "creates new source" do
      path = "test/fixtures/source/hello.txt"

      assert Source.read!(path) == %Source{
               from: :file,
               owner: Rewrite,
               path: path,
               content: "hello\n",
               filetype: nil,
               hash:
                 <<173, 163, 154, 142, 118, 254, 168, 202, 109, 79, 216, 205, 178, 105, 63, 63>>,
               issues: [],
               private: %{},
               history: []
             }
    end

    test "creates new source from full path" do
      path = Path.join(File.cwd!(), "test/fixtures/source/hello.txt")

      assert Source.read!(path) == %Source{
               from: :file,
               owner: Rewrite,
               path: path,
               content: "hello\n",
               filetype: nil,
               hash: <<54, 155, 6, 20, 63, 71, 237, 61, 140, 87, 1, 232, 123, 93, 128, 135>>,
               issues: [],
               private: %{},
               history: []
             }
    end
  end

  describe "from_string/2" do
    test "creates a source from code" do
      content = "foo\n"
      source = Source.from_string(content)

      assert source.content == content
      assert source.path == nil
    end
  end

  describe "owner/1" do
    test "returns the owner of a source" do
      source = Source.from_string("hello")
      assert Source.owner(source) == Rewrite
    end
  end

  describe "rm/1" do
    @describetag :tmp_dir

    test "deletes file", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        File.write!("a.exs", ":a")
        source = Source.read!("a.exs")

        assert Source.rm(source) == :ok

        assert File.exists?("a.exs") == false
      end)
    end

    test "returns a posix error", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        File.write!("a.exs", ":a")
        source = Source.read!("a.exs")

        assert Source.rm(source) == :ok

        assert Source.rm(source) ==
                 {:error, %Rewrite.SourceError{reason: :enoent, path: "a.exs", action: :rm}}
      end)
    end

    test "returns an error" do
      source = Source.from_string(":a")

      assert Source.rm(source) ==
               {:error, %Rewrite.SourceError{reason: :nopath, path: nil, action: :rm}}
    end
  end

  describe "rm!/1" do
    @describetag :tmp_dir

    test "deletes file", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        File.write!("a.exs", ":a")
        source = Source.read!("a.exs")

        assert Source.rm!(source) == :ok

        assert File.exists?("a.exs") == false
      end)
    end

    test "raises an exception for a posix error", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        File.write!("a.exs", ":a")
        source = Source.read!("a.exs")

        assert Source.rm!(source) == :ok

        messsage = ~s'could not remove file "a.exs": no such file or directory'

        assert_raise SourceError, messsage, fn ->
          Source.rm!(source) ==
            {:error, %Rewrite.SourceError{reason: :nopath, path: nil, action: :rm}}
        end
      end)
    end

    test "raises an exception" do
      source = Source.from_string(":a")

      messsage = "could not remove file: no path found"

      assert_raise SourceError, messsage, fn ->
        Source.rm!(source) ==
          {:error, %Rewrite.SourceError{reason: :nopath, path: nil, action: :rm}}
      end
    end
  end

  describe "write/1" do
    @describetag :tmp_dir

    test "writes changes to disk", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        File.write!("a.txt", "a")
        source = "a.txt" |> Source.read!() |> Source.update(:content, "b")

        assert {:ok, _updated} = Source.write(source)

        assert File.read!(source.path) == "b\n"
      end)
    end

    test "writes not to disk", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        path = "a.txt"
        File.write!(path, "a")
        File.touch!(path, 1)
        stats = File.stat!(path)
        source = Source.read!(path)

        assert {:ok, ^source} = Source.write(source)

        assert File.stat!(path) == stats
      end)
    end
  end

  describe "write!/1" do
    @describetag :tmp_dir

    test "writes changes to disk", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        File.write!("a.txt", "a")
        source = "a.txt" |> Source.read!() |> Source.update(:content, "b")

        assert saved = Source.write!(source)

        assert File.read!(source.path) == "b\n"
        assert Source.updated?(saved) == false
      end)
    end

    test "raises an exception when old file can't be removed", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        source = "a" |> Source.from_string("a.txt") |> Source.update(:path, "b.txt")

        message = ~s'could not write to file "a.txt": no such file or directory'

        assert_raise SourceError, message, fn ->
          Source.write!(source)
        end

        assert File.exists?("b.exs") == false
      end)
    end

    test "raises an exception when file changed", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        path = "a.txt"
        File.write!(path, "a")
        source = path |> Source.read!() |> Source.update(:content, "x")
        File.write!(path, "b")

        message = ~s'could not write to file "a.txt": file changed since reading'

        assert_raise SourceError, message, fn ->
          Source.write!(source)
        end
      end)
    end
  end

  describe "update/3" do
    test "does not update source when code not changed" do
      source = Source.read!("test/fixtures/source/hello.txt")
      updated = Source.update(source, Test, :content, source.content)

      assert Source.updated?(updated) == false
    end

    test "updates the code" do
      path = "test/fixtures/source/hello.txt"
      txt = File.read!(path)
      new = "bye"

      source =
        path
        |> Source.read!()
        |> Source.update(Tester, :content, new)

      assert source.history == [{:content, Tester, txt}]
      assert source.content == new
    end

    # TODO: this test goes to source/ex_test.exs
    # test "updates the code with an AST" do
    #   path = "test/fixtures/source/simple.ex"
    #   code = File.read!(path)
    #   changes = code |> String.replace("MyApp", "TheApp") |> String.trim_trailing()
    #   zipper = changes |> Sourceror.parse_string!() |> Zipper.zip()

    #   source =
    #     path
    #     |> Source.read!()
    #     |> Source.update(:test, ast: Zipper.root(zipper))

    #   assert_source(source, %{
    #     path: path,
    #     code: changes,
    #     modules: [TheApp.Simple],
    #     updates: [{:code, :test, code}],
    #     ast: Sourceror.parse_string!(changes)
    #   })
    # end

    #     test "updates the code twice" do
    #       path = "test/fixtures/source/simple.ex"
    #       code = File.read!(path)
    #       changes1 = String.replace(code, "MyApp", "TheApp")
    #       changes2 = String.replace(changes1, "TheApp", "Application")

    #       orig = Source.read!(path)

    #       source =
    #         orig
    #         |> Source.update(:foo, code: changes1)
    #         |> Source.update(:bar, code: changes2)

    #       assert_source(source, %{
    #         path: path,
    #         code: changes2,
    #         modules: [Application.Simple],
    #         updates: [
    #           {:code, :bar, changes1},
    #           {:code, :foo, code}
    #         ]
    #       })
    #     end

    #     test "updates the code and path" do
    #       path = "test/fixtures/source/simple.ex"
    #       code = File.read!(path)
    #       changes1 = String.replace(code, "MyApp", "TheApp")
    #       changes2 = "test/fixtures/source/the_app.ex"

    #       source =
    #         path
    #         |> Source.read!()
    #         |> Source.update(:foo, code: changes1)
    #         |> Source.update(:bar, path: changes2)

    #       assert_source(source, %{
    #         path: changes2,
    #         code: changes1,
    #         modules: [TheApp.Simple],
    #         updates: [
    #           {:path, :bar, path},
    #           {:code, :foo, code}
    #         ]
    #       })
    #     end
  end

  describe "path/1" do
    test "returns path" do
      path = "test/fixtures/source/hello.txt"
      source = Source.read!(path)

      assert Source.path(source) == path
    end

    test "returns current path" do
      source = Source.read!("test/fixtures/source/hello.txt")
      path = "test/fixtures/source/new.ex"

      source = Source.update(source, :path, path)

      assert Source.path(source) == path
    end
  end

  describe "path/2" do
    test "returns the path for the given version" do
      path = "test/fixtures/source/hello.txt"

      source =
        path
        |> Source.read!()
        |> Source.update(:path, "a.txt")
        |> Source.update(:path, "b.txt")
        |> Source.update(:path, "c.txt")

      assert Source.path(source, 1) == path
      assert Source.path(source, 2) == "a.txt"
      assert Source.path(source, 3) == "b.txt"
      assert Source.path(source, 4) == "c.txt"
    end

    test "returns the path for given version without path changes" do
      path = "test/fixtures/source/hello.txt"

      source =
        path
        |> Source.read!()
        |> Source.update(:content, "bye")
        |> Source.update(:content, "hi")

      assert Source.path(source, 1) == path
      assert Source.path(source, 2) == path
      assert Source.path(source, 3) == path
    end
  end

  describe "content/2" do
    test "returns the content for the given version without content changes" do
      path = "test/fixtures/source/hello.txt"
      content = File.read!(path)

      source =
        path
        |> Source.read!()
        |> Source.update(:path, "a.txt")
        |> Source.update(:path, "b.txt")

      assert Source.content(source, 1) == content
      assert Source.content(source, 2) == content
      assert Source.content(source, 3) == content
    end

    test "returns the content for given version" do
      content = "foo"

      source =
        content
        |> Source.from_string()
        |> Source.update(:content, "bar")
        |> Source.update(:content, "baz")

      assert Source.content(source, 1) == content
      assert Source.content(source, 2) == "bar"
      assert Source.content(source, 3) == "baz"
    end
  end

  describe "put_private/3" do
    test "updates the private map" do
      source = Source.from_string("a + b\n")

      assert source = Source.put_private(source, :any_key, :any_value)
      assert source.private[:any_key] == :any_value
    end
  end
end
