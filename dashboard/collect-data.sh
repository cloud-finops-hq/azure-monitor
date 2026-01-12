#!/bin/bash
# Collect Azure usage data and output as JSON for dashboard
# Includes cost estimates and sponsorship tracking

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/data.json"
HISTORY_FILE="$SCRIPT_DIR/history.json"

# Initialize history file if it doesn't exist
if [ ! -f "$HISTORY_FILE" ]; then
    echo '{"daily_snapshots": []}' > "$HISTORY_FILE"
fi

DATE=$(date +%Y-%m-%d)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "Collecting Azure data..." >&2

# Get subscription info
SUB_NAME=$(az account show --query name -o tsv 2>/dev/null)
SUB_ID=$(az account show --query id -o tsv 2>/dev/null)

# Sponsorship end date (April 2026)
SPONSORSHIP_END="2026-04-30"
DAYS_REMAINING=$(( ($(date -j -f "%Y-%m-%d" "$SPONSORSHIP_END" +%s 2>/dev/null || date -d "$SPONSORSHIP_END" +%s) - $(date +%s)) / 86400 ))

# Function to get pricing for a model
get_input_price() {
    case "$1" in
        gpt-4|gpt-4-*) echo "0.03" ;;
        gpt-4o*) echo "0.005" ;;
        gpt-35-turbo*|gpt-3.5*) echo "0.0015" ;;
        gpt-4.1) echo "0.002" ;;
        gpt-4.1-mini) echo "0.0004" ;;
        gpt-4.1-nano) echo "0.0001" ;;
        gpt-5) echo "0.01" ;;
        gpt-5-pro) echo "0.02" ;;
        gpt-5-nano) echo "0.001" ;;
        o4-mini) echo "0.003" ;;
        text-embedding*) echo "0.0001" ;;
        dall-e*) echo "0.04" ;;
        *) echo "0.01" ;;
    esac
}

get_output_price() {
    case "$1" in
        gpt-4|gpt-4-*) echo "0.06" ;;
        gpt-4o*) echo "0.015" ;;
        gpt-35-turbo*|gpt-3.5*) echo "0.002" ;;
        gpt-4.1) echo "0.008" ;;
        gpt-4.1-mini) echo "0.0016" ;;
        gpt-4.1-nano) echo "0.0004" ;;
        gpt-5) echo "0.03" ;;
        gpt-5-pro) echo "0.06" ;;
        gpt-5-nano) echo "0.004" ;;
        o4-mini) echo "0.012" ;;
        text-embedding*) echo "0" ;;
        dall-e*) echo "0" ;;
        *) echo "0.03" ;;
    esac
}

# Other Azure resource pricing (monthly estimates USD)
STORAGE_PRICE_PER_GB=0.02
POSTGRES_FLEX_PRICE=50
CONTAINER_APP_PRICE=20

END_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_DATE_30D=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ)
START_DATE_7D=$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)
START_DATE_1D=$(date -u -v-1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "1 day ago" +%Y-%m-%dT%H:%M:%SZ)

# Collect OpenAI usage with detailed cost breakdown
OPENAI_USAGE="[]"
TOTAL_OPENAI_COST=0
TOTAL_TOKENS=0

