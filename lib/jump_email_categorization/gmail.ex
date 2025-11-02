defmodule JumpEmailCategorization.Gmail do
  @moduledoc """
  The Gmail context - handles Gmail account management and email fetching.
  """

  import Ecto.Query, warn: false
  alias JumpEmailCategorization.Repo
  alias JumpEmailCategorization.Gmail.{GmailAccount, EmailFetcher, ApiClient}

  require Logger

  @doc """
  Returns the list of gmail accounts for a user.
  """
  def list_gmail_accounts(user_id) do
    GmailAccount
    |> where([g], g.user_id == ^user_id)
    |> order_by([g], asc: g.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single gmail_account.
  """
  def get_gmail_account!(id), do: Repo.get!(GmailAccount, id)

  @doc """
  Gets a gmail account by user_id and google_id.
  """
  def get_gmail_account_by_google_id(user_id, google_id) do
    Repo.get_by(GmailAccount, user_id: user_id, google_id: google_id)
  end

  @doc """
  Creates or updates a gmail_account from OAuth data.
  Sets up Gmail push notifications to receive new emails via webhook.
  """
  def create_or_update_gmail_account(user_id, oauth_data) do
    attrs = %{
      user_id: user_id,
      email: oauth_data["email"],
      name: oauth_data["name"],
      picture: oauth_data["picture"],
      google_id: oauth_data["sub"],
      access_token: oauth_data["access_token"],
      refresh_token: oauth_data["refresh_token"],
      token_expires_at: calculate_token_expiry(oauth_data["expires_in"]),
      scopes: oauth_data["scopes"] || []
    }

    result =
      case get_gmail_account_by_google_id(user_id, oauth_data["sub"]) do
        nil ->
          %GmailAccount{}
          |> GmailAccount.changeset(attrs)
          |> Repo.insert()

        existing_account ->
          existing_account
          |> GmailAccount.changeset(attrs)
          |> Repo.update()
      end

    # Setup Gmail push notifications for real-time email processing
    case result do
      {:ok, account} ->
        Logger.info("Setting up Gmail account: #{account.email}")

        # Setup Gmail push notifications to receive new emails
        setup_gmail_push_notifications(account)

        {:ok, account}

      error ->
        error
    end
  end

  @doc """
  Deletes a gmail_account, stops push notifications, and revokes OAuth access.

  IMPORTANT: Operations are performed in this specific order:
  1. Stop push notifications (requires valid OAuth token)
  2. Revoke OAuth access (invalidates the token)
  3. Delete from local database
  """
  def delete_gmail_account(%GmailAccount{} = gmail_account) do
    # Step 1: Stop push notifications (while token is still valid)
    case ApiClient.stop_push_notifications(gmail_account) do
      {:ok, :stopped} ->
        Logger.info("Successfully stopped push notifications for #{gmail_account.email}")

      {:error, reason} ->
        Logger.warning(
          "Failed to stop push notifications for #{gmail_account.email}: #{inspect(reason)}. " <>
            "Proceeding with account deletion anyway."
        )
    end

    # Step 2: Revoke OAuth access from Google (invalidates the token)
    revoke_oauth_access(gmail_account)

    # Step 3: Delete the account from the database
    Repo.delete(gmail_account)
  end

  @doc """
  Fetches emails from Gmail for a given account.
  This delegates to EmailFetcher for async processing.
  """
  def fetch_emails(%GmailAccount{} = account) do
    EmailFetcher.start_fetch(account)
  end

  @doc """
  Checks if an account is currently fetching emails.
  """
  def account_fetching_emails?(account_id) do
    # Check if there's an active task for this account
    # This is a simplified check - you might want to use a more sophisticated
    # state management solution like GenServer or ETS for production
    Phoenix.PubSub.broadcast(
      JumpEmailCategorization.PubSub,
      "gmail_account:#{account_id}",
      {:check_status}
    )
  end

  @doc """
  Sets up Gmail push notifications via Pub/Sub.

  Note: This requires proper Google Cloud Pub/Sub configuration:
  1. Create a Pub/Sub topic in your Google Cloud project
  2. Grant gmail-api-push@system.gserviceaccount.com the "Pub/Sub Publisher" role on the topic
  3. Configure the topic name in your application config
  """
  def setup_gmail_push_notifications(%GmailAccount{} = account) do
    # Format: projects/{project-id}/topics/{topic-name}
    topic_name = Application.get_env(:jump_email_categorization, :gmail_pubsub_topic)

    if topic_name do
      case ApiClient.setup_push_notifications(account, topic_name) do
        {:ok, response} ->
          Logger.info("Gmail push notifications setup for #{account.email}: #{inspect(response)}")

          # Store the initial history_id so we can track changes from this point forward
          if history_id = response["historyId"] do
            account
            |> GmailAccount.changeset(%{last_history_id: to_string(history_id)})
            |> Repo.update()
          end

          {:ok, response}

        {:error, {:api_error, 403, _body}} ->
          Logger.warning("""
          Failed to setup push notifications for #{account.email}: Permission denied.

          Gmail needs permission to publish to your Pub/Sub topic.
          To fix this:
          1. Go to Google Cloud Console > Pub/Sub > Topics
          2. Select your topic: #{topic_name}
          3. Click "Permissions" tab
          4. Add gmail-api-push@system.gserviceaccount.com as a member
          5. Grant it the "Pub/Sub Publisher" role

          The account will still work, but won't receive real-time notifications.
          """)

          {:error, :permission_denied}

        {:error, reason} ->
          Logger.error(
            "Failed to setup push notifications for #{account.email}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      Logger.warning("Gmail Pub/Sub topic not configured. Push notifications disabled.")
      {:error, :topic_not_configured}
    end
  end

  @doc """
  Revokes OAuth access from Google for a Gmail account.
  This disconnects the app from the user's Google account.
  """
  def revoke_oauth_access(%GmailAccount{access_token: access_token} = _account)
      when not is_nil(access_token) do
    # Google OAuth2 revocation endpoint
    url = "https://oauth2.googleapis.com/revoke"

    # Make a POST request to revoke the token
    case Req.post(url, form: [token: access_token]) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, :revoked}

      {:ok, %{status: status, body: body}} ->
        # Log the error but don't fail the deletion
        IO.puts("Failed to revoke OAuth token: #{status} - #{inspect(body)}")
        {:error, :revocation_failed}

      {:error, reason} ->
        IO.puts("Error revoking OAuth token: #{inspect(reason)}")
        {:error, :revocation_failed}
    end
  end

  def revoke_oauth_access(_account) do
    # No access token to revoke
    {:ok, :no_token}
  end

  defp calculate_token_expiry(nil), do: nil

  defp calculate_token_expiry(expires_in) when is_integer(expires_in) do
    DateTime.utc_now()
    |> DateTime.add(expires_in, :second)
  end

  defp calculate_token_expiry(expires_in) when is_binary(expires_in) do
    case Integer.parse(expires_in) do
      {seconds, _} -> calculate_token_expiry(seconds)
      :error -> nil
    end
  end
end
