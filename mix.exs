defmodule SchedEx.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sched_ex,
      version: "1.0.2",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "SchedEx",
      source_url: "https://github.com/SchedEx/SchedEx"
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
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:mix_test_watch, "~> 0.0", only: :dev, runtime: false},
      {:inch_ex, only: :docs}
    ]
  end

  defp description() do
    "SchedEx is a simple yet deceptively powerful scheduling library for Elixir."
  end

  defp package() do
    [
      files: ["lib", "test", "config", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Mat Trudel"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/SchedEx/SchedEx"}
    ]
  end
end
