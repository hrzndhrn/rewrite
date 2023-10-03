defmodule RewriteNewBench do
  use BencheeDsl.Benchmark

  config time: 20

  before_scenario do
    path = "tmp/bench"
    File.mkdir_p(path)
    File.cd!(path, fn ->
      for x <- 1..1_000 do
        File.write!("bench_#{x}.ex", ":bench" |> List.duplicate(x) |> Enum.join("\n") )
      end
    end)
  end

  job new do
    Rewrite.new!("tmp/bench/**")
  end
end
