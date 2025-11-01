# Gmail Integration Documentation

This document explains the Gmail email fetching and Pub/Sub integration implemented in this application.

## Overview

The application automatically fetches emails from connected Gmail accounts, stores them in the database, archives them in Gmail, and sets up real-time notifications for new emails via Gmail Pub/Sub.

## Features Implemented

### 1. Async Email Fetching

When a user connects a Gmail account (via OAuth), the application automatically:
- Triggers an asynchronous task to fetch emails
- Fetches up to 100 emails (configurable) from the INBOX
- Stores emails in the `emails` table with full metadata
- Archives fetched emails by removing the INBOX label
- Records the archive timestamp

**Configuration:**
The number of emails to fetch is controlled by `@max_emails_to_fetch` in `lib/jump_email_categorization/gmail/email_fetcher.ex` (currently set to 100).

### 2. Email Storage

Emails are stored with the following information:
- Gmail message ID and thread ID
- Subject, body, and snippet
- From email and name
- To and CC email addresses
- Gmail labels
- Received timestamp
- Archived timestamp
- Category (for future categorization)
- Summary (for future AI summarization)

### 3. Email Processing Workflow

```
User adds Gmail account
  ↓
OAuth authentication completes
  ↓
create_or_update_gmail_account() called
  ↓
EmailFetcher.start_fetch() triggered (async)
  ↓
Fetch 100 emails from INBOX (in chunks of 10)
  ↓
For each email:
  - Parse Gmail API response
  - Store in database
  - Archive in Gmail (remove INBOX label)
  - Mark as archived in database
  ↓
Setup Gmail Pub/Sub for real-time notifications
```

### 4. Real-time Email Notifications (Pub/Sub)

The application sets up Gmail push notifications using Google Cloud Pub/Sub:
- When a new email arrives in Gmail, Google sends a push notification
- The webhook endpoint (`/api/webhooks/gmail`) receives the notification
- The application fetches and processes the new email
- The email is stored and archived automatically

### 5. Loading State UI

When emails are being fetched:
- The central pane displays "Loading emails..." with a spinner
- PubSub broadcasts keep the UI updated on fetch status
- A success message appears when fetching completes

### 6. Placeholder Functions for Future Features

Two functions are ready for implementation:
- `Emails.categorize_email/1` - For AI-based email categorization
- `Emails.summarize_email/1` - For AI-based email summarization

## Setup Instructions

### 1. Google Cloud Configuration

You need to set up a Google Cloud Pub/Sub topic for push notifications:

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project
3. Navigate to Pub/Sub > Topics
4. Create a new topic (e.g., `gmail-notifications`)
5. Note the full topic name: `projects/{project-id}/topics/{topic-name}`

### 2. Configure the Application

Add to your `config/config.exs` or `config/runtime.exs`:

```elixir
config :jump_email_categorization,
  gmail_pubsub_topic: "projects/{your-project-id}/topics/gmail-notifications"
```

### 3. Set up Pub/Sub Push Subscription

Create a push subscription that points to your webhook endpoint:

```bash
gcloud pubsub subscriptions create gmail-push-sub \
  --topic=gmail-notifications \
  --push-endpoint=https://your-domain.com/api/webhooks/gmail
```

### 4. Grant Gmail API Permission

Ensure your OAuth app has the following scope:
- `https://www.googleapis.com/auth/gmail.modify`

This allows the app to:
- Read emails
- Modify labels (for archiving)
- Set up push notifications

## API Modules

### Gmail.ApiClient

Handles all Gmail API interactions:
- `fetch_messages/2` - Fetch message list
- `get_message/2` - Fetch full message details
- `archive_message/2` - Archive by removing INBOX label
- `setup_push_notifications/2` - Set up Pub/Sub
- `refresh_access_token/1` - Refresh expired tokens

### Gmail.EmailParser

Parses Gmail API responses into database-friendly structures:
- Extracts headers (subject, from, to, cc, date)
- Decodes message body (handles base64 encoding)
- Handles multipart messages (text/html)
- Parses email addresses from headers

### Gmail.EmailFetcher

Manages async email fetching:
- Processes emails in chunks
- Handles token refresh automatically
- Broadcasts fetch status via PubSub
- Archives emails after successful storage

### GmailWebhookController

Handles incoming Pub/Sub push notifications:
- Decodes base64-encoded messages
- Triggers email fetch for new messages
- Returns 200 OK to acknowledge receipt

## Database Schema

### emails table

```sql
create table emails (
  id bigserial primary key,
  gmail_account_id bigint references gmail_accounts on delete cascade,
  user_id bigint references users on delete cascade,
  gmail_message_id text not null,
  gmail_thread_id text,
  subject text,
  body text,
  snippet text,
  from_email text,
  from_name text,
  to_emails text[],
  cc_emails text[],
  labels text[],
  category_id bigint references categories on delete set null,
  summary text,
  received_at timestamp,
  archived_at timestamp,
  internal_date bigint,
  inserted_at timestamp,
  updated_at timestamp
);

create unique index on emails (gmail_account_id, gmail_message_id);
```

## Important Notes

### Token Management

Access tokens expire after a certain time. The `EmailFetcher` automatically:
- Checks if the token is expired before making API calls
- Refreshes the token using the refresh_token
- Updates the account with the new token

### Duplicate Prevention

The unique index on `(gmail_account_id, gmail_message_id)` prevents duplicate emails from being stored, even if the fetch is triggered multiple times.

### Error Handling

- Failed email fetches are logged but don't stop the process
- Individual email failures don't affect the batch
- Archive failures are logged but the email remains in the database

### Cleanup on Account Deletion

When a Gmail account is deleted:
- All associated emails are automatically deleted (cascade)
- A TODO reminder exists to stop Pub/Sub notifications

**TODO:** Implement in `Gmail.delete_gmail_account/1`:
```elixir
ApiClient.stop_push_notifications(gmail_account)
# Delete the Pub/Sub topic from Google Cloud
```

## Testing

To test the integration:

1. **Connect a Gmail account** - OAuth flow should complete
2. **Check logs** - You should see "Starting email fetch for..." messages
3. **Check database** - Emails should appear in the `emails` table
4. **Check Gmail** - Emails should be archived (removed from INBOX)
5. **Send a test email** - New emails should be fetched via Pub/Sub webhook

## Monitoring

Watch the logs for:
- Email fetch start/complete messages
- Token refresh activity
- Archive operations
- Pub/Sub webhook calls
- Any error messages

## Future Enhancements

1. **Categorization** - Implement `Emails.categorize_email/1` with AI
2. **Summarization** - Implement `Emails.summarize_email/1` with AI
3. **History API** - Use Gmail's history endpoint for more efficient Pub/Sub processing
4. **Attachments** - Store and manage email attachments
5. **Search** - Implement full-text search on email content
6. **Filters** - Allow users to create custom email filters

