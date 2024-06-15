defmodule Rewrite.MixProject do
  use Mix.Project

  @version "0.10.5"
  @source_url "https://github.com/hrzndhrn/rewrite"

  def project do
    [
      aliases: aliases(),
      app: :rewrite,
      version: @version,
      deps: deps(),
      description: description(),
      dialyzer: dialyzer(),
      docs: docs(),
      elixir: "~> 1.13",
      package: package(),
      preferred_cli_env: preferred_cli_env(),
      source_url: @source_url,
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      xref: [exclude: [FreedomFormatter.Formatter]]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mix, :crypto],
      mod: {Rewrite.Application, []}
    ]
  end

  defp description do
    "An API for rewriting sources in an Elixir project. Powered by sourceror."
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end

  defp dialyzer do
    [
      ignore_warnings: ".dialyzer_ignore.exs",
      plt_file: {:no_warn, "test/support/plts/dialyzer.plt"},
      flags: [:unmatched_returns]
    ]
  end

  def preferred_cli_env do
    [
      carp: :test,
      cover: :test,
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.html": :test,
      "coveralls.github": :test
    ]
  end

  defp aliases do
    [
      carp: "test --trace --seed 0 --max-failures 1",
      cover: "coveralls.html"
    ]
  end

  defp deps do
    [
      {:glob_ex, "~> 0.1"},
      {:sourceror, "~> 1.0"},
      # dev/test
      {:benchee_dsl, "~> 0.5", only: :dev},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.25", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Marcus Kruse"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
