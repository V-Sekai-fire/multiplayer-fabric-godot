defmodule Uro.Repo.Migrations.FixBackpackJoinFkeyReferencesBackpacks do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    execute("ALTER TABLE backpack_join DROP CONSTRAINT IF EXISTS backpack_join_backpack_id_fkey")
    execute("ALTER TABLE backpack_join ADD CONSTRAINT backpack_join_backpack_id_fkey FOREIGN KEY (backpack_id) REFERENCES backpacks(id)")
  end

  def down do
    execute("ALTER TABLE backpack_join DROP CONSTRAINT IF EXISTS backpack_join_backpack_id_fkey")
    execute("ALTER TABLE backpack_join ADD CONSTRAINT backpack_join_backpack_id_fkey FOREIGN KEY (backpack_id) REFERENCES users(id)")
  end
end
