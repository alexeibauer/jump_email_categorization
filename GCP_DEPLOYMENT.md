# Deploying Jump Email Categorization to Google Cloud Platform (GCP)

This guide provides a guide to deploy your Phoenix application to GCP using **Cloud Run** and **Cloud SQL**.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [GCP Project Setup](#gcp-project-setup)
3. [Cloud SQL PostgreSQL Setup](#cloud-sql-postgresql-setup)
4. [Environment Variables Configuration](#environment-variables-configuration)
5. [SMTP Email Configuration](#smtp-email-configuration)
6. [Google OAuth Setup](#google-oauth-setup)
7. [Create Dockerfile](#create-dockerfile)
8. [Build and Deploy](#build-and-deploy)
9. [Database Migrations](#database-migrations)
10. [Monitoring and Logs](#monitoring-and-logs)

---

## Prerequisites

1. **Google Cloud SDK** installed ([Install Guide](https://cloud.google.com/sdk/docs/install))
2. **Docker** installed locally
3. A **Google Cloud Project** with billing enabled
4. **OpenAI API Key** ([Get one here](https://platform.openai.com/api-keys))

---

## GCP Project Setup

### 1. Initialize gcloud CLI

```bash
# Login to GCP
gcloud auth login

# Create a new project (or use existing)
gcloud projects create jump-email-app --name="Jump Email Categorization"

# Set the project
gcloud config set project jump-email-app

# Enable required APIs
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com
```

### 2. Set Environment Variables

```bash
export PROJECT_ID="jumpelixiremailcategorization"
export REGION="us-central1"
export SERVICE_NAME="jump-email-categorization"
```

---

## Cloud SQL PostgreSQL Setup

### 1. Create PostgreSQL Instance

```bash
# Create Cloud SQL instance (this takes ~10 minutes)
gcloud sql instances create jump-email-db \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=$REGION \
  --root-password="CHANGE_THIS_ROOT_PASSWORD"

# Create the application database
gcloud sql databases create jump_email_categorization_prod \
  --instance=jump-email-db

# Create a database user
gcloud sql users create jump_app_user \
  --instance=jump-email-db \
  --password="CHANGE_THIS_USER_PASSWORD"
```

### 2. Get Database Connection String

```bash
# Get the connection name (format: project:region:instance)
gcloud sql instances describe jump-email-db --format="value(connectionName)"

# Example output: jump-email-app:us-central1:jump-email-db
```

### 3. Enable Cloud SQL Proxy for Cloud Run

Cloud Run will connect via Unix socket. Your `DATABASE_URL` format will be:

```
ecto://jump_app_user:PASSWORD@/jump_email_categorization_prod?host=/cloudsql/PROJECT:REGION:INSTANCE
```

Example:
```
ecto://jump_app_user:mypassword@/jump_email_categorization_prod?host=/cloudsql/jump-email-app:us-central1:jump-email-db
```

---

## Environment Variables Configuration

### Required Environment Variables

| Variable | Description | How to Generate |
|----------|-------------|-----------------|
| `SECRET_KEY_BASE` | Phoenix secret key | `mix phx.gen.secret` |
| `DATABASE_URL` | PostgreSQL connection string | See format above |
| `PHX_HOST` | Your domain | `your-app.run.app` (or custom domain) |
| `GOOGLE_CLIENT_ID` | Google OAuth Client ID | See Google OAuth Setup section |
| `GOOGLE_CLIENT_SECRET` | Google OAuth Client Secret | See Google OAuth Setup section |
| `OPENAI_API_KEY` | OpenAI API key | Get from OpenAI dashboard |
| `SMTP_USERNAME` | SMTP username for email | See SMTP Configuration section |
| `SMTP_PASSWORD` | SMTP password | See SMTP Configuration section |
| `SMTP_RELAY` | SMTP server address | `smtp.sendgrid.net` or `smtp.gmail.com` |

### Store Secrets in Secret Manager

```bash
# Generate SECRET_KEY_BASE
SECRET_KEY_BASE=$(mix phx.gen.secret)

# Create secrets
echo -n "$SECRET_KEY_BASE" | gcloud secrets create secret-key-base --data-file=-
echo -n "ecto://jump_app_user:PASSWORD@/jump_email_categorization_prod?host=/cloudsql/jump-email-app:us-central1:jump-email-db" | gcloud secrets create database-url --data-file=-
echo -n "YOUR_GOOGLE_CLIENT_ID" | gcloud secrets create google-client-id --data-file=-
echo -n "YOUR_GOOGLE_CLIENT_SECRET" | gcloud secrets create google-client-secret --data-file=-
echo -n "YOUR_OPENAI_API_KEY" | gcloud secrets create openai-api-key --data-file=-
echo -n "YOUR_SMTP_USERNAME" | gcloud secrets create smtp-username --data-file=-
echo -n "YOUR_SMTP_PASSWORD" | gcloud secrets create smtp-password --data-file=-
```

---

## SMTP Email Configuration

You have two main options for SMTP in production:

### Option 1: SendGrid (Recommended - Free tier available)

1. **Sign up**: https://sendgrid.com/
2. **Create API Key**: Settings → API Keys → Create API Key
3. **Configuration**:
   ```bash
   SMTP_USERNAME="apikey"
   SMTP_PASSWORD="YOUR_SENDGRID_API_KEY"
   SMTP_RELAY="smtp.sendgrid.net"
   SMTP_PORT="587"
   ```

### Option 2: Gmail SMTP (Simple but less reliable)

1. **Enable 2-Factor Authentication** on your Google account
2. **Create App Password**: https://myaccount.google.com/apppasswords
3. **Configuration**:
   ```bash
   SMTP_USERNAME="your-email@gmail.com"
   SMTP_PASSWORD="your-16-char-app-password"
   SMTP_RELAY="smtp.gmail.com"
   SMTP_PORT="587"
   ```

### Update `config/runtime.exs`

Add to the production section in `config/runtime.exs`:

```elixir
if config_env() == :prod do
  # ... existing config ...

  # Mailer configuration
  config :jump_email_categorization, JumpEmailCategorization.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: System.get_env("SMTP_RELAY") || "smtp.sendgrid.net",
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
    tls: :always,
    auth: :always,
    retries: 2
end
```

---

## Google OAuth Setup

### 1. Configure OAuth Consent Screen

1. Go to: https://console.cloud.google.com/apis/credentials
2. Click **"Configure Consent Screen"**
3. Choose **External** (or Internal if workspace)
4. Fill in:
   - **App name**: Jump Email Categorization
   - **User support email**: your email
   - **Developer contact**: your email
5. Add scopes:
   - `email`
   - `profile`
   - `https://www.googleapis.com/auth/gmail.modify`
6. Add test users if in testing mode

### 2. Create OAuth 2.0 Client

1. Go to: https://console.cloud.google.com/apis/credentials
2. Click **"Create Credentials"** → **"OAuth 2.0 Client ID"**
3. Application type: **Web application**
4. Name: `Jump Email App Production`
5. **Authorized redirect URIs** (VERY IMPORTANT):
   ```
   https://YOUR-SERVICE-NAME-XXXXX-uc.a.run.app/auth/google/callback
   ```
   
   If using custom domain:
   ```
   https://yourdomain.com/auth/google/callback
   ```

6. Click **Create** and save your:
   - Client ID
   - Client Secret

### 3. Store in Secret Manager

```bash
echo -n "YOUR_CLIENT_ID" | gcloud secrets create google-client-id --data-file=-
echo -n "YOUR_CLIENT_SECRET" | gcloud secrets create google-client-secret --data-file=-
```

---

## Create Dockerfile

Create a `Dockerfile` in your project root:

```dockerfile
# Build stage
FROM hexpm/elixir:1.15.7-erlang-26.1.2-alpine-3.18.4 AS build

# Install build dependencies
RUN apk add --no-cache build-base git nodejs npm

# Prepare build directory
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before compiling dependencies
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy assets
COPY priv priv
COPY assets assets

# Compile assets
RUN mix assets.deploy

# Compile the release
COPY lib lib
RUN mix compile

# Generate release
COPY config/runtime.exs config/
RUN mix release

# Start a new build stage
FROM alpine:3.18.4 AS app

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

# Set environment
ENV USER="elixir"
ENV MIX_ENV="prod"
ENV PHX_SERVER="true"

# Create user
RUN addgroup -g 1000 ${USER} && \
    adduser -u 1000 -G ${USER} -s /bin/sh -D ${USER}

WORKDIR /app

# Set runner ENV
ENV HOME=/app

# Copy built application
COPY --from=build --chown=${USER}:${USER} /app/_build/${MIX_ENV}/rel/jump_email_categorization ./

USER ${USER}

# Expose port (Cloud Run will override this)
EXPOSE 4000

# Start the release
CMD ["bin/jump_email_categorization", "start"]
```

### Create `.dockerignore`

```
_build/
deps/
.git/
.gitignore
*.md
test/
.elixir_ls/
node_modules/
assets/node_modules/
```

---

## Build and Deploy

### 1. Create Artifact Registry Repository

```bash
gcloud artifacts repositories create jump-email-repo \
  --repository-format=docker \
  --location=$REGION
```

### 2. Build and Push Docker Image

```bash
# Configure Docker authentication
gcloud auth configure-docker ${REGION}-docker.pkg.dev

# Build the image
docker build -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/jump-email-repo/${SERVICE_NAME}:latest .

# Push to Artifact Registry
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/jump-email-repo/${SERVICE_NAME}:latest
```

### 3. Deploy to Cloud Run

```bash
gcloud run deploy $SERVICE_NAME \
  --image=${REGION}-docker.pkg.dev/${PROJECT_ID}/jump-email-repo/${SERVICE_NAME}:latest \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --port=4000 \
  --memory=512Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=10 \
  --timeout=300 \
  --add-cloudsql-instances=jump-email-app:us-central1:jump-email-db \
  --set-secrets=\
SECRET_KEY_BASE=secret-key-base:latest,\
DATABASE_URL=database-url:latest,\
GOOGLE_CLIENT_ID=google-client-id:latest,\
GOOGLE_CLIENT_SECRET=google-client-secret:latest,\
OPENAI_API_KEY=openai-api-key:latest,\
SMTP_USERNAME=smtp-username:latest,\
SMTP_PASSWORD=smtp-password:latest \
  --set-env-vars=\
PHX_HOST=jump-email-categorization-XXXXX-uc.a.run.app,\
SMTP_RELAY=smtp.sendgrid.net,\
SMTP_PORT=587,\
PORT=4000,\
POOL_SIZE=2
```

**Note**: Replace `PHX_HOST` with your actual Cloud Run URL (you'll get this after first deploy).

### 4. Update PHX_HOST

After first deployment, get your service URL:

```bash
gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)"
```

Then redeploy with the correct `PHX_HOST`:

```bash
gcloud run services update $SERVICE_NAME \
  --region=$REGION \
  --update-env-vars=PHX_HOST=jump-email-categorization-XXXXX-uc.a.run.app
```

---

## Database Migrations

### Run migrations using Cloud Run Jobs

```bash
# Create a migration job
gcloud run jobs create ${SERVICE_NAME}-migrate \
  --image=${REGION}-docker.pkg.dev/${PROJECT_ID}/jump-email-repo/${SERVICE_NAME}:latest \
  --region=$REGION \
  --set-cloudsql-instances=jump-email-app:us-central1:jump-email-db \
  --set-secrets=DATABASE_URL=database-url:latest \
  --set-env-vars=MIX_ENV=prod \
  --command="bin/jump_email_categorization" \
  --args="eval,JumpEmailCategorization.Release.migrate"
```

### Create Release module for migrations

Create `lib/jump_email_categorization/release.ex`:

```elixir
defmodule JumpEmailCategorization.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :jump_email_categorization

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
```

### Run the migration

```bash
gcloud run jobs execute ${SERVICE_NAME}-migrate --region=$REGION
```

---

## Monitoring and Logs

### View Logs

```bash
# Stream logs
gcloud run services logs tail $SERVICE_NAME --region=$REGION

# View in Console
https://console.cloud.google.com/run/detail/${REGION}/${SERVICE_NAME}/logs
```

### Set up Alerts (Optional)

1. Go to: https://console.cloud.google.com/monitoring
2. Create alerts for:
   - High error rates
   - High latency
   - Instance count

---

## Custom Domain (Optional)

### Map Custom Domain

```bash
gcloud run domain-mappings create \
  --service=$SERVICE_NAME \
  --domain=yourdomain.com \
  --region=$REGION
```

Follow the instructions to add DNS records to your domain provider.

**Don't forget to update**:
1. `PHX_HOST` environment variable
2. Google OAuth redirect URI

---

## Update and Redeploy

To update your application:

```bash
# 1. Build new image
docker build -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/jump-email-repo/${SERVICE_NAME}:latest .

# 2. Push to registry
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/jump-email-repo/${SERVICE_NAME}:latest

# 3. Deploy (Cloud Run automatically uses latest tag)
gcloud run deploy $SERVICE_NAME \
  --image=${REGION}-docker.pkg.dev/${PROJECT_ID}/jump-email-repo/${SERVICE_NAME}:latest \
  --region=$REGION

# 4. Run migrations if needed
gcloud run jobs execute ${SERVICE_NAME}-migrate --region=$REGION
```

---

## Troubleshooting

### Application won't start

```bash
# Check logs
gcloud run services logs tail $SERVICE_NAME --region=$REGION

# Common issues:
# - Database connection: Check DATABASE_URL format
# - Secrets: Verify all secrets are created and accessible
# - Port: Cloud Run expects app to listen on $PORT (default 8080, we set to 4000)
```

### Database connection errors

```bash
# Test Cloud SQL connection
gcloud sql connect jump-email-db --user=jump_app_user

# Verify Cloud SQL instance is attached to Cloud Run service
gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(spec.template.spec.containers[0].resources.limits)"
```

### OAuth redirect URI mismatch

1. Check your deployed URL: `gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)"`
2. Ensure Google OAuth console has exact redirect URI: `https://YOUR-URL/auth/google/callback`
3. No trailing slashes!

---

## Cost Estimation

### Cloud Run (with default settings)
- **Free tier**: 2 million requests/month
- **After free tier**: ~$0.00002400 per request
- **Memory**: $0.0000025 per GB-second
- **CPU**: $0.00002400 per vCPU-second

### Cloud SQL (db-f1-micro)
- **Instance**: ~$10/month
- **Storage**: $0.17 per GB/month

### Estimated monthly cost: $10-30 (depending on traffic)

---

## Security Checklist

- [ ] Secrets stored in Secret Manager (not in code)
- [ ] Cloud SQL uses private IP or Cloud SQL Proxy
- [ ] Google OAuth credentials updated with production redirect URI
- [ ] SMTP credentials secured
- [ ] Database user has minimal permissions
- [ ] Cloud Run authentication configured (if needed)
- [ ] Environment variables verified
- [ ] SSL/TLS enabled (automatic with Cloud Run)

---

## Next Steps

1. **Enable GitHub Actions**: Automate deployments on push
2. **Set up monitoring**: Cloud Monitoring and Error Reporting
3. **Configure backups**: Cloud SQL automatic backups
4. **Add custom domain**: Professional appearance
5. **Scale settings**: Adjust based on traffic patterns

---

## Support

For issues specific to:
- **Cloud Run**: https://cloud.google.com/run/docs
- **Cloud SQL**: https://cloud.google.com/sql/docs
- **Phoenix Framework**: https://hexdocs.pm/phoenix

---

**Last Updated**: November 3, 2025

