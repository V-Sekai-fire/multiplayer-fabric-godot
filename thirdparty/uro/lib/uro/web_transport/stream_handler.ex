defmodule Uro.WebTransport.StreamHandler do
  @moduledoc """
  Handles reliable ordered streams from Godot clients.

  Incoming stream data is published to PubSub so game logic can
  subscribe without coupling to the transport layer.
  """

  @behaviour Wtransport.StreamHandler

  require Logger

  @impl true
  def handle_stream(stream, state) do
    Logger.debug("WebTransport stream opened: #{inspect(stream.id)} session=#{state.session_id}")
    {:ok, Map.put(state, :stream_id, stream.id)}
  end

  @impl true
  def handle_data(data, state) do
    Phoenix.PubSub.broadcast(
      Uro.PubSub,
      "webtransport:session:#{state.session_id}:streams",
      {:stream_data, state.stream_id, data}
    )
    {:ok, state}
  end
end
