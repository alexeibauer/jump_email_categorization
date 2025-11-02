defmodule JumpEmailCategorization.Gmail.GmailAccount do
  use Ecto.Schema
  import Ecto.Changeset

  schema "gmail_accounts" do
    field :email, :string
    field :name, :string
    field :picture, :string
    field :google_id, :string
    field :access_token, :string
    field :refresh_token, :string
    field :token_expires_at, :utc_datetime
    field :scopes, {:array, :string}, default: []
    field :last_history_id, :string

    belongs_to :user, JumpEmailCategorization.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(gmail_account, attrs) do
    gmail_account
    |> cast(attrs, [
      :user_id,
      :email,
      :name,
      :picture,
      :google_id,
      :access_token,
      :refresh_token,
      :token_expires_at,
      :scopes,
      :last_history_id
    ])
    |> validate_required([:user_id, :email, :google_id])
    |> unique_constraint([:user_id, :google_id])
    |> unique_constraint([:user_id, :email])
  end
end
