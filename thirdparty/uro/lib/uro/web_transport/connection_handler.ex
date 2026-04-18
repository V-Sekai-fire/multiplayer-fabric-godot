defmodule Uro.WebTransport.ConnectionHandler do
  use Wtransport.ConnectionHandler

  require Logger

  @impl true
  def handle_session(session) do
    Logger.info("WebTransport session opened: #{inspect(session.id)}")
    Phoenix.PubSub.broadcast(Uro.PubSub, "webtransport:sessions", {:session_opened, session.id})
    {:continue, %{session_id: session.id}}
  end

  @impl true
  def handle_connection(connection, state) do
    Phoenix.PubSub.broadcast(
      Uro.PubSub,
      "webtransport:session:#{state.session_id}",
      {:connection_opened, connection.id}
    )
    {:continue, state}
  end

  @impl true
  def handle_datagram(datagram, _connection, state) do
    Phoenix.PubSub.broadcast(
      Uro.PubSub,
      "webtransport:session:#{state.session_id}:datagrams",
      {:datagram, datagram}
    )
    {:continue, state}
  end

  @impl true
  def handle_close(_connection, state) do
    Phoenix.PubSub.broadcast(
      Uro.PubSub,
      "webtransport:session:#{state.session_id}",
      :session_closed
    )
    :ok
  end

  @impl true
  def handle_error(reason, _connection, _state) do
    Logger.warning("WebTransport connection error: #{inspect(reason)}")
    :ok
  end
end
