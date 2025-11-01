defmodule JumpEmailCategorization.Emails do
  @moduledoc """
  The Emails context - handles email storage and management.
  """

  import Ecto.Query, warn: false
  alias JumpEmailCategorization.Repo
  alias JumpEmailCategorization.Emails.Email

  @doc """
  Returns the list of emails for a user.
  """
  def list_emails(user_id, opts \\ []) do
    Email
    |> where([e], e.user_id == ^user_id)
    |> apply_filters(opts)
    |> order_by([e], desc: e.received_at)
    |> Repo.all()
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:category_id, category_id}, query ->
        where(query, [e], e.category_id == ^category_id)

      {:gmail_account_id, account_id}, query ->
        where(query, [e], e.gmail_account_id == ^account_id)

      _, query ->
        query
    end)
  end

  @doc """
  Gets a single email.
  """
  def get_email!(id), do: Repo.get!(Email, id)

  @doc """
  Creates an email.
  """
  def create_email(attrs \\ %{}) do
    %Email{}
    |> Email.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an email.
  """
  def update_email(%Email{} = email, attrs) do
    email
    |> Email.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an email.
  """
  def delete_email(%Email{} = email) do
    Repo.delete(email)
  end

  @doc """
  Categorizes an email based on its content.
  TODO: Implement AI-based categorization logic.
  """
  def categorize_email(%Email{} = _email) do
    # TODO: Implement categorization logic
    # This will use AI/ML to determine the category based on:
    # - subject
    # - body
    # - from_email
    # - previous categorization patterns
    nil
  end

  @doc """
  Generates a summary for an email.
  TODO: Implement AI-based summarization logic.
  """
  def summarize_email(%Email{} = _email) do
    # TODO: Implement summarization logic
    # This will use AI/ML to generate a brief summary of the email content
    nil
  end

  @doc """
  Marks an email as archived.
  """
  def mark_as_archived(%Email{} = email) do
    update_email(email, %{archived_at: DateTime.utc_now()})
  end
end
