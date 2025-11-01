defmodule JumpEmailCategorization.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:categories, [:user_id])
    create unique_index(:categories, [:user_id, :name])
  end
end
