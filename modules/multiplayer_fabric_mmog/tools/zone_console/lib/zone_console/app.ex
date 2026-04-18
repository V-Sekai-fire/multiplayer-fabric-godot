defmodule ZoneConsole.App do
  @moduledoc "ExRatatui TUI for the zone operator console."

  use ExRatatui.App

  alias ZoneConsole.UroClient

  @help_rows [
    {"help",                    "show this message"},
    {"shards",                  "list zones from Uro"},
    {"connect <name|index>",    "connect to a zone"},
    {"status",                  "zone entity count and neighbor links"},
    {"entities [n]",            "list live jellyfish (default 20)"},
    {"kick <id>",               "force-migrate entity out of zone"},
    {"tombstone <hash>",        "blacklist UGC asset; despawn instances"},
    {"rip <x> <z> <strength>",  "inject rip current into flow field"},
    {"bloom <x> <z>",           "trigger jellyfish bloom event"},
    {"exit / quit / Ctrl-C",    "disconnect and exit"},
  ]

  # ── state ───────────────────────────────────────────────────────────────────

  defstruct [
    :uro,
    shards: [],
    connected_zone: nil,
    output: [],
    input: ""
  ]

  # ── lifecycle ────────────────────────────────────────────────────────────────

  @impl ExRatatui.App
  def init(_opts) do
    uro = Application.fetch_env!(:zone_console, :uro_client)

    banner = [
      line(:info, "Multiplayer Fabric Zone Console"),
      line(:dim,  "Uro: #{uro.base_url}"),
      line(:dim,  "User: #{get_in(uro.user, ["username"]) || "?"}"),
      line(:dim,  ""),
      line(:dim,  "Type 'help' for commands."),
    ]

    {shard_lines, shards} =
      case UroClient.list_shards(uro) do
        {:ok, []} ->
          {[line(:warn, "No zones registered.")], []}

        {:ok, shards} ->
          {[line(:info, "Available zones:") | format_shards(shards)], shards}

        {:error, reason} ->
          {[line(:err, "Could not reach Uro: #{reason}")], []}
      end

    %__MODULE__{
      uro: uro,
      shards: shards,
      output: banner ++ shard_lines
    }
  end

  # ── event handling ───────────────────────────────────────────────────────────

  @impl ExRatatui.App
  def handle_event(state, {:key, :enter}) do
    cmd = String.trim(state.input)
    state = %{state | input: ""}
    state = append(state, line(:prompt, "> #{cmd}"))
    run_command(state, cmd)
  end

  def handle_event(state, {:key, key}) when key in [:backspace, :delete] do
    %{state | input: String.slice(state.input, 0..-2//1)}
  end

  def handle_event(_state, {:key, :ctrl_c}), do: :exit
  def handle_event(_state, {:key, :ctrl_d}), do: :exit

  def handle_event(state, {:char, ch}) do
    %{state | input: state.input <> ch}
  end

  def handle_event(state, _event), do: state

  # ── render ───────────────────────────────────────────────────────────────────

  @impl ExRatatui.App
  def render(state) do
    zone_label =
      case state.connected_zone do
        nil -> "offline"
        z   -> "#{z["name"]} (#{z["address"]}:#{z["port"]})"
      end

    prompt_prefix =
      case state.connected_zone do
        nil -> "[offline]"
        z   -> "[#{z["name"]}]"
      end

    ExRatatui.View.layout(:vertical, [
      ExRatatui.View.block(
        title: " zone console ",
        borders: [:all],
        flex: 1
      ) do
        ExRatatui.View.list(state.output, fn {style, text} ->
          ExRatatui.View.span(text, fg: style_color(style))
        end)
      end,

      ExRatatui.View.block(borders: [:all], height: 3) do
        ExRatatui.View.line([
          ExRatatui.View.span(prompt_prefix <> " > ", fg: :cyan),
          ExRatatui.View.span(state.input, fg: :white),
          ExRatatui.View.span("█", fg: :cyan)
        ])
      end,

      ExRatatui.View.block(borders: [], height: 1) do
        ExRatatui.View.line([
          ExRatatui.View.span(" Uro: #{state.uro.base_url}  |  Zone: #{zone_label}", fg: :dark_gray)
        ])
      end
    ])
  end

  defp style_color(:ok),     do: :green
  defp style_color(:err),    do: :red
  defp style_color(:warn),   do: :yellow
  defp style_color(:info),   do: :cyan
  defp style_color(:prompt), do: :white
  defp style_color(_),       do: :reset

  # ── commands ─────────────────────────────────────────────────────────────────

  defp run_command(state, ""), do: state

  defp run_command(_state, cmd) when cmd in ["exit", "quit"], do: :exit

  defp run_command(state, "help") do
    rows =
      Enum.map(@help_rows, fn {cmd, desc} ->
        line(:dim, "  #{String.pad_trailing(cmd, 26)} #{desc}")
      end)

    append_many(state, [line(:info, "Commands:") | rows])
  end

  defp run_command(state, "shards") do
    case UroClient.list_shards(state.uro) do
      {:ok, shards} ->
        state = %{state | shards: shards}
        append_many(state, [line(:info, "Zones:") | format_shards(shards)])

      {:error, reason} ->
        append(state, line(:err, "Error: #{reason}"))
    end
  end

  defp run_command(state, "connect " <> arg) do
    arg = String.trim(arg)

    shard =
      case Integer.parse(arg) do
        {idx, ""} -> Enum.at(state.shards, idx)
        _         -> Enum.find(state.shards, &(&1["name"] == arg))
      end

    case shard do
      nil ->
        append(state, line(:err, "Unknown zone: #{arg}  (run 'shards' to list)"))

      s ->
        state = %{state | connected_zone: s}
        append(state, line(:ok, "Connected to #{s["name"]} (#{s["address"]}:#{s["port"]})"))
    end
  end

  defp run_command(%{connected_zone: nil} = state, cmd)
       when cmd in ["status", "entities"] or
              match?("entities " <> _, cmd) or
              match?("kick " <> _, cmd) or
              match?("tombstone " <> _, cmd) or
              match?("rip " <> _, cmd) or
              match?("bloom " <> _, cmd) do
    append(state, line(:warn, "Not connected. Run 'shards' then 'connect <name>'."))
  end

  defp run_command(state, "status") do
    z = state.connected_zone

    append_many(state, [
      line(:info, "Zone: #{z["name"]}"),
      line(:dim,  "  address:  #{z["address"]}:#{z["port"]}"),
      line(:dim,  "  map:      #{z["map"]}"),
      line(:dim,  "  users:    #{z["current_users"]}"),
      line(:dim,  "  (live entity data requires zone server WebTransport — pending)"),
    ])
  end

  defp run_command(state, "entities" <> _rest) do
    append(state, line(:warn, "Entity list requires live zone connection (pending)."))
  end

  defp run_command(state, "kick " <> _id) do
    append(state, line(:warn, "Kick requires live zone connection (pending)."))
  end

  defp run_command(state, "tombstone " <> _hash) do
    append(state, line(:warn, "Tombstone requires live zone connection (pending)."))
  end

  defp run_command(state, "rip " <> args) do
    case String.split(String.trim(args)) do
      [x, z, strength] ->
        append(state, line(:ok, "rip queued: x=#{x} z=#{z} strength=#{strength}  (zone connection pending)"))
      _ ->
        append(state, line(:err, "usage: rip <x> <z> <strength>"))
    end
  end

  defp run_command(state, "bloom " <> args) do
    case String.split(String.trim(args)) do
      [x, z] ->
        append(state, line(:ok, "bloom queued: x=#{x} z=#{z}  (zone connection pending)"))
      _ ->
        append(state, line(:err, "usage: bloom <x> <z>"))
    end
  end

  defp run_command(state, unknown) do
    append(state, line(:err, "Unknown command: #{unknown}  (try 'help')"))
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  defp line(style, text), do: {style, text}

  defp append(state, line), do: %{state | output: state.output ++ [line]}
  defp append_many(state, lines), do: %{state | output: state.output ++ lines}

  defp format_shards([]), do: [line(:warn, "  (none)")]

  defp format_shards(shards) do
    header =
      line(
        :dim,
        "  #   #{String.pad_trailing("name", 20)} #{String.pad_trailing("address", 18)} port   users  map"
      )

    rows =
      shards
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        line(
          :dim,
          "  #{String.pad_trailing(to_string(i), 4)}" <>
            "#{String.pad_trailing(s["name"] || "?", 20)} " <>
            "#{String.pad_trailing(s["address"] || "?", 18)} " <>
            "#{String.pad_trailing(to_string(s["port"] || "?"), 6)} " <>
            "#{String.pad_trailing(to_string(s["current_users"] || 0), 6)} " <>
            "#{s["map"] || "?"}"
        )
      end)

    [header | rows]
  end
end
