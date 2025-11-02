defmodule JumpEmailCategorization.Workers.EmailProcessorWorker do
  @moduledoc """
  Oban worker for processing emails: summarization and categorization.

  This worker:
  1. Summarizes the email using OpenAI
  2. Categorizes the email using OpenAI (if categories exist)
  3. Updates the email in the database
  """

  use Oban.Worker,
    queue: :emails,
    max_attempts: 3

  alias JumpEmailCategorization.{Emails, Categories, Repo}
  alias JumpEmailCategorization.AI.OpenAIClient

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
    Logger.info("Processing email #{email_id} for AI summarization and categorization")

    case Repo.get(Emails.Email, email_id) do
      nil ->
        Logger.error("Email #{email_id} not found in database")
        {:error, :email_not_found}

      email ->
        # Preload any associations if needed
        email = Repo.preload(email, [:user, :category])

        # Step 1: Summarize the email
        summary_result = summarize_email(email)

        # Step 2: Categorize the email
        categorization_result = categorize_email(email)

        # Return overall result
        case {summary_result, categorization_result} do
          {{:ok, _}, {:ok, _}} ->
            Logger.info("Successfully processed email #{email_id}")
            :ok

          {{:error, reason}, _} ->
            Logger.error("Failed to summarize email #{email_id}: #{inspect(reason)}")
            {:error, :summarization_failed}

          {_, {:error, reason}} ->
            Logger.error("Failed to categorize email #{email_id}: #{inspect(reason)}")
            {:error, :categorization_failed}
        end
    end
  end

  defp summarize_email(email) do
    case OpenAIClient.summarize_email(email.subject, email.body || email.snippet) do
      {:ok, summary} ->
        case Emails.update_email(email, %{summary: summary}) do
          {:ok, updated_email} ->
            Logger.info("Email #{email.id} summarized successfully")
            {:ok, updated_email}

          {:error, changeset} ->
            Logger.error(
              "Failed to save summary for email #{email.id}: #{inspect(changeset.errors)}"
            )

            {:error, :database_error}
        end

      {:error, :api_key_not_configured} ->
        Logger.warning("OpenAI API key not configured, skipping summarization")
        {:ok, email}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp categorize_email(email) do
    # Get user's categories
    categories = Categories.list_categories(email.user_id)

    if categories == [] do
      Logger.info("No categories available for user #{email.user_id}, marking as uncategorized")
      {:ok, email}
    else
      case OpenAIClient.categorize_email(
             email.subject,
             email.body || email.snippet,
             email.from_email,
             categories
           ) do
        {:ok, category_id} ->
          case Emails.update_email(email, %{category_id: category_id}) do
            {:ok, updated_email} ->
              if category_id do
                Logger.info("Email #{email.id} categorized as category ID #{category_id}")
              else
                Logger.info("Email #{email.id} marked as uncategorized (no good match)")
              end

              {:ok, updated_email}

            {:error, changeset} ->
              Logger.error(
                "Failed to save category for email #{email.id}: #{inspect(changeset.errors)}"
              )

              {:error, :database_error}
          end

        {:error, :api_key_not_configured} ->
          Logger.warning("OpenAI API key not configured, skipping categorization")
          {:ok, email}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
