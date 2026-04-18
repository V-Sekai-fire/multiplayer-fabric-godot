defmodule Uro.BackpackController do
  use Uro, :controller

  alias Uro.Inventory
  alias Uro.Helpers.Auth

  action_fallback Uro.FallbackController

  def create(conn, _params) do
    user = Auth.get_current_user(conn)

    case Inventory.create_backpack(user.id) do
      {:ok, backpack} ->
        conn |> put_status(201) |> json(%{data: %{id: backpack.id}})

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def show(conn, %{"id" => id}) do
    user = Auth.get_current_user(conn)

    case Inventory.get_backpack(id, user.id) do
      {:ok, backpack} ->
        conn |> put_status(200) |> json(%{data: serialize(backpack)})

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "not found"})

      {:error, :forbidden} ->
        conn |> put_status(403) |> json(%{error: "forbidden"})
    end
  end

  def delete(conn, %{"id" => id}) do
    user = Auth.get_current_user(conn)

    case Inventory.delete_backpack(id, user.id) do
      :ok -> conn |> put_status(204) |> json(%{})
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "not found"})
      {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "forbidden"})
    end
  end

  def add_item(conn, %{"id" => bp_id, "type" => type, "item_id" => item_id}) do
    user = Auth.get_current_user(conn)

    case parse_type(type) do
      {:ok, item_type} ->
        case Inventory.add_item(bp_id, user.id, item_type, item_id) do
          {:ok, _} -> conn |> put_status(204) |> json(%{})
          {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "forbidden"})
          {:error, changeset} -> conn |> put_status(422) |> json(%{errors: changeset_errors(changeset)})
        end

      :error ->
        conn |> put_status(400) |> json(%{error: "type must be map, avatar, or prop"})
    end
  end

  def remove_item(conn, %{"id" => bp_id, "type" => type, "item_id" => item_id}) do
    user = Auth.get_current_user(conn)

    case parse_type(type) do
      {:ok, item_type} ->
        case Inventory.remove_item(bp_id, user.id, item_type, item_id) do
          :ok -> conn |> put_status(204) |> json(%{})
          {:error, :forbidden} -> conn |> put_status(403) |> json(%{error: "forbidden"})
        end

      :error ->
        conn |> put_status(400) |> json(%{error: "type must be map, avatar, or prop"})
    end
  end

  defp parse_type("map"), do: {:ok, :map}
  defp parse_type("avatar"), do: {:ok, :avatar}
  defp parse_type("prop"), do: {:ok, :prop}
  defp parse_type(_), do: :error

  defp serialize(bp) do
    %{
      id: bp.id,
      owner_id: bp.owner_id,
      maps: Enum.map(bp.maps, & &1.id),
      avatars: Enum.map(bp.avatars, & &1.id),
      props: Enum.map(bp.props, & &1.id)
    }
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
