defmodule Rewrite.TextDiffTest do
  use ExUnit.Case

  alias Rewrite.TextDiff

  doctest Rewrite.TextDiff

  describe "format/3" do
    test "with unchanged texts" do
      assert TextDiff.format("abc", "abc") == []
      assert to_binary("abc", "abc") == ""
    end

    test "with one deleted line" do
      old = "del"
      new = ""

      assert output = to_binary(old, new)

      if IO.ANSI.enabled?() do
        assert output ==
                 "1  \e[31m - \e[0m\e[90m|\e[0m\e[31mdel\e[0m\n  1\e[32m + \e[0m\e[90m|\e[0m\n"
      end

      assert to_binary(old, new, color: false) == """
             1   - |del
               1 + |
             """
    end

    test "with one changed line" do
      old = "one three two"
      new = "one two three"

      assert output = to_binary(old, new)

      if IO.ANSI.enabled?() do
        assert output == """
               1  \e[31m - \e[0m\e[90m|\e[0mone \e[31mthree\e[0m\e[41m \e[0m\e[31m\e[0mtwo
                 1\e[32m + \e[0m\e[90m|\e[0mone two\e[32m\e[0m\e[42m \e[0m\e[32mthree\e[0m
               """
      end

      assert to_binary(old, new, color: false) == """
             1   - |one three two
               1 + |one two three
             """
    end

    test "with one deleted line in the middle" do
      old = """
      aaa
      bbb
      ccc
      ddd
      eee
      fff
      ggg
      """

      new = """
      aaa
      bbb
      ccc
      eee
      fff
      ggg
      """

      exp = """
         ...|
      2 2   |bbb
      3 3   |ccc
      4   - |ddd
      5 4   |eee
      6 5   |fff
         ...|
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false) == exp
    end

    test "with multiple deleted lines" do
      old = """
      aaa
      bbb
      ccc
      ddd
      eee
      fff
      ggg\
      """

      new = """
      aaa
      ggg\
      """

      exp = """
      1 1   |aaa
      2   - |bbb
      3   - |ccc
      4   - |ddd
      5   - |eee
      6   - |fff
      7 2   |ggg
      """

      # assert TextDiff.format(old, new)

      if IO.ANSI.enabled?() do
        assert to_binary(old, new) == """
               1  \e[31m - \e[0m\e[90m|\e[0mone \e[31mthree\e[0m\e[41m \e[0m\e[31m\e[0mtwo
                 1\e[32m + \e[0m\e[90m|\e[0mone two\e[32m\e[0m\e[42m \e[0m\e[32mthree\e[0m
               """
      end

      assert to_binary(old, new, color: false) == exp
    end

    test "with one added line in the middle" do
      old = """
      aaa
      bbb
      ccc
      eee
      fff
      ggg
      """

      new = """
      aaa
      bbb
      ccc
      ddd
      eee
      fff
      ggg
      """

      exp = """
         ...|
      2 2   |bbb
      3 3   |ccc
        4 + |ddd
      4 5   |eee
      5 6   |fff
         ...|
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false) == exp
    end

    test "with changed first line" do
      old = """
      aaa
      bbb
      ccc
      ddd
      """

      new = """
      axa
      bbb
      ccc
      ddd
      """

      exp = """
      1   - |aaa
        1 + |axa
      2 2   |bbb
      3 3   |ccc
         ...|
      """

      assert to_binary(old, new, color: false) == exp
    end

    test "with changed last line" do
      old = """
      aaa
      bbb
      ccc
      ddd
      """

      new = """
      aaa
      bbb
      ccc
      dxd
      """

      exp = """
         ...|
      2 2   |bbb
      3 3   |ccc
      4   - |ddd
        4 + |dxd
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false) == exp
    end

    test "with changed first and last line" do
      old = """
      aaa
      bbb
      ccc
      ddd
      eee
      """

      new = """
      axa
      bbb
      ccc
      ddd
      exe
      """

      exp = """
      1   - |aaa
        1 + |axa
      2 2   |bbb
         ...|
      4 4   |ddd
      5   - |eee
        5 + |exe
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false, before: 1, after: 1) == exp
    end

    test "with changed second and second last line" do
      old = """
      aaa
      bbb
      ccc
      ddd
      eee
      fff
      ggg
      hhh
      iii\
      """

      new = """
      aaa
      bXb
      ccc
      ddd
      eee
      fff
      ggg
      hXh
      iii\
      """

      exp = """
      1 1   |aaa
      2   - |bbb
        2 + |bXb
      3 3   |ccc
         ...|
      7 7   |ggg
      8   - |hhh
        8 + |hXh
      9 9   |iii
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false, before: 1, after: 1) == exp
    end

    test "colorized added tab" do
      assert output = to_binary("ab", "a\tb")

      if IO.ANSI.enabled?() do
        assert output =~ "\e[42m\t"
      end
    end

    test "colorized deleted tab" do
      assert output = to_binary("a\tb", "ab")

      if IO.ANSI.enabled?() do
        assert output =~ "\e[41m\t"
      end
    end

    test "shows added CR" do
      old = """
      aaa
      bbb
      """

      new = """
      aaa\r
      bbb
      """

      exp = """
      1   - |aaa
        1 + |aaa↵
      2 2   |bbb
         ...|
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false, before: 1, after: 1) == exp
    end

    test "shows multiple added CRs" do
      old = """
      aaa
      bbb
      """

      new = """
      aaa\r
      bbb\r
      ccc\r
      """

      exp = """
      1   - |aaa
      2   - |bbb
        1 + |aaa↵
        2 + |bbb↵
        3 + |ccc\r
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false, before: 1, after: 1) == exp
    end

    test "shows deleted CR" do
      old = """
      aaa\r
      bbb
      """

      new = """
      aaa
      bbb
      """

      exp = """
      1   - |aaa↵
        1 + |aaa
      2 2   |bbb
         ...|
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false, before: 1, after: 1) == exp
    end

    test "shows multiple deleted CRs" do
      old = """
      aaa\r
      bbb\r
      """

      new = """
      aaa
      bbb
      ccc
      """

      exp = """
      1   - |aaa↵
      2   - |bbb↵
        1 + |aaa
        2 + |bbb
        3 + |ccc
      """

      assert TextDiff.format(old, new)

      assert to_binary(old, new, color: false) == exp
    end

    test "omits line numbers when :line_numbers is false" do
      old = """
      aaa
      bbb
      ccc
      ddd
      eee
      fff
      ggg
      """

      new = """
      aaa
      bbb
      ccc
      eee
      fff
      ggg
      """

      exp = """
      ...|
         |bbb
         |ccc
       - |ddd
         |eee
         |fff
      ...|
      """

      assert TextDiff.format(old, new, line_numbers: false)

      assert to_binary(old, new, color: false, line_numbers: false) == exp
    end

    test "accepts alternate :format" do
      old = """
      aaa
      bbb
      ccc
      ddd
      eee
      """

      new = """
      aaa
      bbb
      xxx
      ddd
      eee
      """

      opts = [
        format: [
          gutter: [
            skip: "~~~",
            ins: "+++",
            del: "---",
            eq: "   "
          ]
        ],
        before: 1,
        after: 1
      ]

      assert to_binary(old, new, [color: false] ++ opts) == """
                ~~~|
             2 2   |bbb
             3  ---|ccc
               3+++|xxx
             4 4   |ddd
                ~~~|
             """

      opts = [
        format: [
          separator: "> "
        ],
        before: 1,
        after: 1
      ]

      assert to_binary(old, new, [color: false] ++ opts) == """
                ...> \n\
             2 2   > bbb
             3   - > ccc
               3 + > xxx
             4 4   > ddd
                ...> \n\
             """

      opts = [
        format: [
          colors: []
        ],
        before: 1,
        after: 1
      ]

      assert to_binary(old, new, opts) == """
                ...|
             2 2   |bbb
             3   - |ccc
               3 + |xxx
             4 4   |ddd
                ...|
             """

      opts = [
        format: [
          colors: [
            ins: [text: :blue],
            del: [text: :magenta],
            skip: [text: :light_black],
            separator: [text: :light_black]
          ]
        ],
        before: 1,
        after: 1
      ]

      assert Rewrite.TextDiff.format(old, new, opts)

      if IO.ANSI.enabled?() do
        assert to_binary(old, new, opts) ==
                 "   \e[90m...\e[0m\e[90m|\e[0m\n2 2   \e[90m|\e[0mbbb\n3  \e[35m - \e[0m\e[90m|\e[0m\e[35mccc\e[0m\n  3\e[34m + \e[0m\e[90m|\e[0m\e[34mxxx\e[0m\n4 4   \e[90m|\e[0mddd\n   \e[90m...\e[0m\e[90m|\e[0m\n"
      end
    end

    test "accepts alternate :tokenizer" do
      for opts <- [[tokenizer: &String.graphemes/1], [tokenizer: {String, :graphemes, []}]] do
        old = "one three two"
        new = "one two three"

        assert output = to_binary(old, new, opts)

        if IO.ANSI.enabled?() do
          assert output == """
                 1  \e[31m - \e[0m\e[90m|\e[0mone three\e[31m\e[0m\e[41m \e[0m\e[31mtwo\e[0m
                   1\e[32m + \e[0m\e[90m|\e[0mone t\e[32mwo\e[0m\e[42m \e[0m\e[32mt\e[0mhree
                 """
        end

        assert to_binary(old, new, [color: false] ++ opts) == """
               1   - |one three two
                 1 + |one two three
               """
      end
    end
  end

  defp to_binary(old, new, opts \\ []) do
    old
    |> TextDiff.format(new, opts)
    |> IO.iodata_to_binary()

    # |> tap(fn result -> IO.puts(result) end)
  end
end
