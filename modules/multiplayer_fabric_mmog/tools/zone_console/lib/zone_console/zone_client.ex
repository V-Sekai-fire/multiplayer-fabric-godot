defmodule ZoneConsole.ZoneClient do
  @moduledoc "GenServer: WebTransport connection to a fabric zone as a player."

  use GenServer
  import Bitwise

  alias Wtransport.Client

  @heartbeat_ms 300

  # CH_PLAYER = 3, unreliable → flag = (3 << 1) | 1 = 7
  @ch_player_flag 0x07

  defstruct [:client, :player_id, :pos, :app_pid]

  # ── public API ────────────────────────────────────────────────────────────────

  @spec start_link(String.t(), String.t(), non_neg_integer(), pid()) ::
          {:ok, pid()} | {:error, term()}
  def start_link(url, cert_hash, player_id, app_pid) do
    GenServer.start_link(__MODULE__, {url, cert_hash, player_id, app_pid})
  end

  @spec set_pos(pid(), float(), float(), float()) :: :ok
  def set_pos(pid, x, y, z), do: GenServer.cast(pid, {:set_pos, x, y, z})

  @spec send_nudge(pid(), non_neg_integer()) :: :ok
  def send_nudge(pid, target_id), do: GenServer.cast(pid, {:nudge, target_id})

  @spec stop(pid()) :: :ok
  def stop(pid), do: GenServer.stop(pid, :normal)

  # ── lifecycle ────────────────────────────────────────────────────────────────

  @impl GenServer
  def init({url, cert_hash, player_id, app_pid}) do
    case Client.connect(url, cert_hash, self()) do
      {:ok, client} ->
        Process.send_after(self(), :heartbeat, @heartbeat_ms)

        {:ok,
         %__MODULE__{client: client, player_id: player_id, pos: {0.0, 0.0, 0.0}, app_pid: app_pid}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def terminate(_reason, %{client: client}) when not is_nil(client) do
    Client.disconnect(client)
  end

  def terminate(_reason, _state), do: :ok

  # ── messages ─────────────────────────────────────────────────────────────────

  @impl GenServer
  def handle_info(:heartbeat, state) do
    {x, y, z} = state.pos
    packet = encode_player(state.player_id, x, y, z, 0)
    datagram = wtd_encode(@ch_player_flag, packet)
    Client.send_datagram(state.client, datagram)
    Process.send_after(self(), :heartbeat, @heartbeat_ms)
    {:noreply, state}
  end

  def handle_info({:zone_datagram, data}, state) do
    case decode_wtd(data) do
      {:ok, ch, payload} when ch == 2 ->
        entities = decode_entity_snapshots(payload)
        send(state.app_pid, {:zone_entities, entities})

      _ ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_cast({:set_pos, x, y, z}, state) do
    {:noreply, %{state | pos: {x, y, z}}}
  end

  def handle_cast({:nudge, target_id}, state) do
    {x, y, z} = state.pos
    # CMD_NUDGE = 2, payload[0] low byte = 2, payload[1] = target_id
    packet = encode_player(state.player_id, x, y, z, 2, target_id)
    datagram = wtd_encode(@ch_player_flag, packet)
    Client.send_datagram(state.client, datagram)
    {:noreply, state}
  end

  # ── encoding / decoding ───────────────────────────────────────────────────────

  # WTD frame: flag(1) | varint(len) | payload
  defp wtd_encode(flag, payload) do
    len = byte_size(payload)
    <<flag::8>> <> encode_varint(len) <> payload
  end

  # QUIC RFC 9000 §16 variable-length integer encoding
  defp encode_varint(v) when v < 0x40, do: <<v::8>>
  defp encode_varint(v) when v < 0x4000, do: <<1::2, v::14>>
  defp encode_varint(v) when v < 0x40_000_000, do: <<2::2, v::30>>
  defp encode_varint(v), do: <<3::2, v::62>>

  defp decode_varint(<<0::2, v::6, rest::binary>>), do: {v, rest}
  defp decode_varint(<<1::2, v::14, rest::binary>>), do: {v, rest}
  defp decode_varint(<<2::2, v::30, rest::binary>>), do: {v, rest}
  defp decode_varint(<<3::2, v::62, rest::binary>>), do: {v, rest}
  defp decode_varint(_), do: :error

  defp decode_wtd(<<flag::8, rest::binary>>) do
    ch = flag >>> 1 &&& 0x07

    case decode_varint(rest) do
      {_len, payload} -> {:ok, ch, payload}
      :error -> :error
    end
  end

  defp decode_wtd(_), do: :error

  # 100-byte fabric packet (little-endian):
  # [u32 gid@0][f64 cx@4][f64 cy@12][f64 cz@20]
  # [i16 vx@28][i16 vy@30][i16 vz@32]
  # [i16 ax@34][i16 ay@36][i16 az@38]
  # [u32 hlc@40][u32×14 payload@44] = 100 bytes
  defp decode_entity_snapshots(data) do
    decode_entries(data, %{})
  end

  defp decode_entries(
         <<gid::little-32, cx::little-float-64, cy::little-float-64, cz::little-float-64,
           _vx::little-signed-16, _vy::little-signed-16, _vz::little-signed-16,
           _ax::little-signed-16, _ay::little-signed-16, _az::little-signed-16, hlc::little-32,
           _payload::binary-size(56), rest::binary>>,
         acc
       ) do
    entry = %{cx: cx, cy: cy, cz: cz, hlc: hlc}
    decode_entries(rest, Map.put(acc, gid, entry))
  end

  defp decode_entries(_, acc), do: acc

  # Build 100-byte player packet. cmd is payload[0] low byte (0=heartbeat, 2=nudge).
  defp encode_player(player_id, x, y, z, cmd, target_id \\ 0) do
    cmd_word = cmd ||| target_id <<< 8
    # 14 u32 payload words
    payload_tail = :binary.copy(<<0::little-32>>, 13)

    xyz = <<player_id::little-32, x::little-float-64, y::little-float-64, z::little-float-64>>
    xyz <> <<0::96, 0::little-32, cmd_word::little-32>> <> payload_tail
  end
end
