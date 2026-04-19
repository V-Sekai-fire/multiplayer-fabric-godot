defmodule Wtransport.Client do
  @moduledoc "WebTransport client connection with cert-hash pinning."

  defstruct [:send_tx, :shutdown_tx]

  @doc """
  Connect to a WebTransport server.

  - `url` — `"https://host:port/path"`
  - `cert_hash_b64` — base64-encoded SHA-256 DER hash (14-day cert)
  - `owner_pid` — receives `{:zone_datagram, binary}` messages
  """
  @spec connect(String.t(), String.t(), pid()) :: {:ok, %__MODULE__{}} | {:error, String.t()}
  def connect(url, cert_hash_b64, owner_pid) do
    Wtransport.Native.connect_client(url, cert_hash_b64, owner_pid)
  end

  @spec send_datagram(%__MODULE__{}, binary()) :: :ok | {:error, String.t()}
  def send_datagram(%__MODULE__{} = client, data) when is_binary(data) do
    case Wtransport.Native.send_datagram_client(client, data) do
      :ok -> :ok
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  @spec disconnect(%__MODULE__{}) :: :ok
  def disconnect(%__MODULE__{} = client) do
    case Wtransport.Native.disconnect_client(client) do
      :ok -> :ok
      {:ok, _} -> :ok
      _ -> :ok
    end
  end
end
