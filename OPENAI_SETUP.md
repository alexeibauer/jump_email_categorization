# OpenAI Integration Setup

This application uses OpenAI's GPT-4o-mini model to automatically summarize and categorize incoming emails.

## Prerequisites

1. An OpenAI API account
2. An OpenAI API key

## Setup Steps

### 1. Get Your OpenAI API Key

1. Go to https://platform.openai.com/
2. Sign up or log in to your account
3. Navigate to API Keys section
4. Create a new API key
5. Copy the key (you won't be able to see it again!)

### 2. Configure the API Key

Add your OpenAI API key to your environment:

**For Development:**
```bash
export OPENAI_API_KEY="sk-your-api-key-here"
```

Or add it to your `.env` file (if you're using one):
```
OPENAI_API_KEY=sk-your-api-key-here
```

**For Production:**

Set the `OPENAI_API_KEY` environment variable in your production environment.

### 3. Verify Configuration

The application will automatically use the API key from the environment variable. If the key is not configured:
- Emails will still be stored and archived
- AI processing jobs will be enqueued but will skip summarization/categorization
- Warning messages will appear in logs

## How It Works

### Email Processing Flow

When a new email arrives:

1. **Email is stored** in the database
2. **Oban job is enqueued** for AI processing
3. **Job is processed asynchronously** (within seconds):
   - Email is summarized using GPT-4o-mini
   - Email is categorized into one of your user-defined categories
   - Results are saved to the database
4. **Email is archived** in Gmail (INBOX label removed)

### Summarization

The AI generates a concise 2-3 sentence summary of each email, focusing on:
- Main point of the email
- Any action items
- Key information

Example:
```
Original: [Long email about project update...]
Summary: "Team completed Phase 1 of the project ahead of schedule. 
         Phase 2 kickoff meeting scheduled for next Monday at 2 PM. 
         Need to review and approve budget allocation by end of week."
```

### Categorization

The AI analyzes each email and assigns it to one of your categories based on:
- Email subject
- Email body content
- Sender email address
- Category names and descriptions

If no category is a good fit, the email is marked as "Uncategorized".

## Cost Estimation

Using **GPT-4o-mini** (recommended):
- Summarization: ~$0.0002 per email
- Categorization: ~$0.0001 per email
- **Total: ~$0.0003 per email** or **$0.30 per 1,000 emails**

For comparison, GPT-4 is 10-20x more expensive but provides higher quality.

## Background Job Processing

The application uses **Oban** for reliable background job processing:

### Benefits:
- ✅ Jobs are persisted to the database
- ✅ Automatic retries on failures (up to 3 attempts)
- ✅ Graceful handling of OpenAI API errors
- ✅ Rate limiting (max 10 concurrent jobs)
- ✅ Jobs survive app restarts/deployments

### Job Monitoring

Jobs are stored in the `oban_jobs` table. You can monitor them:

```elixir
# In IEx console
alias JumpEmailCategorization.Repo
alias Oban.Job

# See pending jobs
Repo.all(from j in Job, where: j.state == "available")

# See failed jobs
Repo.all(from j in Job, where: j.state == "retryable")

# See completed jobs (last 100)
Repo.all(from j in Job, where: j.state == "completed", limit: 100, order_by: [desc: j.completed_at])
```

### Job Retries

If OpenAI API is temporarily unavailable:
- Attempt 1: Immediate
- Attempt 2: After 15 seconds
- Attempt 3: After 1 minute
- After 3 failures: Job is marked as "discarded"

## Troubleshooting

### "OpenAI API key not configured"

**Problem:** `OPENAI_API_KEY` environment variable is not set.

**Solution:**
```bash
export OPENAI_API_KEY="sk-your-key-here"
# Then restart the app
```

### "Rate limit exceeded"

**Problem:** Too many requests to OpenAI API.

**Solution:** The application is configured to process max 10 emails concurrently. If you're hitting rate limits, you can reduce this in `config/config.exs`:

```elixir
config :jump_email_categorization, Oban,
  queues: [emails: 5]  # Reduce from 10 to 5
```

### Jobs are failing

**Check the logs:**
```bash
# Development
tail -f log/dev.log | grep "EmailProcessorWorker"

# Or check the oban_jobs table
```

**Common causes:**
- Invalid API key
- Network issues
- OpenAI API outage
- Malformed email data

## API Usage Monitoring

Monitor your OpenAI API usage at:
https://platform.openai.com/usage

Set up usage alerts to avoid unexpected charges:
1. Go to Settings > Billing
2. Set up usage limits and email alerts

## Testing Without OpenAI

To test the application without using OpenAI credits:

1. Don't set the `OPENAI_API_KEY` environment variable
2. Emails will still be processed and stored
3. Summaries and categories will be skipped (set to nil)
4. Check logs for "OpenAI API key not configured" messages

## Model Configuration

To change the OpenAI model, edit `config/config.exs`:

```elixir
config :jump_email_categorization,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  openai_model: "gpt-4o"  # Change to gpt-4o or gpt-4 for better quality
```

Available models:
- `gpt-4o-mini` (default) - Fast, cheap, good quality
- `gpt-4o` - Better quality, moderate cost
- `gpt-4` - Best quality, highest cost

## Security Notes

⚠️ **Never commit your API key to version control**

✅ Always use environment variables
✅ Add `.env` to `.gitignore`
✅ Rotate keys if accidentally exposed
✅ Use separate keys for dev/prod

