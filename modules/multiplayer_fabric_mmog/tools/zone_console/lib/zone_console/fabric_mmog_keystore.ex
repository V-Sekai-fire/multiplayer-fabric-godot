defmodule ZoneConsole.FabricMMOGKeyStore do
  @moduledoc """
  Elixir port of modules/keychain/fabric_mmog_keystore.cpp.

  Persists AES-128 key + GCM IV under an asset UUID in the OS keychain, with a
  24-hour TTL enforced on read. The blob stored by the OS is JSON:
    {"key":"<base64>","iv":"<base64>","stored_at":<unix_seconds>}

  Constants mirror the C++ definitions exactly:
    AES_KEY_BYTES = 16
    AES_IV_BYTES  = 12
    KEY_TTL_SECONDS = 86400
    PACKAGE  = "org.v-sekai.godot"
    SERVICE  = "multiplayer_fabric_mmog.asset_key"
  """

  alias ZoneConsole.Keychain

  @aes_key_bytes 16
  @aes_iv_bytes 12
  @key_ttl_seconds 86_400
  @package "org.v-sekai.godot"
  @service "multiplayer_fabric_mmog.asset_key"

  def aes_key_bytes, do: @aes_key_bytes
  def aes_iv_bytes, do: @aes_iv_bytes
  def key_ttl_seconds, do: @key_ttl_seconds
  def package, do: @package
  def service, do: @service

  @doc """
  Persist raw key (16 bytes) + iv (12 bytes) under asset_uuid.
  Overwrites any existing entry. Returns :ok or {:error, message}.
  Mirrors FabricMMOGKeyStore::put.
  """
  @spec put(String.t(), binary(), binary()) :: :ok | {:error, String.t()}
  def put(asset_uuid, key, iv)
      when byte_size(key) == @aes_key_bytes and byte_size(iv) == @aes_iv_bytes do
    blob =
      Jason.encode!(%{
        "key" => Base.encode64(key),
        "iv" => Base.encode64(iv),
        "stored_at" => System.os_time(:second)
      })

    case Keychain.set_password(@package, @service, asset_uuid, blob) do
      :ok -> :ok
      {:error, err} -> {:error, err.message}
    end
  end

  @doc """
  Retrieve key + iv for asset_uuid. Returns {:ok, key, iv} or {:error, reason}
  where reason is :not_found | :expired | {:invalid, msg} | {:os_error, msg}.
  Mirrors FabricMMOGKeyStore::get.
  """
  @spec get(String.t()) ::
          {:ok, binary(), binary()}
          | {:error, :not_found | :expired | {:invalid | :os_error, String.t()}}
  def get(asset_uuid) do
    get_with_clock(asset_uuid, System.os_time(:second))
  end

  @doc "Like get/1 but with an injected unix timestamp for TTL testing."
  @spec get_with_clock(String.t(), integer()) ::
          {:ok, binary(), binary()}
          | {:error, :not_found | :expired | {:invalid | :os_error, String.t()}}
  def get_with_clock(asset_uuid, now) do
    case Keychain.get_password(@package, @service, asset_uuid) do
      {:error, :not_found} -> {:error, :not_found}
      {:error, msg} -> {:error, {:os_error, msg}}
      {:ok, blob} -> decode_blob(blob, now)
    end
  end

  @doc """
  Remove asset_uuid's entry. Deleting a missing entry returns :ok (idempotent).
  Mirrors FabricMMOGKeyStore::remove.
  """
  @spec remove(String.t()) :: :ok | {:error, String.t()}
  def remove(asset_uuid) do
    case Keychain.delete_password(@package, @service, asset_uuid) do
      :ok -> :ok
      {:error, :not_found} -> :ok
      {:error, msg} -> {:error, msg}
    end
  end

  # ── private ──────────────────────────────────────────────────────────────────

  defp decode_blob(blob, now) do
    with {:ok, map} <- Jason.decode(blob),
         {:ok, key_b64} <- required(map, "key"),
         {:ok, iv_b64} <- required(map, "iv"),
         {:ok, stored_at} <- required(map, "stored_at"),
         :ok <- check_ttl(stored_at, now),
         {:ok, key} <- decode_bytes(key_b64, @aes_key_bytes, "key"),
         {:ok, iv} <- decode_bytes(iv_b64, @aes_iv_bytes, "iv") do
      {:ok, key, iv}
    end
  end

  defp required(map, field) do
    case Map.fetch(map, field) do
      {:ok, v} -> {:ok, v}
      :error -> {:error, {:invalid, "stored key material missing #{field}"}}
    end
  end

  defp check_ttl(stored_at, now) when is_integer(stored_at) do
    if now - stored_at > @key_ttl_seconds do
      {:error, :expired}
    else
      :ok
    end
  end

  defp check_ttl(_, _), do: {:error, {:invalid, "stored_at is not an integer"}}

  defp decode_bytes(b64, expected_len, field_name) do
    case Base.decode64(b64) do
      {:ok, bytes} when byte_size(bytes) == expected_len ->
        {:ok, bytes}

      {:ok, bytes} ->
        {:error, {:invalid, "stored #{field_name} length #{byte_size(bytes)} != #{expected_len}"}}

      :error ->
        {:error, {:invalid, "stored #{field_name} is not valid base64"}}
    end
  end
end
