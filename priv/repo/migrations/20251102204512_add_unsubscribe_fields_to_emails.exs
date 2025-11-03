defmodule JumpEmailCategorization.Repo.Migrations.AddUnsubscribeFieldsToEmails do
  use Ecto.Migration

  def change do
    alter table(:emails) do
      add :unsubscribe_link, :string
      add :unsubscribe_status, :string
      add :unsubscribe_attempted_at, :utc_datetime
      add :unsubscribe_completed_at, :utc_datetime
      add :unsubscribe_error, :text
      add :unsubscribe_method, :string
    end

    create index(:emails, [:unsubscribe_status])
  end
end
