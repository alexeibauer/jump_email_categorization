#!/bin/bash
set -e

# Configuration (Update these values before running)
PROJECT_ID="${GCP_PROJECT_ID:-jump-email-app}"
REGION="${GCP_REGION:-us-central1}"
DB_INSTANCE="${DB_INSTANCE:-jump-email-db}"

echo "🗄️  Setting up Cloud SQL PostgreSQL"
echo "===================================="
echo ""

# Generate random passwords if not set
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-$(openssl rand -base64 32)}"
DB_USER_PASSWORD="${DB_USER_PASSWORD:-$(openssl rand -base64 32)}"

echo "Creating Cloud SQL instance (this takes ~10 minutes)..."
gcloud sql instances create $DB_INSTANCE \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=$REGION \
  --root-password="$DB_ROOT_PASSWORD" \
  --backup \
  --backup-start-time=03:00

echo ""
echo "Creating database..."
gcloud sql databases create jump_email_categorization_prod \
  --instance=$DB_INSTANCE

echo ""
echo "Creating database user..."
gcloud sql users create jump_app_user \
  --instance=$DB_INSTANCE \
  --password="$DB_USER_PASSWORD"

echo ""
echo "✅ Database setup complete!"
echo ""

# Get connection name
CONNECTION_NAME=$(gcloud sql instances describe $DB_INSTANCE --format="value(connectionName)")
echo "📋 Connection details:"
echo "  Connection Name: $CONNECTION_NAME"
echo "  Database: jump_email_categorization_prod"
echo "  User: jump_app_user"
echo "  Password: $DB_USER_PASSWORD"
echo ""

# Build DATABASE_URL
DATABASE_URL="ecto://jump_app_user:${DB_USER_PASSWORD}@/jump_email_categorization_prod?host=/cloudsql/${CONNECTION_NAME}"

echo "🔗 DATABASE_URL:"
echo "  $DATABASE_URL"
echo ""
echo "⚠️  IMPORTANT: Save these credentials securely!"
echo "Add the DATABASE_URL to your .env.production file"
echo ""
echo "Next step: Run ./setup-secrets.sh to store secrets in Secret Manager"

