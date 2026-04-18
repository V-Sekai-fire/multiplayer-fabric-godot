defmodule Uro.WebTransport.Zone do
  @moduledoc """
  GenServer managing one headless Godot fabric-zone process.

  Freshness uses the same updated_at-based mechanism as shards:
    - On the ready beacon, cert_hash + status are set to "running".
    - Every @ping_interval ms, update_zone/2 is called with force: true
      to bump updated_at so list_fresh_zones/0 keeps returning this zone.
    - On Godot exit, the zone is marked "stopping" and the GenServer exits.
      ShardJanitor reaps the DB row on its normal schedule.

  Godot stdout protocol (one JSON line each):
    ready:     {"event":"ready","port":N,"cert_hash":"<base64>"}
    (all other stdout is logged at debug level and ignored)

  Process management uses erlexec (:exec.run/2) so that :exec.kill/2 can
  deliver signals to the Godot OS process by PID.
  """

  use GenServer, restart: :transient

  require Logger

  alias Uro.Repo
  alias Uro.VSekai
  alias Uro.VSekai.Zone, as: ZoneSchema

  @zone_script "modules/http3/demo/wt_server_demo.gd"
  @ping_interval :timer.seconds(10)

  # ── public API ──────────────────────────────────────────────────────────────

  def start_link(opts) do
    shard_id = Keyword.fetch!(opts, :shard_id)
    port = Keyword.fetch!(opts, :port)
    GenServer.start_link(__MODULE__, {shard_id, port}, name: via(shard_id, port))
  end

  def via(shard_id, port),
    do: {:via, Registry, {Uro.WebTransport.ZoneRegistry, {shard_id, port}}}

  # ── GenServer callbacks ──────────────────────────────────────────────────────

  @impl true
  def init({shard_id, port}) do
    Process.flag(:trap_exit, true)
    {:ok, zone} = VSekai.create_zone(%{shard_id: shard_id, address: "0.0.0.0", port: port, status: "starting"})
    {:ok, exec_pid, os_pid} = start_godot(port, shard_id)
    schedule_ping()
    {:ok, %{zone_id: zone.id, shard_id: shard_id, port: port, exec_pid: exec_pid, os_pid: os_pid, buffer: ""}}
  end

  @impl true
  def handle_info(:ping, state) do
    case Repo.get(ZoneSchema, state.zone_id) do
      nil -> {:noreply, state}
      zone ->
        VSekai.update_zone(zone, %{})
        schedule_ping()
        {:noreply, state}
    end
  end

  def handle_info({:stdout, os_pid, data}, %{os_pid: os_pid} = state) do
    {lines, rest} = split_lines(state.buffer <> data)
    state = Enum.reduce(lines, state, &handle_line/2)
    {:noreply, %{state | buffer: rest}}
  end

  def handle_info({:stderr, os_pid, data}, %{os_pid: os_pid} = state) do
    Logger.debug("Zone #{state.zone_id} stderr: #{String.trim(data)}")
    {:noreply, state}
  end

  def handle_info({:DOWN, os_pid, :process, _exec_pid, reason}, %{os_pid: os_pid} = state) do
    Logger.warning("Godot zone #{state.zone_id} (OS PID #{os_pid}) exited: #{inspect(reason)}")
    mark_stopping(state.zone_id)
    {:stop, :normal, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    kill_godot(state.os_pid)
    mark_stopping(state.zone_id)
    :ok
  end

  # ── private ─────────────────────────────────────────────────────────────────

  defp start_godot(port, shard_id) do
    godot_bin = System.get_env("GODOT_BIN", "godot")
    godot_exe = System.find_executable(godot_bin) || raise "GODOT_BIN not found: #{godot_bin}"
    project_dir = System.get_env("GODOT_PROJECT", File.cwd!())

    cmd = "#{godot_exe} --headless --script #{@zone_script}"

    :exec.run(cmd, [
      :monitor,
      {:stdout, self()},
      {:stderr, self()},
      {:cd, project_dir},
      {:env, [{"ZONE_PORT", "#{port}"}, {"ZONE_SHARD_ID", "#{shard_id}"}]}
    ])
  end

  defp kill_godot(nil), do: :ok

  defp kill_godot(os_pid) do
    Logger.info("Sending SIGTERM to Godot OS PID #{os_pid} via erlexec")

    case :exec.kill(os_pid, 15) do
      :ok ->
        Logger.info("SIGTERM delivered to Godot PID #{os_pid}")

      {:error, reason} ->
        Logger.warning("SIGTERM failed (#{inspect(reason)}), sending SIGKILL to #{os_pid}")
        :exec.kill(os_pid, 9)
    end
  rescue
    e -> Logger.error("kill_godot failed: #{inspect(e)}")
  end

  defp schedule_ping, do: Process.send_after(self(), :ping, @ping_interval)

  defp split_lines(data) do
    parts = String.split(data, "\n")
    {Enum.slice(parts, 0..-2//1), List.last(parts)}
  end

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"event" => "ready", "cert_hash" => hash}} ->
        Repo.get!(ZoneSchema, state.zone_id)
        |> ZoneSchema.changeset(%{cert_hash: hash, status: "running"})
        |> Repo.update!()

        Phoenix.PubSub.broadcast(Uro.PubSub, "zone:#{state.zone_id}", {:zone_ready, state.zone_id, hash})
        Logger.info("Zone #{state.zone_id} ready cert_hash=#{hash}")
        state

      {:error, _} ->
        Logger.debug("Zone #{state.zone_id} stdout: #{line}")
        state
    end
  end

  defp mark_stopping(zone_id) do
    case Repo.get(ZoneSchema, zone_id) do
      nil -> :ok
      zone -> VSekai.update_zone(zone, %{status: "stopping"})
    end
  end
end
