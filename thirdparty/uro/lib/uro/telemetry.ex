defmodule Uro.Telemetry do
  @moduledoc """
  Telemetry supervisor — wires up periodic measurements and declares the
  metrics that appear in the LiveDashboard Metrics tab and any custom pages.
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Supervisor
  def init(_opts) do
    children = [
      {:telemetry_poller,
       measurements: periodic_measurements(),
       period: :timer.seconds(10),
       name: Uro.TelemetryPoller}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # ── HTTP ──────────────────────────────────────────────────────────────
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        tags: [:method, :route, :status]
      ),
      counter("phoenix.endpoint.stop.duration",
        tags: [:method, :route, :status],
        description: "Total HTTP requests"
      ),

      # ── Ecto ──────────────────────────────────────────────────────────────
      summary("uro.repo.query.total_time",
        unit: {:native, :millisecond},
        tags: [:source, :command]
      ),
      counter("uro.repo.query.total_time",
        tags: [:source],
        description: "Total DB queries"
      ),

      # ── VM ────────────────────────────────────────────────────────────────
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.io"),
      summary("vm.system_counts.process_count"),

      # ── Zones (custom) ────────────────────────────────────────────────────
      last_value("uro.zones.running.count",  description: "Live zone processes"),
      last_value("uro.zones.starting.count", description: "Zones initialising"),
      last_value("uro.zones.players.total",  description: "Sum of current_users across running zones"),
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :emit_zone_metrics, []}
    ]
  end

  def emit_zone_metrics do
    zones = Uro.Repo.all(Uro.VSekai.Zone)

    running  = Enum.count(zones, &(&1.status == "running"))
    starting = Enum.count(zones, &(&1.status == "starting"))
    players  = zones |> Enum.filter(&(&1.status == "running")) |> Enum.sum_by(& &1.current_users || 0)

    :telemetry.execute([:uro, :zones, :running],  %{count: running},  %{})
    :telemetry.execute([:uro, :zones, :starting], %{count: starting}, %{})
    :telemetry.execute([:uro, :zones, :players],  %{total: players},  %{})
  end
end
