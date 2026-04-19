Application.ensure_all_started(:propcheck)
ZoneConsole.Keychain.Mock.start()
Application.put_env(:zone_console, :keychain_backend, ZoneConsole.Keychain.Mock)
ExUnit.start()
