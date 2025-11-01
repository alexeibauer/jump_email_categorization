defmodule JumpEmailCategorization.Gmail.EmailFetcher do
  @moduledoc """
  Handles asynchronous fetching of emails from Gmail accounts.
  """

  use Task

  alias JumpEmailCategorization.Gmail.{ApiClient, EmailParser, GmailAccount}
  alias JumpEmailCategorization.Emails
  alias JumpEmailCategorization.Repo

  require Logger

  # Configurable limit for email fetching
  @max_emails_to_fetch 100

  @doc """
  Starts an async task to fetch emails for a Gmail account.
  """
  def start_fetch(%GmailAccount{} = account) do
    Task.Supervisor.start_child(
      JumpEmailCategorization.TaskSupervisor,
      __MODULE__,
      :fetch_and_store_emails,
      [account]
    )
  end

  @doc """
  Fetches emails and stores them in the database.
  This is the main entry point for the async task.
  """
  def fetch_and_store_emails(%GmailAccount{} = account) do
    Logger.info("Starting email fetch for account: #{account.email}")

    # Ensure token is valid
    account = ensure_valid_token(account)

    # Fetch message list
    case ApiClient.fetch_messages(account, max_results: @max_emails_to_fetch) do
      {:ok, %{"messages" => messages}} when is_list(messages) ->
        Logger.info("Fetched #{length(messages)} message IDs for #{account.email}")

        # Process messages in chunks to avoid overwhelming the API
        messages
        |> Enum.chunk_every(10)
        |> Enum.each(fn chunk ->
          process_message_chunk(account, chunk)
        end)

        Logger.info("Completed email fetch for account: #{account.email}")
        :ok

      {:ok, _response} ->
        Logger.info("No messages found for account: #{account.email}")
        :ok

      {:error, reason} ->
        Logger.error("Failed to fetch messages for #{account.email}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Processes a single new email (used for Pub/Sub notifications).
  """
  def process_single_email(%GmailAccount{} = account, message_id) do
    Logger.info("Processing single email #{message_id} for account: #{account.email}")

    account = ensure_valid_token(account)

    case fetch_and_store_message(account, message_id) do
      {:ok, email} ->
        # Archive the email
        case ApiClient.archive_message(account, message_id) do
          {:ok, _} ->
            Emails.mark_as_archived(email)
            Logger.info("Archived email #{message_id}")
            {:ok, email}

          {:error, reason} ->
            Logger.error("Failed to archive email #{message_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Failed to process email #{message_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp process_message_chunk(account, messages) do
    # Fetch full message details
    emails =
      messages
      |> Enum.map(fn %{"id" => message_id} ->
        fetch_and_store_message(account, message_id)
      end)
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, email} -> email end)

    # Archive successfully stored emails
    if emails != [] do
      Logger.info("Archiving #{length(emails)} emails")
      archive_emails(account, emails)
    end
  end

  defp fetch_and_store_message(account, message_id) do
    case ApiClient.get_message(account, message_id) do
      {:ok, message_data} ->
        attrs = EmailParser.parse_message(message_data, account.id, account.user_id)

        case Emails.create_email(attrs) do
          {:ok, email} ->
            # TODO: Trigger categorization and summarization
            # spawn(fn ->
            #   Emails.categorize_email(email)
            #   Emails.summarize_email(email)
            # end)
            {:ok, email}

          {:error, changeset} ->
            Logger.error("Failed to store email #{message_id}: #{inspect(changeset.errors)}")
            {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("Failed to fetch message #{message_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp archive_emails(account, emails) do
    message_ids = Enum.map(emails, & &1.gmail_message_id)

    results = ApiClient.batch_archive_messages(account, message_ids)

    # Update archived_at timestamp for successfully archived emails
    Enum.each(results, fn {message_id, result} ->
      case result do
        {:ok, _} ->
          email = Enum.find(emails, &(&1.gmail_message_id == message_id))
          if email, do: Emails.mark_as_archived(email)

        {:error, reason} ->
          Logger.error("Failed to archive #{message_id}: #{inspect(reason)}")
      end
    end)
  end

  defp ensure_valid_token(account) do
    if token_expired?(account) do
      case ApiClient.refresh_access_token(account) do
        {:ok, %{access_token: new_token, expires_in: expires_in}} ->
          {:ok, updated_account} =
            account
            |> GmailAccount.changeset(%{
              access_token: new_token,
              token_expires_at: calculate_expiry(expires_in)
            })
            |> Repo.update()

          updated_account

        {:error, reason} ->
          Logger.error("Failed to refresh token: #{inspect(reason)}")
          account
      end
    else
      account
    end
  end

  defp token_expired?(%GmailAccount{token_expires_at: nil}), do: false

  defp token_expired?(%GmailAccount{token_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  defp calculate_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
  end
end
