defmodule Uro.Repo.Migrations.AddEntities do
  use Ecto.Migration

  def change do
    # Persistent entity state — written by zones at despawn (C4) and read at spawn.
    # Coordinates are world-frame μm int64 (C6: never chunk-relative).
    # payload stores the 14 u32 fabric slots as a jsonb array.
    create table(:entities, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Fabric ephemeral ID — u32 assigned by zone per session.
      add :global_id, :integer, null: false

      # Nullable: world entities (concerts, convoys) have no owner.
      add :owner_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # Which zone last held authority.
      add :zone_shard_id, :string

      # World-frame position in μm (C6: never chunk-relative).
      add :cx, :bigint, null: false, default: 0
      add :cy, :bigint, null: false, default: 0
      add :cz, :bigint, null: false, default: 0

      # Velocity in μm/tick (i32 range covers all physical speeds).
      add :vx, :integer, null: false, default: 0
      add :vy, :integer, null: false, default: 0
      add :vz, :integer, null: false, default: 0

      # Acceleration in μm/tick² (i32).
      add :ax, :integer, null: false, default: 0
      add :ay, :integer, null: false, default: 0
      add :az, :integer, null: false, default: 0

      # Hybrid logical clock tick from the last authoritative update.
      add :hlc, :bigint, null: false, default: 0

      # 14-slot fabric payload as jsonb array of integers.
      add :payload, :map, null: false, default: "{}"

      timestamps()
    end

    create index(:entities, [:global_id])
    create index(:entities, [:owner_id])
  end
end
