defmodule Uro.VSekai.EntityTeleport do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "entity_teleports" do
    belongs_to :entity, Uro.VSekai.Entity

    field :from_cx, :integer
    field :from_cy, :integer
    field :from_cz, :integer
    field :to_cx, :integer
    field :to_cy, :integer
    field :to_cz, :integer

    field :from_zone_shard_id, :string
    field :to_zone_shard_id, :string

    field :hlc, :integer

    timestamps(updated_at: false)
  end

  @required ~w(entity_id from_cx from_cy from_cz to_cx to_cy to_cz hlc)a
  @optional ~w(from_zone_shard_id to_zone_shard_id)a

  def changeset(teleport, attrs) do
    teleport
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> foreign_key_constraint(:entity_id)
  end
end
