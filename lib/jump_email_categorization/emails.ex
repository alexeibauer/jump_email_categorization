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

  @doc """
  Returns paginated emails for a user.
  Options:
    - page: page number (default: 1)
    - page_size: number of emails per page (default: 30)
    - category_id: filter by category
    - gmail_account_id: filter by Gmail account
  """
  def list_emails_paginated(user_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 30)

    query =
      Email
      |> where([e], e.user_id == ^user_id)
      |> apply_filters(opts)
      |> order_by([e], desc: e.received_at)

    # Get total count for pagination metadata
    total_count = Repo.aggregate(query, :count)

    # Calculate pagination
    total_pages = ceil(total_count / page_size)
    offset = (page - 1) * page_size

    # Get paginated results
    emails =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    %{
      emails: emails,
      page: page,
      page_size: page_size,
      total_count: total_count,
      total_pages: total_pages,
      has_prev: page > 1,
      has_next: page < total_pages
    }
  end

  @doc """
  Counts total emails for a user with optional filters.
  """
  def count_emails(user_id, opts \\ []) do
    Email
    |> where([e], e.user_id == ^user_id)
    |> apply_filters(opts)
    |> Repo.aggregate(:count)
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:category_id, category_id}, query ->
        where(query, [e], e.category_id == ^category_id)

      {:gmail_account_id, account_id}, query ->
        where(query, [e], e.gmail_account_id == ^account_id)

      {:page, _}, query ->
        query

      {:page_size, _}, query ->
        query

      _, query ->
        query
    end)
  end

  @doc """
  Gets a single email.
  """
  def get_email!(id), do: Repo.get!(Email, id)

  @doc """
  Creates an email and broadcasts to PubSub.
  """
  def create_email(attrs \\ %{}) do
    case %Email{}
         |> Email.changeset(attrs)
         |> Repo.insert() do
      {:ok, email} = result ->
        # Broadcast to user-specific topic
        Phoenix.PubSub.broadcast(
          JumpEmailCategorization.PubSub,
          "user_emails:#{email.user_id}",
          {:new_email, email}
        )

        result

      error ->
        error
    end
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
