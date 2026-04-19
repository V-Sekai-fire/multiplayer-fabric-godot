defmodule Uro.Telemetry.SpanStore do
  @moduledoc """
  ETS-backed time-window span store for recent OTel spans.

  Spans are keyed by `{monotonic_time, unique_integer}` so the table stays
  ordered chronologically. A periodic sweep (every @sweep_interval ms) removes
  entries older than @ttl_ms. The key is wall-clock monotonic time so `recent/1`
  and `since/1` can do efficient range scans without a full table scan.

  Configuration via application env (set in config.exs or runtime.exs):

      config :uro, Uro.Telemetry.SpanStore,
        ttl_ms: 300_000,          # keep spans for 5 min (default)
        sweep_interval_ms: 30_000 # sweep every 30 s (default)
  """

  use GenServer

  require Record

  Record.defrecordp :otel_span, :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")

  @table :uro_otel_spans

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :ordered_set])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:sweep, state) do
    cutoff = System.monotonic_time(:millisecond) - ttl_ms()
    delete_before(cutoff)
    schedule_sweep()
    {:noreply, state}
  end

  # ── public API ──────────────────────────────────────────────────────────────

  @doc "Record a completed span. Called from SpanProcessor.on_end/1."
  def record(span) do
    now_ms = System.monotonic_time(:millisecond)
    key = {now_ms, :erlang.unique_integer([:monotonic])}
    :ets.insert(@table, {key, normalize(span)})
  end

  @doc "Return up to `limit` spans from the last `window_ms` milliseconds, newest first."
  def recent(window_ms \\ nil, limit \\ 500) do
    cutoff_ms = System.monotonic_time(:millisecond) - (window_ms || ttl_ms())
    cutoff_key = {cutoff_ms, :math.pow(2, 63) |> trunc() |> Kernel.-()}

    :ets.select(@table, [{{:"$1", :"$2"}, [{:>=, :"$1", {:const, cutoff_key}}], [{{:"$1", :"$2"}}]}])
    |> Enum.sort_by(fn {{ts, _}, _} -> ts end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_key, span} -> span end)
  end

  @doc "Return spans in a specific time range (monotonic ms)."
  def since(since_ms, limit \\ 500) do
    recent(System.monotonic_time(:millisecond) - since_ms, limit)
  end

  @doc "Return spans whose trace_id matches, within the TTL window."
  def for_trace(trace_id) do
    recent() |> Enum.filter(&(&1.trace_id == trace_id))
  end

  @doc "Current TTL in milliseconds (from application env or default 5 min)."
  def ttl_ms do
    Application.get_env(:uro, __MODULE__, [])
    |> Keyword.get(:ttl_ms, :timer.minutes(5))
  end

  # ── private ─────────────────────────────────────────────────────────────────

  defp sweep_interval_ms do
    Application.get_env(:uro, __MODULE__, [])
    |> Keyword.get(:sweep_interval_ms, :timer.seconds(30))
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, sweep_interval_ms())
  end

  defp delete_before(cutoff_ms) do
    # ETS ordered_set: delete all keys with timestamp < cutoff_ms
    delete_loop(:ets.first(@table), cutoff_ms)
  end

  defp delete_loop(:"$end_of_table", _cutoff), do: :ok

  defp delete_loop({ts, _} = key, cutoff) when ts < cutoff do
    next = :ets.next(@table, key)
    :ets.delete(@table, key)
    delete_loop(next, cutoff)
  end

  defp delete_loop(_key, _cutoff), do: :ok

  defp normalize(s) do
    %{
      trace_id:   otel_span(s, :trace_id) |> format_id(),
      span_id:    otel_span(s, :span_id) |> format_id(),
      parent_id:  otel_span(s, :parent_span_id) |> format_id(),
      name:       otel_span(s, :name),
      kind:       otel_span(s, :kind),
      status:     otel_span(s, :status),
      start_time: otel_span(s, :start_time),
      end_time:   otel_span(s, :end_time),
      attributes: otel_span(s, :attributes)
    }
  end

  defp format_id(0),   do: nil
  defp format_id(nil), do: nil
  defp format_id(id) when is_integer(id),
    do: id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(16, "0")
  defp format_id(_),   do: nil
end
