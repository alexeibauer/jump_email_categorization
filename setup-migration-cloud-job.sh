export GCP_PROJECT_ID="jumpelixiremailcategorization"
export GCP_REGION="us-central1"
export SERVICE_NAME="jump-email-categorization"
export DB_INSTANCE="jump-email-db"
export IMAGE_URL="us-central1-docker.pkg.dev/jumpelixiremailcategorization/jump-email-repo/jump-email-categorization:latest"

gcloud run jobs create ${SERVICE_NAME}-migrate \
  --image=$IMAGE_URL \
  --region=$GCP_REGION \
  --set-cloudsql-instances=${GCP_PROJECT_ID}:${GCP_REGION}:${DB_INSTANCE} \
  --set-secrets=DATABASE_URL=database-url:latest,SECRET_KEY_BASE=secret-key-base:latest \
  --command=/app/bin/jump_email_categorization \
  --args=eval,JumpEmailCategorization.Release.migrate \
  --max-retries=0 \
  --task-timeout=10m