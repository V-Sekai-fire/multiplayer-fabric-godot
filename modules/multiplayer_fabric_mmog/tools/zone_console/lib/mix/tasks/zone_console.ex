defmodule Mix.Tasks.ZoneConsole do
  @shortdoc "Launch the zone operator TUI"
  use Mix.Task

  @impl true
  def run(args) do
    Application.ensure_all_started(:zone_console)
    ZoneConsole.CLI.main(args)
  end
end
