defmodule JumpEmailCategorization.AI.UnsubscribeHandler do
  @moduledoc """
  Handles the actual unsubscribe process by following links
  and using AI to complete forms.
  """

  require Logger
  alias JumpEmailCategorization.AI.OpenAIClient

  @doc """
  Attempts to unsubscribe by visiting the link and completing any required actions.
  """
  def process_unsubscribe(unsubscribe_url, email_address) do
    Logger.info("Visiting unsubscribe URL: #{unsubscribe_url}")

    # Step 1: Follow the link
    case Req.get(unsubscribe_url, redirect: true, max_redirects: 5) do
      {:ok, %{status: status, body: html_body}} when status in 200..299 ->
        Logger.info(
          "Successfully fetched page, status: #{status}, body length: #{byte_size(html_body)} bytes"
        )

        Logger.debug("HTML Preview: #{String.slice(html_body, 0..500)}")

        # Step 2: Analyze the page with AI
        analyze_and_complete_unsubscribe(html_body, unsubscribe_url, email_address)

      {:ok, %{status: status}} ->
        Logger.error("HTTP request failed with status: #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp analyze_and_complete_unsubscribe(html_body, original_url, email_address) do
    prompt = """
    Analyze this unsubscribe page HTML and determine what actions are needed.

    HTML Content (truncated):
    #{String.slice(html_body, 0..3000)}

    IMPORTANT: Look for:
    - Forms with action URLs
    - Submit buttons (look for button, input type="submit", or clickable elements)
    - Radio buttons or checkboxes for unsubscribe reasons
    - The actual form action URL (could be relative or absolute)

    If you see an "Unsubscribe" button, this is a "form" type.
    If the page says you're already unsubscribed, this is a "direct" type.

    CRITICAL: For radio buttons, select ONLY ONE value (the first option).
    Do NOT return arrays like ["1", "2"] - return a single string value like "1".

    Respond ONLY with valid JSON, no other text:
    {
      "type": "direct" | "form" | "confirmation_needed",
      "success_indicators": ["unsubscribed", "removed", "opted out"],
      "form_data": {
        "action_url": "full URL or relative path",
        "method": "POST" | "GET",
        "fields": {"field_name": "single_value"}
      },
      "requires_email": false
    }

    Example for radio buttons:
    - BAD: {"reason": ["1", "2"]}
    - GOOD: {"reason": "1"}

    User email: #{email_address}
    Original URL: #{original_url}
    """

    Logger.info("Sending HTML to OpenAI for analysis...")

    case OpenAIClient.chat_completion(prompt, max_tokens: 400, temperature: 0.2) do
      {:ok, response} ->
        Logger.info("OpenAI response received: #{response}")
        parse_and_execute_action(response, html_body, original_url, email_address)

      {:error, reason} ->
        Logger.error("OpenAI analysis failed: #{inspect(reason)}")
        {:error, {:ai_analysis_failed, reason}}
    end
  end

  defp parse_and_execute_action(ai_response, html_body, original_url, email_address) do
    # Try to extract JSON if AI returned it with markdown formatting
    cleaned_response =
      ai_response
      |> String.replace(~r/```json\n?/, "")
      |> String.replace(~r/```\n?/, "")
      |> String.trim()

    Logger.debug("Attempting to parse JSON: #{cleaned_response}")

    case Jason.decode(cleaned_response) do
      {:ok, %{"type" => "direct"} = result} ->
        Logger.info("AI determined this is a 'direct' unsubscribe (already done or automatic)")
        # Page says you're already unsubscribed or it's automatic
        check_success_indicators(html_body, result["success_indicators"])

      {:ok, %{"type" => "form", "form_data" => form_data} = result} ->
        Logger.info("AI determined this requires form submission")
        # Need to submit a form - resolve relative URLs
        form_data = resolve_form_action(form_data, original_url)
        submit_unsubscribe_form(form_data, email_address, result)

      {:ok, %{"type" => "confirmation_needed"}} ->
        Logger.info("AI determined manual confirmation is needed")
        {:ok, :requires_manual_confirmation}

      {:ok, parsed} ->
        Logger.error("AI returned JSON but with unexpected structure: #{inspect(parsed)}")
        {:error, :unexpected_json_structure}

      {:error, reason} ->
        Logger.error("Failed to parse AI response as JSON: #{inspect(reason)}")
        Logger.error("AI response was: #{ai_response}")
        {:error, :could_not_parse_page}
    end
  end

  defp resolve_form_action(form_data, original_url) do
    action_url = form_data["action_url"]

    resolved_url =
      cond do
        # Already absolute URL
        String.starts_with?(action_url, "http") ->
          action_url

        # Relative URL starting with /
        String.starts_with?(action_url, "/") ->
          uri = URI.parse(original_url)
          "#{uri.scheme}://#{uri.host}#{action_url}"

        # Relative URL without /
        true ->
          uri = URI.parse(original_url)
          base_path = Path.dirname(uri.path || "/")
          "#{uri.scheme}://#{uri.host}#{base_path}/#{action_url}"
      end

    Logger.info("Resolved form action URL: #{action_url} -> #{resolved_url}")
    Map.put(form_data, "action_url", resolved_url)
  end

  defp check_success_indicators(html, indicators) when is_list(indicators) do
    Logger.debug("Checking #{length(indicators)} success indicators against response")
    html_lower = String.downcase(html)

    found =
      Enum.find(indicators, fn indicator ->
        indicator_lower = String.downcase(indicator)
        contains = String.contains?(html_lower, indicator_lower)

        Logger.debug(
          "  Checking '#{indicator}': #{if contains, do: "✓ FOUND", else: "✗ not found"}"
        )

        contains
      end)

    if found do
      Logger.info("✓ Success indicator '#{found}' found in response")
      {:ok, :unsubscribed}
    else
      Logger.warning("✗ No success indicators found in response")
      Logger.debug("Response text (first 200 chars): #{String.slice(html, 0..200)}")
      {:error, :success_not_confirmed}
    end
  end

  defp check_success_indicators(_html, indicators) do
    Logger.error("Invalid success indicators: #{inspect(indicators)}")
    {:error, :invalid_indicators}
  end

  defp submit_unsubscribe_form(form_data, email_address, ai_result) do
    action_url = form_data["action_url"]
    method = String.downcase(form_data["method"] || "post")
    fields = form_data["fields"] || %{}

    # Add email if required
    fields =
      if ai_result["requires_email"] do
        Map.put(fields, "email", email_address)
      else
        fields
      end

    # Fix array values - take first element if it's a list (for radio buttons, checkboxes)
    fields =
      fields
      |> Enum.map(fn
        {key, value} when is_list(value) ->
          Logger.debug(
            "Converting array field '#{key}': #{inspect(value)} -> #{inspect(List.first(value))}"
          )

          {key, List.first(value) || ""}

        {key, value} ->
          {key, value}
      end)
      |> Map.new()

    Logger.info(
      "Submitting form to #{action_url} with method #{method}, fields: #{inspect(fields)}"
    )

    result =
      try do
        Logger.debug("About to make HTTP #{method} request...")

        res =
          case method do
            "post" ->
              Req.post(action_url,
                form: fields,
                redirect: true,
                max_redirects: 5,
                receive_timeout: 30_000,
                connect_options: [timeout: 10_000]
              )

            "get" ->
              Req.get(action_url,
                params: fields,
                redirect: true,
                max_redirects: 5,
                receive_timeout: 30_000,
                connect_options: [timeout: 10_000]
              )

            _ ->
              Logger.error("Invalid HTTP method: #{method}")
              {:error, :invalid_method}
          end

        Logger.debug("HTTP request returned: #{inspect(res)}")
        res
      rescue
        error ->
          Logger.error("EXCEPTION during HTTP request: #{inspect(error)}")
          Logger.error("Exception details: #{Exception.format(:error, error, __STACKTRACE__)}")
          {:error, {:exception, error}}
      catch
        kind, value ->
          Logger.error("CAUGHT #{kind}: #{inspect(value)}")
          {:error, {:caught, kind, value}}
      end

    Logger.info("Result obtained from form submission to #{action_url}: #{inspect(result)}")

    case result do
      {:ok, %{status: status, body: response_html}} when status in 200..299 ->
        Logger.info(
          "✓ Form submitted successfully, status: #{status}, body size: #{byte_size(response_html)} bytes"
        )

        Logger.debug("Response preview: #{String.slice(response_html, 0..500)}")

        # Check if unsubscribe was successful
        success_indicators =
          ai_result["success_indicators"] || ["unsubscribed", "success", "successfully"]

        Logger.info("Checking success indicators: #{inspect(success_indicators)}")

        result = check_success_indicators(response_html, success_indicators)
        Logger.info("Check result: #{inspect(result)}")
        result

      {:ok, %{status: status, body: body}} ->
        Logger.error("Form submission returned non-2xx status: #{status}")
        Logger.debug("Response body: #{String.slice(body, 0..500)}")
        {:error, {:form_submission_failed, status}}

      {:ok, response} ->
        Logger.error("Unexpected response structure: #{inspect(Map.keys(response))}")
        {:error, :unexpected_response_format}

      {:error, reason} ->
        Logger.error("Form submission request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end
end
