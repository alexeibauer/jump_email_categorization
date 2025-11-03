defmodule JumpEmailCategorization.Emails do
  @moduledoc """
  The Emails context - handles email storage and management.
  """

  import Ecto.Query, warn: false
  require Logger
  alias JumpEmailCategorization.Repo
  alias JumpEmailCategorization.Emails.Email
  alias JumpEmailCategorization.Gmail.{ApiClient, GmailAccount}

  @doc """
  Returns the list of emails for a user.
  """
  def list_emails(user_id, opts \\ []) do
    Email
    |> where([e], e.user_id == ^user_id)
    |> apply_filters(opts)
    |> order_by([e], desc: e.received_at)
    |> Repo.all()
    |> Repo.preload(:category)
  end

  @doc """
  Returns paginated emails for a user.
  Options:
    - page: page number (default: 1)
    - page_size: number of emails per page (default: 30)
    - category_id: filter by category ID
    - category_name: filter by category name
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
      |> Repo.preload(:category)

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

      {:category_name, category_name}, query ->
        query
        |> join(:inner, [e], c in assoc(e, :category))
        |> where([e, c], c.name == ^category_name)

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
  Updates an email and broadcasts to PubSub.
  """
  def update_email(%Email{} = email, attrs) do
    require Logger

    case email
         |> Email.changeset(attrs)
         |> Repo.update() do
      {:ok, updated_email} ->
        # Preload category association for the broadcast
        updated_email = Repo.preload(updated_email, :category, force: true)

        # Broadcast to user-specific topic
        Logger.info(
          "Broadcasting email update for email #{updated_email.id} to user #{updated_email.user_id}"
        )

        Phoenix.PubSub.broadcast(
          JumpEmailCategorization.PubSub,
          "user_emails:#{updated_email.user_id}",
          {:email_updated, updated_email}
        )

        {:ok, updated_email}

      error ->
        error
    end
  end

  @doc """
  Deletes an email from the database and moves it to Gmail trash.
  If the Gmail trash operation fails, the email is still deleted from the database.
  """
  def delete_email(%Email{} = email) do
    # Preload the gmail_account association if not already loaded
    email = Repo.preload(email, :gmail_account)

    # Try to move the email to Gmail trash first
    gmail_result =
      case email.gmail_account do
        %GmailAccount{} = account ->
          Logger.info(
            "Attempting to trash Gmail message #{email.gmail_message_id} for email #{email.id}"
          )

          # Ensure token is valid before making the request
          account = ensure_valid_token(account)

          case ApiClient.trash_message(account, email.gmail_message_id) do
            {:ok, _response} ->
              Logger.info("Successfully trashed Gmail message #{email.gmail_message_id}")
              :ok

            {:error, {:api_error, 401, _body}} ->
              Logger.warning(
                "Gmail token expired for email #{email.id}, attempting to refresh and retry"
              )

              # Token might have expired between check and use, try refreshing and retrying once
              case refresh_token_and_retry_trash(account, email.gmail_message_id) do
                :ok ->
                  Logger.info(
                    "Successfully trashed Gmail message #{email.gmail_message_id} after token refresh"
                  )

                  :ok

                :failed ->
                  Logger.error(
                    "Failed to trash Gmail message #{email.gmail_message_id} even after token refresh"
                  )

                  :failed
              end

            {:error, reason} ->
              Logger.warning(
                "Failed to trash Gmail message #{email.gmail_message_id}: #{inspect(reason)}"
              )

              :failed
          end

        nil ->
          Logger.warning(
            "Email #{email.id} has no associated Gmail account, skipping Gmail trash"
          )

          :no_account
      end

    # Delete from database regardless of Gmail trash result
    # This ensures we clean up our database even if Gmail API fails
    result = Repo.delete(email)

    case result do
      {:ok, deleted_email} ->
        Logger.info(
          "Successfully deleted email #{email.id} from database (Gmail: #{gmail_result})"
        )

        {:ok, deleted_email}

      {:error, changeset} ->
        Logger.error("Failed to delete email #{email.id} from database: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  # Private helper functions for token management

  defp ensure_valid_token(%GmailAccount{} = account) do
    if token_expired?(account) do
      Logger.info("Gmail token expired, refreshing for account #{account.id}")

      case ApiClient.refresh_access_token(account) do
        {:ok, %{access_token: new_token, expires_in: expires_in}} ->
          {:ok, updated_account} =
            account
            |> GmailAccount.changeset(%{
              access_token: new_token,
              token_expires_at: calculate_token_expiry(expires_in)
            })
            |> Repo.update()

          Logger.info("Successfully refreshed token for Gmail account #{account.id}")
          updated_account

        {:error, reason} ->
          Logger.error("Failed to refresh token for account #{account.id}: #{inspect(reason)}")
          account
      end
    else
      account
    end
  end

  defp refresh_token_and_retry_trash(%GmailAccount{} = account, message_id) do
    case ApiClient.refresh_access_token(account) do
      {:ok, %{access_token: new_token, expires_in: expires_in}} ->
        {:ok, updated_account} =
          account
          |> GmailAccount.changeset(%{
            access_token: new_token,
            token_expires_at: calculate_token_expiry(expires_in)
          })
          |> Repo.update()

        # Retry with fresh token
        case ApiClient.trash_message(updated_account, message_id) do
          {:ok, _response} -> :ok
          {:error, _reason} -> :failed
        end

      {:error, _reason} ->
        :failed
    end
  end

  defp token_expired?(%GmailAccount{token_expires_at: nil}), do: false

  defp token_expired?(%GmailAccount{token_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp calculate_token_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
    |> DateTime.add(-300, :second)
  end

  defp calculate_token_expiry(_), do: nil

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
