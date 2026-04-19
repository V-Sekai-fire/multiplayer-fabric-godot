defmodule ZoneConsole.MixProject do
  use Mix.Project

  def project do
    [
      app: :zone_console,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: ZoneConsole.CLI]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ex_ratatui, "~> 0.1"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:rustler, "~> 0.34"},
      {:propcheck, "~> 1.4", only: [:test, :dev], runtime: false}
    ]
  end
end
