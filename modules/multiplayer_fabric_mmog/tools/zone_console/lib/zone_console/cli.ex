defmodule ZoneConsole.CLI do
  @moduledoc "Escript entry point — authenticate against Uro then launch the TUI."

  alias ZoneConsole.UroClient

  def main(args) do
    load_dotenv()

    uro_url =
      Enum.at(args, 0) ||
        System.get_env("URO_URL") ||
        "http://localhost:4000"

    IO.puts("Uro: #{uro_url}")

    username =
      System.get_env("URO_USERNAME") ||
        (IO.gets("username: ") |> String.trim())

    password =
      System.get_env("URO_PASSWORD") ||
        (IO.gets("password: ") |> String.trim())

    client = UroClient.new(uro_url)

    case UroClient.login(client, username, password) do
      {:ok, authed} ->
        Application.put_env(:zone_console, :uro_client, authed)

        {:ok, _pid} = ZoneConsole.App.start_link([])
        Process.sleep(:infinity)

      {:error, reason} ->
        IO.puts(:stderr, "Login failed: #{reason}")
        System.halt(1)
    end
  end

  defp load_dotenv do
    path = Path.join([File.cwd!(), ".env"])

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.each(fn line ->
        case String.split(line, "=", parts: 2) do
          [key, value] -> System.put_env(String.trim(key), String.trim(value))
          _ -> :ok
        end
      end)
    end
  end
end
