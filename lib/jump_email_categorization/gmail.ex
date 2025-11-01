defmodule JumpEmailCategorization.Gmail do
  @moduledoc """
  The Gmail context - handles Gmail account management and email fetching.
  """

  import Ecto.Query, warn: false
  alias JumpEmailCategorization.Repo
  alias JumpEmailCategorization.Gmail.GmailAccount

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
  end

  @doc """
  Deletes a gmail_account.
  """
  def delete_gmail_account(%GmailAccount{} = gmail_account) do
    Repo.delete(gmail_account)
  end

  # TODO: Implement email fetching from Gmail API
  @doc """
  Fetches emails from Gmail for a given account.
  This is a placeholder - implement Gmail API integration here.
  """
  def fetch_emails(%GmailAccount{} = _account) do
    # TODO: Use the Gmail API to fetch emails
    # 1. Check if access_token is expired, refresh if needed
    # 2. Call Gmail API with the access_token
    # 3. Parse and store emails in the database
    # 4. Return the fetched emails
    {:ok, []}
  end

  @doc """
  Refreshes the access token for a Gmail account.
  This is a placeholder - implement token refresh logic here.
  """
  def refresh_access_token(%GmailAccount{} = _account) do
    # TODO: Implement OAuth token refresh
    # 1. Use the refresh_token to get a new access_token
    # 2. Update the account with the new token
    # 3. Update token_expires_at
    {:ok, nil}
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
