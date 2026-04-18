defmodule ZoneConsole.App do
  @moduledoc "ExRatatui TUI for the zone operator console."

  use ExRatatui.App

  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph, WidgetList}
  alias ZoneConsole.UroClient

  @help_rows [
    {"help",                    "show this message"},
    {"shards",                  "list shards from Uro"},
    {"connect <name|index>",    "connect to a shard"},
    {"zones",                   "list zones within connected shard"},
    {"status",                  "shard entity count and neighbor links"},
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
    connected_shard: nil,
    output: [],
    input: ""
  ]

  # ── lifecycle ────────────────────────────────────────────────────────────────

  @impl ExRatatui.App
  def mount(_opts) do
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
          {[line(:warn, "No shards registered.")], []}

        {:ok, shards} ->
          {[line(:info, "Available shards:") | format_shards(shards)], shards}

        {:error, reason} ->
          {[line(:err, "Could not reach Uro: #{reason}")], []}
      end

    state = %__MODULE__{
      uro: uro,
      shards: shards,
      output: banner ++ shard_lines
    }

    {:ok, state}
  end

  @impl ExRatatui.App
  def terminate(_reason, _state), do: System.stop(0)

  # ── event handling ───────────────────────────────────────────────────────────

  @impl ExRatatui.App
  def handle_event(%ExRatatui.Event.Key{code: "enter", kind: "press"}, state) do
    cmd = String.trim(state.input)
    state = %{state | input: ""}
    state = append(state, line(:prompt, "> #{cmd}"))

    case run_command(state, cmd) do
      :exit -> {:stop, state}
      new_state -> {:noreply, new_state}
    end
  end

  def handle_event(%ExRatatui.Event.Key{code: code, kind: "press"}, state)
      when code in ["backspace", "delete"] do
    {:noreply, %{state | input: String.slice(state.input, 0..-2//1)}}
  end

  def handle_event(%ExRatatui.Event.Key{code: code, kind: "press", modifiers: mods}, state)
      when code in ["c", "d"] do
    if "ctrl" in mods, do: {:stop, state}, else: {:noreply, %{state | input: state.input <> code}}
  end

  def handle_event(%ExRatatui.Event.Key{code: ch, kind: "press"}, state)
      when is_binary(ch) and byte_size(ch) == 1 do
    {:noreply, %{state | input: state.input <> ch}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  # ── render ───────────────────────────────────────────────────────────────────

  @impl ExRatatui.App
  def render(state, frame) do
    area = %Rect{x: 0, y: 0, width: frame.width, height: frame.height}

    [output_area, input_area, status_area] =
      Layout.split(area, :vertical, [
        {:min, 0},
        {:length, 3},
        {:length, 1}
      ])

    shard_label =
      case state.connected_shard do
        nil -> "offline"
        s   -> "#{s["name"]} (#{s["address"]}:#{s["port"]})"
      end

    prompt_prefix =
      case state.connected_shard do
        nil -> "[offline]"
        s   -> "[#{s["name"]}]"
      end

    output_items =
      Enum.map(state.output, fn {style, text} ->
        {%Paragraph{text: text, style: %Style{fg: style_color(style)}}, 1}
      end)

    scroll_offset = max(0, length(output_items) - (output_area.height - 2))

    output_widget = %WidgetList{
      items: output_items,
      scroll_offset: scroll_offset,
      block: %Block{title: " zone console ", borders: [:all]}
    }

    input_widget = %Paragraph{
      text: "#{prompt_prefix} > #{state.input}█",
      style: %Style{fg: :white},
      block: %Block{borders: [:all]}
    }

    status_widget = %Paragraph{
      text: " Uro: #{state.uro.base_url}  |  Shard: #{shard_label}",
      style: %Style{fg: :dark_gray}
    }

    [
      {output_widget, output_area},
      {input_widget, input_area},
      {status_widget, status_area}
    ]
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
        append_many(state, [line(:info, "Shards:") | format_shards(shards)])

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
        append(state, line(:err, "Unknown shard: #{arg}  (run 'shards' to list)"))

      s ->
        state = %{state | connected_shard: s}
        append(state, line(:ok, "Connected to shard #{s["name"]} (#{s["address"]}:#{s["port"]})"))
    end
  end

  defp run_command(state, "zones") do
    require_shard(state, fn s ->
      zones = s["zones"] || []

      if zones == [] do
        append(state, line(:dim, "  No zone subdivisions listed for this shard."))
      else
        rows = Enum.with_index(zones, fn z, i ->
          line(:dim, "  #{i}  #{inspect(z)}")
        end)
        append_many(state, [line(:info, "Zones in #{s["name"]}:") | rows])
      end
    end)
  end

  defp run_command(state, cmd) when cmd in ["status", "entities"] do
    require_shard(state, fn s ->
      append_many(state, [
        line(:info, "Shard: #{s["name"]}"),
        line(:dim,  "  address:  #{s["address"]}:#{s["port"]}"),
        line(:dim,  "  map:      #{s["map"]}"),
        line(:dim,  "  users:    #{s["current_users"]}"),
        line(:dim,  "  (live entity data requires WebTransport — pending)"),
      ])
    end)
  end

  defp run_command(state, "entities " <> _rest) do
    require_shard(state, fn _s ->
      append(state, line(:warn, "Entity list requires live zone connection (pending)."))
    end)
  end

  defp run_command(state, "kick " <> _id) do
    require_shard(state, fn _s ->
      append(state, line(:warn, "Kick requires live zone connection (pending)."))
    end)
  end

  defp run_command(state, "tombstone " <> _hash) do
    require_shard(state, fn _s ->
      append(state, line(:warn, "Tombstone requires live zone connection (pending)."))
    end)
  end

  defp run_command(state, "rip " <> args) do
    require_shard(state, fn _s ->
      case String.split(String.trim(args)) do
        [x, z, strength] ->
          append(state, line(:ok, "rip queued: x=#{x} z=#{z} strength=#{strength}  (pending)"))
        _ ->
          append(state, line(:err, "usage: rip <x> <z> <strength>"))
      end
    end)
  end

  defp run_command(state, "bloom " <> args) do
    require_shard(state, fn _s ->
      case String.split(String.trim(args)) do
        [x, z] ->
          append(state, line(:ok, "bloom queued: x=#{x} z=#{z}  (pending)"))
        _ ->
          append(state, line(:err, "usage: bloom <x> <z>"))
      end
    end)
  end

  defp run_command(state, unknown) do
    append(state, line(:err, "Unknown command: #{unknown}  (try 'help')"))
  end

  defp require_shard(%{connected_shard: nil} = state, _fun) do
    append(state, line(:warn, "Not connected. Run 'shards' then 'connect <name>'."))
  end

  defp require_shard(%{connected_shard: s} = _state, fun), do: fun.(s)

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
