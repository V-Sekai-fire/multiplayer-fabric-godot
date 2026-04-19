defmodule Uro.Repo.Migrations.AddKeychainEntries do
  use Ecto.Migration

  @disable_ddl_transaction true

  def change do
    create table(:keychain_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :service, :string, null: false
      add :account, :string, null: false
      add :blob_enc, :binary, null: false
      add :enc_iv, :binary, null: false
      add :stored_at, :integer, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:keychain_entries, [:service, :account])
  end
end
