defmodule Uro.VSekai.Zone do
  use Ecto.Schema
  import Ecto.Changeset

  alias OpenApiSpex.Schema
  alias Uro.VSekai.Shard

  @primary_key {:id, :binary_id, autogenerate: true}

  @derive {Jason.Encoder, only: [:id, :address, :port, :cert_hash, :current_users, :status]}

  schema "zones" do
    belongs_to :shard, Shard, foreign_key: :shard_id, type: :id

    field :address, :string
    field :port, :integer
    field :cert_hash, :string
    field :current_users, :integer, default: 0
    field :status, :string, default: "starting"

    timestamps()
  end

  @json_schema %Schema{
    title: "Zone",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      address: %Schema{type: :string},
      port: %Schema{type: :integer},
      cert_hash: %Schema{type: :string},
      current_users: %Schema{type: :integer},
      status: %Schema{type: :string, enum: ["starting", "running", "stopping"]}
    }
  }

  def json_schema, do: @json_schema

  def changeset(zone, attrs) do
    zone
    |> cast(attrs, [:shard_id, :address, :port, :cert_hash, :current_users, :status])
    |> validate_required([:shard_id, :address, :port])
    |> validate_inclusion(:status, ["starting", "running", "stopping"])
  end
end
