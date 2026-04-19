defmodule ZoneConsole.Keychain.Nif do
  @moduledoc """
  Rustler NIF wrapping the Rust `keyring` crate.

  Delegates to the OS secure credential store:
    macOS   → Security.framework (Keychain)
    Linux   → libsecret / kernel keyring
    Windows → Credential Vault

  All functions are scheduled as DirtyIo because keychain operations can
  block (e.g. macOS prompts the user to unlock the keychain).
  """

  use Rustler, otp_app: :zone_console, crate: "keychain_nif"

  # Stubs replaced at load time by the compiled NIF.
  def get_password(_service, _user), do: :erlang.nif_error(:nif_not_loaded)
  def set_password(_service, _user, _password), do: :erlang.nif_error(:nif_not_loaded)
  def delete_credential(_service, _user), do: :erlang.nif_error(:nif_not_loaded)
end
