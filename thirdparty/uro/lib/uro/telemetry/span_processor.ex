defmodule Uro.Telemetry.SpanProcessor do
  @moduledoc """
  OTel span processor that mirrors completed spans into SpanStore (ETS).
  Register alongside the batch processor in config so spans flow to both
  the in-app dashboard and the external OTLP exporter.
  """

  @behaviour :otel_span_processor

  @impl :otel_span_processor
  def on_start(span, _parent_ctx), do: span

  @impl :otel_span_processor
  def on_end(span) do
    Uro.Telemetry.SpanStore.record(span)
    :ok
  end

  @impl :otel_span_processor
  def force_flush(timeout), do: {:ok, timeout}

  @impl :otel_span_processor
  def shutdown(_timeout), do: :ok
end
