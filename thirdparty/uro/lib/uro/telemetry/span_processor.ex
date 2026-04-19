defmodule Uro.Telemetry.SpanProcessor do
  @moduledoc """
  OTel span processor that mirrors completed spans into SpanStore (ETS).
  Register alongside the batch processor in config so spans flow to both
  the in-app dashboard and the external OTLP exporter.
  """

  @behaviour :otel_span_processor

  @impl :otel_span_processor
  def on_start(span, _parent_ctx, _config), do: span

  @impl :otel_span_processor
  def on_end(span, _config) do
    Uro.Telemetry.SpanStore.record(span)
    :ok
  end

  @impl :otel_span_processor
  def force_flush(_timeout), do: :ok

  def shutdown(_config), do: :ok
end
