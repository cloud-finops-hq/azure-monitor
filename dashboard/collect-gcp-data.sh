#!/bin/bash
# Collect GCP usage data and output as JSON for dashboard

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/gcp-data.json"

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "Collecting GCP data..." >&2

# Use full path to gcloud
GCLOUD="/opt/homebrew/share/google-cloud-sdk/bin/gcloud"

# Check if running in GitHub Actions
if [ -n "$GITHUB_ACTIONS" ]; then
    GCLOUD="gcloud"
fi

# Get active account
ACCOUNT=$($GCLOUD auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null || echo "unknown")

# Get billing account
BILLING_ACCOUNT=$($GCLOUD billing accounts list --format="value(name)" 2>/dev/null | head -1 || echo "")
BILLING_NAME=$($GCLOUD billing accounts list --format="value(displayName)" 2>/dev/null | head -1 || echo "Unknown")

# Collect project information
PROJECTS="[]"
TOTAL_COST=0

for project in $($GCLOUD projects list --format="value(projectId)" 2>/dev/null); do
    # Get project details
    PROJECT_NAME=$($GCLOUD projects describe "$project" --format="value(name)" 2>/dev/null || echo "$project")
    PROJECT_NUMBER=$($GCLOUD projects describe "$project" --format="value(projectNumber)" 2>/dev/null || echo "0")

    # Check billing status
    BILLING_RAW=$($GCLOUD billing projects describe "$project" --format="value(billingEnabled)" 2>/dev/null || echo "false")
    BILLING_ENABLED=$(echo "$BILLING_RAW" | tr '[:upper:]' '[:lower:]')

    # Get enabled APIs count
    API_COUNT=$($GCLOUD services list --enabled --project="$project" --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')

    # Check for Vertex AI usage
    VERTEX_ENABLED=$($GCLOUD services list --enabled --project="$project" --format="value(name)" 2>/dev/null | grep "aiplatform" | wc -l | tr -d ' ' || echo "0")
    [ -z "$VERTEX_ENABLED" ] && VERTEX_ENABLED=0

    # Check for Cloud Run
    CLOUDRUN_COUNT=$($GCLOUD run services list --project="$project" --format="value(name)" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    [ -z "$CLOUDRUN_COUNT" ] && CLOUDRUN_COUNT=0

    # Check for GCE instances
    GCE_COUNT=$($GCLOUD compute instances list --project="$project" --format="value(name)" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    [ -z "$GCE_COUNT" ] && GCE_COUNT=0

    # Check for GKE clusters
    GKE_COUNT=$($GCLOUD container clusters list --project="$project" --format="value(name)" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    [ -z "$GKE_COUNT" ] && GKE_COUNT=0

    # Check for Cloud Storage buckets
    GCS_COUNT=$($GCLOUD storage buckets list --project="$project" --format="value(name)" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    [ -z "$GCS_COUNT" ] && GCS_COUNT=0

    # Check for BigQuery datasets
    BQ_COUNT=$($GCLOUD alpha bq datasets list --project="$project" --format="value(datasetId)" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    [ -z "$BQ_COUNT" ] && BQ_COUNT=0

    [ -z "$API_COUNT" ] && API_COUNT=0

    PROJECTS=$(echo "$PROJECTS" | jq ". + [{
        \"projectId\": \"$project\",
        \"name\": \"$PROJECT_NAME\",
        \"projectNumber\": \"$PROJECT_NUMBER\",
        \"billingEnabled\": $BILLING_ENABLED,
        \"enabledApis\": $API_COUNT,
        \"vertexAi\": $VERTEX_ENABLED,
        \"cloudRun\": $CLOUDRUN_COUNT,
        \"computeInstances\": $GCE_COUNT,
        \"gkeClusters\": $GKE_COUNT,
        \"storageBuckets\": $GCS_COUNT,
        \"bigqueryDatasets\": $BQ_COUNT
    }]")
done

# Count totals
TOTAL_PROJECTS=$(echo "$PROJECTS" | jq 'length')
TOTAL_VERTEX=$(echo "$PROJECTS" | jq '[.[].vertexAi] | add')
TOTAL_CLOUDRUN=$(echo "$PROJECTS" | jq '[.[].cloudRun] | add')
TOTAL_GCE=$(echo "$PROJECTS" | jq '[.[].computeInstances] | add')
TOTAL_GKE=$(echo "$PROJECTS" | jq '[.[].gkeClusters] | add')
TOTAL_GCS=$(echo "$PROJECTS" | jq '[.[].storageBuckets] | add')
TOTAL_BQ=$(echo "$PROJECTS" | jq '[.[].bigqueryDatasets] | add')

# Build final JSON
cat > "$OUTPUT_FILE" << ENDJSON
{
  "timestamp": "$TIMESTAMP",
  "date": "$DATE",
  "account": "$ACCOUNT",
  "billing": {
    "accountId": "$BILLING_ACCOUNT",
    "name": "$BILLING_NAME",
    "note": "For detailed cost breakdown, enable BigQuery billing export"
  },
  "summary": {
    "totalProjects": $TOTAL_PROJECTS,
    "vertexAiProjects": $TOTAL_VERTEX,
    "cloudRunServices": $TOTAL_CLOUDRUN,
    "computeInstances": $TOTAL_GCE,
    "gkeClusters": $TOTAL_GKE,
    "storageBuckets": $TOTAL_GCS,
    "bigqueryDatasets": $TOTAL_BQ
  },
  "projects": $PROJECTS,
  "alerts": {
    "hasVertexAi": $([ "$TOTAL_VERTEX" -gt 0 ] && echo "true" || echo "false"),
    "hasCompute": $([ "$TOTAL_GCE" -gt 0 ] && echo "true" || echo "false")
  }
}
ENDJSON

echo "GCP data collected and saved to $OUTPUT_FILE" >&2
