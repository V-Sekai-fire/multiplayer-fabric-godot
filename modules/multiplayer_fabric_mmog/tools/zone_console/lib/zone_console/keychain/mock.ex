defmodule ZoneConsole.Keychain.Mock do
  @moduledoc """
  In-process ETS keychain for tests. Injected via:
    Application.put_env(:zone_console, :keychain_backend, ZoneConsole.Keychain.Mock)

  Mirrors the same get_password/set_password/delete_password interface as the
  NIF so property tests run without a compiled Rust binary or OS keychain.
  """

  @table :keychain_mock

  def start do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  def reset, do: :ets.delete_all_objects(@table)

  def get_password(service, user) do
    case :ets.lookup(@table, {service, user}) do
      [{_, password}] -> {:ok, password}
      [] -> {:error, :not_found}
    end
  end

  def set_password(service, user, password) do
    :ets.insert(@table, {{service, user}, password})
    :ok
  end

  def delete_password(service, user) do
    case :ets.lookup(@table, {service, user}) do
      [] ->
        {:error, :not_found}

      _ ->
        :ets.delete(@table, {service, user})
        :ok
    end
  end
end
