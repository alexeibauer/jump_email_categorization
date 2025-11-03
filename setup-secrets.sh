#!/bin/bash
set -e

# Load environment variables from .env.production
if [ -f .env.production ]; then
    echo "📄 Loading environment variables from .env.production..."
    export $(cat .env.production | grep -v '^#' | xargs)
else
    echo "❌ Error: .env.production file not found!"
    echo "Please copy env.production.template to .env.production and fill in your values."
    exit 1
fi

echo "🔐 Creating secrets in Secret Manager"
echo "====================================="
echo ""

# Set project
gcloud config set project $GCP_PROJECT_ID

# Function to create or update secret
create_or_update_secret() {
    local secret_name=$1
    local secret_value=$2
    
    if [ -z "$secret_value" ]; then
        echo "⚠️  Skipping $secret_name (value is empty)"
        return
    fi
    
    echo "Creating/updating: $secret_name"
    
    # Check if secret exists
    if gcloud secrets describe $secret_name &>/dev/null; then
        # Add new version
        echo -n "$secret_value" | gcloud secrets versions add $secret_name --data-file=-
    else
        # Create new secret
        echo -n "$secret_value" | gcloud secrets create $secret_name --data-file=-
    fi
}

# Create secrets
create_or_update_secret "secret-key-base" "$SECRET_KEY_BASE"
create_or_update_secret "database-url" "$DATABASE_URL"
create_or_update_secret "google-client-id" "$GOOGLE_CLIENT_ID"
create_or_update_secret "google-client-secret" "$GOOGLE_CLIENT_SECRET"
create_or_update_secret "openai-api-key" "$OPENAI_API_KEY"
create_or_update_secret "smtp-username" "$SMTP_USERNAME"
create_or_update_secret "smtp-password" "$SMTP_PASSWORD"

echo ""
echo "✅ Secrets created successfully!"
echo ""
echo "Next step: Deploy your application with ./deploy-gcp.sh"

