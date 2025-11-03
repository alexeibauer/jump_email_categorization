# Jump Email Categorization

An intelligent email management application built with Phoenix LiveView that automatically categorizes, summarizes, and helps manage your Gmail inbox using AI.

## Overview

Jump Email Categorization is a real-time email management platform that integrates with Gmail to provide smart email organization. The application uses OpenAI's GPT-4o-mini to automatically categorize emails, generate summaries, and intelligently handle unsubscribe requests. Built with Phoenix LiveView, it provides a responsive, real-time user interface with instant updates as emails are processed.

### Key Features

- **Gmail Integration**: Connect multiple Gmail accounts via OAuth 2.0
- **Real-time Email Sync**: Webhook-based real-time email delivery
- **AI-Powered Categorization**: Automatic email categorization using GPT-4o-mini
- **Smart Summarization**: Generate concise email summaries with AI
- **Intelligent Unsubscribe**: AI-driven unsubscribe link detection and automated form submission
- **Bulk Actions**: Select multiple emails for batch operations (unsubscribe, delete)
- **Category Management**: Create, edit, and organize custom email categories
- **Gmail Trash Integration**: Deleted emails are moved to Gmail's trash folder

## Prerequisites

Before you begin, ensure you have the following installed:

- **Elixir** 1.15 or later
- **Erlang/OTP** 26 or later
- **PostgreSQL** 14 or later
- **Node.js** 18 or later (for asset compilation)
- **Docker** (optional, for containerized deployment)

### External Services

You'll need accounts and API keys for:

