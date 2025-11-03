# GCP Deployment Scripts

Quick automation scripts to deploy Jump Email Categorization to Google Cloud Platform.

## Quick Start

### 1. Setup Infrastructure

```bash
# Set your project ID
export GCP_PROJECT_ID="your-project-id"

# Run setup
./setup-gcp.sh
```

### 2. Setup Database

```bash
./setup-database.sh
```

This will:
- Create a Cloud SQL PostgreSQL instance
- Create the production database
- Create a database user
- Output the DATABASE_URL (save this!)

### 3. Configure Secrets

```bash
# 1. Copy the template
cp env.production.template .env.production

# 2. Edit with your values
nano .env.production

# 3. Generate SECRET_KEY_BASE
mix phx.gen.secret

# 4. Fill in all values in .env.production

# 5. Upload secrets to Secret Manager
./setup-secrets.sh
```

### 4. Deploy Application

```bash
./deploy-gcp.sh
```

## Scripts Overview

### `setup-gcp.sh`
- Enables required GCP APIs
- Creates Artifact Registry repository
- Configures Docker authentication

### `setup-database.sh`
- Creates Cloud SQL instance (takes ~10 minutes)
- Sets up database and user
- Generates secure passwords
- Outputs DATABASE_URL

### `setup-secrets.sh`
- Reads from `.env.production`
- Creates/updates secrets in Secret Manager
- Handles all required secrets

### `deploy-gcp.sh`
- Builds Docker image
- Pushes to Artifact Registry
- Deploys to Cloud Run
- Outputs service URL

## Environment Variables

See `env.production.template` for all required variables.

### Required Variables:
- `SECRET_KEY_BASE` - Generate with `mix phx.gen.secret`
- `DATABASE_URL` - From `setup-database.sh` output
- `GOOGLE_CLIENT_ID` - From Google Cloud Console
- `GOOGLE_CLIENT_SECRET` - From Google Cloud Console
- `OPENAI_API_KEY` - From OpenAI dashboard
- `SMTP_USERNAME` - From your SMTP provider
- `SMTP_PASSWORD` - From your SMTP provider
- `SMTP_RELAY` - SMTP server address

### Optional Variables:
- `GCP_PROJECT_ID` - Default: `jump-email-app`
- `GCP_REGION` - Default: `us-central1`
- `POOL_SIZE` - Default: `2`

## Post-Deployment

After first deployment:

1. **Get your service URL:**
   ```bash
   gcloud run services describe jump-email-categorization \
     --region=us-central1 \
     --format="value(status.url)"
   ```

2. **Update PHX_HOST:**
   ```bash
   gcloud run services update jump-email-categorization \
     --region=us-central1 \
     --update-env-vars=PHX_HOST=your-service-url.run.app
   ```

3. **Update Google OAuth Redirect URI:**
   - Go to Google Cloud Console → APIs & Credentials
   - Add redirect URI: `https://your-service-url.run.app/auth/google/callback`

4. **Run Database Migrations:**
   ```bash
   # Create migration job (first time only)
   gcloud run jobs create jump-email-categorization-migrate \
     --image=us-central1-docker.pkg.dev/jump-email-app/jump-email-repo/jump-email-categorization:latest \
     --region=us-central1 \
     --set-cloudsql-instances=jump-email-app:us-central1:jump-email-db \
     --set-secrets=DATABASE_URL=database-url:latest \
     --set-env-vars=MIX_ENV=prod \
     --command="bin/jump_email_categorization" \
     --args="eval,JumpEmailCategorization.Release.migrate"
   
   # Run migrations
   gcloud run jobs execute jump-email-categorization-migrate --region=us-central1
   ```

## Troubleshooting

### Docker build fails
```bash
# Check Docker is running
docker info

# Authenticate to Artifact Registry
gcloud auth configure-docker us-central1-docker.pkg.dev
```

### Database connection fails
```bash
# Test connection
gcloud sql connect jump-email-db --user=jump_app_user

# Check if instance is running
gcloud sql instances list
```

### Secrets not found
```bash
# List secrets
gcloud secrets list

# Check secret value
gcloud secrets versions access latest --secret=secret-key-base
```

## Clean Up

To delete all resources:

```bash
# Delete Cloud Run service
gcloud run services delete jump-email-categorization --region=us-central1

# Delete Cloud SQL instance
gcloud sql instances delete jump-email-db

# Delete secrets
gcloud secrets delete secret-key-base
gcloud secrets delete database-url
gcloud secrets delete google-client-id
gcloud secrets delete google-client-secret
gcloud secrets delete openai-api-key
gcloud secrets delete smtp-username
gcloud secrets delete smtp-password

# Delete Artifact Registry repository
gcloud artifacts repositories delete jump-email-repo --location=us-central1
```

## Need More Details?

See the comprehensive guide: **[GCP_DEPLOYMENT.md](./GCP_DEPLOYMENT.md)**

