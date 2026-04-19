defmodule ZoneConsole.Keychain do
  @moduledoc """
  Cross-platform OS keychain access — Elixir port of thirdparty/keychain/.

  Backed by ZoneConsole.Keychain.Nif (Rustler + `keyring` crate):
    macOS   → Security.framework
    Linux   → libsecret / kernel keyring
    Windows → Credential Vault

  All three functions mirror the C++ keychain:: namespace:
    get_password(package, service, user)
    set_password(package, service, user, password)
    delete_password(package, service, user)

  On macOS, service = package <> "." <> service (makeServiceName).
  """

  alias ZoneConsole.Keychain.Nif

  @doc "Returns {:ok, password} | {:error, :not_found} | {:error, message}."
  @spec get_password(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :not_found | String.t()}
  def get_password(package, service, user) do
    backend().get_password(service_name(package, service), user)
  end

  @doc "Returns :ok | {:error, message}."
  @spec set_password(String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, String.t()}
  def set_password(package, service, user, password) do
    backend().set_password(service_name(package, service), user, password)
  end

  @doc "Returns :ok | {:error, :not_found} | {:error, message}."
  @spec delete_password(String.t(), String.t(), String.t()) ::
          :ok | {:error, :not_found | String.t()}
  def delete_password(package, service, user) do
    backend().delete_password(service_name(package, service), user)
  end

  # package + "." + service mirrors makeServiceName in keychain_mac.cpp
  defp service_name(package, service), do: package <> "." <> service

  defp backend do
    Application.get_env(:zone_console, :keychain_backend, Nif)
  end
end
