defmodule Uro.WebTransport.ConnectionHandler do
  @moduledoc """
  Handles WebTransport sessions and connections from Godot clients.

  Each accepted session maps to one Godot peer. Datagrams carry
  unreliable game-state (position, animation); streams carry reliable
  ordered messages (chat, RPC calls).
  """

  @behaviour Wtransport.ConnectionHandler

  require Logger

  @impl true
  def handle_session(session) do
    Logger.info("WebTransport session opened: #{inspect(session.id)}")
    Phoenix.PubSub.broadcast(Uro.PubSub, "webtransport:sessions", {:session_opened, session.id})
    {:ok, %{session_id: session.id}}
  end

  @impl true
  def handle_connection(connection, state) do
    Logger.debug("WebTransport connection: #{inspect(connection.id)} session=#{state.session_id}")
    Phoenix.PubSub.broadcast(
      Uro.PubSub,
      "webtransport:session:#{state.session_id}",
      {:connection_opened, connection.id}
    )
    {:ok, state}
  end

  @impl true
  def handle_datagram(datagram, state) do
    Phoenix.PubSub.broadcast(
      Uro.PubSub,
      "webtransport:session:#{state.session_id}:datagrams",
      {:datagram, datagram}
    )
    {:ok, state}
  end
end
