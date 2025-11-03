defmodule JumpEmailCategorization.AI.UnsubscribeAnalyzer do
  @moduledoc """
  Uses AI to find and extract unsubscribe links from emails.
  """

  require Logger
  alias JumpEmailCategorization.AI.OpenAIClient

  @doc """
  Analyzes email content to find unsubscribe links.
  Returns {:ok, %{link: url, method: type}} or {:error, reason}
  """
  def find_unsubscribe_link(email_body, email_headers \\ nil) do
    # First try to find obvious patterns without AI
    case extract_obvious_unsubscribe_link(email_body) do
      {:ok, link} ->
        {:ok, %{link: link, method: "link", confidence: "high"}}

      :not_found ->
        # Use AI to find less obvious unsubscribe methods
        analyze_with_ai(email_body, email_headers)
    end
  end

  defp extract_obvious_unsubscribe_link(body) when is_binary(body) do
    # Look for common patterns
    patterns = [
      ~r/https?:\/\/[^\s"'<>]+unsubscribe[^\s"'<>]*/i,
      ~r/https?:\/\/[^\s"'<>]+opt-out[^\s"'<>]*/i,
      ~r/https?:\/\/[^\s"'<>]+remove[^\s"'<>]*/i
    ]

    Enum.find_value(patterns, :not_found, fn pattern ->
      case Regex.run(pattern, body) do
        [link | _] -> {:ok, link}
        nil -> nil
      end
    end)
  end

  defp extract_obvious_unsubscribe_link(_), do: :not_found

  defp analyze_with_ai(body, _headers) when is_binary(body) do
    prompt = """
    Analyze this email and find the unsubscribe mechanism.
    Look for:
    1. Unsubscribe links (most common)
    2. Mailto links for unsubscribe
    3. Instructions to reply with specific text
    4. Form submission URLs

    Email Body:
    #{String.slice(body, 0..2000)}

    Respond in JSON format:
    {
      "found": true/false,
      "method": "link" | "mailto" | "reply" | "form" | "none",
      "url": "the actual URL or email address",
      "instructions": "any additional steps needed"
    }

    If no unsubscribe method found, return {"found": false}
    """

    case OpenAIClient.chat_completion(prompt, max_tokens: 200, temperature: 0.3) do
      {:ok, response} ->
        parse_ai_response(response)

      {:error, reason} ->
        Logger.error("AI analysis failed: #{inspect(reason)}")
        {:error, :ai_failed}
    end
  end

  defp analyze_with_ai(_, _), do: {:error, :invalid_body}

  defp parse_ai_response(response) do
    case Jason.decode(response) do
      {:ok, %{"found" => true, "url" => url, "method" => method}} ->
        {:ok, %{link: url, method: method, confidence: "medium"}}

      {:ok, %{"found" => false}} ->
        {:error, :not_found}

      _ ->
        {:error, :parse_failed}
    end
  end
end
