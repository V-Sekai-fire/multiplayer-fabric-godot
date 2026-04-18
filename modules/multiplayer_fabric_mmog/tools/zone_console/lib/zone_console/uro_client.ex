defmodule ZoneConsole.UroClient do
  @moduledoc "Thin REST client for Uro auth + shard management."

  defstruct [:base_url, :access_token, :user]

  @type t :: %__MODULE__{
          base_url: String.t(),
          access_token: String.t() | nil,
          user: map() | nil
        }

  def new(base_url), do: %__MODULE__{base_url: String.trim_trailing(base_url, "/")}

  @doc "POST /session — accepts email or username. Returns {:ok, client} or {:error, reason}."
  def login(%__MODULE__{} = client, username_or_email, password) do
    cred_key = if String.contains?(username_or_email, "@"), do: :email, else: :username

    case Req.post("#{client.base_url}/session",
           json: %{user: %{cred_key => username_or_email, password: password}},
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok, %{client | access_token: data["access_token"], user: data["user"]}}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc "GET /shards — returns {:ok, [shard]} or {:error, reason}."
  def list_shards(%__MODULE__{} = client) do
    case Req.get("#{client.base_url}/shards",
           headers: auth_headers(client),
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"data" => %{"shards" => shards}}}} ->
        {:ok, shards}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc "POST /shards — register a new shard. Returns {:ok, id} or {:error, reason}."
  def register_shard(%__MODULE__{} = client, address, port, map, name) do
    case Req.post("#{client.base_url}/shards",
           json: %{shard: %{address: address, port: port, map: map, name: name}},
           headers: auth_headers(client),
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"data" => %{"id" => id}}}} ->
        {:ok, id}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc "DELETE /shards/:id — unregister a shard. Returns :ok or {:error, reason}."
  def delete_shard(%__MODULE__{} = client, id) do
    case Req.delete("#{client.base_url}/shards/#{id}",
           headers: auth_headers(client),
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc "PUT /shards/:id — heartbeat keepalive for a shard. Returns :ok or {:error, reason}."
  def heartbeat_shard(%__MODULE__{} = client, id) do
    case Req.put("#{client.base_url}/shards/#{id}",
           json: %{},
           headers: auth_headers(client),
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc "GET /zones?shard_id=<id> — returns {:ok, [zone]} or {:error, reason}."
  def list_zones(%__MODULE__{} = client, shard_id \\ nil) do
    url =
      if shard_id,
        do: "#{client.base_url}/zones?shard_id=#{shard_id}",
        else: "#{client.base_url}/zones"

    case Req.get(url, headers: auth_headers(client), receive_timeout: 10_000) do
      {:ok, %{status: 200, body: %{"data" => %{"zones" => zones}}}} ->
        {:ok, zones}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc "POST /zones — spawn a zone process. Returns {:ok, map} or {:error, reason}."
  def spawn_zone(%__MODULE__{} = client, shard_id, port) do
    case Req.post("#{client.base_url}/zones",
           json: %{shard_id: shard_id, port: port},
           headers: auth_headers(client),
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc "DELETE /zones/:shard_id/:port — stop a zone process. Returns :ok or {:error, reason}."
  def stop_zone(%__MODULE__{} = client, shard_id, port) do
    case Req.delete("#{client.base_url}/zones/#{shard_id}/#{port}",
           headers: auth_headers(client),
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp auth_headers(%__MODULE__{access_token: nil}), do: []
  defp auth_headers(%__MODULE__{access_token: tok}), do: [{"authorization", "Bearer #{tok}"}]
end
