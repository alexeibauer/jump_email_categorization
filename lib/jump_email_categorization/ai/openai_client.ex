defmodule JumpEmailCategorization.AI.OpenAIClient do
  @moduledoc """
  Client for interacting with OpenAI API for email processing.
  Uses gpt-4o-mini model for cost-effective AI processing.
  """

  require Logger

  @api_base "https://api.openai.com/v1"
  @model "gpt-4o-mini"

  @doc """
  Generates a summary for an email using OpenAI.
  Returns a concise 2-3 sentence summary.
  """
  def summarize_email(subject, body) do
    prompt = """
    Summarize the following email in 2-3 concise sentences. Focus on the main point and any action items.

    Subject: #{subject || "(No subject)"}

    Body:
    #{truncate_body(body)}
    """

    case chat_completion(prompt, max_tokens: 150, temperature: 0.7) do
      {:ok, summary} ->
        {:ok, String.trim(summary)}

      {:error, reason} ->
        Logger.error("Failed to summarize email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Categorizes an email based on its content and available categories.
  Returns the best matching category ID or nil if no good match.
  """
  def categorize_email(subject, body, from_email, available_categories) do
    if available_categories == [] do
      Logger.info("No categories available for categorization")
      {:ok, nil}
    else
      category_list =
        Enum.map_join(available_categories, "\n", fn cat ->
          "- #{cat.name}: #{cat.description}"
        end)

      prompt = """
      Analyze this email and categorize it into ONE of the following categories.
      If none fit well, respond with "NONE".

      Available Categories:
      #{category_list}

      Email Details:
      From: #{from_email || "Unknown"}
      Subject: #{subject || "(No subject)"}
      Body: #{truncate_body(body)}

      Respond with ONLY the category name or "NONE".
      """

      case chat_completion(prompt, max_tokens: 50, temperature: 0.3) do
        {:ok, response} ->
          category_name = String.trim(response)

          # Find matching category (case-insensitive)
          matching_category =
            Enum.find(available_categories, fn cat ->
              String.downcase(cat.name) == String.downcase(category_name)
            end)

          if matching_category do
            Logger.info(
              "Email categorized as '#{matching_category.name}' (ID: #{matching_category.id})"
            )

            {:ok, matching_category.id}
          else
            if category_name == "NONE" do
              Logger.info("OpenAI determined no category fits this email")
            else
              Logger.info(
                "OpenAI returned '#{category_name}' but no matching category found in database"
              )
            end

            {:ok, nil}
          end

        {:error, reason} ->
          Logger.error("Failed to categorize email: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Private functions

  @doc """
  Makes a chat completion request to OpenAI.
  Public for use by other AI modules.
  """
  def chat_completion(prompt, opts) do
    api_key = Application.get_env(:jump_email_categorization, :openai_api_key)

    unless api_key do
      Logger.error("OpenAI API key not configured")
      {:error, :api_key_not_configured}
    else
      body = %{
        model: @model,
        messages: [
          %{
            role: "user",
            content: prompt
          }
        ],
        max_tokens: Keyword.get(opts, :max_tokens, 150),
        temperature: Keyword.get(opts, :temperature, 0.7)
      }

      case Req.post("#{@api_base}/chat/completions",
             json: body,
             headers: [
               {"Authorization", "Bearer #{api_key}"},
               {"Content-Type", "application/json"}
             ],
             retry: :transient,
             max_retries: 2
           ) do
        {:ok, %{status: 200, body: response}} ->
          content = get_in(response, ["choices", Access.at(0), "message", "content"])
          {:ok, content}

        {:ok, %{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp truncate_body(nil), do: "(No content)"

  defp truncate_body(body) when is_binary(body) do
    # Truncate to ~3000 chars to avoid token limits
    if byte_size(body) > 3000 do
      binary_part(body, 0, 3000) <> "... [truncated]"
    else
      body
    end
  end

  defp truncate_body(_), do: "(No content)"
end