- **Google Cloud Platform**: For Gmail API access and OAuth 2.0
  - Create a project at [Google Cloud Console](https://console.cloud.google.com)
  - Enable Gmail API
  - Create OAuth 2.0 credentials (Web application)
  - Set authorized redirect URI: `http://localhost:4000/auth/google/callback` (development)

- **OpenAI Platform**: For AI categorization and summarization
  - Get your API key at [OpenAI API Keys](https://platform.openai.com/api-keys)

- **SMTP Provider** (for production email delivery):
  - SendGrid, Gmail App Password, or any SMTP service

## Setup

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd jump_email_categorization
mix setup
```

The `mix setup` command will:
- Install Elixir dependencies
- Create and migrate the database
- Install and build frontend assets (Tailwind CSS, esbuild)

### 2. Configure Environment Variables

Create a `.env` file in the project root:

```bash
# Database
DATABASE_URL=ecto://postgres:postgres@localhost/jump_email_categorization_dev

# Phoenix
SECRET_KEY_BASE=your_secret_key_base_here  # Generate with: mix phx.gen.secret
PHX_HOST=localhost

# Google OAuth
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret

# OpenAI
OPENAI_API_KEY=sk-proj-your-api-key-here
```

### 3. Database Setup

```bash
# Create and migrate database
mix ecto.setup

# Or manually:
mix ecto.create
mix ecto.migrate
mix run priv/repo/seeds.exs
```

### 4. Gmail API Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project or select existing one
3. Enable the Gmail API
4. Create OAuth 2.0 credentials:
   - Application type: Web application
   - Authorized redirect URIs: `http://localhost:4000/auth/google/callback`
5. Download credentials and add to your `.env` file

## Running the Application

### Development

Load environment variables and start the Phoenix server:

```bash
source .env
mix phx.server
```

Or run inside IEx for interactive development:

```bash
source .env
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) in your browser.

### Production (Google Cloud Run)

For production deployment to Google Cloud Platform, see the comprehensive deployment guide:

- [GCP_DEPLOYMENT.md](GCP_DEPLOYMENT.md) - Step-by-step deployment instructions
- [DEPLOYMENT_SCRIPTS_README.md](DEPLOYMENT_SCRIPTS_README.md) - Automated deployment scripts

Quick production deployment:

```bash
# Setup GCP infrastructure
./setup-gcp.sh

# Setup Cloud SQL database
./setup-database.sh

# Create secrets in Secret Manager
./setup-secrets.sh

# Build and deploy to Cloud Run
./deploy-gcp.sh
```

## Development Commands

```bash
# Run tests
mix test

# Run tests for specific file
mix test test/path/to/test.exs

# Format code
mix format

# Run pre-commit checks (compile, format, test)
mix precommit

# Reset database
mix ecto.reset

# Generate a new secret
mix phx.gen.secret
```

## Architecture & Technologies

### Core Stack

- **Phoenix Framework 1.8**: Web framework with real-time capabilities
- **Phoenix LiveView 1.1**: Server-rendered real-time UI
- **Ecto 3.13**: Database wrapper and query generator
- **PostgreSQL**: Primary database
- **Oban 2.17**: Background job processing
- **Tailwind CSS 4.1**: Utility-first CSS framework
- **DaisyUI**: Tailwind component library

### External Integrations

- **Gmail API**: Email fetching and management
- **OpenAI API**: GPT-4o-mini for AI operations
- **OAuth 2.0**: User authentication via Google
- **Swoosh**: Email delivery (magic link authentication)

## Features & Implementation

### 1. Email Synchronization

**How it works**: Gmail accounts are connected via OAuth 2.0. The application uses Gmail's Push Notifications (Cloud Pub/Sub webhooks) to receive real-time updates when new emails arrive. Historical emails are fetched via batch requests to the Gmail API.

**Implementation**:
- `GmailAccount` schema stores OAuth tokens with automatic refresh
- `EmailFetcher` module handles Gmail API interactions
- `GmailWebhookController` processes incoming webhook notifications
- `Email` schema stores email data with associations to categories and Gmail accounts

### 2. AI-Powered Categorization

**How it works**: When an email is received, an Oban background job sends the email's subject, sender, and preview to OpenAI's GPT-4o-mini. The AI analyzes the content and assigns it to one of the user's custom categories or suggests a new category.

**Implementation**:
- `EmailProcessorWorker` (Oban) orchestrates the categorization flow
- `OpenAIClient` handles API communication with structured prompts
- `EmailCategorizer` module parses AI responses and creates/assigns categories
- Categories are user-specific and dynamically managed
- Real-time UI updates via Phoenix PubSub

### 3. Email Summarization

**How it works**: Email bodies are processed by GPT-4o-mini to generate concise, actionable summaries. Summaries are generated either automatically when emails arrive or on-demand when users click "Summarize email."

**Implementation**:
- `EmailProcessorWorker` handles summarization as a distinct job action
- AI prompt engineering focuses on extracting key points and action items
- Summaries are stored in the `Email.summary` field
- LiveView updates immediately show summaries without page refresh
- `categorizing_emails` and `summarizing_emails` MapSets track in-progress operations

### 4. Intelligent Unsubscribe

**How it works**: When a user requests to unsubscribe from emails, the application uses a multi-step AI process: (1) Extract unsubscribe links from email body using regex and AI, (2) Fetch the unsubscribe page, (3) Use AI to analyze the page HTML and determine the unsubscribe mechanism (direct link, form submission, or manual), (4) Automatically submit forms or provide manual instructions.

**Implementation**:
- `UnsubscribeWorker` (Oban) orchestrates the unsubscribe flow
- `UnsubscribeAnalyzer` finds unsubscribe links using pattern matching and AI
- `UnsubscribeHandler` fetches pages, analyzes HTML with AI, and submits forms
- AI returns structured JSON with form fields, actions, and methods
- Defensive form handling converts array values to single values for `Req`
- Status tracking: `pending`, `processing`, `success`, `failed`, `not_found`, `pending_confirmation`
- Results stored in `Email.unsubscribe_status`, `unsubscribe_link`, `unsubscribe_error`

### 5. Bulk Email Actions

**How it works**: Users can select multiple emails using checkboxes and perform batch operations. A floating action bar appears when emails are selected, offering options to unsubscribe, delete, or cancel.

**Implementation**:
- `selected_for_unsubscribe` assign tracks selected email IDs (stored as strings)
- Checkbox state synchronized via `phx-click="toggle-email-selection"`
- "Select all" checkbox at the top for bulk selection/deselection
- Floating `action_toast` component displays available actions
- Confirmation modal for destructive delete operations
- Batch operations iterate through selected emails and enqueue jobs

### 6. Email Deletion & Gmail Sync

**How it works**: When emails are deleted, the application first attempts to move them to Gmail's trash folder via the Gmail API, then removes them from the local database. This ensures consistency between the app and Gmail.

**Implementation**:
- `Emails.delete_email/1` function handles both Gmail and database operations
- `ApiClient.trash_message/2` calls Gmail API to move emails to trash
- Token expiration handling with automatic refresh and retry logic
- Database deletion proceeds even if Gmail API fails (logged as warning)
- Transaction-like behavior ensures cleanup regardless of external failures

### 7. Real-time Updates

**How it works**: All email operations (categorization, summarization, status changes) broadcast updates via Phoenix PubSub. LiveView subscriptions ensure all connected clients see changes instantly without polling.

**Implementation**:
- `Emails.update_email/2` broadcasts `{:email_updated, email}` messages
- `HomeLive` subscribes to `"emails:#{current_scope.user.id}"` topic
- `handle_info({:email_updated, updated_email}, socket)` updates assigns
- Email list and selected email view update reactively
- Loading states managed with `categorizing_emails` and `summarizing_emails` MapSets

### 8. Background Job Processing

**How it works**: Long-running operations (AI processing, HTTP requests, email fetching) run in background jobs via Oban. This keeps the UI responsive and allows for retry logic, rate limiting, and monitoring.

**Implementation**:
- Oban queues: `:default` (general), `:email_processing` (AI), `:unsubscribe` (web scraping)
- Job concurrency limits prevent API rate limit issues
- Automatic retries with exponential backoff for transient failures
- Job telemetry and error tracking for debugging

### 9. Authentication & Authorization

**How it works**: Passwordless authentication via magic links. Users enter their email, receive a login link, and gain access. All database queries are scoped to the authenticated user.

**Implementation**:
- Generated with `mix phx.gen.auth` using magic link strategy
- `UserToken` stores time-limited (15 min) magic link tokens
- `UserNotifier` sends magic links via Swoosh (SMTP in production)
- `current_scope` assigns ensure data isolation between users
- Gmail accounts, emails, and categories are all user-scoped

## Project Structure

```
lib/
├── jump_email_categorization/          # Business logic
│   ├── accounts/                       # User auth & magic links
│   ├── ai/                            # OpenAI integrations
│   │   ├── openai_client.ex           # AI API client
│   │   ├── email_categorizer.ex       # Email categorization
│   │   ├── unsubscribe_analyzer.ex    # Unsubscribe link detection
│   │   └── unsubscribe_handler.ex     # Unsubscribe page automation
│   ├── emails/                        # Email domain
│   │   ├── email.ex                   # Email schema
│   │   └── category.ex                # Category schema
│   ├── emails.ex                      # Email context
│   ├── gmail/                         # Gmail API
│   │   ├── api_client.ex              # Gmail API wrapper
│   │   └── gmail_account.ex           # Account schema
│   ├── workers/                       # Oban background jobs
│   │   ├── email_processor_worker.ex  # Categorization & summarization
│   │   ├── email_fetcher.ex           # Gmail sync
│   │   └── unsubscribe_worker.ex      # Unsubscribe automation
│   └── release.ex                     # Release tasks (migrations)
│
├── jump_email_categorization_web/     # Web interface
│   ├── components/                    # Reusable components
│   │   ├── email_components.ex        # Email list & detail views
│   │   ├── layouts.ex                 # App layouts
│   │   └── core_components.ex         # UI primitives
│   ├── live/                          # LiveView pages
│   │   └── home_live.ex               # Main email interface
│   └── controllers/                   # HTTP controllers
│       ├── gmail_webhook_controller.ex # Webhook handler
│       └── user_session_controller.ex  # Auth controller
│
config/                                # Configuration
├── config.exs                         # Compile-time config
├── dev.exs                            # Development config
├── prod.exs                           # Production config
└── runtime.exs                        # Runtime config (env vars)

priv/
└── repo/migrations/                   # Database migrations

assets/                                # Frontend assets
├── css/                               # Stylesheets
└── js/                                # JavaScript
```

## Database Schema

### Core Tables

- **users**: User accounts with email and magic link tokens
- **gmail_accounts**: Gmail OAuth credentials and metadata
- **categories**: User-defined email categories
- **emails**: Stored emails with content, status, and relationships
- **user_tokens**: Magic link and session tokens
- **oban_jobs**: Background job queue

### Key Relationships

- `User` has many `GmailAccount`s
- `User` has many `Category`s
- `Email` belongs to `GmailAccount` and `Category`
- `Email` belongs to `User` (derived through `GmailAccount`)

## Configuration

### Environment Variables

See `env.production.template` for a complete list of required environment variables.

Key configurations:

- `DATABASE_URL`: PostgreSQL connection string
- `SECRET_KEY_BASE`: Phoenix secret (generate with `mix phx.gen.secret`)
- `PHX_HOST`: Application hostname for URL generation
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`: OAuth credentials
- `OPENAI_API_KEY`: OpenAI API access
- `SMTP_*`: Email delivery configuration

### Important Notes

- **Sender Email**: Update `lib/jump_email_categorization/accounts/user_notifier.ex` line 12 to change the FROM address from `contact@example.com` to your real email address
- **OAuth Redirect**: Ensure Google OAuth redirect URI matches your deployment URL
- **Database**: Cloud SQL requires Unix socket connection in production
- **Secrets**: Use Google Secret Manager for production secrets

## Monitoring & Debugging

### Logs

Development logs are printed to console. Production logs are available in Google Cloud Run console.

```bash
# View Cloud Run logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=jump-email-categorization" --limit 50 --format json
```

### Background Jobs

Monitor Oban jobs via LiveDashboard at `/dev/dashboard` (development) or configure for production.

### Common Issues

1. **Token Expired**: Gmail tokens expire after 1 hour. The application automatically refreshes them.
2. **Rate Limits**: OpenAI and Gmail APIs have rate limits. Oban concurrency settings help manage this.
3. **Webhook Delivery**: Gmail webhooks require a publicly accessible HTTPS endpoint.
4. **Email Sender**: Magic link emails won't send if `contact@example.com` isn't updated to a real address.

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/jump_email_categorization/emails_test.exs

# Run tests with coverage
mix test --cover
```

Test structure:
- Unit tests for contexts (`test/jump_email_categorization/`)
- LiveView integration tests (`test/jump_email_categorization_web/live/`)
- Controller tests (`test/jump_email_categorization_web/controllers/`)

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests and formatting (`mix precommit`)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues, questions, or contributions, please open an issue on the GitHub repository.

## Learn More

- [Phoenix Framework](https://www.phoenixframework.org/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
- [Ecto](https://hexdocs.pm/ecto/)
- [Oban](https://hexdocs.pm/oban/)
- [Gmail API](https://developers.google.com/gmail/api)
- [OpenAI API](https://platform.openai.com/docs)