for account in $(az cognitiveservices account list --query "[?kind=='OpenAI'].name" -o tsv 2>/dev/null); do
    rg=$(az cognitiveservices account list --query "[?name=='$account'].resourceGroup" -o tsv 2>/dev/null)
    resource_id="/subscriptions/$SUB_ID/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account"

    # Get deployments with models
    deployments=$(az cognitiveservices account deployment list -n "$account" -g "$rg" --query "[].{name:name, model:properties.model.name}" -o json 2>/dev/null || echo "[]")

    # Get 30-day token metrics
    prompt_tokens=$(az monitor metrics list --resource "$resource_id" \
        --metric "ProcessedPromptTokens" --interval PT1H \
        --start-time "$START_DATE_30D" --end-time "$END_DATE" \
        --query "value[0].timeseries[0].data[*].total" -o tsv 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

    completion_tokens=$(az monitor metrics list --resource "$resource_id" \
        --metric "GeneratedCompletionTokens" --interval PT1H \
        --start-time "$START_DATE_30D" --end-time "$END_DATE" \
        --query "value[0].timeseries[0].data[*].total" -o tsv 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

    # Get 7-day and 1-day for trends
    prompt_7d=$(az monitor metrics list --resource "$resource_id" \
        --metric "ProcessedPromptTokens" --interval PT1H \
        --start-time "$START_DATE_7D" --end-time "$END_DATE" \
        --query "value[0].timeseries[0].data[*].total" -o tsv 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

    prompt_1d=$(az monitor metrics list --resource "$resource_id" \
        --metric "ProcessedPromptTokens" --interval PT1H \
        --start-time "$START_DATE_1D" --end-time "$END_DATE" \
        --query "value[0].timeseries[0].data[*].total" -o tsv 2>/dev/null | awk '{sum+=$1} END {print sum+0}')

    # Calculate cost based on primary model used
    primary_model=$(echo "$deployments" | jq -r '.[0].model // "gpt-4"')

    input_rate=$(get_input_price "$primary_model")
    output_rate=$(get_output_price "$primary_model")

    account_cost=$(echo "scale=2; ($prompt_tokens / 1000 * $input_rate) + ($completion_tokens / 1000 * $output_rate)" | bc 2>/dev/null || echo "0")
    TOTAL_OPENAI_COST=$(echo "scale=2; $TOTAL_OPENAI_COST + $account_cost" | bc 2>/dev/null || echo "$TOTAL_OPENAI_COST")
    TOTAL_TOKENS=$((TOTAL_TOKENS + prompt_tokens + completion_tokens))

    OPENAI_USAGE=$(echo "$OPENAI_USAGE" | jq ". + [{
        \"account\": \"$account\",
        \"resourceGroup\": \"$rg\",
        \"primaryModel\": \"$primary_model\",
        \"promptTokens30d\": $prompt_tokens,
        \"completionTokens30d\": $completion_tokens,
        \"promptTokens7d\": $prompt_7d,
        \"promptTokens1d\": $prompt_1d,
        \"estimatedCost30d\": $account_cost,
        \"deployments\": $deployments
    }]")
done

# Get AIServices
AISERVICES=$(az cognitiveservices account list --query "[?kind=='AIServices'].{name:name, endpoint:properties.endpoint, resourceGroup:resourceGroup}" -o json 2>/dev/null)

# Count other billable resources
STORAGE_COUNT=$(az storage account list --query "length(@)" -o tsv 2>/dev/null || echo "0")
POSTGRES_COUNT=$(az postgres flexible-server list --query "length(@)" -o tsv 2>/dev/null || echo "0")
CONTAINER_APPS=$(az containerapp list --query "length(@)" -o tsv 2>/dev/null || echo "0")

# Estimate other costs (monthly)
OTHER_COSTS=$(echo "scale=2; ($STORAGE_COUNT * $STORAGE_PRICE_PER_GB * 10) + ($POSTGRES_COUNT * $POSTGRES_FLEX_PRICE) + ($CONTAINER_APPS * $CONTAINER_APP_PRICE)" | bc 2>/dev/null || echo "0")

# Total estimated monthly cost
TOTAL_MONTHLY_COST=$(echo "scale=2; $TOTAL_OPENAI_COST + $OTHER_COSTS" | bc 2>/dev/null || echo "0")

# Project cost until sponsorship ends
PROJECTED_COST_TILL_APRIL=$(echo "scale=2; $TOTAL_MONTHLY_COST * ($DAYS_REMAINING / 30)" | bc 2>/dev/null || echo "0")

# Get resources summary
RESOURCES_BY_TYPE=$(az resource list --query "[].type" -o tsv 2>/dev/null | sort | uniq -c | sort -rn | head -15 | awk '{print "{\"type\":\""$2"\",\"count\":"$1"}"}' | jq -s '.')

# Check for SaaS subscriptions
SAAS_COUNT=$(az resource list --resource-type "Microsoft.SaaS/resources" --query "length(@)" -o tsv 2>/dev/null || echo "0")

# Get daily metrics for the past 7 days (for graph)
DAILY_METRICS="[]"
for i in 6 5 4 3 2 1 0; do
    day_start=$(date -u -v-${i}d +%Y-%m-%dT00:00:00Z 2>/dev/null || date -u -d "$i days ago" +%Y-%m-%dT00:00:00Z)
    day_end=$(date -u -v-${i}d +%Y-%m-%dT23:59:59Z 2>/dev/null || date -u -d "$i days ago" +%Y-%m-%dT23:59:59Z)
    day_label=$(date -v-${i}d +%Y-%m-%d 2>/dev/null || date -d "$i days ago" +%Y-%m-%d)

    day_tokens=0
    for account in $(az cognitiveservices account list --query "[?kind=='OpenAI'].name" -o tsv 2>/dev/null); do
        rg=$(az cognitiveservices account list --query "[?name=='$account'].resourceGroup" -o tsv 2>/dev/null)
        resource_id="/subscriptions/$SUB_ID/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account"

        tokens=$(az monitor metrics list --resource "$resource_id" \
            --metric "ProcessedPromptTokens" --interval PT1H \
            --start-time "$day_start" --end-time "$day_end" \
            --query "value[0].timeseries[0].data[*].total" -o tsv 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
        day_tokens=$((day_tokens + tokens))
    done

    # Estimate daily cost
    day_cost=$(echo "scale=2; $day_tokens / 1000 * 0.01" | bc 2>/dev/null || echo "0")
    DAILY_METRICS=$(echo "$DAILY_METRICS" | jq ". + [{\"date\": \"$day_label\", \"tokens\": $day_tokens, \"cost\": $day_cost}]")
done

# Build final JSON
cat > "$OUTPUT_FILE" << ENDJSON
{
  "timestamp": "$TIMESTAMP",
  "date": "$DATE",
  "subscription": {
    "name": "$SUB_NAME",
    "id": "$SUB_ID",
    "type": "Microsoft Azure Sponsorship",
    "sponsorshipEnds": "$SPONSORSHIP_END",
    "daysRemaining": $DAYS_REMAINING
  },
  "costs": {
    "openAi30d": $TOTAL_OPENAI_COST,
    "otherServices30d": $OTHER_COSTS,
    "totalMonthly": $TOTAL_MONTHLY_COST,
    "projectedTillApril": $PROJECTED_COST_TILL_APRIL,
    "coveredBySponsorship": true,
    "note": "These costs are currently offset by Microsoft Azure Sponsorship until April 2026"
  },
  "summary": {
    "totalTokens30d": $TOTAL_TOKENS,
    "openAiAccounts": $(echo "$OPENAI_USAGE" | jq 'length'),
    "aiServicesAccounts": $(echo "$AISERVICES" | jq 'length'),
    "saasSubscriptions": $SAAS_COUNT,
    "storageAccounts": $STORAGE_COUNT,
    "postgresServers": $POSTGRES_COUNT,
    "containerApps": $CONTAINER_APPS
  },
  "openAiUsage": $OPENAI_USAGE,
  "aiServices": $AISERVICES,
  "resourcesByType": $RESOURCES_BY_TYPE,
  "dailyMetrics": $DAILY_METRICS,
  "alerts": {
    "hasSaasSubscriptions": $([ "$SAAS_COUNT" -gt 0 ] && echo "true" || echo "false"),
    "hasAiServices": $([ "$(echo "$AISERVICES" | jq 'length')" -gt 0 ] && echo "true" || echo "false")
  },
  "pricing": {
    "note": "Estimated based on Azure OpenAI public pricing",
    "models": {
      "gpt-4": {"input": 0.03, "output": 0.06},
      "gpt-4o": {"input": 0.005, "output": 0.015},
      "gpt-4.1": {"input": 0.002, "output": 0.008},
      "gpt-5": {"input": 0.01, "output": 0.03}
    }
  }
}
ENDJSON

# Fetch invoices from Azure Billing
echo "Fetching invoices..." >&2
BILLING_ACCOUNT="86977968-84de-43a3-be1f-ba01891b28ef"
INVOICES=$(az billing invoice list --account-name "$BILLING_ACCOUNT" --period-start-date "2024-01-01" --period-end-date "2026-12-31" -o json 2>/dev/null | jq '[.[] | {
  id: .name,
  date: .invoiceDate,
  periodStart: .invoicePeriodStartDate,
  periodEnd: .invoicePeriodEndDate,
  status: .status,
  type: .invoiceType,
  dueDate: .dueDate,
  currency: (.totalAmount.currency // .amountDue.currency),
  amountDue: .amountDue.value,
  subtotal: .billedAmount.value,
  tax: (.taxAmount.value // 0),
  total: (.totalAmount.value // .billedAmount.value)
}]' 2>/dev/null || echo "[]")

# Calculate total invoiced amount (using total which includes tax)
TOTAL_INVOICED=$(echo "$INVOICES" | jq '[.[] | .total // 0] | add // 0')
TOTAL_DUE=$(echo "$INVOICES" | jq '[.[] | select(.status == "Due") | .amountDue // 0] | add // 0')
INVOICE_COUNT=$(echo "$INVOICES" | jq 'length')

# Add invoices to the output JSON
jq --argjson invoices "$INVOICES" \
   --argjson totalInvoiced "$TOTAL_INVOICED" \
   --argjson totalDue "$TOTAL_DUE" \
   --argjson invoiceCount "$INVOICE_COUNT" \
   '. + {
     invoices: $invoices,
     invoiceSummary: {
       totalInvoiced: $totalInvoiced,
       totalDue: $totalDue,
       count: $invoiceCount,
       note: "All invoices are AzureMarketplace (Anthropic/Claude) - NOT covered by sponsorship"
     }
   }' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Save to history (once per day)
EXISTING_DATE=$(jq -r ".daily_snapshots[-1].date // \"\"" "$HISTORY_FILE" 2>/dev/null)
if [ "$EXISTING_DATE" != "$DATE" ]; then
    jq ".daily_snapshots += [{\"date\": \"$DATE\", \"totalCost\": $TOTAL_MONTHLY_COST, \"tokens\": $TOTAL_TOKENS}]" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
fi

echo "Data collected and saved to $OUTPUT_FILE" >&2
