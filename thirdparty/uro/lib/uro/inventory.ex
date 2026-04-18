defmodule Uro.Inventory do
  import Ecto.Query
  alias Uro.Repo
  alias Uro.Inventory.Backpack
  alias Uro.Inventory.Backpack.Join

  # ── ACL tuple helpers ────────────────────────────────────────────────

  defp backpack_obj(id), do: "backpack:#{id}"
  defp user_subj(user_id), do: "user:#{user_id}"

  defp authorized?(backpack_id, user_id) do
    Uro.Acl.check(backpack_obj(backpack_id), "owner", user_subj(user_id))
  end

  # ── Backpack CRUD ────────────────────────────────────────────────────

  def create_backpack(user_id) do
    %Backpack{}
    |> Ecto.Changeset.change(%{owner_id: user_id})
    |> Repo.insert()
    |> case do
      {:ok, backpack} = ok ->
        Uro.Acl.put({backpack_obj(backpack.id), "owner", user_subj(user_id)})
        ok

      err ->
        err
    end
  end

  def get_backpack(backpack_id, user_id) do
    if authorized?(backpack_id, user_id) do
      case Repo.get(Backpack, backpack_id) do
        nil -> {:error, :not_found}
        bp -> {:ok, Repo.preload(bp, [:maps, :avatars, :props])}
      end
    else
      {:error, :forbidden}
    end
  end

  def delete_backpack(backpack_id, user_id) do
    if authorized?(backpack_id, user_id) do
      case Repo.get(Backpack, backpack_id) do
        nil ->
          {:error, :not_found}

        bp ->
          Repo.delete(bp)
          Uro.Acl.delete({backpack_obj(backpack_id), "owner", user_subj(user_id)})
          :ok
      end
    else
      {:error, :forbidden}
    end
  end

  def list_backpacks(user_id) do
    Repo.all(from b in Backpack, where: b.owner_id == ^user_id)
  end

  # ── Item management ──────────────────────────────────────────────────

  def add_item(backpack_id, user_id, item_type, item_id)
      when item_type in [:map, :avatar, :prop] do
    if authorized?(backpack_id, user_id) do
      col = :"#{item_type}_id"
      attrs = Map.put(%{backpack_id: backpack_id}, col, item_id)

      %Join{}
      |> Ecto.Changeset.change(attrs)
      |> Repo.insert(on_conflict: :nothing)
    else
      {:error, :forbidden}
    end
  end

  def remove_item(backpack_id, user_id, item_type, item_id)
      when item_type in [:map, :avatar, :prop] do
    if authorized?(backpack_id, user_id) do
      col = :"#{item_type}_id"

      Repo.delete_all(
        from j in Join,
          where: j.backpack_id == ^backpack_id and field(j, ^col) == ^item_id
      )

      :ok
    else
      {:error, :forbidden}
    end
  end
end
