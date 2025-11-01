defmodule JumpEmailCategorization.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails) do
      add :gmail_account_id, references(:gmail_accounts, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :gmail_message_id, :string, null: false
      add :gmail_thread_id, :string
      add :subject, :string
      add :body, :text
      add :snippet, :text
      add :from_email, :string
      add :from_name, :string
      add :to_emails, {:array, :string}, default: []
      add :cc_emails, {:array, :string}, default: []
      add :labels, {:array, :string}, default: []
      add :category_id, references(:categories, on_delete: :nilify_all)
      add :summary, :text
      add :received_at, :utc_datetime
      add :archived_at, :utc_datetime
      add :internal_date, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:emails, [:gmail_account_id])
    create index(:emails, [:user_id])
    create index(:emails, [:category_id])
    create unique_index(:emails, [:gmail_account_id, :gmail_message_id])
  end
end
