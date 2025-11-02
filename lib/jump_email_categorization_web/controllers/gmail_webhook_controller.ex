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
        Logger.info("Processing webhook for #{email}, historyId: #{history_id}")

        # Find the Gmail account by email
        case find_account_by_email(email) do
          nil ->
            Logger.warning("No account found for email: #{email}")
            send_resp(conn, 200, "OK")

          account ->
            # Process new emails asynchronously using history to find which messages are new
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

  defp process_new_emails(account, history_id) do
    # Use history API to identify which specific emails just arrived in INBOX
    # This filters out drafts, sent emails, and other non-inbox changes
    # Broadcasting happens inside EmailFetcher only when INBOX messages are found
    Logger.info("Checking for new INBOX emails for account: #{account.email}")

    EmailFetcher.process_new_emails_from_history(account, history_id)
  end
end
