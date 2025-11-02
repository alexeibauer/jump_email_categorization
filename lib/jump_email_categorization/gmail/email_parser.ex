defmodule JumpEmailCategorization.Gmail.EmailParser do
  @moduledoc """
  Parses Gmail API responses into database-friendly structures.
  """

  @doc """
  Parses a Gmail message response into email attributes.
  """
  def parse_message(message_data, gmail_account_id, user_id) do
    headers = get_headers(message_data)

    # Use internalDate as the primary source for received_at since it's more reliable
    # internalDate is a timestamp in milliseconds
    internal_date = parse_internal_date(message_data["internalDate"])

    received_at =
      case internal_date do
        nil -> parse_date(get_header(headers, "Date"))
        timestamp -> DateTime.from_unix!(timestamp, :millisecond)
      end

    %{
      gmail_account_id: gmail_account_id,
      user_id: user_id,
      gmail_message_id: message_data["id"],
      gmail_thread_id: message_data["threadId"],
      subject: get_header(headers, "Subject"),
      from_email: extract_email(get_header(headers, "From")),
      from_name: extract_name(get_header(headers, "From")),
      to_emails: parse_email_list(get_header(headers, "To")),
      cc_emails: parse_email_list(get_header(headers, "Cc")),
      labels: message_data["labelIds"] || [],
      snippet: message_data["snippet"],
      body: extract_body(message_data),
      received_at: received_at,
      internal_date: internal_date
    }
  end

  defp get_headers(%{"payload" => %{"headers" => headers}}), do: headers
  defp get_headers(_), do: []

  defp get_header(headers, name) do
    headers
    |> Enum.find(fn header -> header["name"] == name end)
    |> case do
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp extract_email(nil), do: nil

  defp extract_email(from_header) do
    case Regex.run(~r/<(.+?)>/, from_header) do
      [_, email] -> email
      _ -> from_header
    end
  end

  defp extract_name(nil), do: nil

  defp extract_name(from_header) do
    case Regex.run(~r/^(.+?)\s*</, from_header) do
      [_, name] -> String.trim(name, "\"")
      _ -> nil
    end
  end

  defp parse_email_list(nil), do: []

  defp parse_email_list(email_string) do
    email_string
    |> String.split(",")
    |> Enum.map(&extract_email/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_body(%{"payload" => payload}) do
    cond do
      # Try to get plain text body
      text_body = find_text_part(payload) ->
        decode_body(text_body)

      # Try to get HTML body
      html_body = find_html_part(payload) ->
        decode_body(html_body)

      # Try to get body from main payload
      payload["body"]["data"] ->
        decode_body(payload["body"]["data"])

      true ->
        nil
    end
  end

  defp extract_body(_), do: nil

  defp find_text_part(%{"parts" => parts}) do
    parts
    |> Enum.find(fn part ->
      part["mimeType"] == "text/plain"
    end)
    |> case do
      %{"body" => %{"data" => data}} -> data
      _ -> find_nested_text_part(parts)
    end
  end

  defp find_text_part(_), do: nil

  defp find_nested_text_part(parts) do
    parts
    |> Enum.find_value(fn part ->
      case part["parts"] do
        nil -> nil
        nested_parts -> find_text_part(%{"parts" => nested_parts})
      end
    end)
  end

  defp find_html_part(%{"parts" => parts}) do
    parts
    |> Enum.find(fn part ->
      part["mimeType"] == "text/html"
    end)
    |> case do
      %{"body" => %{"data" => data}} -> data
      _ -> find_nested_html_part(parts)
    end
  end

  defp find_html_part(_), do: nil

  defp find_nested_html_part(parts) do
    parts
    |> Enum.find_value(fn part ->
      case part["parts"] do
        nil -> nil
        nested_parts -> find_html_part(%{"parts" => nested_parts})
      end
    end)
  end

  defp decode_body(nil), do: nil

  defp decode_body(encoded_data) do
    encoded_data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> Base.decode64!(padding: false)
  rescue
    _ -> nil
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) do
    # Gmail date headers can be in various formats
    # Try parsing common formats
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp parse_internal_date(nil), do: nil

  defp parse_internal_date(timestamp) when is_binary(timestamp) do
    case Integer.parse(timestamp) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_internal_date(timestamp) when is_integer(timestamp), do: timestamp
end
