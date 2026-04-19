defmodule ZoneConsole.CLI do
  @moduledoc "Escript entry point — authenticate against Uro then launch the TUI."

  alias ZoneConsole.{Keychain, UroClient}

  # session tokens are plain strings — use Keychain directly, not FabricMMOGKeyStore
  @kc_package "org.v-sekai.godot"
  @kc_service "zone_console"
  @kc_account "uro_session"

  def main(args) do
    load_dotenv()

    uro_url =
      Enum.at(args, 0) ||
        System.get_env("URO_URL") ||
        "http://localhost:4000"

    IO.puts("Uro: #{uro_url}")

    authed =
      with {:cached, {:ok, token}} <- {:cached, Keychain.get_password(@kc_package, @kc_service, @kc_account)},
           client = %UroClient{base_url: uro_url, access_token: token},
           {:ok, verified} <- UroClient.current_user(client) do
        IO.puts("(session restored from keychain)")
        verified
      else
        _ -> fresh_login(uro_url)
      end

    Application.put_env(:zone_console, :uro_client, authed)
    {:ok, _pid} = ZoneConsole.App.start_link([])
    Process.sleep(:infinity)
  end

  defp fresh_login(uro_url) do
    username =
      System.get_env("URO_USERNAME") ||
        (IO.gets("username: ") |> String.trim())

    password =
      System.get_env("URO_PASSWORD") ||
        (IO.gets("password: ") |> String.trim())

    case UroClient.login(UroClient.new(uro_url), username, password) do
      {:ok, authed} ->
        Keychain.set_password(@kc_package, @kc_service, @kc_account, authed.access_token)
        authed

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
