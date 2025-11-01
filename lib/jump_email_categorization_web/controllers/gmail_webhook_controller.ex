defmodule JumpEmailCategorizationWeb.GmailWebhookController do
  use JumpEmailCategorizationWeb, :controller

  alias JumpEmailCategorization.Gmail.EmailFetcher

  require Logger

  @doc """
  Handles Gmail Pub/Sub push notifications.

  Gmail sends push notifications to this endpoint when new emails arrive.
  The notification is sent as a base64-encoded JSON message.
  """
  def webhook(conn, params) do
    Logger.info("Received Gmail webhook: #{inspect(params)}")

    case decode_pubsub_message(params) do
      {:ok, %{"emailAddress" => email, "historyId" => history_id}} ->
        Logger.info("Processing webhook for #{email}, history_id: #{history_id}")

        # Find the Gmail account by email
        case find_account_by_email(email) do
          nil ->
            Logger.warning("No account found for email: #{email}")
            send_resp(conn, 200, "OK")

          account ->
            # Trigger email fetch for this account
            # In a production system, you'd use the history_id to fetch only new messages
            # For now, we'll just trigger a fetch which will handle duplicates via unique constraint
            Task.start(fn ->
              process_new_emails(account, history_id)
            end)

            send_resp(conn, 200, "OK")
        end

      {:error, reason} ->
        Logger.error("Failed to decode Pub/Sub message: #{inspect(reason)}")
        send_resp(conn, 400, "Bad Request")
    end
  end

  # Private functions

  defp decode_pubsub_message(%{"message" => %{"data" => data}}) do
    try do
      data
      |> Base.decode64!()
      |> Jason.decode()
    rescue
      error ->
        Logger.error("Error decoding Pub/Sub message: #{inspect(error)}")
        {:error, :decode_failed}
    end
  end

  defp decode_pubsub_message(_), do: {:error, :invalid_format}

  defp find_account_by_email(email) do
    JumpEmailCategorization.Repo.get_by(
      JumpEmailCategorization.Gmail.GmailAccount,
      email: email
    )
  end

  defp process_new_emails(account, _history_id) do
    # In a production system, you would use the Gmail API's history endpoint
    # to fetch only the messages that changed since the last history_id
    # For now, we'll just fetch recent messages

    # Broadcast that we're processing emails for this account
    Phoenix.PubSub.broadcast(
      JumpEmailCategorization.PubSub,
      "gmail_account:#{account.id}",
      {:fetching_emails, account.id}
    )

    EmailFetcher.fetch_and_store_emails(account)

    # Broadcast that we're done processing
    Phoenix.PubSub.broadcast(
      JumpEmailCategorization.PubSub,
      "gmail_account:#{account.id}",
      {:fetch_complete, account.id}
    )
  end
end
