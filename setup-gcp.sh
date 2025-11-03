#!/bin/bash
set -e

# Configuration (Update these values before running)
PROJECT_ID="${GCP_PROJECT_ID:-jump-email-app}"
REGION="${GCP_REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-jump-email-categorization}"
DB_INSTANCE="${DB_INSTANCE:-jump-email-db}"

echo "🔧 Setting up GCP Infrastructure"
echo "=================================="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo ""

# Login and set project
echo "📋 Setting up GCP project..."
gcloud config set project $PROJECT_ID

# Enable APIs
echo "🔌 Enabling required APIs..."
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com

# Create Artifact Registry repository
echo "📦 Creating Artifact Registry repository..."
gcloud artifacts repositories create jump-email-repo \
  --repository-format=docker \
  --location=$REGION \
  --description="Docker images for Jump Email Categorization" || echo "Repository already exists"

# Configure Docker authentication
echo "🔐 Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev

echo ""
echo "✅ Infrastructure setup complete!"
echo ""
echo "⚠️  Next steps:"
echo "1. Create Cloud SQL instance (takes ~10 minutes):"
echo "   ./setup-database.sh"
echo ""
echo "2. Create secrets in Secret Manager:"
echo "   - Edit .env.production with your values"
echo "   - Run: ./setup-secrets.sh"
echo ""
echo "3. Deploy application:"
echo "   ./deploy-gcp.sh"

