defmodule JumpEmailCategorizationWeb.OAuthController do
  use JumpEmailCategorizationWeb, :controller
  plug Ueberauth

  alias JumpEmailCategorization.Gmail

  @doc """
  Initiates the Google OAuth flow.
  This redirects the user to Google's OAuth consent screen.
  """
  def request(conn, %{"provider" => _provider}) do
    # Ueberauth plug will handle the redirect to Google
    # This function is just here as a placeholder
    conn
  end

  @doc """
  Handles the OAuth callback from Google.
  Receives the authorization code and exchanges it for tokens.
  """
  def callback(conn, %{"provider" => "google"} = _params) do
    # Get the current user
    user = conn.assigns.current_scope.user

    case conn.assigns do
      %{ueberauth_auth: auth} ->
        # Extract OAuth data from the Ueberauth response
        oauth_data = %{
          "email" => auth.info.email,
          "name" => auth.info.name,
          "picture" => auth.info.image,
          "sub" => auth.uid,
          "access_token" => auth.credentials.token,
          "refresh_token" => auth.credentials.refresh_token,
          "expires_in" => auth.credentials.expires_at,
          "scopes" => auth.credentials.scopes || []
        }

        case Gmail.create_or_update_gmail_account(user.id, oauth_data) do
          {:ok, _gmail_account} ->
            conn
            |> put_flash(:info, "Gmail account connected successfully!")
            |> redirect(to: ~p"/")

          {:error, changeset} ->
            conn
            |> put_flash(:error, "Failed to connect Gmail account: #{inspect(changeset.errors)}")
            |> redirect(to: ~p"/")
        end

      %{ueberauth_failure: failure} ->
        errors = Enum.map(failure.errors, & &1.message) |> Enum.join(", ")

        conn
        |> put_flash(:error, "Authentication failed: #{errors}")
        |> redirect(to: ~p"/")

      _ ->
        conn
        |> put_flash(:error, "Authentication failed: Unknown error")
        |> redirect(to: ~p"/")
    end
  end

  # Handles OAuth errors/cancellations
  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Authentication was cancelled or failed")
    |> redirect(to: ~p"/")
  end
end
