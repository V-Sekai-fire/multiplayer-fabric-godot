defmodule ZoneConsole.UroClient do
  @moduledoc "Thin REST client for Uro auth + shard listing."

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
        {:ok,
         %{
           client
           | access_token: data["access_token"],
             user: data["user"]
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc "GET /shards — returns {:ok, [shard]} or {:error, reason}."
  def list_shards(%__MODULE__{} = client) do
    headers =
      if client.access_token,
        do: [{"authorization", "Bearer #{client.access_token}"}],
        else: []

    case Req.get("#{client.base_url}/shards",
           headers: headers,
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
end
