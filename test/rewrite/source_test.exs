defmodule Rewrite.SourceTest do
  use ExUnit.Case

  alias Rewrite.DotFormatter
  alias Rewrite.Source
  alias Rewrite.SourceError
  alias Rewrite.SourceKeyError

  doctest Rewrite.Source

  describe "read/1" do
    test "creates new source" do
      path = "test/fixtures/source/hello.txt"
      mtime = File.stat!(path, time: :posix).mtime
      hash = hash(path)

      assert Source.read!(path) == %Source{
               from: :file,
               owner: Rewrite,
               path: path,
               content: "hello\n",
               filetype: nil,
               hash: hash,
               issues: [],
               private: %{},
               timestamp: mtime,
               history: []
             }
    end

    test "creates new source from full path" do
      path = Path.join(File.cwd!(), "test/fixtures/source/hello.txt")
      mtime = File.stat!(path, time: :posix).mtime
      hash = hash(path)

      assert Source.read!(path) == %Source{
               from: :file,
               owner: Rewrite,
               path: path,
               content: "hello\n",
               filetype: nil,
               hash: hash,
               issues: [],
               private: %{},
               timestamp: mtime,
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
        source = "a" |> Source.from_string(path: "a.txt") |> Source.update(:path, "b.txt")

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

  describe "update/4" do
    test "does not update source when code not changed" do
      source = Source.read!("test/fixtures/source/hello.txt")
      updated = Source.update(source, :content, source.content, by: Test)

      assert Source.updated?(updated) == false
    end

    test "updates the content" do
      path = "test/fixtures/source/hello.txt"
      txt = File.read!(path)
      new = "bye"

      source =
        path
        |> Source.read!()
        |> Source.update(:content, new, by: Tester)

      assert source.history == [{:content, Tester, txt}]
      assert source.content == new
      assert updated_timestamp?(source)
    end

    test "updates the path" do
      path = "test/fixtures/source/hello.txt"
      new = "test/fixtures/source/bye.txt"

      source =
        path
        |> Source.read!()
        |> Source.update(:path, new)

      assert source.history == [{:path, Rewrite, path}]
      assert source.path == new
      assert updated_timestamp?(source)
    end

    test "updates with filetype value" do
      source = ":a" |> Source.Ex.from_string(path: "test/a.ex") |> Source.touch(now(-10))
      quoted = Sourceror.parse_string!(":b")

      assert source = Source.update(source, :quoted, quoted)
      assert source.filetype != nil
      assert Source.get(source, :content) == ":b\n"
      assert Source.updated?(source) == true
      assert updated_timestamp?(source)
    end

    test "does not update with filetype value without any changes" do
      timestamp = now(-10)
      source = ":a" |> Source.Ex.from_string(path: "test/a.ex") |> Source.touch(timestamp)
      quoted = Sourceror.parse_string!(":a")

      assert source = Source.update(source, :quoted, quoted)
      assert source.filetype != nil
      assert Source.get(source, :content) == ":a"
      assert Source.updated?(source) == false
      assert source.timestamp == timestamp
    end
  end

  describe "get/3" do
    test "returns the content for the given version without content changes" do
      path = "test/fixtures/source/hello.txt"
      content = File.read!(path)

      source =
        path
        |> Source.read!()
        |> Source.update(:path, "a.txt")
        |> Source.update(:path, "b.txt")

      assert Source.get(source, :content, 1) == content
      assert Source.get(source, :content, 2) == content
      assert Source.get(source, :content, 3) == content
    end

    test "returns the content for given version" do
      content = "foo"

      source =
        content
        |> Source.from_string()
        |> Source.update(:content, "bar")
        |> Source.update(:content, "baz")

      assert Source.get(source, :content, 1) == content
      assert Source.get(source, :content, 2) == "bar"
      assert Source.get(source, :content, 3) == "baz"
    end

    test "returns path" do
      path = "test/fixtures/source/hello.txt"
      source = Source.read!(path)

      assert Source.get(source, :path) == path
    end

    test "returns current path" do
      source = Source.read!("test/fixtures/source/hello.txt")
      path = "test/fixtures/source/new.ex"

      source = Source.update(source, :path, path)

      assert Source.get(source, :path) == path
    end

    test "returns the path for the given version" do
      path = "test/fixtures/source/hello.txt"

      source =
        path
        |> Source.read!()
        |> Source.update(:path, "a.txt")
        |> Source.update(:path, "b.txt")
        |> Source.update(:path, "c.txt")

      assert Source.get(source, :path, 1) == path
      assert Source.get(source, :path, 2) == "a.txt"
      assert Source.get(source, :path, 3) == "b.txt"
      assert Source.get(source, :path, 4) == "c.txt"
    end

    test "returns the path for given version without path changes" do
      path = "test/fixtures/source/hello.txt"

      source =
        path
        |> Source.read!()
        |> Source.update(:content, "bye")
        |> Source.update(:content, "hi")

      assert Source.get(source, :path, 1) == path
      assert Source.get(source, :path, 2) == path
      assert Source.get(source, :path, 3) == path
    end

    test "returns quoted from filetype ex" do
      source = ":a" |> Source.Ex.from_string() |> Source.update(:content, ":b")

      assert Source.get(source, :quoted) ==
               {:__block__, [trailing_comments: [], leading_comments: [], line: 1, column: 1],
                [:b]}

      assert Source.get(source, :quoted, 1) ==
               {:__block__, [trailing_comments: [], leading_comments: [], line: 1, column: 1],
                [:a]}
    end

    test "raises a SourceKeyError" do
      source = Source.from_string("test")

      message = """
      key :unknown not found in source. This function is just definded for the \
      keys :content, :path and keys provided by filetype.\
      """

      assert_raise SourceKeyError, message, fn ->
        Source.get(source, :unknown)
      end

      assert_raise SourceKeyError, message, fn ->
        Source.get(source, :unknown, 1)
      end
    end

    test "raises a SourceKeyError for a source with filetype" do
      source = Source.Ex.from_string("test")

      message = """
      key :unknown not found in source. This function is just definded for the \
      keys :content, :path and keys provided by filetype.\
      """

      assert_raise SourceKeyError, message, fn ->
        Source.get(source, :unknown)
      end

      assert_raise SourceKeyError, message, fn ->
        Source.get(source, :unknown, 1)
      end
    end
  end

  describe "put_private/3" do
    test "updates the private map" do
      source = Source.from_string("a + b\n")

      assert source = Source.put_private(source, :any_key, :any_value)
      assert source.private[:any_key] == :any_value
    end
  end

  describe "undo/2" do
    test "returns unchanged source when source not updated" do
      source = Source.from_string("test")

      assert Source.undo(source) == source
      assert Source.undo(source, 5) == source
    end

    test "returns first source when source was updated once" do
      source = Source.from_string("test")
      updated = Source.update(source, :content, "changed")
      undo = Source.undo(updated)

      assert undo == source
      assert Source.updated?(undo) == false
    end

    test "returns previous source" do
      a = Source.from_string("test-a")
      b = Source.update(a, :content, "test-b")
      c = Source.update(b, :path, "test/foo.txt")
      d = Source.update(c, :content, "test-d")

      assert Source.undo(d) == c
      assert Source.undo(d, 2) == b
      assert Source.undo(d, 3) == a
      assert Source.undo(d, 9) == a
    end

    test "returns previous Elixir source" do
      a = Source.Ex.from_string(":a")
      b = Source.update(a, :content, ":b")
      c = Source.update(b, :path, "test/foo.txt")
      d = Source.update(c, :content, ":d")

      assert Source.undo(d) == c
      assert Source.undo(d, 2) == b
      assert Source.undo(d, 3) == a
      assert Source.undo(d, 9) == a
    end
  end

  describe "issues/1" do
    test "returns issues" do
      source =
        Source.from_string("test")
        |> Source.add_issue(:foo)
        |> Source.add_issue(:bar)

      assert Source.issues(source) == [:bar, :foo]
    end
  end

  describe "format/2" do
    test "formats a source" do
      source = Source.Ex.from_string("foo  bar   baz")
      assert {:ok, source} = Source.format(source)
      assert source.content == "foo(bar(baz))\n"
      assert source.owner == Rewrite
      assert source.history == [{:content, Rewrite, "foo  bar   baz"}]
    end

    test "does not updates source when not needed" do
      source = Source.Ex.from_string(":foo\n")
      assert {:ok, source} = Source.format(source)
      assert source.content == ":foo\n"
      assert source.history == []
    end

    test "formats a source with owner and by" do
      source = Source.Ex.from_string("foo  bar   baz", owner: Walter)
      assert {:ok, source} = Source.format(source, by: Felix)
      assert source.content == "foo(bar(baz))\n"
      assert source.owner == Walter
      assert source.history == [{:content, Felix, "foo  bar   baz"}]
    end

    test "returns an error" do
      source = Source.from_string("x =", path: "no.ex")
      assert {:error, _error} = Source.format(source)
    end

    test "formats a source with source.dot_formatter" do
      dot_formatter = DotFormatter.from_formatter_opts(locals_without_parens: [foo: 1])
      source = Source.Ex.from_string("foo  bar   baz")
      assert {:ok, source} = Source.format(source, dot_formatter: dot_formatter)
      assert source.content == "foo bar(baz)\n"
    end
  end

  describe "format!/2" do
    test "formats a source" do
      source = Source.Ex.from_string("foo  bar   baz")
      assert source = Source.format!(source)
      assert source.content == "foo(bar(baz))\n"
    end

    test "raises an exception" do
      source = Source.from_string("x =", path: "no.ex")

      assert_raise TokenMissingError, fn ->
        Source.format!(source)
      end
    end
  end

  test "inspect" do
    source = Source.from_string("test", path: "foo.ex")
    assert inspect(source) == "#Rewrite.Source<foo.ex>"
  end

  defp hash(path) do
    content = File.read!(path)
    :erlang.phash2({path, content})
  end

  defp now(diff \\ 0) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    now + diff
  end

  defp updated_timestamp?(source) do
    if File.regular?(source.path) do
      mtime = File.stat!(source.path, time: :posix).mtime
      assert mtime < source.timestamp
    end

    assert_in_delta source.timestamp, now(), 1
  end
end
