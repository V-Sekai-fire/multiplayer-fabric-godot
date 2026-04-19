defmodule Uro.Repo.Migrations.AddEntityTeleports do
  use Ecto.Migration

  def change do
    # C3 teleport records — zones write before a portal/spatial discontinuity.
    # The receiving zone reads this to reconstruct the entity at the landing
    # position without treating the jump as a physics violation.
    create table(:entity_teleports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :entity_id, references(:entities, type: :binary_id, on_delete: :delete_all),
        null: false

      # World-frame source position (μm).
      add :from_cx, :bigint, null: false
      add :from_cy, :bigint, null: false
      add :from_cz, :bigint, null: false

      # World-frame destination position (μm).
      add :to_cx, :bigint, null: false
      add :to_cy, :bigint, null: false
      add :to_cz, :bigint, null: false

      add :from_zone_shard_id, :string
      add :to_zone_shard_id, :string

      # HLC tick at which the jump was registered.
      add :hlc, :bigint, null: false

      timestamps(updated_at: false)
    end

    create index(:entity_teleports, [:entity_id])
    create index(:entity_teleports, [:entity_id, :hlc])
  end
end
