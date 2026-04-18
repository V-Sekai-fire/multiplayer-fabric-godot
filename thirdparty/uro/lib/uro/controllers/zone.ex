defmodule Uro.ZoneController do
  use Uro, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Uro.VSekai
  alias Uro.VSekai.Zone
  alias Uro.WebTransport.ZoneSupervisor

  tags(["zones"])

  operation(:index,
    operation_id: "listZones",
    summary: "List Zones",
    description: "List all live zone processes, optionally filtered to a shard.",
    parameters: [
      shard_id: [in: :query, schema: %Schema{type: :string}, required: false]
    ],
    responses: [
      ok: {
        "",
        "application/json",
        %Schema{
          type: :object,
          properties: %{
            data: %Schema{
              type: :object,
              properties: %{zones: %Schema{type: :array, items: Zone.json_schema()}}
            }
          }
        }
      }
    ]
  )

  def index(conn, %{"shard_id" => shard_id}) do
    zones = VSekai.list_fresh_zones_for_shard(shard_id)
    json(conn, %{data: %{zones: Enum.map(zones, &Zone.to_json_schema/1)}})
  end

  def index(conn, _params) do
    zones = VSekai.list_fresh_zones()
    json(conn, %{data: %{zones: Enum.map(zones, &Zone.to_json_schema/1)}})
  end

  operation(:create,
    operation_id: "spawnZone",
    summary: "Spawn Zone",
    description: "Start a headless Godot zone process under the given shard.",
    request_body: {
      "",
      "application/json",
      %Schema{
        title: "SpawnZoneRequest",
        type: :object,
        required: [:shard_id, :port],
        properties: %{
          shard_id: %Schema{type: :string, description: "ID of the parent shard"},
          port: %Schema{type: :integer, description: "UDP/QUIC port for the zone"}
        }
      }
    },
    responses: [
      ok: {
        "",
        "application/json",
        %Schema{
          type: :object,
          properties: %{
            data: %Schema{
              type: :object,
              properties: %{
                shard_id: %Schema{type: :string},
                port: %Schema{type: :integer},
                status: %Schema{type: :string}
              }
            }
          }
        }
      },
      unprocessable_entity: {"Spawn failed", "application/json", error_json_schema()}
    ]
  )

  def create(conn, %{"shard_id" => shard_id, "port" => port}) do
    case ZoneSupervisor.start_zone(shard_id, port) do
      {:ok, _pid} ->
        conn
        |> put_status(200)
        |> json(%{data: %{shard_id: shard_id, port: port, status: "starting"}})

      {:error, reason} ->
        json_error(conn, code: :unprocessable_entity, message: inspect(reason))
    end
  end

  def create(conn, _params) do
    json_error(conn, code: :bad_request, message: "shard_id and port are required")
  end

  operation(:delete,
    operation_id: "stopZone",
    summary: "Stop Zone",
    description: "Terminate a running zone process.",
    parameters: [
      shard_id: [in: :path, schema: %Schema{type: :string}],
      port: [in: :path, schema: %Schema{type: :integer}]
    ],
    responses: [
      ok: {"Zone stopped", "application/json", success_json_schema()},
      not_found: {"Zone not found", "application/json", error_json_schema()}
    ]
  )

  def delete(conn, %{"shard_id" => shard_id, "port" => port_str}) do
    port = String.to_integer(port_str)

    case ZoneSupervisor.stop_zone(shard_id, port) do
      :ok ->
        json(conn, %{message: "Zone #{shard_id}:#{port} stopped"})

      {:error, :not_found} ->
        json_error(conn, code: :not_found, message: "No running zone for shard #{shard_id} port #{port}")
    end
  end
end
