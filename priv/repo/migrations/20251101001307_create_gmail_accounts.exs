defmodule JumpEmailCategorization.Repo.Migrations.CreateGmailAccounts do
  use Ecto.Migration

  def change do
    create table(:gmail_accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :email, :string, null: false
      add :name, :string
      add :picture, :string
      add :google_id, :string, null: false
      add :access_token, :text
      add :refresh_token, :text
      add :token_expires_at, :utc_datetime
      add :scopes, {:array, :string}, default: []

      timestamps(type: :utc_datetime)
    end

    create index(:gmail_accounts, [:user_id])
    create unique_index(:gmail_accounts, [:user_id, :google_id])
    create unique_index(:gmail_accounts, [:user_id, :email])
  end
end
