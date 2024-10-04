defmodule RewriteTest do
  use RewriteCase, async: false

  alias Rewrite.Source

  alias Rewrite.DotFormatter
  alias Rewrite.Error
  alias Rewrite.SourceError
  alias Rewrite.UpdateError

  doctest Rewrite

  describe "put!/1" do
    test "adds a source to the project" do
      project = Rewrite.new()

      assert project = Rewrite.put!(project, Source.from_string(":a", "a.exs"))
      assert map_size(project.sources) == 1
    end

    test "raises an exception when path is nil" do
      project = Rewrite.new()

      message = "no path found"

      assert_raise Error, message, fn ->
        Rewrite.put!(project, Source.Ex.from_string(":a"))
      end
    end

    test "raises an exception when overwrites" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":a", "a.exs")
        ])

      message = ~s'overwrites "a.exs"'

      assert_raise Error, message, fn ->
        Rewrite.put!(project, Source.from_string(":b", "a.exs"))
      end
    end
  end

  describe "rm!/2" do
    @describetag :tmp_dir

    test "removes a source file", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        path = "a.exs"
        File.write!(path, ":a")
        project = Rewrite.new!("**")

        assert project = Rewrite.rm!(project, path)
        assert Enum.empty?(project) == true
        assert File.exists?(path) == false
      end)
    end

    test "raises an exception when file operation fails", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        path = "a.exs"
        File.write!(path, ":a")
        project = Rewrite.new!("**")
        File.rm!(path)

        message = ~s'could not remove file "a.exs": no such file or directory'

        assert_raise SourceError, message, fn ->
          Rewrite.rm!(project, path)
        end
      end)
    end

    test "raises an exception when path not in project" do
      project = Rewrite.new()

      message = ~s'no source found for "a.exs"'

      assert_raise Error, message, fn ->
        Rewrite.rm!(project, "a.exs")
      end
    end
  end

  describe "new!/2" do
    test "creates a project from one file" do
      path = "test/fixtures/source/simple.ex"
      assert project = Rewrite.new!(path)
      assert Enum.count(project.sources) == 1
      assert %Source{filetype: %Source.Ex{}} = Rewrite.source!(project, path)
    end

    test "creates a project from one file without extensions" do
      path = "test/fixtures/source/simple.ex"
      assert project = Rewrite.new!(path, filetypes: [])
      assert Enum.count(project.sources) == 1
      assert %Source{filetype: nil} = Rewrite.source!(project, path)
    end

    test "creates a project from one file with given extensions" do
      ex = "test/fixtures/source/simple.ex"
      txt = "test/fixtures/source/hello.txt"

      assert project =
               Rewrite.new!([ex, txt],
                 filetypes: [
                   {Source, owner: Test},
                   {Source.Ex, formatter_opts: [exclude_plugins: [Test]]}
                 ]
               )

      assert Enum.count(project.sources) == 2
      assert %Source{filetype: nil, owner: Test} = Rewrite.source!(project, txt)

      assert %Source{filetype: %Source.Ex{opts: opts}} =
               Rewrite.source!(project, ex)

      assert opts == [formatter_opts: [exclude_plugins: [Test]]]
    end

    test "creates a project from wildcard" do
      inputs = ["test/fixtures/source/*.ex"]
      assert project = Rewrite.new!(inputs)
      assert Enum.count(project.sources) == 4
    end

    test "creates a project from wildcards" do
      inputs = ["test/fixtures/source/d*.ex", "test/fixtures/source/s*.ex"]
      assert project = Rewrite.new!(inputs)
      assert Enum.count(project.sources) == 2
    end

    test "creates a project from glob" do
      inputs = [GlobEx.compile!("test/fixtures/source/*.ex")]
      assert project = Rewrite.new!(inputs)
      assert Enum.count(project.sources) == 4
    end

    test "creates a project from globs" do
      inputs = [
        GlobEx.compile!("test/fixtures/source/d*.ex"),
        GlobEx.compile!("test/fixtures/source/s*.ex")
      ]

      assert project = Rewrite.new!(inputs)
      assert Enum.count(project.sources) == 2
    end

    test "throws an error for unreadable file" do
      file = "test/fixtures/source/simple.ex"
      File.chmod(file, 0o111)
      inputs = ["test/fixtures/source/*.ex"]
      message = ~s|could not read file "test/fixtures/source/simple.ex": permission denied|

      assert_raise File.Error, message, fn ->
        Rewrite.new!(inputs)
      end

      File.chmod(file, 0o644)
    end

    test "throws a syntax error in code" do
      inputs = ["test/fixtures/error.ex"]

      assert_raise SyntaxError, fn ->
        Rewrite.new!(inputs)
      end
    end
  end

  describe "read!/2" do
    test "extends project" do
      project = Rewrite.new()

      assert project = Rewrite.read!(project, "test/fixtures/source/simple.ex")
      assert Enum.count(project.sources) == 1
    end

    test "extends project with full path" do
      project = Rewrite.new()
      path = Path.join(File.cwd!(), "test/fixtures/source/simple.ex")

      assert project = Rewrite.read!(project, path)
      assert Enum.count(project.sources) == 1
    end

    test "does not read already read files" do
      path = "test/fixtures/source/simple.ex"
      project = Rewrite.new!(path)

      assert project = Rewrite.read!(project, path)
      assert Enum.count(project.sources) == 1
    end
  end

  describe "from_sources/1" do
    test "creates a project" do
      assert {:ok,
              %Rewrite{
                extensions: %{"default" => Source, ".ex" => Source.Ex, ".exs" => Source.Ex},
                sources: %{
                  "b.txt" => %Source{
                    from: :string,
                    path: "b.txt",
                    content: "b",
                    hash: <<174, 49, 163, 166, 58, 86, 116, 125, 28, 58, 67, 31, 0, 34, 7, 180>>,
                    owner: Rewrite,
                    history: [],
                    issues: [],
                    private: %{},
                    timestamp: timestamp
                  }
                }
              }} =
               Rewrite.from_sources([
                 Source.from_string("b", "b.txt")
               ])

      assert_in_delta timestamp, DateTime.utc_now() |> DateTime.to_unix(), 1
    end

    test "returns an error if path is missing" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b")

      assert {:error, error} = Rewrite.from_sources([a, b])

      assert error == %Error{
               reason: :invalid_sources,
               duplicated_paths: [],
               missing_paths: [b]
             }

      assert Error.message(error) == "invalid sources"
    end

    test "returns an error if paths are duplicated" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "a.exs")

      assert {:error, error} = Rewrite.from_sources([a, b])

      assert error == %Error{
               reason: :invalid_sources,
               duplicated_paths: [b],
               missing_paths: []
             }

      assert Error.message(error) == "invalid sources"
    end
  end

  describe "from_sources!/1" do
    test "creates a project" do
      assert %Rewrite{
               extensions: %{
                 "default" => Source,
                 ".ex" => Source.Ex,
                 ".exs" => Source.Ex
               },
               sources: %{
                 "b.txt" => %Source{
                   from: :string,
                   path: "b.txt",
                   content: "b",
                   hash: <<174, 49, 163, 166, 58, 86, 116, 125, 28, 58, 67, 31, 0, 34, 7, 180>>,
                   owner: Rewrite,
                   history: [],
                   issues: [],
                   timestamp: timestamp,
                   private: %{}
                 }
               }
             } =
               Rewrite.from_sources!([
                 Source.from_string("b", "b.txt")
               ])

      assert_in_delta timestamp, DateTime.utc_now() |> DateTime.to_unix(), 1
    end

    test "raises an error if path is missing" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b")

      assert_raise Error, "invalid sources", fn ->
        Rewrite.from_sources!([a, b])
      end
    end

    test "raises an error if paths are duplicated" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "a.exs")

      assert_raise Error, "invalid sources", fn ->
        Rewrite.from_sources!([a, b])
      end
    end
  end

  describe "source/2" do
    test "returns the source struct for a path" do
      path = "test/fixtures/source/simple.ex"
      project = Rewrite.new!([path])
      assert {:ok, %Source{}} = Rewrite.source(project, path)
    end

    test "raises an :error for an invalid path" do
      project = Rewrite.new!(["test/fixtures/source/simple.ex"])
      path = "foo/bar.ex"

      assert Rewrite.source(project, path) ==
               {:error, %Error{reason: :nosource, path: path}}
    end
  end

  describe "source!/2" do
    test "returns the source struct for a path" do
      path = "test/fixtures/source/simple.ex"
      project = Rewrite.new!([path])
      assert %Source{} = Rewrite.source!(project, path)
    end

    test "raises an error for an invalid path" do
      project = Rewrite.new!(["test/fixtures/source/simple.ex"])

      assert_raise Error, ~s|no source found for "foo/bar.ex"|, fn ->
        Rewrite.source!(project, "foo/bar.ex")
      end
    end
  end

  describe "map/2" do
    @describetag :tmp_dir

    test "maps a project without any changes", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      baz = Path.join(tmp_dir, "baz.ex")
      File.write!(foo, ":foo")
      File.write!(bar, ":bar")
      File.write!(baz, ":baz")

      project = Rewrite.new!("#{tmp_dir}/**")

      {:ok, mapped} = Rewrite.map(project, fn source -> source end)

      assert project == mapped
    end

    test "maps a project", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      baz = Path.join(tmp_dir, "baz.ex")
      File.write!(foo, ":foo")
      File.write!(bar, ":bar")
      File.write!(baz, ":baz")

      project = Rewrite.new!("#{tmp_dir}/**")

      {:ok, mapped} =
        Rewrite.map(project, fn source ->
          Source.update(source, :content, ":test")
        end)

      assert project != mapped
    end

    test "returns an error", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      baz = Path.join(tmp_dir, "baz.ex")
      File.write!(foo, ":foo")
      File.write!(bar, ":bar")
      File.write!(baz, ":baz")

      project = Rewrite.new!("#{tmp_dir}/**")

      {:error, errors, mapped} =
        Rewrite.map(project, fn
          %Source{path: ^foo} = source -> Source.update(source, :content, ":test")
          %Source{path: ^bar} = source -> Source.update(source, :path, foo)
          %Source{path: ^baz} = source -> Source.update(source, :path, nil)
        end)

      assert project != mapped
      assert mapped |> Rewrite.source!(foo) |> Source.get(:content) == ":test"

      assert errors == [
               %UpdateError{reason: :nopath, source: baz},
               %UpdateError{reason: :overwrites, source: bar, path: foo}
             ]
    end
  end

  describe "map!/2" do
    @describetag :tmp_dir

    test "maps a project without any changes", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      baz = Path.join(tmp_dir, "baz.ex")
      File.write!(foo, ":foo")
      File.write!(bar, ":bar")
      File.write!(baz, ":baz")

      project = Rewrite.new!("#{tmp_dir}/**")

      mapped = Rewrite.map!(project, fn source -> source end)

      assert project == mapped
    end

    test "maps a project", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      baz = Path.join(tmp_dir, "baz.ex")
      File.write!(foo, ":foo")
      File.write!(bar, ":bar")
      File.write!(baz, ":baz")

      project = Rewrite.new!("#{tmp_dir}/**")

      mapped =
        Rewrite.map!(project, fn source ->
          Source.update(source, :content, ":test")
        end)

      assert project != mapped
    end

    test "raises an exception when overwrites", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      File.write!(foo, ":foo")
      File.write!(bar, ":bar")

      project = Rewrite.new!("#{tmp_dir}/**")

      message = ~s|can't update source "#{bar}": updated source overwrites "#{foo}"|

      assert_raise UpdateError, message, fn ->
        Rewrite.map!(project, fn source ->
          Source.update(source, :path, foo)
        end)
      end
    end

    test "raises an exception when path is missing", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      File.write!(foo, ":foo")

      project = Rewrite.new!("#{tmp_dir}/**")

      message = ~s|can't update source "#{foo}": no path in updated source|

      assert_raise UpdateError, message, fn ->
        Rewrite.map!(project, fn source ->
          Source.update(source, :path, nil)
        end)
      end
    end

    test "raises RuntimeError" do
      {:ok, project} = Rewrite.from_sources([Source.from_string(":a", "a.exs")])

      message = "expected %Source{} from anonymous function given to Rewrite.update/3, got: :foo"

      assert_raise RuntimeError, message, fn ->
        Rewrite.map!(project, fn _source -> :foo end)
      end
    end
  end

  describe "Enum.map/2" do
    test "maps a project without any changes" do
      inputs = ["test/fixtures/source/simple.ex"]

      project = Rewrite.new!(inputs)

      mapped = Enum.map(project, fn source -> source end)

      assert is_list(mapped)
      assert Enum.sort(mapped) == project.sources |> Map.values() |> Enum.sort()
    end

    test "maps a project" do
      inputs = ["test/fixtures/source/simple.ex"]

      project = Rewrite.new!(inputs)

      mapped =
        Enum.map(project, fn source ->
          Source.update(source, :test, :path, "new/path/simple.ex")
        end)

      assert is_list(mapped)
      assert Rewrite.from_sources(mapped) != {:ok, project}
    end
  end

  describe "update/2" do
    test "updates a source" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "a.exs")
      {:ok, project} = Rewrite.from_sources([a])

      {:ok, project} = Rewrite.update(project, b)

      assert project.sources == %{"a.exs" => b}
    end

    test "returns an error when path changed" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert Rewrite.update(project, b) ==
               {:error, %Error{reason: :nosource, path: "b.exs"}}
    end

    test "returns an error when path is nil" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b")
      {:ok, project} = Rewrite.from_sources([a])

      assert Rewrite.update(project, b) == {:error, %Error{reason: :nopath}}
    end
  end

  describe "update!/2" do
    test "raises an exception when source not in project" do
      project = Rewrite.new()
      source = Source.from_string(":a", "a.exs")

      message = ~s|no source found for "a.exs"|

      assert_raise Error, message, fn ->
        Rewrite.update!(project, source)
      end
    end

    test "raises an exception when source path is nil" do
      project = Rewrite.new()
      source = Source.from_string(":a")

      message = "no path found"

      assert_raise Error, message, fn ->
        Rewrite.update!(project, source)
      end
    end
  end

  describe "update/3" do
    test "updates a source" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert {:ok, project} = Rewrite.update(project, a.path, b)

      assert project.sources == %{"b.exs" => b}
    end

    test "updates a source with a function" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert {:ok, project} = Rewrite.update(project, a.path, fn _ -> b end)

      assert project.sources == %{"b.exs" => b}
    end

    test "returns an error when source not in project" do
      project = Rewrite.new()
      a = Source.from_string(":a", "a.exs")

      assert Rewrite.update(project, a.path, a) ==
               {:error, %Error{reason: :nosource, path: a.path}}
    end

    test "returns an error when path is nil" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b")
      {:ok, project} = Rewrite.from_sources([a])

      assert Rewrite.update(project, a.path, b) ==
               {:error, %UpdateError{reason: :nopath, source: a.path}}
    end

    test "returns an error when another source would be overwritten" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")
      c = Source.from_string(":c", "b.exs")
      {:ok, project} = Rewrite.from_sources([a, b])

      assert Rewrite.update(project, a.path, c) ==
               {:error, %UpdateError{reason: :overwrites, source: a.path, path: c.path}}
    end

    test "raises an error when function does not returns a source" do
      a = Source.from_string(":a", "a.exs")
      {:ok, project} = Rewrite.from_sources([a])
      message = "expected %Source{} from anonymous function given to Rewrite.update/3, got: nil"

      assert_raise RuntimeError, message, fn ->
        Rewrite.update(project, a.path, fn _ -> nil end)
      end
    end
  end

  describe "update!/3" do
    test "updates a source" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert project = Rewrite.update!(project, a.path, b)

      assert project.sources == %{"b.exs" => b}
    end

    test "updates a source with a function" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert project = Rewrite.update!(project, a.path, fn _ -> b end)

      assert project.sources == %{"b.exs" => b}
    end

    test "returns an error when source not in project" do
      project = Rewrite.new()
      a = Source.from_string(":a", "a.exs")

      message = ~s'no source found for "a.exs"'

      assert_raise Error, message, fn ->
        Rewrite.update!(project, a.path, a)
      end
    end

    test "returns an error when path is nil" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b")
      {:ok, project} = Rewrite.from_sources([a])

      message = ~s|can't update source "a.exs": no path in updated source|

      assert_raise UpdateError, message, fn ->
        Rewrite.update!(project, a.path, b)
      end
    end

    test "returns an error when another source would be overwritten" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")
      c = Source.from_string(":c", "b.exs")
      {:ok, project} = Rewrite.from_sources([a, b])

      message = ~s|can't update source "a.exs": updated source overwrites "b.exs"|

      assert_raise(UpdateError, message, fn ->
        Rewrite.update!(project, a.path, c)
      end)
    end

    test "raises an error when function does not returns a source" do
      a = Source.from_string(":a", "a.exs")
      {:ok, project} = Rewrite.from_sources([a])
      message = "expected %Source{} from anonymous function given to Rewrite.update/3, got: nil"

      assert_raise RuntimeError, message, fn ->
        Rewrite.update!(project, a.path, fn _ -> nil end)
      end
    end
  end

  describe "count/2" do
    test "counts by the given type" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":a", "a.ex"),
          Source.from_string(":b", "b.exs")
        ])

      assert Rewrite.count(project, ".ex") == 1
      assert Rewrite.count(project, ".exs") == 1
    end
  end

  describe "sources/1" do
    test "returns all sources" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":c", "c.exs"),
          Source.from_string(":a", "a.exs"),
          Source.from_string(":b", "b.exs")
        ])

      assert project
             |> Rewrite.sources()
             |> Enum.map(fn source -> source.path end) == ["a.exs", "b.exs", "c.exs"]
    end
  end

  describe "write/2" do
    @describetag :tmp_dir

    test "writes a source to disk", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      File.write!(foo, ":foo")

      source = Source.read!(foo)
      {:ok, project} = Rewrite.from_sources([source])
      source = Source.update(source, :content, ":foofoo\n")

      assert {:ok, project} = Rewrite.write(project, source)
      assert {:ok, source} = Rewrite.source(project, foo)
      assert Source.get(source, :content) == File.read!(foo)
      assert Source.updated?(source) == false
    end

    test "returns an error when the file was changed", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      File.write!(foo, ":foo")

      source = Source.read!(foo)
      {:ok, project} = Rewrite.from_sources([source])
      source = Source.update(source, :test, :content, ":foofoo\n")

      File.write!(foo, ":bar")

      assert Rewrite.write(project, source) ==
               {:error, %SourceError{reason: :changed, path: foo, action: :write}}
    end

    test "writes a source to disk by path", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      File.write!(foo, ":foo")

      source = Source.read!(foo)
      {:ok, project} = Rewrite.from_sources([source])
      source = Source.update(source, :test, :content, ":foofoo\n")
      project = Rewrite.update!(project, source)

      assert {:ok, project} = Rewrite.write(project, foo)
      assert {:ok, source} = Rewrite.source(project, foo)
      assert Source.get(source, :content) == File.read!(foo)
      assert Source.updated?(source) == false
    end

    test "returns an error for missing source" do
      project = Rewrite.new()

      assert Rewrite.write(project, "source.ex") ==
               {:error, %Error{reason: :nosource, path: "source.ex"}}
    end
  end

  describe "write_all/2" do
    @describetag :tmp_dir

    test "writes sources to disk", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "test.ex")

      {:ok, project} =
        Rewrite.from_sources([
          ":foo" |> Source.from_string(path) |> Source.update(Test, :content, ":test")
        ])

      assert {:ok, project} = Rewrite.write_all(project)
      assert File.read!(path) == ":test\n"
      assert project |> Rewrite.source!(path) |> Source.updated?() == false
    end

    test "creates dir", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "new_dir/test.ex")

      {:ok, project} =
        Rewrite.from_sources([
          ":foo\n" |> Source.from_string() |> Source.update(Test, :path, path)
        ])

      assert {:ok, _project} = Rewrite.write_all(project)
      assert File.read!(path) == ":foo\n"
    end

    test "removes old file", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      File.write!(foo, ":bar")

      {:ok, project} =
        Rewrite.from_sources([
          foo |> Source.read!() |> Source.update(:test, :path, bar)
        ])

      assert {:ok, _project} = Rewrite.write_all(project)
      refute File.exists?(foo)
      assert File.read!(bar) == ":bar\n"
    end

    test "excludes files", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      File.write!(foo, ":foo")

      {:ok, project} =
        Rewrite.from_sources([
          foo |> Source.read!() |> Source.update(:test, :path, bar)
        ])

      assert {:ok, _project} = Rewrite.write_all(project, exclude: [bar])
      assert File.exists?(foo)
    end

    test "returns {:error, errors, project}", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "foo.ex")
      File.write!(path, ":bar")
      System.cmd("chmod", ["-w", path])

      {:ok, project} =
        Rewrite.from_sources([
          path |> Source.read!() |> Source.update(:test, :content, ":new")
        ])

      assert {:error, [error], _project} = Rewrite.write_all(project)
      assert error == %SourceError{reason: :eacces, path: path, action: :write}
    end

    test "does nothing without updates", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "foo.ex")
      File.write!(path, ":bar")

      project = Rewrite.new!(path)

      assert {:ok, saved} = Rewrite.write_all(project)
      assert project == saved
    end

    test "returns {:error, errors, project} for changed files", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      File.write!(foo, ":foo")
      File.write!(bar, ":bar")

      {:ok, project} =
        Rewrite.from_sources([
          foo |> Source.read!() |> Source.update(:test, :content, ":up"),
          bar |> Source.read!() |> Source.update(:test, :content, ":barbar")
        ])

      File.write!(foo, ":foofoo")

      assert {:error, errors, project} = Rewrite.write_all(project)

      assert errors == [%SourceError{reason: :changed, path: foo, action: :write}]
      assert File.read!(bar) == ":barbar\n"
      assert project |> Rewrite.source!(foo) |> Source.updated?() == true
      assert project |> Rewrite.source!(bar) |> Source.updated?() == false

      assert {:ok, _project} = Rewrite.write_all(project, force: true)
      assert File.read!(foo) == ":up\n"
    end
  end

  describe "issue?/1" do
    test "returns false" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":a", "a.exs"),
          Source.from_string(":b", "b.exs"),
          Source.from_string(":c", "c.exs")
        ])

      assert Rewrite.issues?(project) == false
    end

    test "returns true" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":a", "a.exs"),
          Source.from_string(":b", "b.exs"),
          ":c" |> Source.from_string("c.exs") |> Source.add_issue(%{foo: 42})
        ])

      assert Rewrite.issues?(project) == true
    end
  end

  describe "Enum" do
    test "count/1" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":a", "a.exs"),
          Source.from_string(":b", "b.exs"),
          Source.from_string(":c", "c.exs")
        ])

      assert Enum.count(project) == 3
    end

    test "slice/3" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")
      c = Source.from_string(":c", "c.exs")
      {:ok, project} = Rewrite.from_sources([a, b, c])

      assert Enum.slice(project, 1, 2) == [b, c]
      assert Enum.slice(project, 1, 1) == [b]
      assert Enum.slice(project, 1, 0) == []
    end

    test "member?/1 returns true" do
      source = Source.from_string(":a", "a.exs")
      {:ok, project} = Rewrite.from_sources([source])

      assert Enum.member?(project, source) == true
    end

    test "member?/1 returns false" do
      a = Source.from_string(":a", "a.exs")
      b = Source.from_string(":b", "b.exs")

      {:ok, project} = Rewrite.from_sources([a])

      assert Enum.member?(project, b) == false
      assert Enum.member?(project, :a) == false
    end
  end

  describe "dot_formatter/1/2" do
    test "returns a default dot formatter" do
      project = Rewrite.new()
      assert Rewrite.dot_formatter(project) == DotFormatter.new()
    end

    test "returns the set dot formatter" do
      {:ok, dot_formatter} = DotFormatter.read()
      project = Rewrite.new()

      assert dot_formatter != DotFormatter.new()
      assert Rewrite.dot_formatter(project, dot_formatter) == project
      assert Rewrite.dot_formatter(project) == dot_formatter
    end
  end

  describe "new_source/4" do
    test "creates a source" do
      rewrite = Rewrite.new()
      assert {:ok, rewrite} = Rewrite.new_source(rewrite, "test.ex", "test")
      assert {:ok, source} = Rewrite.source(rewrite, "test.ex")
      assert is_struct(source.filetype, Source.Ex)
      assert rewrite.id == source.rewrite_id
    end

    test "return an error tuple when the source already exists" do
      rewrite = Rewrite.new()
      assert {:ok, rewrite} = Rewrite.new_source(rewrite, "test.ex", "test")
      assert {:error, _error} = Rewrite.new_source(rewrite, "test.ex", "test")
    end

    test "creates a source with opts" do
      rewrite = Rewrite.new()

      assert {:ok, rewrite} =
               Rewrite.new_source(rewrite, "test.ex", "test", owner: MyApp, sync_quoted: false)

      assert {:ok, source} = Rewrite.source(rewrite, "test.ex")
      assert source.owner == MyApp
      assert source.filetype.opts == [sync_quoted: false]
    end
  end

  describe "new_source!/4" do
    test "raises an error tuple when the source already exists" do
      rewrite = Rewrite.new()
      assert rewrite = Rewrite.new_source!(rewrite, "test.ex", "test")

      message = "overwrites \"test.ex\""

      assert_raise Error, message, fn ->
        Rewrite.new_source!(rewrite, "test.ex", "test")
      end
    end
  end

  describe "format/2" do
    @describetag :tmp_dir
    test "formats the rewrite project", context do
      in_tmp context do
        write!(%{
          ".formatter.exs" => """
          [
            inputs: ["**/*{.ex,.exs}"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex" => """
            foo   bar   baz
          """
        })

        project = Rewrite.new!("**/*")

        assert {:ok, formatted} = Rewrite.format(project)
        assert read!(formatted, "a.ex") == "foo(bar(baz))\n"

        {:ok, dot_formatter} = DotFormatter.read()
        assert Rewrite.dot_formatter(project, dot_formatter)
        assert {:ok, formatted} = Rewrite.format(project)
        assert read!(formatted, "a.ex") == "foo bar(baz)\n"

        project = Rewrite.new!("**/*", dot_formatter: dot_formatter)

        assert {:ok, formatted} = Rewrite.format(project)
        assert read!(formatted, "a.ex") == "foo bar(baz)\n"
      end
    end
  end

  describe "KeyValueStore" do
    test "returns the default for unset value" do
      rewrite = Rewrite.new()
      assert Rewrite.KeyValueStore.get(rewrite, "foo", "bar") == "bar"
    end
  end
end
