defmodule Uro.Repo.Migrations.AddZones do
  use Ecto.Migration

  def change do
    create table(:zones, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shard_id, references(:shards, type: :id, on_delete: :delete_all), null: false
      add :address, :string, null: false
      add :port, :integer, null: false
      add :cert_hash, :string
      add :current_users, :integer, default: 0, null: false
      add :status, :string, default: "starting", null: false

      timestamps()
    end

    create index(:zones, [:shard_id])
  end
end
