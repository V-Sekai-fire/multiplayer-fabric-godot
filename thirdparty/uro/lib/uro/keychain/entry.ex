defmodule Uro.Keychain.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "keychain_entries" do
    field :service, :string
    field :account, :string
    field :blob_enc, :binary
    field :enc_iv, :binary
    field :stored_at, :integer

    timestamps(updated_at: false)
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:service, :account, :blob_enc, :enc_iv, :stored_at])
    |> validate_required([:service, :account, :blob_enc, :enc_iv, :stored_at])
    |> unique_constraint([:service, :account])
  end
end
