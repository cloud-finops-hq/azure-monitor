#!/bin/bash
# Azure Usage Monitor Script
# Run daily to track spending and resource usage

set -e

DATE=$(date +%Y-%m-%d)
REPORT_FILE="/Users/satish/qlp-projects/azure-monitor/reports/usage-${DATE}.txt"
mkdir -p /Users/satish/qlp-projects/azure-monitor/reports

echo "========================================" | tee "$REPORT_FILE"
echo "Azure Usage Report - $DATE" | tee -a "$REPORT_FILE"
echo "========================================" | tee -a "$REPORT_FILE"

# Check Azure login
if ! az account show &>/dev/null; then
    echo "ERROR: Not logged into Azure CLI" | tee -a "$REPORT_FILE"
    exit 1
fi

SUB_NAME=$(az account show --query name -o tsv)
echo "Subscription: $SUB_NAME" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 1. List all Cognitive Services (AI resources)
echo "=== AI/Cognitive Services ===" | tee -a "$REPORT_FILE"
az cognitiveservices account list --query "[].{Name:name, Kind:kind, SKU:sku.name, RG:resourceGroup}" -o table 2>/dev/null | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 2. Check for any AIServices (could have Claude)
echo "=== AIServices Resources (Potential Marketplace Billing) ===" | tee -a "$REPORT_FILE"
AISERVICES=$(az cognitiveservices account list --query "[?kind=='AIServices'].{Name:name, Endpoint:properties.endpoint, RG:resourceGroup}" -o table 2>/dev/null)
if [ -n "$AISERVICES" ]; then
    echo "$AISERVICES" | tee -a "$REPORT_FILE"
    echo "⚠️  WARNING: AIServices can host Claude models (Marketplace billing)" | tee -a "$REPORT_FILE"
else
    echo "✓ No AIServices resources found" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 3. Check OpenAI token usage (last 30 days)
echo "=== Azure OpenAI Token Usage (Last 30 Days) ===" | tee -a "$REPORT_FILE"
for account in $(az cognitiveservices account list --query "[?kind=='OpenAI'].name" -o tsv 2>/dev/null); do
    rg=$(az cognitiveservices account list --query "[?name=='$account'].resourceGroup" -o tsv 2>/dev/null)
    echo "Account: $account" | tee -a "$REPORT_FILE"
    
    # Get deployments
    az cognitiveservices account deployment list -n "$account" -g "$rg" \
        --query "[].{Deployment:name, Model:properties.model.name}" -o table 2>/dev/null | tee -a "$REPORT_FILE"
    
    # Get metrics (tokens processed)
    END_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    START_DATE=$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ)
    
    TOKENS=$(az monitor metrics list --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$account" \
        --metric "ProcessedPromptTokens" --interval PT1H --start-time "$START_DATE" --end-time "$END_DATE" \
        --query "value[0].timeseries[0].data[*].total" -o tsv 2>/dev/null | awk '{sum+=$1} END {print sum}')
    
    echo "  Total Prompt Tokens (30d): ${TOKENS:-0}" | tee -a "$REPORT_FILE"
    echo "" | tee -a "$REPORT_FILE"
done

# 4. List all resources by type
echo "=== All Resources by Type ===" | tee -a "$REPORT_FILE"
az resource list --query "[].{Type:type}" -o tsv 2>/dev/null | sort | uniq -c | sort -rn | head -20 | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

# 5. Check for SaaS/Marketplace subscriptions
echo "=== Marketplace/SaaS Subscriptions ===" | tee -a "$REPORT_FILE"
SAAS=$(az resource list --resource-type "Microsoft.SaaS/resources" -o table 2>/dev/null)
if [ -n "$SAAS" ] && [ "$SAAS" != "" ]; then
    echo "$SAAS" | tee -a "$REPORT_FILE"
    echo "⚠️  WARNING: Active Marketplace SaaS subscriptions found!" | tee -a "$REPORT_FILE"
else
    echo "✓ No Marketplace SaaS subscriptions" | tee -a "$REPORT_FILE"
fi
echo "" | tee -a "$REPORT_FILE"

# 6. Recent resource creations (last 7 days)
echo "=== Resources Created (Last 7 Days) ===" | tee -a "$REPORT_FILE"
az monitor activity-log list --offset 7d \
    --query "[?operationName.value=='Microsoft.Resources/deployments/write' && status.value=='Succeeded'].{Time:eventTimestamp, Resource:resourceId}" \
    -o table 2>/dev/null | head -20 | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"

echo "========================================" | tee -a "$REPORT_FILE"
echo "Report saved to: $REPORT_FILE"
