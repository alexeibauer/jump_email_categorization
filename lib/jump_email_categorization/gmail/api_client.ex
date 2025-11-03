defmodule JumpEmailCategorization.Gmail.ApiClient do
  @moduledoc """
  Gmail API client for fetching and managing emails.
  """

  alias JumpEmailCategorization.Gmail.GmailAccount

  @gmail_api_base "https://gmail.googleapis.com/gmail/v1"

  # Configurable limit for email fetching
  @default_max_results 100

  @doc """
  Fetches emails from Gmail API.
  Options:
    - max_results: maximum number of emails to fetch (default: #{@default_max_results})
    - page_token: token for pagination
  """
  def fetch_messages(%GmailAccount{} = account, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, @default_max_results)
    page_token = Keyword.get(opts, :page_token)

    query_params =
      [
        maxResults: max_results,
        labelIds: "INBOX"
      ]
      |> maybe_add_page_token(page_token)

    url = "#{@gmail_api_base}/users/me/messages"

    case make_request(:get, url, account, params: query_params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches a single message with full details.
  """
  def get_message(%GmailAccount{} = account, message_id) do
    url = "#{@gmail_api_base}/users/me/messages/#{message_id}"

    case make_request(:get, url, account, params: [format: "full"]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches history of changes since a given history_id.
  Returns messages that were added/modified.
  """
  def get_history(%GmailAccount{} = account, start_history_id) do
    url = "#{@gmail_api_base}/users/me/history"

    query_params = [
      startHistoryId: start_history_id,
      historyTypes: "messageAdded"
    ]

    case make_request(:get, url, account, params: query_params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 404, body: _body}} ->
        # History ID is too old, return empty history
        {:ok, %{"history" => []}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Modifies message labels (e.g., to archive by removing INBOX).
  """
  def modify_message_labels(%GmailAccount{} = account, message_id, opts \\ []) do
    add_labels = Keyword.get(opts, :add_labels, [])
    remove_labels = Keyword.get(opts, :remove_labels, [])

    url = "#{@gmail_api_base}/users/me/messages/#{message_id}/modify"

    body =
      %{}
      |> maybe_add_labels(add_labels)
      |> maybe_remove_labels(remove_labels)

    case make_request(:post, url, account, json: body) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Archives a message by removing the INBOX label.
  """
  def archive_message(%GmailAccount{} = account, message_id) do
    modify_message_labels(account, message_id, remove_labels: ["INBOX"])
  end

  @doc """
  Batch archive messages.
  """
  def batch_archive_messages(%GmailAccount{} = account, message_ids) do
    Enum.map(message_ids, fn message_id ->
      {message_id, archive_message(account, message_id)}
    end)
  end

  @doc """
  Moves a message to the trash folder.
  """
  def trash_message(%GmailAccount{} = account, message_id) do
    url = "#{@gmail_api_base}/users/me/messages/#{message_id}/trash"

    case make_request(:post, url, account, json: %{}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sets up Gmail push notifications via Pub/Sub.
  """
  def setup_push_notifications(%GmailAccount{} = account, topic_name) do
    url = "#{@gmail_api_base}/users/me/watch"

    body = %{
      topicName: topic_name,
      labelIds: ["INBOX"]
    }

    case make_request(:post, url, account, json: body) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stops Gmail push notifications.
  """
  def stop_push_notifications(%GmailAccount{} = account) do
    url = "#{@gmail_api_base}/users/me/stop"

    case make_request(:post, url, account, json: %{}) do
      {:ok, %{status: 204}} ->
        {:ok, :stopped}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes an expired access token.
  """
  def refresh_access_token(%GmailAccount{} = account) do
    client_id = Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:client_id]

    client_secret =
      Application.get_env(:ueberauth, Ueberauth.Strategy.Google.OAuth)[:client_secret]

    url = "https://oauth2.googleapis.com/token"

    body = %{
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: account.refresh_token,
      grant_type: "refresh_token"
    }

    case Req.post(url, json: body) do
      {:ok, %{status: 200, body: response}} ->
        new_token = response["access_token"]
        expires_in = response["expires_in"]

        {:ok,
         %{
           access_token: new_token,
           expires_in: expires_in
         }}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_refresh_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp make_request(method, url, account, opts) do
    headers = [
      {"Authorization", "Bearer #{account.access_token}"},
      {"Accept", "application/json"}
    ]

    base_opts = [
      method: method,
      url: url,
      headers: headers,
      decode_json: [keys: :strings]
    ]

    # Merge additional options with base options
    final_opts = Keyword.merge(base_opts, opts)

    Req.request(final_opts)
  end

  defp maybe_add_page_token(params, nil), do: params
  defp maybe_add_page_token(params, token), do: Keyword.put(params, :pageToken, token)

  defp maybe_add_labels(body, []), do: body
  defp maybe_add_labels(body, labels), do: Map.put(body, "addLabelIds", labels)

  defp maybe_remove_labels(body, []), do: body
  defp maybe_remove_labels(body, labels), do: Map.put(body, "removeLabelIds", labels)
end
