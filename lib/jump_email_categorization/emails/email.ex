defmodule JumpEmailCategorization.Emails.Email do
  use Ecto.Schema
  import Ecto.Changeset

  alias JumpEmailCategorization.Accounts.User
  alias JumpEmailCategorization.Gmail.GmailAccount
  alias JumpEmailCategorization.Categories.Category

  schema "emails" do
    field :gmail_message_id, :string
    field :gmail_thread_id, :string
    field :subject, :string
    field :body, :string
    field :snippet, :string
    field :from_email, :string
    field :from_name, :string
    field :to_emails, {:array, :string}
    field :cc_emails, {:array, :string}
    field :labels, {:array, :string}
    field :summary, :string
    field :received_at, :utc_datetime
    field :archived_at, :utc_datetime
    field :internal_date, :integer

    belongs_to :gmail_account, GmailAccount
    belongs_to :user, User
    belongs_to :category, Category

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(email, attrs) do
    email
    |> cast(attrs, [
      :gmail_message_id,
      :gmail_thread_id,
      :subject,
      :body,
      :snippet,
      :from_email,
      :from_name,
      :to_emails,
      :cc_emails,
      :labels,
      :summary,
      :received_at,
      :archived_at,
      :internal_date,
      :gmail_account_id,
      :user_id,
      :category_id
    ])
    |> validate_required([:gmail_message_id, :gmail_account_id, :user_id])
    |> unique_constraint([:gmail_account_id, :gmail_message_id])
  end
end
