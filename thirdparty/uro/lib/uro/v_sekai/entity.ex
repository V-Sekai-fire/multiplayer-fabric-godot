defmodule Uro.VSekai.Entity do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "entities" do
    field :global_id, :integer
    field :zone_shard_id, :string

    belongs_to :owner, Uro.Accounts.User, foreign_key: :owner_id

    field :cx, :integer
    field :cy, :integer
    field :cz, :integer
    field :vx, :integer
    field :vy, :integer
    field :vz, :integer
    field :ax, :integer
    field :ay, :integer
    field :az, :integer
    field :hlc, :integer
    field :payload, :map

    has_many :teleports, Uro.VSekai.EntityTeleport

    timestamps()
  end

  @required ~w(global_id cx cy cz vx vy vz ax ay az hlc payload)a
  @optional ~w(owner_id zone_shard_id)a

  def changeset(entity, attrs) do
    entity
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
  end
end
