defmodule Uro.Telemetry.SpansPage do
  @moduledoc "Phoenix LiveDashboard custom page — shows recent OTel spans from SpanStore."

  use Phoenix.LiveDashboard.PageBuilder, refresher?: true

  @impl Phoenix.LiveDashboard.PageBuilder
  def menu_link(_, _), do: {:ok, "Traces"}

  @impl Phoenix.LiveDashboard.PageBuilder
  def render_page(assigns) do
    spans =
      Uro.Telemetry.SpanStore.recent(200)
      |> Enum.map(fn s ->
        duration =
          if s.start_time && s.end_time && s.end_time > s.start_time,
            do: System.convert_time_unit(s.end_time - s.start_time, :native, :microsecond),
            else: nil

        Map.put(s, :duration_us, duration)
      end)

    assigns = assign(assigns, spans: spans)

    ~H"""
    <div class="tabular-page">
      <h5 class="card-title">Recent Spans (<%= length(@spans) %>)</h5>
      <div class="card">
        <div class="card-body p-0">
          <table class="table table-hover">
            <thead>
              <tr>
                <th>Span</th>
                <th>Kind</th>
                <th>Status</th>
                <th>Duration μs</th>
                <th>Trace ID</th>
                <th>Span ID</th>
              </tr>
            </thead>
            <tbody>
              <%= for span <- @spans do %>
                <tr>
                  <td><code><%= span.name %></code></td>
                  <td><%= span.kind %></td>
                  <td><%= inspect(span.status) %></td>
                  <td><%= span.duration_us %></td>
                  <td><small><%= span.trace_id %></small></td>
                  <td><small><%= span.span_id %></small></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end
end
