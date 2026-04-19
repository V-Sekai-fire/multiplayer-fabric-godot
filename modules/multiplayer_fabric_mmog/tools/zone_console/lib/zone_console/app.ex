defmodule ZoneConsole.App do
  @moduledoc "ExRatatui TUI for the zone operator console."

  use ExRatatui.App

  alias ExRatatui.Layout
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Style
  alias ExRatatui.Widgets.{Block, Paragraph, WidgetList}
  alias ZoneConsole.UroClient

  @help_rows [
    {"help", "show this message"},
    {"shards", "list shards from Uro"},
    {"connect <name|index>", "connect to a shard"},
    {"register <addr> <port> <map> <name>", "register a new shard"},
    {"unregister <name|index>", "delete a shard from Uro"},
    {"heartbeat", "send keepalive for connected shard"},
    {"start <port>", "spawn a Godot zone on the connected shard"},
    {"stop <port>", "stop a running zone on the connected shard"},
    {"zones", "list running zones for connected shard"},
    {"status", "show connected shard details"},
    {"entities [n]", "list live jellyfish (default 20)"},
    {"kick <id>", "force-migrate entity out of zone"},
    {"tombstone <hash>", "blacklist UGC asset; despawn instances"},
    {"rip <x> <z> <strength>", "inject rip current into flow field"},
    {"bloom <x> <z>", "trigger jellyfish bloom event"},
    {"exit / quit / Ctrl-C", "disconnect and exit"}
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
      line(:dim, "Uro: #{uro.base_url}"),
      line(:dim, "User: #{get_in(uro.user, ["username"]) || "?"}"),
      line(:dim, ""),
      line(:dim, "Type 'help' for commands.")
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
        s -> "#{s["name"]} (#{s["address"]}:#{s["port"]})"
      end

    prompt_prefix =
      case state.connected_shard do
        nil -> "[offline]"
        s -> "[#{s["name"]}]"
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

  defp style_color(:ok), do: :green
  defp style_color(:err), do: :red
  defp style_color(:warn), do: :yellow
  defp style_color(:info), do: :cyan
  defp style_color(:prompt), do: :white
  defp style_color(_), do: :reset

  # ── commands ─────────────────────────────────────────────────────────────────

  defp run_command(state, ""), do: state

  defp run_command(_state, cmd) when cmd in ["exit", "quit"], do: :exit

  defp run_command(state, "help") do
    rows =
      Enum.map(@help_rows, fn {cmd, desc} ->
        line(:dim, "  #{String.pad_trailing(cmd, 34)} #{desc}")
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
        _ -> Enum.find(state.shards, &(&1["name"] == arg))
      end

    case shard do
      nil ->
        append(state, line(:err, "Unknown shard: #{arg}  (run 'shards' to list)"))

      s ->
        state = %{state | connected_shard: s}
        append(state, line(:ok, "Connected to #{s["name"]} (#{s["address"]}:#{s["port"]})"))
    end
  end

  defp run_command(state, "register " <> args) do
    case String.split(String.trim(args)) do
      [address, port_str, map, name] ->
        case Integer.parse(port_str) do
          {port, ""} ->
            case UroClient.register_shard(state.uro, address, port, map, name) do
              {:ok, id} ->
                state = append(state, line(:ok, "Registered #{name} (id: #{id})"))
                run_command(state, "shards")

              {:error, reason} ->
                append(state, line(:err, "Register failed: #{reason}"))
            end

          _ ->
            append(state, line(:err, "Port must be an integer"))
        end

      _ ->
        append(state, line(:err, "usage: register <address> <port> <map> <name>"))
    end
  end

  defp run_command(state, "unregister " <> arg) do
    arg = String.trim(arg)

    shard =
      case Integer.parse(arg) do
        {idx, ""} -> Enum.at(state.shards, idx)
        _ -> Enum.find(state.shards, &(&1["name"] == arg))
      end

    case shard do
      nil ->
        append(state, line(:err, "Unknown shard: #{arg}  (run 'shards' to list)"))

      s ->
        case UroClient.delete_shard(state.uro, s["id"]) do
          :ok ->
            state =
              if state.connected_shard && state.connected_shard["id"] == s["id"],
                do: %{state | connected_shard: nil},
                else: state

            state = append(state, line(:ok, "Unregistered #{s["name"]}"))
            run_command(state, "shards")

          {:error, reason} ->
            append(state, line(:err, "Unregister failed: #{reason}"))
        end
    end
  end

  defp run_command(state, "heartbeat") do
    require_shard(state, fn s ->
      case UroClient.heartbeat_shard(state.uro, s["id"]) do
        :ok -> append(state, line(:ok, "Heartbeat sent for #{s["name"]}"))
        {:error, reason} -> append(state, line(:err, "Heartbeat failed: #{reason}"))
      end
    end)
  end

  defp run_command(state, "start " <> port_str) do
    require_shard(state, fn s ->
      case Integer.parse(String.trim(port_str)) do
        {port, ""} ->
          case UroClient.spawn_zone(state.uro, s["id"], port) do
            {:ok, data} ->
              append_many(state, [
                line(:ok, "Zone spawning on shard #{s["name"]} port #{port}"),
                line(:dim, "  status: #{data["status"]}"),
                line(:dim, "  run 'zones' to monitor progress")
              ])

            {:error, reason} ->
              append(state, line(:err, "Spawn failed: #{reason}"))
          end

        _ ->
          append(state, line(:err, "usage: start <port>"))
      end
    end)
  end

  defp run_command(state, "stop " <> port_str) do
    require_shard(state, fn s ->
      case Integer.parse(String.trim(port_str)) do
        {port, ""} ->
          case UroClient.stop_zone(state.uro, s["id"], port) do
            :ok ->
              append(state, line(:ok, "Zone #{s["name"]}:#{port} stopped"))

            {:error, reason} ->
              append(state, line(:err, "Stop failed: #{reason}"))
          end

        _ ->
          append(state, line(:err, "usage: stop <port>"))
      end
    end)
  end

  defp run_command(state, "zones") do
    require_shard(state, fn s ->
      case UroClient.list_zones(state.uro, s["id"]) do
        {:ok, []} ->
          append_many(state, [
            line(:warn, "No running zones for shard #{s["name"]}."),
            line(:dim, "  Use 'start <port>' to spawn one.")
          ])

        {:ok, zones} ->
          header = line(:dim, "  #{String.pad_trailing("id", 38)} port   status    cert_hash")

          rows =
            Enum.map(zones, fn z ->
              cert = String.slice(z["cert_hash"] || "-", 0, 12)

              line(
                :dim,
                "  #{String.pad_trailing(z["id"] || "?", 38)} " <>
                  "#{String.pad_trailing(to_string(z["port"] || "?"), 6)} " <>
                  "#{String.pad_trailing(z["status"] || "?", 9)} " <>
                  cert
              )
            end)

          append_many(state, [line(:info, "Zones for #{s["name"]}:"), header | rows])

        {:error, reason} ->
          append(state, line(:err, "Error: #{reason}"))
      end
    end)
  end

  defp run_command(state, "status") do
    require_shard(state, fn s ->
      owner = get_in(s, ["user", "username"]) || "?"

      append_many(state, [
        line(:info, "Shard: #{s["name"]}"),
        line(:dim, "  id:      #{s["id"]}"),
        line(:dim, "  address: #{s["address"]}:#{s["port"]}"),
        line(:dim, "  map:     #{s["map"]}"),
        line(:dim, "  owner:   #{owner}"),
        line(:dim, "  users:   #{s["current_users"] || 0} / #{s["max_users"] || "?"}"),
        line(:dim, "  (live entity data requires zone server connection — pending)")
      ])
    end)
  end

  defp run_command(state, "entities" <> rest) do
    require_shard(state, fn _s ->
      _n =
        rest
        |> String.trim()
        |> Integer.parse()
        |> then(fn
          {n, ""} -> n
          _ -> 20
        end)

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

  defp require_shard(%{connected_shard: _s} = state, fun) do
    fun.(state.connected_shard)
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
        users = "#{s["current_users"] || 0}/#{s["max_users"] || "?"}"

        line(
          :dim,
          "  #{String.pad_trailing(to_string(i), 4)}" <>
            "#{String.pad_trailing(s["name"] || "?", 20)} " <>
            "#{String.pad_trailing(s["address"] || "?", 18)} " <>
            "#{String.pad_trailing(to_string(s["port"] || "?"), 6)} " <>
            "#{String.pad_trailing(users, 7)} " <>
            "#{s["map"] || "?"}"
        )
      end)

    [header | rows]
  end
end
