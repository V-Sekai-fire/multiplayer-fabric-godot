defmodule ZoneConsole.CLI do
  @moduledoc "Escript entry point — authenticate against Uro then launch the TUI."

  alias ZoneConsole.UroClient

  def main(args) do
    uro_url = Enum.at(args, 0) || "http://localhost:4000"

    IO.puts("Uro: #{uro_url}")
    username = IO.gets("username: ") |> String.trim()
    password = IO.gets("password: ") |> String.trim()

    client = UroClient.new(uro_url)

    case UroClient.login(client, username, password) do
      {:ok, authed} ->
        Application.put_env(:zone_console, :uro_client, authed)
        ExRatatui.run(ZoneConsole.App, [])

      {:error, reason} ->
        IO.puts(:stderr, "Login failed: #{reason}")
        System.halt(1)
    end
  end
end
