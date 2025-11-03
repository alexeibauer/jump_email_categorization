defmodule JumpEmailCategorization.Workers.UnsubscribeWorker do
  @moduledoc """
  Processes unsubscribe requests for emails.
  """

  use Oban.Worker,
    queue: :unsubscribe,
    max_attempts: 2

  alias JumpEmailCategorization.{Emails, Repo}
  alias JumpEmailCategorization.AI.{UnsubscribeAnalyzer, UnsubscribeHandler}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"email_id" => email_id}}) do
    Logger.info("Processing unsubscribe request for email #{email_id}")

    case Repo.get(Emails.Email, email_id) do
      nil ->
        {:error, :email_not_found}

      email ->
        process_unsubscribe(email)
    end
  end

  defp process_unsubscribe(email) do
    Logger.info("=== Starting unsubscribe process for email #{email.id} ===")
    Logger.info("From: #{email.from_email}, Subject: #{email.subject}")

    # Update status to processing
    Emails.update_email(email, %{
      unsubscribe_status: "processing",
      unsubscribe_attempted_at: DateTime.utc_now()
    })

    # Step 1: Find unsubscribe link
    Logger.info("Step 1: Finding unsubscribe link in email body...")

    case UnsubscribeAnalyzer.find_unsubscribe_link(email.body) do
      {:ok, %{link: link, method: method, confidence: confidence}} ->
        Logger.info("✓ Found unsubscribe link for email #{email.id}")
        Logger.info("  Link: #{link}")
        Logger.info("  Method: #{method}")
        Logger.info("  Confidence: #{confidence}")

        # Update with found link
        Emails.update_email(email, %{
          unsubscribe_link: link,
          unsubscribe_method: method
        })

        # Step 2: Process the unsubscribe
        Logger.info("Step 2: Processing unsubscribe action...")

        case UnsubscribeHandler.process_unsubscribe(link, email.from_email) do
          {:ok, :unsubscribed} ->
            Logger.info("✓ Successfully unsubscribed from email #{email.id}")

            Emails.update_email(email, %{
              unsubscribe_status: "success",
              unsubscribe_completed_at: DateTime.utc_now()
            })

            {:ok, :success}

          {:ok, :requires_manual_confirmation} ->
            Logger.info("⚠ Email #{email.id} requires manual confirmation")

            Emails.update_email(email, %{
              unsubscribe_status: "pending_confirmation",
              unsubscribe_error:
                "Requires manual confirmation. Please visit the link to complete."
            })

            {:ok, :pending}

          {:error, reason} ->
            error_msg = format_error_message(reason)
            Logger.error("✗ Unsubscribe failed for email #{email.id}: #{error_msg}")

            Emails.update_email(email, %{
              unsubscribe_status: "failed",
              unsubscribe_error: error_msg
            })

            {:error, reason}
        end

      {:error, :not_found} ->
        Logger.warning("⚠ No unsubscribe link found for email #{email.id}")
        Logger.debug("Email body preview: #{String.slice(email.body || "", 0..500)}")

        Emails.update_email(email, %{
          unsubscribe_status: "not_found",
          unsubscribe_error:
            "No unsubscribe link found in email. The email may not have an unsubscribe option."
        })

        {:ok, :not_found}

      {:error, reason} ->
        error_msg = "Link detection failed: #{inspect(reason)}"
        Logger.error("✗ #{error_msg} for email #{email.id}")

        Emails.update_email(email, %{
          unsubscribe_status: "failed",
          unsubscribe_error: error_msg
        })

        {:error, reason}
    end
  end

  defp format_error_message(reason) do
    case reason do
      :could_not_parse_page ->
        "Could not understand the unsubscribe page format. The AI was unable to parse the page structure. This may require manual action."

      {:ai_analysis_failed, _} ->
        "AI analysis of the unsubscribe page failed. Please try again or unsubscribe manually."

      {:http_error, status} ->
        "HTTP error #{status} when accessing the unsubscribe page."

      {:request_failed, _} ->
        "Network request failed. Please check your connection and try again."

      {:form_submission_failed, status} ->
        "Form submission failed with HTTP status #{status}."

      :success_not_confirmed ->
        "Unsubscribe action completed but success could not be verified. Please check manually."

      :unexpected_json_structure ->
        "AI returned an unexpected response format. This may require manual unsubscribe."

      _ ->
        "Failed to process: #{inspect(reason)}"
    end
  end
end
