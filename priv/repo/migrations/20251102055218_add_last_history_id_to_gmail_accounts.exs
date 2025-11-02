defmodule JumpEmailCategorization.Repo.Migrations.AddLastHistoryIdToGmailAccounts do
  use Ecto.Migration

  def change do
    alter table(:gmail_accounts) do
      add :last_history_id, :string
    end
  end
end
