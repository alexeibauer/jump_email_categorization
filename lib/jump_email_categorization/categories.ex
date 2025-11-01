defmodule JumpEmailCategorization.Categories do
  @moduledoc """
  The Categories context - handles email category management.
  """

  import Ecto.Query, warn: false
  alias JumpEmailCategorization.Repo
  alias JumpEmailCategorization.Categories.Category

  @doc """
  Returns the list of categories for a user, sorted alphabetically.
  """
  def list_categories(user_id) do
    Category
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Gets a single category.
  """
  def get_category!(id), do: Repo.get!(Category, id)

  @doc """
  Creates a category.
  """
  def create_category(attrs \\ %{}) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a category.
  """
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a category.
  """
  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.
  """
  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end
end
