defmodule Uro.WebTransport.StreamHandler do
  use Wtransport.StreamHandler

  require Logger

  @impl true
  def handle_stream(stream, state) do
    {:continue, Map.put(state, :stream_id, stream.id)}
  end

  @impl true
  def handle_data(data, _stream, state) do
    Phoenix.PubSub.broadcast(
      Uro.PubSub,
      "webtransport:session:#{state.session_id}:streams",
      {:stream_data, state.stream_id, data}
    )
    {:continue, state}
  end

  @impl true
  def handle_close(_stream, state) do
    {:continue, state}
  end

  @impl true
  def handle_error(reason, _stream, _state) do
    Logger.warning("WebTransport stream error: #{inspect(reason)}")
    :ok
  end
end
