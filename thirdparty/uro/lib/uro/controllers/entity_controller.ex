defmodule Uro.EntityController do
  use Uro, :controller
  use Uro.Helpers.API

  import Ecto.Query
  alias Uro.Repo
  alias Uro.VSekai.Entity
  alias Uro.VSekai.EntityTeleport

  # ── C4 spawn: zone reads last-known state ────────────────────────────────────
  # GET /entities/:global_id
  # Returns the most recently persisted state for this fabric global_id.
  # If no record exists (first spawn) returns 404 — zone spawns with defaults.
  def show(conn, %{"global_id" => global_id_str}) do
    global_id = String.to_integer(global_id_str)

    entity =
      Entity
      |> where([e], e.global_id == ^global_id)
      |> order_by([e], desc: e.hlc)
      |> limit(1)
      |> Repo.one()

    case entity do
      nil ->
        json_error(conn, code: :not_found, message: "No persisted state for global_id #{global_id}")

      entity ->
        # Include the latest teleport if hlc matches — lets the zone
        # reconstruct the landing position without a physics violation (C3).
        teleport =
          EntityTeleport
          |> where([t], t.entity_id == ^entity.id and t.hlc == ^entity.hlc)
          |> Repo.one()

        json(conn, %{
          data: %{
            id: entity.id,
            global_id: entity.global_id,
            owner_id: entity.owner_id,
            zone_shard_id: entity.zone_shard_id,
            position: %{cx: entity.cx, cy: entity.cy, cz: entity.cz},
            velocity: %{vx: entity.vx, vy: entity.vy, vz: entity.vz},
            acceleration: %{ax: entity.ax, ay: entity.ay, az: entity.az},
            hlc: entity.hlc,
            payload: entity.payload,
            teleport: teleport && %{
              from: %{cx: teleport.from_cx, cy: teleport.from_cy, cz: teleport.from_cz},
              to: %{cx: teleport.to_cx, cy: teleport.to_cy, cz: teleport.to_cz},
              from_zone: teleport.from_zone_shard_id,
              to_zone: teleport.to_zone_shard_id
            }
          }
        })
    end
  end

  # ── C4 despawn: zone writes final state ──────────────────────────────────────
  # PUT /entities/:global_id
  # Zone calls this on entity despawn or zone shutdown.
  # Creates or updates the record; higher HLC wins (last-write-wins on HLC).
  def update(conn, %{"global_id" => global_id_str} = params) do
    global_id = String.to_integer(global_id_str)

    existing =
      Entity
      |> where([e], e.global_id == ^global_id)
      |> order_by([e], desc: e.hlc)
      |> limit(1)
      |> Repo.one()

    incoming_hlc = Map.get(params, "hlc", 0)

    if existing && existing.hlc >= incoming_hlc do
      json(conn, %{data: %{id: existing.id, status: "stale"}})
    else
      attrs = %{
        global_id: global_id,
        owner_id: params["owner_id"],
        zone_shard_id: params["zone_shard_id"],
        cx: get_in(params, ["position", "cx"]) || 0,
        cy: get_in(params, ["position", "cy"]) || 0,
        cz: get_in(params, ["position", "cz"]) || 0,
        vx: get_in(params, ["velocity", "vx"]) || 0,
        vy: get_in(params, ["velocity", "vy"]) || 0,
        vz: get_in(params, ["velocity", "vz"]) || 0,
        ax: get_in(params, ["acceleration", "ax"]) || 0,
        ay: get_in(params, ["acceleration", "ay"]) || 0,
        az: get_in(params, ["acceleration", "az"]) || 0,
        hlc: incoming_hlc,
        payload: params["payload"] || %{}
      }

      result =
        case existing do
          nil -> %Entity{} |> Entity.changeset(attrs) |> Repo.insert()
          e -> e |> Entity.changeset(attrs) |> Repo.update()
        end

      case result do
        {:ok, entity} ->
          conn |> put_status(:ok) |> json(%{data: %{id: entity.id, status: "saved"}})

        {:error, changeset} ->
          json_error(conn, code: :unprocessable_entity, message: inspect(changeset.errors))
      end
    end
  end

  # ── C3 teleport: zone registers a spatial discontinuity ──────────────────────
  # POST /entities/:global_id/teleport
  # Zone A calls this before the entity crosses a portal.
  # The receiving zone (B) reads it via GET /entities/:global_id and sees
  # the teleport field — skipping the C3 gap check for this transition.
  def teleport(conn, %{"global_id" => global_id_str} = params) do
    global_id = String.to_integer(global_id_str)

    entity =
      Entity
      |> where([e], e.global_id == ^global_id)
      |> order_by([e], desc: e.hlc)
      |> limit(1)
      |> Repo.one()

    case entity do
      nil ->
        json_error(conn, code: :not_found, message: "Unknown entity global_id #{global_id}")

      entity ->
        attrs = %{
          entity_id: entity.id,
          from_cx: get_in(params, ["from", "cx"]) || entity.cx,
          from_cy: get_in(params, ["from", "cy"]) || entity.cy,
          from_cz: get_in(params, ["from", "cz"]) || entity.cz,
          to_cx: get_in(params, ["to", "cx"]) || 0,
          to_cy: get_in(params, ["to", "cy"]) || 0,
          to_cz: get_in(params, ["to", "cz"]) || 0,
          from_zone_shard_id: params["from_zone_shard_id"],
          to_zone_shard_id: params["to_zone_shard_id"],
          hlc: params["hlc"] || entity.hlc
        }

        case %EntityTeleport{} |> EntityTeleport.changeset(attrs) |> Repo.insert() do
          {:ok, tp} ->
            conn |> put_status(:created) |> json(%{data: %{id: tp.id, status: "registered"}})

          {:error, changeset} ->
            json_error(conn, code: :unprocessable_entity, message: inspect(changeset.errors))
        end
    end
  end
end
