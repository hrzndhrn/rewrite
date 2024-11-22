defmodule RewriteTest do
  use RewriteCase, async: false

  import GlobEx.Sigils

  alias Rewrite.DotFormatter
  alias Rewrite.DotFormatterError
  alias Rewrite.Error
  alias Rewrite.Source
  alias Rewrite.SourceError
  alias Rewrite.UpdateError

  doctest Rewrite

  describe "put!/1" do
    test "adds a source to the project" do
      project = Rewrite.new()

      assert project = Rewrite.put!(project, Source.from_string(":a", path: "a.exs"))
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
          Source.from_string(":a", path: "a.exs")
        ])

      message = ~s'overwrites "a.exs"'

      assert_raise Error, message, fn ->
        Rewrite.put!(project, Source.from_string(":b", path: "a.exs"))
      end
    end
  end

  describe "delete/2" do
    @describetag :tmp_dir

    test "removes a source file by path", context do
      in_tmp context do
        path = "a.exs"
        File.write!(path, ":a")
        project = Rewrite.new!("**")
        project = Rewrite.delete(project, path)

        assert Enum.empty?(project) == true
        assert File.exists?(path) == true

        Rewrite.write_all(project)
        assert File.exists?(path) == true
      end
    end
  end

  describe "move/4" do
    @describetag :tmp_dir

    test "moves a file to a new location", context do
      in_tmp context do
        from = "a.exs"
        to = "foo/a.exs"
        File.write!(from, ":a")
        project = Rewrite.new!("**")

        {:ok, project} = Rewrite.move(project, from, to)

        assert {:error, _error} = Rewrite.source(project, from)
        assert {:ok, _source} = Rewrite.source(project, to)

        Rewrite.write_all(project)

        assert File.exists?(from) == false
        assert File.read!(to) == ":a\n"
      end
    end

    test "moves a source to a new location", context do
      in_tmp context do
        from = "a.exs"
        to = "foo/a.exs"
        File.write!(from, ":a")
        project = Rewrite.new!("**")
        source = Rewrite.source!(project, from)

        {:ok, project} = Rewrite.move(project, source, to)

        assert {:error, _error} = Rewrite.source(project, from)
        assert {:ok, _source} = Rewrite.source(project, to)

        Rewrite.write_all(project)

        assert File.exists?(from) == false
        assert File.read!(to) == ":a\n"
      end
    end

    test "swaps two files", context do
      in_tmp context do
        a = "a.exs"
        b = "b.exs"
        swap = "swap.exs"
        File.write!(a, ":a")
        File.write!(b, ":b")
        project = Rewrite.new!("**")

        {:ok, project} = Rewrite.move(project, a, swap)
        {:ok, project} = Rewrite.move(project, b, a)
        {:ok, project} = Rewrite.move(project, swap, b)

        assert {:ok, project} = Rewrite.write_all(project)

        assert Rewrite.paths(project) == ["a.exs", "b.exs"]

        assert File.read!(a) == ":b\n"
        assert File.read!(b) == ":a\n"
        assert File.exists?(swap) == false
      end
    end

    test "returns an error if from source not exists" do
      project = Rewrite.new()
      source = Rewrite.create_source(project, "foo.ex", "foo")

      assert {:error, %{reason: :nosource}} = Rewrite.move(project, "foo.ex", "bar.ex")
      assert {:error, %{reason: :nosource}} = Rewrite.move(project, source, "bar.ex")
    end

    test "returns an error if to source exists" do
      project = Rewrite.new()
      project = Rewrite.new_source!(project, "foo.ex", "foo")
      project = Rewrite.new_source!(project, "bar.ex", "bar")

      assert {:error, %{reason: :overwrites}} = Rewrite.move(project, "foo.ex", "bar.ex")
    end
  end

  describe "move!/4" do
    @describetag :tmp_dir

    test "moves a file to a new location", context do
      in_tmp context do
        from = "a.exs"
        to = "foo/a.exs"
        File.write!(from, ":a")
        project = Rewrite.new!("**")

        assert %Rewrite{} = Rewrite.move!(project, from, to)
      end
    end

    test "raises an exception" do
      project = Rewrite.new()

      assert_raise Error, ~s|no source found for "foo.ex"|, fn ->
        Rewrite.move!(project, "foo.ex", "bar.ex")
      end
    end
  end

  describe "rm!/2" do
    @describetag :tmp_dir

    test "removes a source file by path", context do
      in_tmp context do
        path = "a.exs"
        File.write!(path, ":a")
        project = Rewrite.new!("**")

        assert project = Rewrite.rm!(project, path)
        assert Enum.empty?(project) == true
        assert File.exists?(path) == false
      end
    end

    test "removes a source file by source", context do
      in_tmp context do
        path = "a.exs"
        File.write!(path, ":a")
        project = Rewrite.new!("**")
        source = Rewrite.source!(project, path)

        assert project = Rewrite.rm!(project, source)
        assert Enum.empty?(project) == true
        assert File.exists?(path) == false
      end
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

      assert %Source{filetype: %Source.Ex{opts: opts}} = Rewrite.source!(project, ex)

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

    @tag :tmp_dir
    test "excludes files by path and glob", context do
      in_tmp context do
        File.write!("foo.ex", ":foo")
        File.write!("bar.ex", ":bar")
        File.write!("baz.ex", ":baz")

        assert project = Rewrite.new!("**", exclude: ["foo.ex", ~g/baz*/])
        assert project.sources |> Map.keys() == ["bar.ex"]
        assert project.excluded == ["foo.ex", "baz.ex"]
      end
    end

    @tag :tmp_dir
    test "excludes file by function", context do
      in_tmp context do
        File.write!("foo.ex", ":foo")
        File.write!("bar.ex", ":bar")

        exclude? = fn path -> path == "foo.ex" end

        assert project = Rewrite.new!("**", exclude: exclude?)
        assert project.sources |> Map.keys() == ["bar.ex"]
        assert project.excluded == ["foo.ex"]
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
                    hash: 103_569_618,
                    owner: Rewrite,
                    history: [],
                    issues: [],
                    private: %{},
                    timestamp: timestamp
                  }
                }
              }} =
               Rewrite.from_sources([
                 Source.from_string("b", path: "b.txt")
               ])

      assert_in_delta timestamp, DateTime.utc_now() |> DateTime.to_unix(), 1
    end

    test "returns an error if path is missing" do
      a = Source.from_string(":a", path: "a.exs")
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
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "a.exs")

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
                   hash: 103_569_618,
                   owner: Rewrite,
                   history: [],
                   issues: [],
                   timestamp: timestamp,
                   private: %{}
                 }
               }
             } =
               Rewrite.from_sources!([
                 Source.from_string("b", path: "b.txt")
               ])

      assert_in_delta timestamp, DateTime.utc_now() |> DateTime.to_unix(), 1
    end

    test "raises an error if path is missing" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b")

      assert_raise Error, "invalid sources", fn ->
        Rewrite.from_sources!([a, b])
      end
    end

    test "raises an error if paths are duplicated" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "a.exs")

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
      {:ok, project} = Rewrite.from_sources([Source.from_string(":a", path: "a.exs")])

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
          Source.update(source, :path, "new/path/simple.ex", by: :test)
        end)

      assert is_list(mapped)
      assert Rewrite.from_sources(mapped) != {:ok, project}
    end
  end

  describe "update/2" do
    test "updates a source" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "a.exs")
      {:ok, project} = Rewrite.from_sources([a])

      {:ok, project} = Rewrite.update(project, b)

      assert project.sources == %{"a.exs" => b}
    end

    test "returns an error when path changed" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert Rewrite.update(project, b) ==
               {:error, %Error{reason: :nosource, path: "b.exs"}}
    end

    test "returns an error when path is nil" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b")
      {:ok, project} = Rewrite.from_sources([a])

      assert Rewrite.update(project, b) == {:error, %Error{reason: :nopath}}
    end
  end

  describe "update!/2" do
    test "raises an exception when source not in project" do
      project = Rewrite.new()
      source = Source.from_string(":a", path: "a.exs")

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
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert {:ok, project} = Rewrite.update(project, a.path, b)

      assert project.sources == %{"b.exs" => b}
    end

    test "updates a source with a function" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert {:ok, project} = Rewrite.update(project, a.path, fn _ -> b end)

      assert project.sources == %{"b.exs" => b}
    end

    test "returns an error when source not in project" do
      project = Rewrite.new()
      a = Source.from_string(":a", path: "a.exs")

      assert Rewrite.update(project, a.path, a) ==
               {:error, %Error{reason: :nosource, path: a.path}}
    end

    test "returns an error when path is nil" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b")
      {:ok, project} = Rewrite.from_sources([a])

      assert Rewrite.update(project, a.path, b) ==
               {:error, %UpdateError{reason: :nopath, source: a.path}}
    end

    test "returns an error when another source would be overwritten" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")
      c = Source.from_string(":c", path: "b.exs")
      {:ok, project} = Rewrite.from_sources([a, b])

      assert Rewrite.update(project, a.path, c) ==
               {:error, %UpdateError{reason: :overwrites, source: a.path, path: c.path}}
    end

    test "raises an error when function does not returns a source" do
      a = Source.from_string(":a", path: "a.exs")
      {:ok, project} = Rewrite.from_sources([a])
      message = "expected %Source{} from anonymous function given to Rewrite.update/3, got: nil"

      assert_raise RuntimeError, message, fn ->
        Rewrite.update(project, a.path, fn _ -> nil end)
      end
    end
  end

  describe "update!/3" do
    test "updates a source" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert project = Rewrite.update!(project, a.path, b)

      assert project.sources == %{"b.exs" => b}
    end

    test "updates a source with a function" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")
      {:ok, project} = Rewrite.from_sources([a])

      assert project = Rewrite.update!(project, a.path, fn _ -> b end)

      assert project.sources == %{"b.exs" => b}
    end

    test "returns an error when source not in project" do
      project = Rewrite.new()
      a = Source.from_string(":a", path: "a.exs")

      message = ~s'no source found for "a.exs"'

      assert_raise Error, message, fn ->
        Rewrite.update!(project, a.path, a)
      end
    end

    test "returns an error when path is nil" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b")
      {:ok, project} = Rewrite.from_sources([a])

      message = ~s|can't update source "a.exs": no path in updated source|

      assert_raise UpdateError, message, fn ->
        Rewrite.update!(project, a.path, b)
      end
    end

    test "returns an error when another source would be overwritten" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")
      c = Source.from_string(":c", path: "b.exs")
      {:ok, project} = Rewrite.from_sources([a, b])

      message = ~s|can't update source "a.exs": updated source overwrites "b.exs"|

      assert_raise(UpdateError, message, fn ->
        Rewrite.update!(project, a.path, c)
      end)
    end

    test "raises an error when function does not returns a source" do
      a = Source.from_string(":a", path: "a.exs")
      {:ok, project} = Rewrite.from_sources([a])
      message = "expected %Source{} from anonymous function given to Rewrite.update/3, got: nil"

      assert_raise RuntimeError, message, fn ->
        Rewrite.update!(project, a.path, fn _ -> nil end)
      end
    end
  end

  describe "update_source!/4" do
    test "raises an error" do
      project = Rewrite.new()
      message = ~s|no source found for "some.txt"|

      assert_raise Error, message, fn ->
        Rewrite.update_source!(project, "some.txt", :content, &String.upcase/1)
      end
    end
  end

  describe "count/2" do
    test "counts by the given type" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":a", path: "a.ex"),
          Source.from_string(":b", path: "b.exs")
        ])

      assert Rewrite.count(project, ".ex") == 1
      assert Rewrite.count(project, ".exs") == 1
    end
  end

  describe "sources/1" do
    test "returns all sources" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":c", path: "c.exs"),
          Source.from_string(":a", path: "a.exs"),
          Source.from_string(":b", path: "b.exs")
        ])

      assert project
             |> Rewrite.sources()
             |> Enum.map(fn source -> source.path end) == ["a.exs", "b.exs", "c.exs"]
    end
  end

  describe "write!/2" do
    @describetag :tmp_dir

    test "writes a source to disk", context do
      in_tmp context do
        File.write!("foo.ex", ":foo")

        source = Source.read!("foo.ex")
        {:ok, project} = Rewrite.from_sources([source])
        source = Source.update(source, :content, ":foofoo\n")

        assert project = Rewrite.write!(project, source)
        assert source = Rewrite.source!(project, "foo.ex")
        assert Source.get(source, :content) == File.read!("foo.ex")
        assert Source.updated?(source) == false
      end
    end

    test "writes a source to disk by path", context do
      in_tmp context do
        File.write!("foo.ex", ":foo")

        source = Source.read!("foo.ex")
        {:ok, project} = Rewrite.from_sources([source])
        source = Source.update(source, :content, ":foofoo\n", by: :test)
        project = Rewrite.update!(project, source)

        assert project = Rewrite.write!(project, "foo.ex")
        assert source = Rewrite.source!(project, "foo.ex")
        assert Source.get(source, :content) == File.read!("foo.ex")
        assert Source.updated?(source) == false
      end
    end

    test "raises an error for missing source" do
      project = Rewrite.new()

      assert_raise Error, ~s|no source found for "source.ex"|, fn ->
        Rewrite.write!(project, "source.ex")
      end
    end
  end

  describe "write/2" do
    @describetag :tmp_dir

    test "returns an error when the file was changed", context do
      in_tmp context do
        File.write!("foo.ex", ":foo")

        source = Source.read!("foo.ex")
        {:ok, project} = Rewrite.from_sources([source])
        source = Source.update(source, :content, ":foofoo\n", by: :test)

        File.write!("foo.ex", ":bar")

        assert Rewrite.write(project, source) ==
                 {:error, %SourceError{reason: :changed, path: "foo.ex", action: :write}}
      end
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
          ":foo" |> Source.from_string(path: path) |> Source.update(:content, ":test", by: Test)
        ])

      assert {:ok, project} = Rewrite.write_all(project)
      assert File.read!(path) == ":test\n"
      assert project |> Rewrite.source!(path) |> Source.updated?() == false
    end

    test "creates dir", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "new_dir/test.ex")

      {:ok, project} =
        Rewrite.from_sources([
          ":foo\n" |> Source.from_string() |> Source.update(:path, path, by: Test)
        ])

      assert {:ok, _project} = Rewrite.write_all(project)
      assert File.read!(path) == ":foo\n"
    end

    test "removes old file", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      File.write!(foo, ":foo")

      {:ok, project} =
        Rewrite.from_sources([
          foo |> Source.read!() |> Source.update(:path, bar, by: :test)
        ])

      assert {:ok, _project} = Rewrite.write_all(project)
      assert File.exists?(foo) == false
      assert File.read!(bar) == ":foo\n"
    end

    test "excludes files", %{tmp_dir: tmp_dir} do
      foo = Path.join(tmp_dir, "foo.ex")
      bar = Path.join(tmp_dir, "bar.ex")
      File.write!(foo, ":foo")

      {:ok, project} =
        Rewrite.from_sources([
          foo |> Source.read!() |> Source.update(:path, bar, by: :test)
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
          path |> Source.read!() |> Source.update(:content, ":new", by: :test)
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
          foo |> Source.read!() |> Source.update(:content, ":up", by: :test),
          bar |> Source.read!() |> Source.update(:content, ":barbar", by: :test)
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
          Source.from_string(":a", path: "a.exs"),
          Source.from_string(":b", path: "b.exs"),
          Source.from_string(":c", path: "c.exs")
        ])

      assert Rewrite.issues?(project) == false
    end

    test "returns true" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":a", path: "a.exs"),
          Source.from_string(":b", path: "b.exs"),
          ":c" |> Source.from_string(path: "c.exs") |> Source.add_issue(%{foo: 42})
        ])

      assert Rewrite.issues?(project) == true
    end
  end

  describe "Enum" do
    test "count/1" do
      {:ok, project} =
        Rewrite.from_sources([
          Source.from_string(":a", path: "a.exs"),
          Source.from_string(":b", path: "b.exs"),
          Source.from_string(":c", path: "c.exs")
        ])

      assert Enum.count(project) == 3
    end

    test "slice/3" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")
      c = Source.from_string(":c", path: "c.exs")
      {:ok, project} = Rewrite.from_sources([a, b, c])

      assert project |> Enum.slice(1, 2) |> Enum.map(fn source -> source.path end) ==
               ["b.exs", "c.exs"]

      assert project |> Enum.slice(1, 1) |> Enum.map(fn source -> source.path end) ==
               ["b.exs"]

      assert Enum.slice(project, 1, 0) == []
    end

    test "member?/1 returns true" do
      project = Rewrite.new()
      project = Rewrite.new_source!(project, "a.ex", ":a")
      source = Rewrite.source!(project, "a.ex")

      assert Enum.member?(project, source) == true
    end

    test "member?/1 returns false" do
      a = Source.from_string(":a", path: "a.exs")
      b = Source.from_string(":b", path: "b.exs")

      {:ok, project} = Rewrite.from_sources([a])

      assert Enum.member?(project, b) == false
      assert Enum.member?(project, :a) == false
    end
  end

  describe "dot_formatter/1/2" do
    test "returns a default dot formatter" do
      project = Rewrite.new()
      assert Rewrite.dot_formatter(project) == DotFormatter.default()
    end

    test "returns the set dot formatter" do
      {:ok, dot_formatter} = DotFormatter.read()
      project = Rewrite.new()

      assert dot_formatter != DotFormatter.default()
      assert project = Rewrite.dot_formatter(project, dot_formatter)
      assert Rewrite.dot_formatter(project) == dot_formatter
    end
  end

  describe "new_source/4" do
    test "creates a source" do
      rewrite = Rewrite.new()
      assert {:ok, rewrite} = Rewrite.new_source(rewrite, "test.ex", "test")
      assert {:ok, source} = Rewrite.source(rewrite, "test.ex")
      assert is_struct(source.filetype, Source.Ex)
    end

    test "return an error tuple when the source already exists" do
      rewrite = Rewrite.new()
      assert {:ok, rewrite} = Rewrite.new_source(rewrite, "test.ex", "test")
      assert {:error, _error} = Rewrite.new_source(rewrite, "test.ex", "test")
    end

    test "creates a source with opts" do
      rewrite = Rewrite.new()

      assert {:ok, rewrite} =
               Rewrite.new_source(rewrite, "test.ex", "test", owner: MyApp, resync_quoted: false)

      assert {:ok, source} = Rewrite.source(rewrite, "test.ex")
      assert source.owner == MyApp
      assert source.filetype.opts == [resync_quoted: false]
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

  describe "create_source/4" do
    test "creates a source" do
      rewrite = Rewrite.new()
      assert source = Rewrite.create_source(rewrite, "test.ex", "test")
      assert is_struct(source.filetype, Source.Ex)
    end

    test "creates a default source" do
      rewrite = Rewrite.new()
      Rewrite.create_source(rewrite, nil, "test")
      assert source = Rewrite.create_source(rewrite, nil, "test")
      refute is_struct(source.filetype, Source.Ex)
    end
  end

  describe "format/2" do
    @describetag :tmp_dir

    test "formats the rewrite project", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["**/*.{ex,.exs}"],
            locals_without_parens: [foo: 1]
          ]
          """,
          "a.ex": """
            foo   bar   baz
          """
        )

        project = Rewrite.new!("**/*")

        assert {:ok, formatted} = Rewrite.format(project)
        assert read!(formatted, "a.ex") == "foo(bar(baz))\n"

        {:ok, dot_formatter} = DotFormatter.read()
        assert project = Rewrite.dot_formatter(project, dot_formatter)
        assert {:ok, formatted} = Rewrite.format(project)
        assert read!(formatted, "a.ex") == "foo bar(baz)\n"

        project = Rewrite.new!("**/*", dot_formatter: dot_formatter)

        assert {:ok, formatted} = Rewrite.format(project)
        assert read!(formatted, "a.ex") == "foo bar(baz)\n"
      end
    end
  end

  describe "format!/2" do
    @describetag :tmp_dir

    test "raises an error", context do
      in_tmp context do
        write!(
          ".formatter.exs": """
          [
            inputs: ["**/*.{ex,.exs}"],
            locals_without_parens: [foo: 1]
          ]
          """
        )

        project = Rewrite.new!("**/*")

        message = "Expected :remove_plugins to be a list of modules, got: :bar"

        assert_raise DotFormatterError, message, fn ->
          Rewrite.format!(project, remove_plugins: :bar) == :error
        end

        message = "Expected :replace_plugins to be a list of tuples, got: :bar"

        assert_raise DotFormatterError, message, fn ->
          Rewrite.format!(project, replace_plugins: :bar) == :error
        end
      end
    end
  end

  describe "hooks" do
    @describetag :tmp_dir

    test "are called", context do
      in_tmp context do
        File.write!("README.md", "readme")

        "**/*"
        |> Rewrite.new!(hooks: [InspectHook])
        |> Rewrite.new_source!("foo.ex", "foo")
        |> Rewrite.put!(Source.from_string("bar", path: "bar.ex"))
        |> Rewrite.update!("foo.ex", fn source -> Source.update(source, :content, "foofoo") end)
        |> Rewrite.update!("bar.ex", Source.from_string("barbar", path: "bar.ex"))

        assert File.read!("inspect.txt") == """
               :new - #Rewrite<0 source(s)>
               {:added, ["README.md", "inspect.txt"]} - #Rewrite<2 source(s)>
               {:added, ["foo.ex"]} - #Rewrite<3 source(s)>
               {:added, ["bar.ex"]} - #Rewrite<4 source(s)>
               {:updated, "foo.ex"} - #Rewrite<4 source(s)>
               {:updated, "bar.ex"} - #Rewrite<4 source(s)>
               """
      end
    end

    test "are called by from_sources", context do
      in_tmp context do
        source = Source.from_string("foo", path: "foo.ex")
        Rewrite.from_sources([source], hooks: [InspectHook])

        assert File.read!("inspect.txt") == """
               :new - #Rewrite<0 source(s)>
               {:added, ["foo.ex"]} - #Rewrite<1 source(s)>
               """
      end
    end

    test "are called for successfull formatting", context do
      in_tmp context do
        write!(
          "a.ex": """
          x   =   y
          """,
          "b.ex": """
          y   =   x
          """
        )

        project = Rewrite.new!("**/*", hooks: [InspectHook])
        project = Rewrite.format!(project)

        expected = """
        :new - #Rewrite<0 source(s)>
        {:added, ["a.ex", "b.ex", "inspect.txt"]} - #Rewrite<3 source(s)>
        {:updated, "a.ex"} - #Rewrite<3 source(s)>
        {:updated, "b.ex"} - #Rewrite<3 source(s)>
        """

        assert File.read!("inspect.txt") == expected

        Rewrite.format!(project)

        assert File.read!("inspect.txt") == expected
      end
    end

    test "raises an error", context do
      defmodule RaiseHook do
        def handle(_action, _project), do: :foo
      end

      message = "unexpected response from hook, got: :foo"

      assert_raise Error, message, fn ->
        Rewrite.new(hooks: [RaiseHook])
      end
    end
  end

  test "inspect" do
    rewrite = Rewrite.new()
    assert inspect(rewrite) == "#Rewrite<0 source(s)>"
  end
end
