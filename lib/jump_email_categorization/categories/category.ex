defmodule JumpEmailCategorization.Categories.Category do
  use Ecto.Schema
  import Ecto.Changeset

  alias JumpEmailCategorization.Accounts.User

  schema "categories" do
    field :name, :string
    field :description, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :description, :user_id])
    |> validate_required([:name, :description, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, min: 1, max: 500)
    |> unique_constraint(:name, name: :categories_user_id_name_index, message: "already exists")
  end
end
