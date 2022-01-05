defmodule SchedEx.Mixfile do
  use Mix.Project

  @source_url "https://github.com/SchedEx/SchedEx"
  @version "1.1.4"

  def project do
    [
      app: :sched_ex,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      docs: docs(),
      dialyzer: dialyzer(),
      name: "SchedEx"
    ]
  end

  def application do
    [
      extra_applications: [:crontab, :logger, :timex]
    ]
  end

  defp deps do
    [
      {:crontab, "~> 1.1.2"},
      {:timex, "~> 3.1"},
      {:ex_doc, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: [
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end

  defp package do
    [
      description: "SchedEx is a simple yet deceptively powerful scheduling library for Elixir.",
      files: ["lib", "test", "config", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Mat Trudel"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp dialyzer do
    [
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
    ]
  end
end
