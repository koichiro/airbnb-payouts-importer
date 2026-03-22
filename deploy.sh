#!/bin/bash

set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-airbnb-payouts-import}"
TRIGGER_NAME="${TRIGGER_NAME:-${SERVICE_NAME}-gcs-finalized}"
REGION="${REGION:-asia-northeast1}"
TRIGGER_BUCKET="${TRIGGER_BUCKET:-YOUR_BUCKET_NAME}"
PROJECT_ID="${PROJECT_ID:-YOUR_PROJECT_ID}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_EMAIL:-YOUR_SERVICE_ACCOUNT_EMAIL}"
BQ_DATASET_ID="${BQ_DATASET_ID:-airbnb_management}"
BQ_TABLE_ID="${BQ_TABLE_ID:-earnings_cleaned}"

echo "Deploying Cloud Run service ${SERVICE_NAME} to ${REGION}..."

gcloud run deploy "${SERVICE_NAME}" \
  --project "${PROJECT_ID}" \
  --region "${REGION}" \
  --source . \
  --memory 512Mi \
  --service-account "${SERVICE_ACCOUNT_EMAIL}" \
  --no-allow-unauthenticated \
  --set-env-vars "GCP_PROJECT_ID=${PROJECT_ID},BQ_DATASET_ID=${BQ_DATASET_ID},BQ_TABLE_ID=${BQ_TABLE_ID}"

echo "Creating or updating Eventarc trigger ${TRIGGER_NAME}..."

if gcloud eventarc triggers describe "${TRIGGER_NAME}" --project "${PROJECT_ID}" --location "${REGION}" >/dev/null 2>&1; then
  gcloud eventarc triggers delete "${TRIGGER_NAME}" \
    --project "${PROJECT_ID}" \
    --location "${REGION}" \
    --quiet
fi

gcloud eventarc triggers create "${TRIGGER_NAME}" \
  --project "${PROJECT_ID}" \
  --location "${REGION}" \
  --destination-run-service "${SERVICE_NAME}" \
  --destination-run-region "${REGION}" \
  --event-filters "type=google.cloud.storage.object.v1.finalized" \
  --event-filters "bucket=${TRIGGER_BUCKET}" \
  --service-account "${SERVICE_ACCOUNT_EMAIL}"

echo "Deployment complete."
