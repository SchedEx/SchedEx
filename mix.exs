defmodule SchedEx.Mixfile do
  use Mix.Project

  def project do
    [
      app: :sched_ex,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :timex]
    ]
  end

  defp deps do
    [
      {:timex, "~> 3.1"},
      {:mix_test_watch, "~> 0.0", only: :dev, runtime: false},
    ]
  end
end
