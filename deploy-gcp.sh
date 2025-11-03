#!/bin/bash
set -e

# Parse arguments
SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# Configuration (Update these values before running)
PROJECT_ID="${GCP_PROJECT_ID:-jumpelixiremailcategorization}"
REGION="${GCP_REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-jump-email-categorization}"
DB_INSTANCE="${DB_INSTANCE:-jump-email-db}"

echo "🚀 Deploying Jump Email Categorization to GCP"
echo "================================================"
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Service: $SERVICE_NAME"
echo ""

# Set project
echo "📋 Setting GCP project..."
gcloud config set project $PROJECT_ID

# Build with Cloud Build (conditionally)
IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/jump-email-repo/${SERVICE_NAME}:latest"
if [ "$SKIP_BUILD" = false ]; then
  echo "🔨 Building Docker image on Cloud Build..."
  gcloud builds submit --tag $IMAGE_URL
else
  echo "⏭️  Skipping build, using existing image: $IMAGE_URL"
fi

# Deploy to Cloud Run
echo "🚢 Deploying to Cloud Run..."
gcloud run deploy $SERVICE_NAME \
  --image=$IMAGE_URL \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --port=4000 \
  --memory=512Mi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=10 \
  --timeout=300 \
  --add-cloudsql-instances=${PROJECT_ID}:${REGION}:${DB_INSTANCE} \
  --set-secrets=SECRET_KEY_BASE=secret-key-base:latest,DATABASE_URL=database-url:latest,GOOGLE_CLIENT_ID=google-client-id:latest,GOOGLE_CLIENT_SECRET=google-client-secret:latest,OPENAI_API_KEY=openai-api-key:latest,SMTP_USERNAME=smtp-username:latest,SMTP_PASSWORD=smtp-password:latest \
  --set-env-vars=PHX_HOST=${SERVICE_NAME}-PLACEHOLDER-uc.a.run.app,SMTP_RELAY=smtp.sendgrid.net,SMTP_PORT=587,POOL_SIZE=2

echo ""
echo "✅ Deployment complete!"
echo ""

# Get service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)")
echo "🌐 Service URL: $SERVICE_URL"
echo ""
echo "⚠️  Next steps:"
echo "1. Update PHX_HOST environment variable with: ${SERVICE_URL#https://}"
echo "2. Update Google OAuth redirect URI: ${SERVICE_URL}/auth/google/callback"
echo "3. Run database migrations if needed"
echo ""
echo "💡 Usage tips:"
echo "  Full deployment (rebuild + deploy): ./deploy-gcp.sh"
echo "  Quick deployment (secrets/env only): ./deploy-gcp.sh --skip-build"
echo ""
echo "Run migrations with:"
echo "  gcloud run jobs execute ${SERVICE_NAME}-migrate --region=$REGION --wait"