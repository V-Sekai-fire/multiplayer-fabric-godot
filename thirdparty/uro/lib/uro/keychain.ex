defmodule Uro.Keychain do
  @moduledoc """
  DB-backed keychain mirroring FabricMMOGKeyStore.

  Blobs are AES-256-GCM encrypted at rest using a key derived from the
  application's secret_key_base. The stored JSON format matches the C++ blob:
    {"key":"<base64>","iv":"<base64>","stored_at":<unix>}

  TTL mirrors C++ KEY_TTL_SECONDS = 86400.
  """

  import Ecto.Query
  alias Uro.Repo
  alias Uro.Keychain.Entry

  @ttl_seconds 86_400
  @package "org.v-sekai.godot"
  @service "multiplayer_fabric_mmog.asset_key"

  @doc "Store or replace an asset key. key and iv are raw binaries (16 and 12 bytes)."
  @spec put(String.t(), binary(), binary()) :: :ok | {:error, term()}
  def put(account, key, iv) when is_binary(key) and is_binary(iv) do
    now = System.os_time(:second)

    blob =
      Jason.encode!(%{
        "key" => Base.encode64(key),
        "iv" => Base.encode64(iv),
        "stored_at" => now
      })

    {enc_blob, enc_iv} = encrypt(blob)

    Repo.transaction(fn ->
      existing = Repo.get_by(Entry, service: @service, account: account)

      attrs = %{
        service: @service,
        account: account,
        blob_enc: enc_blob,
        enc_iv: enc_iv,
        stored_at: now
      }

      result =
        if existing do
          existing |> Entry.changeset(attrs) |> Repo.update()
        else
          %Entry{} |> Entry.changeset(attrs) |> Repo.insert()
        end

      case result do
        {:ok, _} -> :ok
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Fetch a key by account. Returns {:ok, key, iv} or {:error, :not_found | :expired}."
  @spec get(String.t()) :: {:ok, binary(), binary()} | {:error, :not_found | :expired}
  def get(account) do
    get_with_clock(account, System.os_time(:second))
  end

  @doc "Like get/1 but accepts an explicit unix timestamp for TTL checks (testing)."
  @spec get_with_clock(String.t(), integer()) ::
          {:ok, binary(), binary()} | {:error, :not_found | :expired}
  def get_with_clock(account, now) do
    case Repo.get_by(Entry, service: @service, account: account) do
      nil ->
        {:error, :not_found}

      entry ->
        if now - entry.stored_at > @ttl_seconds do
          {:error, :expired}
        else
          blob = decrypt(entry.blob_enc, entry.enc_iv)

          case Jason.decode(blob) do
            {:ok, %{"key" => k64, "iv" => iv64}} ->
              {:ok, Base.decode64!(k64), Base.decode64!(iv64)}

            _ ->
              {:error, :not_found}
          end
        end
    end
  end

  @doc "Delete a stored key."
  @spec remove(String.t()) :: :ok
  def remove(account) do
    Repo.delete_all(
      from e in Entry, where: e.service == @service and e.account == ^account
    )

    :ok
  end

  @doc "Package constant matching C++ PACKAGE."
  def package, do: @package

  @doc "Service constant matching C++ SERVICE."
  def service, do: @service

  # ── encryption ──────────────────────────────────────────────────────────────

  defp derive_key do
    secret = Application.fetch_env!(:uro, UroWeb.Endpoint)[:secret_key_base]
    :crypto.hash(:sha256, secret)
  end

  defp encrypt(plaintext) do
    key = derive_key()
    iv = :crypto.strong_rand_bytes(12)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, "", true)
    {ciphertext <> tag, iv}
  end

  defp decrypt(blob, iv) do
    key = derive_key()
    {ciphertext, tag} = split_tag(blob)
    :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, "", tag, false)
  end

  defp split_tag(blob) do
    tag_size = 16
    ct_size = byte_size(blob) - tag_size
    <<ciphertext::binary-size(ct_size), tag::binary-size(tag_size)>> = blob
    {ciphertext, tag}
  end
end
