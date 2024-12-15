"test/support/**/*.ex"
|> Path.wildcard()
|> Enum.each(&Code.compile_file/1)

ExUnit.start(theme: "block")
